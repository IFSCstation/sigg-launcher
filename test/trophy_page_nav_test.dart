import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamepads/gamepads.dart';
import 'package:sigg_launcher/app_widget.dart';
import 'package:sigg_launcher/screens/home/pages/achievements_page.dart';
import 'package:sigg_launcher/screens/home/pages/game_trophies_page.dart';
import 'package:sigg_launcher/screens/home/widgets/mock_games.dart';
import 'package:sigg_launcher/services/achievement_service.dart';
import 'package:sigg_launcher/services/bgm_player.dart';
import 'package:sigg_launcher/services/game_run_state.dart';
import 'package:sigg_launcher/services/gamepad_nav.dart';
import 'package:sigg_launcher/services/nav_controller.dart';
import 'package:sigg_launcher/services/ui_sounds.dart';
import 'package:sigg_launcher/services/page_nav_controller.dart';

import 'gamepad_test_harness.dart';

class _FakeService extends AchievementService {
  _FakeService() : super(socketPath: '');

  @override
  Future<GameSnapshot> snapshot(String game, {String? username}) async {
    return GameSnapshot(
      game: game,
      user: 'test',
      earnedCount: 1,
      totalCount: 3,
      trophies: [
        Trophy(
          id: '$game-1',
          title: '$game Um',
          description: 'Primeiro troféu do $game',
          points: 50,
          earned: true,
        ),
        Trophy(
          id: '$game-2',
          title: '$game Dois',
          description: 'Segundo troféu do $game',
          points: 100,
          earned: false,
        ),
        Trophy(
          id: '$game-3',
          title: '$game Três',
          description: 'Terceiro troféu do $game',
          points: 200,
          earned: false,
        ),
      ],
    );
  }
}

const _testGames = <GameEntry>[
  GameEntry(
    'Alpha',
    'tagline',
    'genre',
    Icons.star,
    Color(0xFFFF5252),
    id: 'alpha',
  ),
  GameEntry(
    'Beta',
    'tagline',
    'genre',
    Icons.star,
    Color(0xFFFFF59D),
    id: 'beta',
  ),
];

Future<void> _settle(WidgetTester tester, [int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _press(
  WidgetTester tester,
  StreamController<GamepadEvent> ctrl,
  GamepadEvent event,
) async {
  ctrl.add(event);
  await tester.pump();
}

Future<void> _tap(
  WidgetTester tester,
  StreamController<GamepadEvent> ctrl,
  GamepadButton button,
) async {
  await _press(tester, ctrl, buttonEvent(button, 1));
  await _press(tester, ctrl, buttonEvent(button, 0));
  await _settle(tester);
}

void main() {
  setUp(() async {
    installFakeGamepads();
    BgmPlayer.instance.debugDisable();
    UiSounds.instance.debugDisable();
    NavController.instance.debugReset();
    GameRunState.instance.debugReset();
    LauncherRouteObserver.instance.debugReset();
    PageFocusHub.instance.debugReset();
  });

  Future<GamepadNavBridge> pumpTrophies(
    WidgetTester tester,
    Stream<GamepadEvent> events,
  ) async {
    final navKey = GlobalKey<NavigatorState>();
    // The app viewport is fixed at 1280x720 (GTK header shrinks it slightly);
    // the default 800x600 test surface would overflow the expanded trophy row.
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        navigatorKey: navKey,
        navigatorObservers: [LauncherRouteObserver.instance],
        home: const Scaffold(body: SizedBox()),
      ),
    );
    final bridge = GamepadNavBridge(
      events: events,
      layout: GamepadKeyLayout.sdl3,
    );
    addTearDown(bridge.dispose);
    navKey.currentState!.push(
      MaterialPageRoute(
        builder: (_) => AchievementsPage(
          games: Future.value(_testGames),
          service: _FakeService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return bridge;
  }

  testWidgets('d-pad moves game-card focus in the trophies index and A opens '
      'the focused game', (tester) async {
    final ctrl = StreamController<GamepadEvent>.broadcast();
    addTearDown(ctrl.close);
    await pumpTrophies(tester, ctrl.stream);

    expect(find.byType(AchievementsPage), findsOneWidget);
    expect(PageFocusHub.instance.active, isNotNull);
    expect(PageFocusHub.instance.active!.count, _testGames.length);
    expect(PageFocusHub.instance.active!.index, 0);

    await _tap(tester, ctrl, GamepadButton.dpadDown);
    expect(PageFocusHub.instance.active!.index, 1);

    await _tap(tester, ctrl, GamepadButton.dpadUp);
    expect(PageFocusHub.instance.active!.index, 0);

    await _tap(tester, ctrl, GamepadButton.a);
    expect(find.byType(GameTrophiesPage), findsOneWidget);
    final page = tester.widget<GameTrophiesPage>(find.byType(GameTrophiesPage));
    expect(
      page.game.title,
      'Alpha',
      reason: 'A must open the currently focused game',
    );
  });

  testWidgets('d-pad moves through the trophy row, A is inert, B returns to '
      'the previous list keeping focus', (tester) async {
    final ctrl = StreamController<GamepadEvent>.broadcast();
    addTearDown(ctrl.close);
    await pumpTrophies(tester, ctrl.stream);

    await _tap(tester, ctrl, GamepadButton.a);
    expect(find.byType(GameTrophiesPage), findsOneWidget);
    expect(PageFocusHub.instance.active!.count, 3);
    expect(PageFocusHub.instance.active!.index, 0);

    await _tap(tester, ctrl, GamepadButton.dpadRight);
    await _tap(tester, ctrl, GamepadButton.dpadRight);
    expect(PageFocusHub.instance.active!.index, 2);
    expect(
      find.byType(GameTrophiesPage),
      findsOneWidget,
      reason: 'A/rows navigate nobody; page stays open',
    );

    await _tap(tester, ctrl, GamepadButton.dpadLeft);
    expect(PageFocusHub.instance.active!.index, 1);

    await _tap(tester, ctrl, GamepadButton.b);
    expect(find.byType(GameTrophiesPage), findsNothing);
    expect(find.byType(AchievementsPage), findsOneWidget);
    expect(PageFocusHub.instance.active!.count, _testGames.length);
    expect(
      PageFocusHub.instance.active!.index,
      0,
      reason: 'the game-card focus must survive popping back',
    );
  });

  testWidgets('gamepad moves never leak into the home shell while a trophies '
      'page is open', (tester) async {
    final ctrl = StreamController<GamepadEvent>.broadcast();
    addTearDown(ctrl.close);
    await pumpTrophies(tester, ctrl.stream);

    await _tap(tester, ctrl, GamepadButton.dpadUp);
    await _tap(tester, ctrl, GamepadButton.dpadLeft);
    await _tap(tester, ctrl, GamepadButton.dpadRight);
    await _tap(tester, ctrl, GamepadButton.a);
    expect(
      NavController.instance.gamesIndex,
      0,
      reason: 'home shell must not react while the trophies screen is open',
    );
    expect(NavController.instance.isGamesActive, isTrue);

    await _tap(tester, ctrl, GamepadButton.dpadDown);
    await _tap(tester, ctrl, GamepadButton.b);
    expect(NavController.instance.gamesIndex, 0);
  });

  testWidgets('holding down repeats the move on a page list', (tester) async {
    final ctrl = StreamController<GamepadEvent>.broadcast();
    addTearDown(ctrl.close);
    await pumpTrophies(tester, ctrl.stream);

    await _press(tester, ctrl, buttonEvent(GamepadButton.dpadDown, 1));
    expect(PageFocusHub.instance.active!.index, 1);
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      PageFocusHub.instance.active!.index,
      1,
      reason: 'two games only, so the move must stop at the last card',
    );
    await _press(tester, ctrl, buttonEvent(GamepadButton.dpadDown, 0));
  });

  testWidgets('holding right repeats across the trophy row', (tester) async {
    final ctrl = StreamController<GamepadEvent>.broadcast();
    addTearDown(ctrl.close);
    await pumpTrophies(tester, ctrl.stream);

    await _tap(tester, ctrl, GamepadButton.a);
    expect(PageFocusHub.instance.active!.count, 3);

    await _press(tester, ctrl, buttonEvent(GamepadButton.dpadRight, 1));
    expect(PageFocusHub.instance.active!.index, 1);
    await tester.pump(const Duration(milliseconds: 350));
    expect(PageFocusHub.instance.active!.index, 2);
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      PageFocusHub.instance.active!.index,
      2,
      reason: 'three trophies only, so the move must stop at the last card',
    );
    await _press(tester, ctrl, buttonEvent(GamepadButton.dpadRight, 0));
  });
}
