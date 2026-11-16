import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamepads/gamepads.dart';
import 'package:sigg_launcher/app_controller.dart';
import 'package:sigg_launcher/app_widget.dart';
import 'package:sigg_launcher/screens/home/home.dart';
import 'package:sigg_launcher/screens/home/widgets/mock_games.dart';
import 'package:sigg_launcher/services/bgm_player.dart';
import 'package:sigg_launcher/services/game_run_state.dart';
import 'package:sigg_launcher/services/gamepad_nav.dart';
import 'package:sigg_launcher/services/nav_controller.dart';
import 'package:sigg_launcher/services/page_nav_controller.dart';
import 'package:sigg_launcher/services/ui_sounds.dart';

import 'gamepad_test_harness.dart';

/// The profile switcher is a pushed route, so it drives the same
/// [PageFocusHub] contract as the other submenus: the Home keyboard handler
/// and the gamepad bridge both forward arrows/Enter/B to whichever controller
/// is on top. These tests speak through both input paths.
void main() {
  setUp(() {
    installFakeGamepads();
    BgmPlayer.instance.debugDisable();
    UiSounds.instance.debugDisable();
    NavController.instance.debugReset();
    GameRunState.instance.debugReset();
    GamepadStatus.instance.debugReset();
    LauncherRouteObserver.instance.debugReset();
    PageFocusHub.instance.debugReset();
    // Fresh profiles/current user for every test (switchUser is global state).
    AppController.instance = AppController();
  });

  Future<void> settle(WidgetTester tester, [int rounds = 8]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> pressKey(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    await settle(tester);
  }

  Future<void> pumpLibrary(
    WidgetTester tester, [
    Stream<NormalizedGamepadEvent>? events,
  ]) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        navigatorObservers: [LauncherRouteObserver.instance],
        home: Library(games: Future.value(mockGames), gamepadEvents: events),
      ),
    );
    await settle(tester);
  }

  /// Header zone -> Perfil (index 0) -> Enter opens the switcher.
  Future<void> openSwitcher(WidgetTester tester) async {
    await pressKey(tester, LogicalKeyboardKey.arrowUp);
    await pressKey(tester, LogicalKeyboardKey.enter);
    expect(find.text('Quem está jogando?'), findsOneWidget);
    expect(PageFocusHub.instance.active, isNotNull);
  }

  Future<void> tapGamepad(
    WidgetTester tester,
    StreamController<NormalizedGamepadEvent> ctrl,
    GamepadButton button,
  ) async {
    ctrl.add(buttonEvent(button, 1));
    await tester.pump();
    ctrl.add(buttonEvent(button, 0));
    await settle(tester);
  }

  testWidgets('opening the switcher parks focus on the current profile and '
      'left/right walks the row without wrapping', (tester) async {
    final luna = AppController.instance.users[1];
    AppController.instance.switchUser(luna);
    await pumpLibrary(tester);
    await openSwitcher(tester);

    final nav = PageFocusHub.instance.active!;
    expect(nav.count, AppController.instance.users.length + 1);
    expect(nav.index, 1, reason: 'cursor starts on the profile in use');

    await pressKey(tester, LogicalKeyboardKey.arrowRight);
    expect(nav.index, 2);
    await pressKey(tester, LogicalKeyboardKey.arrowLeft);
    expect(nav.index, 1);
    await pressKey(tester, LogicalKeyboardKey.arrowLeft);
    expect(nav.index, 0);
    await pressKey(tester, LogicalKeyboardKey.arrowLeft);
    expect(nav.index, 0, reason: 'no wrap at the row start');
  });

  testWidgets('the focused profile stays centered on screen, including the '
      'first and last entries', (tester) async {
    await pumpLibrary(tester);
    await openSwitcher(tester);

    Future<void> expectCentered(String label) async {
      await settle(tester);
      final x = tester.getCenter(find.text(label)).dx;
      expect(
        x,
        moreOrLessEquals(640, epsilon: 1),
        reason: '"$label" must sit in the screen center',
      );
    }

    await expectCentered('TripleT');
    await pressKey(tester, LogicalKeyboardKey.arrowRight);
    await expectCentered('Luna');

    final users = AppController.instance.users;
    for (var i = 1; i < users.length; i++) {
      await pressKey(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(PageFocusHub.instance.active!.index, users.length);
    await expectCentered('Novo perfil');
  });

  testWidgets('a single white ring slides to the focused entry, like the home '
      'header indicator', (tester) async {
    await pumpLibrary(tester);
    await openSwitcher(tester);

    final ring = find.byWidgetPredicate((widget) {
      if (widget is! DecoratedBox) return false;
      final decoration = widget.decoration;
      if (decoration is! BoxDecoration || decoration.shape != BoxShape.circle) {
        return false;
      }
      final border = decoration.border;
      return border is Border &&
          border.top.color == Colors.white &&
          border.top.style == BorderStyle.solid;
    });
    expect(ring, findsOneWidget);

    Rect ringRect() => tester.getRect(ring);
    expect(ringRect().width, moreOrLessEquals(116, epsilon: 0.5));
    expect(ringRect().height, moreOrLessEquals(116, epsilon: 0.5));
    expect(
      ringRect().center.dx,
      moreOrLessEquals(tester.getCenter(find.text('TripleT')).dx, epsilon: 1),
    );

    await pressKey(tester, LogicalKeyboardKey.arrowRight);
    expect(
      ringRect().center.dx,
      moreOrLessEquals(tester.getCenter(find.text('Luna')).dx, epsilon: 1),
      reason: 'the ring must end up on the newly focused profile',
    );
  });

  testWidgets('uses the home shell neutral backdrop', (tester) async {
    await pumpLibrary(tester);
    await openSwitcher(tester);

    final scaffold = tester.widget<Scaffold>(
      find
          .ancestor(
            of: find.text('Quem está jogando?'),
            matching: find.byType(Scaffold),
          )
          .first,
    );
    expect(
      scaffold.backgroundColor,
      kScreenBackground,
      reason:
          'submenus share the neutral shell backdrop, not a themed gradient',
    );
  });

  testWidgets('Enter on a profile switches the user and closes the switcher', (
    tester,
  ) async {
    await pumpLibrary(tester);
    await openSwitcher(tester);

    await pressKey(tester, LogicalKeyboardKey.arrowRight);
    await pressKey(tester, LogicalKeyboardKey.enter);

    expect(find.text('Quem está jogando?'), findsNothing);
    expect(
      AppController.instance.currentUser.nickname,
      AppController.instance.users[1].nickname,
    );
    expect(PageFocusHub.instance.active, isNull);
    expect(find.byType(Library), findsOneWidget);
  });

  testWidgets('Enter on "Novo perfil" shows the placeholder and keeps the '
      'switcher open', (tester) async {
    await pumpLibrary(tester);
    await openSwitcher(tester);

    final users = AppController.instance.users;
    for (var i = 0; i < users.length; i++) {
      await pressKey(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(PageFocusHub.instance.active!.index, users.length);

    await pressKey(tester, LogicalKeyboardKey.enter);
    expect(find.text('A criação de perfis chega em breve.'), findsOneWidget);
    expect(find.text('Quem está jogando?'), findsOneWidget);
    expect(PageFocusHub.instance.active!.index, users.length);
  });

  testWidgets('Escape closes the switcher without changing the profile', (
    tester,
  ) async {
    await pumpLibrary(tester);
    final before = AppController.instance.currentUser;
    await openSwitcher(tester);

    await pressKey(tester, LogicalKeyboardKey.arrowRight);
    await pressKey(tester, LogicalKeyboardKey.escape);

    expect(find.text('Quem está jogando?'), findsNothing);
    expect(identical(AppController.instance.currentUser, before), isTrue);
    expect(PageFocusHub.instance.active, isNull);
  });

  testWidgets('gamepad d-pad/A select a profile and B backs out unchanged', (
    tester,
  ) async {
    final ctrl = StreamController<NormalizedGamepadEvent>.broadcast();
    addTearDown(ctrl.close);
    await pumpLibrary(tester, ctrl.stream);

    await tapGamepad(tester, ctrl, GamepadButton.dpadUp);
    expect(NavController.instance.isHeaderActive, isTrue);
    await tapGamepad(tester, ctrl, GamepadButton.a);
    expect(find.text('Quem está jogando?'), findsOneWidget);
    expect(PageFocusHub.instance.active!.index, 0);

    await tapGamepad(tester, ctrl, GamepadButton.dpadRight);
    expect(PageFocusHub.instance.active!.index, 1);
    await tapGamepad(tester, ctrl, GamepadButton.a);
    expect(find.text('Quem está jogando?'), findsNothing);
    expect(
      AppController.instance.currentUser.nickname,
      AppController.instance.users[1].nickname,
    );

    // Reopen on the new current profile; B must close without switching.
    await tapGamepad(tester, ctrl, GamepadButton.a);
    expect(PageFocusHub.instance.active!.index, 1);
    await tapGamepad(tester, ctrl, GamepadButton.dpadRight);
    final focusedBeforeBack = PageFocusHub.instance.active!.index;
    expect(focusedBeforeBack, 2);
    await tapGamepad(tester, ctrl, GamepadButton.b);
    expect(find.text('Quem está jogando?'), findsNothing);
    expect(
      AppController.instance.currentUser.nickname,
      AppController.instance.users[1].nickname,
      reason: 'B must only close, never select the focused profile',
    );
    expect(LauncherRouteObserver.instance.isHomeTop, isTrue);
  });
}
