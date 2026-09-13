import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigg_launcher/app_widget.dart';
import 'package:sigg_launcher/screens/home/home.dart';
import 'package:sigg_launcher/screens/home/pages/store_page.dart';
import 'package:sigg_launcher/screens/home/widgets/mock_games.dart';
import 'package:sigg_launcher/services/bgm_player.dart';
import 'package:sigg_launcher/services/game_loader.dart';
import 'package:sigg_launcher/services/gamepad_nav.dart';
import 'package:sigg_launcher/services/nav_controller.dart';

import 'gamepad_test_harness.dart';

const _gameProcessPattern =
    r'DELTARUNE|Funkin|superTux|supertux2|UNDERTALE|Half-Life|rungameid';

Future<bool> anyGameProcessRunning() async {
  final result = await Process.run('pgrep', ['-f', _gameProcessPattern]);
  return result.exitCode == 0;
}

Future<void> killGameProcesses() async {
  await Process.run('pkill', ['-f', _gameProcessPattern]);
}

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

Future<bool> isGameProcessRunning(WidgetTester tester) async {
  var running = false;
  await tester.runAsync(() async {
    running = await anyGameProcessRunning();
  });
  return running;
}

Future<void> killGameProcessesInTest(WidgetTester tester) async {
  await tester.runAsync(killGameProcesses);
}

void main() {
  setUp(() async {
    await killGameProcesses();
    installFakeGamepads();
    BgmPlayer.instance.debugDisable();
    NavController.instance.debugReset();
    GamepadStatus.instance.debugReset();
    LauncherRouteObserver.instance.debugReset();
  });

  tearDown(() async {
    await killGameProcesses();
  });

  Future<Future<List<GameEntry>>> resolveGames(WidgetTester tester) async {
    final completer = Completer<List<GameEntry>>();
    await tester.runAsync(() async {
      final games = await const GameLoader(gamesFolder: kGamesFolder).load();
      completer.complete(games);
    });
    return completer.future;
  }

  Future<void> pumpLibrary(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    final games = await resolveGames(tester);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: Library(games: games),
      ),
    );
    await settle(tester);
  }

  Future<void> stall(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
    await settle(tester);
  }

  Future<void> expectNoLaunch(WidgetTester tester) async {
    await stall(tester);
    expect(await isGameProcessRunning(tester), isFalse,
        reason: 'a game process was started unexpectedly');
  }

  testWidgets('Enter in the games zone still launches the selected game',
      (tester) async {
    await pumpLibrary(tester);
    expect(NavController.instance.isGamesActive, isTrue);

    await pressKey(tester, LogicalKeyboardKey.arrowRight);
    expect(NavController.instance.isGamesActive, isTrue);
    expect(NavController.instance.gamesIndex, 1);

    await pressKey(tester, LogicalKeyboardKey.enter);
    await stall(tester);

    expect(await isGameProcessRunning(tester), isTrue,
        reason: 'sanity: pressing Enter on a game cover must launch a game');
    await killGameProcessesInTest(tester);
  });

  testWidgets(
      'clicking a header icon and later pressing Enter must NOT launch a game',
      (tester) async {
    await pumpLibrary(tester);
    expect(NavController.instance.isGamesActive, isTrue);

    await tester.tap(find.byIcon(Icons.local_mall));
    await settle(tester);

    expect(find.byType(StorePage), findsOneWidget,
        reason: 'clicking the store icon must open the store page');
    await expectNoLaunch(tester);

    await tester.pageBack();
    await settle(tester);

    expect(NavController.instance.isHeaderActive, isTrue,
        reason: 'clicking the header icon must put the header zone in focus');

    await pressKey(tester, LogicalKeyboardKey.enter);

    expect(find.byType(StorePage), findsOneWidget,
        reason: 'Enter after closing must re-open the store (header action)');
    await expectNoLaunch(tester);
  });

  testWidgets('navigating the header by keyboard then Enter opens the page',
      (tester) async {
    await pumpLibrary(tester);

    await pressKey(tester, LogicalKeyboardKey.arrowUp);
    expect(NavController.instance.isHeaderActive, isTrue);

    await pressKey(tester, LogicalKeyboardKey.arrowRight);

    await pressKey(tester, LogicalKeyboardKey.enter);

    expect(find.byType(StorePage), findsOneWidget,
        reason: 'Enter on the store icon must open the store page');
    await expectNoLaunch(tester);
  });
}