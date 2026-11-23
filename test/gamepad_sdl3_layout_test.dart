import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamepads/gamepads.dart';
import 'package:sigg_launcher/app_widget.dart';
import 'package:sigg_launcher/screens/home/home.dart';
import 'package:sigg_launcher/screens/home/pages/store_page.dart';
import 'package:sigg_launcher/screens/home/widgets/mock_games.dart';
import 'package:sigg_launcher/services/bgm_player.dart';
import 'package:sigg_launcher/services/game_run_state.dart';
import 'package:sigg_launcher/services/gamepad_nav.dart';
import 'package:sigg_launcher/services/nav_controller.dart';
import 'package:sigg_launcher/services/page_nav_controller.dart';
import 'package:sigg_launcher/services/ui_sounds.dart';

import 'gamepad_test_harness.dart';

Future<void> _settle(WidgetTester tester, [int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _pumpLibrary(
  WidgetTester tester, {
  Stream<GamepadEvent>? events,
  GamepadKeyLayout? layout,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 720));
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      navigatorObservers: [LauncherRouteObserver.instance],
      home: Library(
        games: Future.value(mockGames),
        gamepadEvents: events,
        gamepadLayout: layout,
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _send(WidgetTester tester, StreamController<GamepadEvent> ctrl,
    GamepadEvent event) async {
  ctrl.add(event);
  await tester.pump();
}

/// Presses a direction/button and pumps a single frame. Settling here would
/// trip the 350 ms auto-repeat and move more than once.
Future<void> _down(
  WidgetTester tester,
  StreamController<GamepadEvent> ctrl,
  GamepadEvent event,
) async {
  await _send(tester, ctrl, event);
}

void main() {
  late FakeGamepadsPlatform fake;

  setUpAll(() {
    // `Gamepads` captures the platform interface once, so the fake must be
    // installed for the whole file rather than per test.
    fake = installFakeGamepads();
  });

  setUp(() async {
    registerSonyMappingOverrides();
    // Tests run with the Android defaultTargetPlatform, so pin the Linux
    // controller-database mapping the desktop build uses, and rebuild it from
    // scratch so the DS4 override and per-device mapping are fresh.
    Gamepads.normalizer = GamepadNormalizer.forPlatform(
      GamepadPlatform.linux,
    );
    BgmPlayer.instance.debugDisable();
    UiSounds.instance.debugDisable();
    NavController.instance.debugReset();
    GamepadStatus.instance.debugReset();
    GameRunState.instance.debugReset();
    LauncherRouteObserver.instance.debugReset();
    PageFocusHub.instance.debugReset();
  });

  group('detectGamepadKeyLayout', () {
    test('the ivi-homescreen embedder gets SDL3 indices', () {
      expect(
        detectGamepadKeyLayout(
          environment: const {},
          executablePath: '/opt/sigg-launcher/runnable/homescreen',
        ),
        GamepadKeyLayout.sdl3,
      );
    });

    test('the GTK runner keeps evdev indices', () {
      expect(
        detectGamepadKeyLayout(
          environment: const {},
          executablePath: '/home/dev/sigg/build/linux/x64/debug/bundle/sigg_launcher',
        ),
        GamepadKeyLayout.evdev,
      );
      expect(
        detectGamepadKeyLayout(
          environment: const {},
          executablePath: Platform.resolvedExecutable,
        ),
        GamepadKeyLayout.evdev,
        reason: 'flutter_tester is not the homescreen embedder',
      );
    });

    test('SIGG_GAMEPAD_LAYOUT overrides detection both ways', () {
      expect(
        detectGamepadKeyLayout(
          environment: const {'SIGG_GAMEPAD_LAYOUT': ' SDL3 '},
          executablePath: '/opt/sigg-launcher/runnable/homescreen',
        ),
        GamepadKeyLayout.sdl3,
      );
      expect(
        detectGamepadKeyLayout(
          environment: const {'SIGG_GAMEPAD_LAYOUT': 'evdev'},
          executablePath: '/opt/sigg-launcher/runnable/homescreen',
        ),
        GamepadKeyLayout.evdev,
      );
      expect(
        detectGamepadKeyLayout(
          environment: const {'SIGG_GAMEPAD_LAYOUT': 'nonsense'},
          executablePath: '/opt/sigg-launcher/runnable/homescreen',
        ),
        GamepadKeyLayout.sdl3,
        reason: 'an unknown value falls back to detection',
      );
    });
  });

  testWidgets('SDL3 d-pad indices 11-14 drive all four directions', (
    tester,
  ) async {
    final ctrl = StreamController<GamepadEvent>.broadcast();
    addTearDown(ctrl.close);
    await _pumpLibrary(tester, events: ctrl.stream, layout: GamepadKeyLayout.sdl3);

    expect(NavController.instance.isGamesActive, isTrue);
    expect(NavController.instance.gamesIndex, 0);

    // 14 = DPAD_RIGHT.
    await _down(tester, ctrl, rawSdl3Button(14, 1));
    expect(NavController.instance.gamesIndex, 1);
    await _send(tester, ctrl, rawSdl3Button(14, 0));

    // 13 = DPAD_LEFT.
    await _down(tester, ctrl, rawSdl3Button(13, 1));
    expect(NavController.instance.gamesIndex, 0);
    await _send(tester, ctrl, rawSdl3Button(13, 0));

    // 11 = DPAD_UP (games -> header).
    await _down(tester, ctrl, rawSdl3Button(11, 1));
    expect(NavController.instance.isHeaderActive, isTrue);
    expect(NavController.instance.headerIndex, 0);
    await _send(tester, ctrl, rawSdl3Button(11, 0));

    // 12 = DPAD_DOWN (header -> games).
    await _down(tester, ctrl, rawSdl3Button(12, 1));
    expect(NavController.instance.isGamesActive, isTrue);
    await _send(tester, ctrl, rawSdl3Button(12, 0));
  });

  testWidgets('SDL3 d-pad release stops the held auto-repeat', (tester) async {
    final ctrl = StreamController<GamepadEvent>.broadcast();
    addTearDown(ctrl.close);
    await _pumpLibrary(tester, events: ctrl.stream, layout: GamepadKeyLayout.sdl3);

    await _down(tester, ctrl, rawSdl3Button(14, 1));
    expect(NavController.instance.gamesIndex, 1);

    await tester.pump(const Duration(milliseconds: 350));
    expect(NavController.instance.gamesIndex, 2);

    await _send(tester, ctrl, rawSdl3Button(14, 0));
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      NavController.instance.gamesIndex,
      2,
      reason: 'a release must cancel the repeat timer',
    );

    // A fresh press after the release moves again (held state was cleared).
    await _down(tester, ctrl, rawSdl3Button(14, 1));
    expect(NavController.instance.gamesIndex, 3);
    await _send(tester, ctrl, rawSdl3Button(14, 0));
  });

  testWidgets('SDL3 SOUTH confirms and EAST backs out', (tester) async {
    final ctrl = StreamController<GamepadEvent>.broadcast();
    addTearDown(ctrl.close);
    await _pumpLibrary(tester, events: ctrl.stream, layout: GamepadKeyLayout.sdl3);

    // Header -> store (index 1).
    await _down(tester, ctrl, rawSdl3Button(11, 1));
    await _send(tester, ctrl, rawSdl3Button(11, 0));
    await _down(tester, ctrl, rawSdl3Button(14, 1));
    await _send(tester, ctrl, rawSdl3Button(14, 0));

    // 0 = SOUTH (Cross/A).
    await _down(tester, ctrl, rawSdl3Button(0, 1));
    await _send(tester, ctrl, rawSdl3Button(0, 0));
    await _settle(tester);
    expect(find.byType(StorePage), findsOneWidget);

    // 1 = EAST (Circle/B).
    await _down(tester, ctrl, rawSdl3Button(1, 1));
    await _send(tester, ctrl, rawSdl3Button(1, 0));
    await tester.pumpAndSettle();
    expect(find.byType(StorePage), findsNothing);
    expect(LauncherRouteObserver.instance.isHomeTop, isTrue);
  });

  testWidgets('SDL3 analog sticks keep driving navigation', (tester) async {
    final ctrl = StreamController<GamepadEvent>.broadcast();
    addTearDown(ctrl.close);
    await _pumpLibrary(tester, events: ctrl.stream, layout: GamepadKeyLayout.sdl3);

    // Axis 0 = left stick X, raw 32767 = right.
    await _send(tester, ctrl, rawSdl3Axis(0, 32767));
    expect(NavController.instance.gamesIndex, 1);
    await _send(tester, ctrl, rawSdl3Axis(0, 0));

    // Axis 1 = left stick Y, raw -32767 = up -> header zone.
    await _send(tester, ctrl, rawSdl3Axis(1, -32767));
    await _settle(tester);
    expect(NavController.instance.isHeaderActive, isTrue);
    await _send(tester, ctrl, rawSdl3Axis(1, 0));
  });

  testWidgets('the bridge listens to raw Gamepads.events, not the normalized '
      'stream', (tester) async {
    await _pumpLibrary(tester, layout: GamepadKeyLayout.sdl3);

    expect(NavController.instance.gamesIndex, 0);
    fake.events.add(rawSdl3Button(14, 1));
    await tester.pump();
    expect(
      NavController.instance.gamesIndex,
      1,
      reason: 'SDL3 key "14" must be mapped as DPAD_RIGHT directly; the evdev '
          'controller database would not resolve it that way',
    );
    fake.events.add(rawSdl3Button(14, 0));
    await tester.pump();
  });

  testWidgets('evdev numbering still decodes through the controller database', (
    tester,
  ) async {
    final ctrl = StreamController<GamepadEvent>.broadcast();
    addTearDown(ctrl.close);
    await _pumpLibrary(tester, events: ctrl.stream, layout: GamepadKeyLayout.evdev);

    // DualShock 4 over Bluetooth: js0 = Cross, hat Y (js7) negative = up.
    await _down(
      tester,
      ctrl,
      rawEvdevEvent(7, KeyType.analog, -32767,
          vendorId: 0x054c, productId: 0x09cc),
    );
    expect(NavController.instance.isHeaderActive, isTrue);

    // Hat X (js6) right = DPAD_RIGHT, over to the store entry.
    await _down(
      tester,
      ctrl,
      rawEvdevEvent(6, KeyType.analog, 32767,
          vendorId: 0x054c, productId: 0x09cc),
    );
    await _send(
      tester,
      ctrl,
      rawEvdevEvent(6, KeyType.analog, 0,
          vendorId: 0x054c, productId: 0x09cc),
    );
    expect(NavController.instance.headerIndex, 1);

    // Cross (js0) opens the highlighted header entry; Circle (js1) backs out.
    await _down(
      tester,
      ctrl,
      rawEvdevEvent(0, KeyType.button, 1,
          vendorId: 0x054c, productId: 0x09cc),
    );
    await _settle(tester);
    expect(find.byType(StorePage), findsOneWidget);

    await _down(
      tester,
      ctrl,
      rawEvdevEvent(1, KeyType.button, 1,
          vendorId: 0x054c, productId: 0x09cc),
    );
    await tester.pumpAndSettle();
    expect(find.byType(StorePage), findsNothing);
  });
}
