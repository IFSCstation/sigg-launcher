import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigg_launcher/app_widget.dart';
import 'package:sigg_launcher/screens/home/home.dart';
import 'package:sigg_launcher/screens/home/widgets/mock_games.dart';
import 'package:sigg_launcher/services/bgm_player.dart';
import 'package:sigg_launcher/services/game_run_state.dart';
import 'package:sigg_launcher/services/gamepad_nav.dart';
import 'package:sigg_launcher/services/nav_controller.dart';
import 'package:sigg_launcher/services/ui_sounds.dart';

import 'gamepad_test_harness.dart';

const _transparentPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUB'
    'AScY42YAAAAASUVORK5CYII=';

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

void main() {
  late Directory tempRoot;

  setUp(() async {
    installFakeGamepads();
    BgmPlayer.instance.debugDisable();
    UiSounds.instance.debugDisable();
    GameRunState.instance.debugReset();
    NavController.instance.debugReset();
    GamepadStatus.instance.debugReset();
    LauncherRouteObserver.instance.debugReset();
    tempRoot = await Directory.systemTemp.createTemp('sigg_bgm_test');
  });

  tearDown(() async {
    await tempRoot.delete(recursive: true);
  });

  void writeGame(String id, {String? bgmName}) {
    final dir = Directory('${tempRoot.path}/$id');
    final imagesDir = Directory('${dir.path}/images');
    final mediaDir = Directory('${dir.path}/media');
    imagesDir.createSync(recursive: true);
    mediaDir.createSync(recursive: true);
    final png = base64Decode(_transparentPng);
    for (final name in ['hero', 'cover', 'icon']) {
      File('${imagesDir.path}/$name.png').writeAsBytesSync(png);
    }
    if (bgmName != null) {
      File('${mediaDir.path}/$bgmName').writeAsStringSync('');
    }
  }

  List<GameEntry> makeEntries(List<String> bgmBearing) {
    final entries = <GameEntry>[];
    for (final id in ['game-a', 'game-b', 'game-c']) {
      writeGame(id, bgmName: bgmBearing.contains(id) ? 'bgm.mp3' : null);
      final base = '${tempRoot.path}/$id';
      entries.add(
        GameEntry(
          id == 'game-a'
              ? 'Game A'
              : id == 'game-b'
              ? 'Game B'
              : 'Game C',
          'Tagline $id',
          'Genre',
          Icons.sports_esports,
          const Color(0xFF7C4DFF),
          id: id,
          heroPath: '$base/images/hero.png',
          coverPath: '$base/images/cover.png',
          iconPath: '$base/images/icon.png',
          bgmPath: bgmBearing.contains(id) ? '$base/media/bgm.mp3' : null,
        ),
      );
    }
    return entries;
  }

  Future<void> pumpLibrary(WidgetTester tester, List<GameEntry> entries) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: Library(games: Future.value(entries)),
      ),
    );
    await settle(tester);
  }

  testWidgets('launching a game resumes the selected game BGM on exit', (
    tester,
  ) async {
    final entries = makeEntries(['game-b']);
    await pumpLibrary(tester, entries);

    await pressKey(tester, LogicalKeyboardKey.arrowRight);
    expect(
      BgmPlayer.instance.debugLastRequested,
      entries[1].bgmPath,
      reason: 'selecting a game must request its BGM',
    );

    BgmPlayer.instance.debugLastRequested = null;
    GameRunState.instance.setRunning(true);
    await settle(tester);
    GameRunState.instance.setRunning(false);
    await settle(tester);

    expect(
      BgmPlayer.instance.debugLastRequested,
      entries[1].bgmPath,
      reason: 'closing a game must request the selected game BGM again',
    );
  });

  testWidgets('closing a game with no BGM requests no new playback', (
    tester,
  ) async {
    final entries = makeEntries(['game-b']);
    await pumpLibrary(tester, entries);

    await pressKey(tester, LogicalKeyboardKey.arrowRight);
    expect(
      BgmPlayer.instance.debugLastRequested,
      entries[1].bgmPath,
      reason: 'sanity: game-b must request its BGM when selected',
    );
    BgmPlayer.instance.debugLastRequested = null;

    await pressKey(tester, LogicalKeyboardKey.arrowRight);
    expect(
      BgmPlayer.instance.debugLastRequested,
      isNull,
      reason: 'selecting a game without BGM must not start any audio',
    );

    GameRunState.instance.setRunning(true);
    await settle(tester);
    GameRunState.instance.setRunning(false);
    await settle(tester);

    expect(
      BgmPlayer.instance.debugLastRequested,
      isNull,
      reason: 'closing a game whose selection has no BGM must not start audio',
    );
  });
}
