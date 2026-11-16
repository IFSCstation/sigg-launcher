import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigg_launcher/app_widget.dart';
import 'package:sigg_launcher/screens/home/pages/audio_settings_page.dart';
import 'package:sigg_launcher/screens/home/home.dart';
import 'package:sigg_launcher/screens/home/pages/achievements_page.dart';
import 'package:sigg_launcher/screens/home/pages/game_trophies_page.dart';
import 'package:sigg_launcher/screens/home/pages/settings_page.dart';
import 'package:sigg_launcher/screens/home/widgets/mock_games.dart';
import 'package:sigg_launcher/services/achievement_service.dart';
import 'package:sigg_launcher/services/audio_preferences.dart';
import 'package:sigg_launcher/services/bgm_player.dart';
import 'package:sigg_launcher/services/game_run_state.dart';
import 'package:sigg_launcher/services/gamepad_nav.dart';
import 'package:sigg_launcher/services/nav_controller.dart';
import 'package:sigg_launcher/services/page_nav_controller.dart';
import 'package:sigg_launcher/services/ui_sounds.dart';

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

void main() {
  setUp(() async {
    installFakeGamepads();
    AudioPreferences.instance.debugReset();
    BgmPlayer.instance.debugDisable();
    UiSounds.instance.debugDisable();
    NavController.instance.debugReset();
    GameRunState.instance.debugReset();
    GamepadStatus.instance.debugReset();
    LauncherRouteObserver.instance.debugReset();
    PageFocusHub.instance.debugReset();
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

  /// Pumps the real [Library] home shell (the only place the keyboard
  /// navigation handler lives) with an injected game list and a fake trophy
  /// daemon, so the trophies submenu is fully navigable by keyboard.
  Future<void> pumpLibrary(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        navigatorObservers: [LauncherRouteObserver.instance],
        home: Library(
          games: Future.value(_testGames),
          achievementsService: _FakeService(),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> openTrophies(WidgetTester tester) async {
    // Header zone: Perfil(0) -> Store(1) -> Troféus(2).
    await pressKey(tester, LogicalKeyboardKey.arrowUp);
    await pressKey(tester, LogicalKeyboardKey.arrowRight);
    await pressKey(tester, LogicalKeyboardKey.arrowRight);
    await pressKey(tester, LogicalKeyboardKey.enter);
    expect(find.byType(AchievementsPage), findsOneWidget);
    expect(PageFocusHub.instance.active, isNotNull);
    expect(PageFocusHub.instance.active!.count, _testGames.length);
    expect(PageFocusHub.instance.active!.index, 0);
  }

  Future<void> openSettings(WidgetTester tester) async {
    // Header zone: Perfil(0) -> Store(1) -> Troféus(2) -> Settings(3).
    await pressKey(tester, LogicalKeyboardKey.arrowUp);
    for (var i = 0; i < 3; i++) {
      await pressKey(tester, LogicalKeyboardKey.arrowRight);
    }
    await pressKey(tester, LogicalKeyboardKey.enter);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(PageFocusHub.instance.active, isNotNull);
    expect(PageFocusHub.instance.active!.count, 4);
    expect(PageFocusHub.instance.active!.index, 0);
    expect(find.text('Account'), findsNothing);
    expect(find.text('Notifications'), findsNothing);
    expect(find.text('Language & Region'), findsOneWidget);
  }

  testWidgets('keyboard arrows move the trophies index and Enter opens the '
      'focused game', (tester) async {
    await pumpLibrary(tester);
    expect(NavController.instance.isGamesActive, isTrue);

    await openTrophies(tester);

    await pressKey(tester, LogicalKeyboardKey.arrowDown);
    expect(PageFocusHub.instance.active!.index, 1);

    await pressKey(tester, LogicalKeyboardKey.arrowUp);
    expect(PageFocusHub.instance.active!.index, 0);

    await pressKey(tester, LogicalKeyboardKey.enter);
    expect(find.byType(GameTrophiesPage), findsOneWidget);
    final page = tester.widget<GameTrophiesPage>(find.byType(GameTrophiesPage));
    expect(
      page.game.title,
      'Alpha',
      reason: 'Enter must open the currently focused game',
    );
  });

  testWidgets('keyboard navigates settings and About shows app information', (
    tester,
  ) async {
    await pumpLibrary(tester);
    await openSettings(tester);

    await pressKey(tester, LogicalKeyboardKey.arrowDown);
    expect(PageFocusHub.instance.active!.index, 1);
    await pressKey(tester, LogicalKeyboardKey.arrowDown);
    expect(PageFocusHub.instance.active!.index, 2);
    await pressKey(tester, LogicalKeyboardKey.arrowDown);
    expect(PageFocusHub.instance.active!.index, 3);

    await pressKey(tester, LogicalKeyboardKey.enter);
    expect(find.text('IFSCstation'), findsOneWidget);
    expect(find.text('1.0.0+1'), findsOneWidget);
    expect(
      PageFocusHub.instance.active,
      isNull,
      reason: 'the About dialog suspends page input routing',
    );

    await pressKey(tester, LogicalKeyboardKey.escape);
    expect(find.text('IFSCstation'), findsNothing);
    expect(PageFocusHub.instance.active, isNotNull);

    await pressKey(tester, LogicalKeyboardKey.escape);
    expect(find.byType(SettingsPage), findsNothing);
  });

  testWidgets('keyboard opens Audio and adjusts live music/UI sound settings', (
    tester,
  ) async {
    await pumpLibrary(tester);
    await openSettings(tester);

    await pressKey(tester, LogicalKeyboardKey.arrowDown);
    expect(PageFocusHub.instance.active!.index, 1);
    await pressKey(tester, LogicalKeyboardKey.enter);
    expect(find.byType(AudioSettingsPage), findsOneWidget);
    expect(PageFocusHub.instance.active!.count, 4);

    // Focus the music volume row and use Left to lower it by one percent.
    await pressKey(tester, LogicalKeyboardKey.arrowDown);
    expect(PageFocusHub.instance.active!.index, 1);
    await pressKey(tester, LogicalKeyboardKey.arrowLeft);
    expect(AudioPreferences.instance.musicVolume, 0.99);
    expect(find.text('99%'), findsOneWidget);
    await pressKey(tester, LogicalKeyboardKey.arrowRight);
    expect(AudioPreferences.instance.musicVolume, 1.0);
    expect(PageFocusHub.instance.active!.index, 1);
    expect(AudioPreferences.instance.musicEnabled, isTrue);
    await pressKey(tester, LogicalKeyboardKey.enter);
    expect(
      AudioPreferences.instance.musicEnabled,
      isTrue,
      reason: 'confirming a volume slider must not toggle music',
    );

    // Focus and toggle interface sounds with Enter.
    await pressKey(tester, LogicalKeyboardKey.arrowDown);
    expect(PageFocusHub.instance.active!.index, 2);
    expect(AudioPreferences.instance.uiSoundsEnabled, isTrue);
    await pressKey(tester, LogicalKeyboardKey.enter);
    expect(AudioPreferences.instance.uiSoundsEnabled, isFalse);

    await pressKey(tester, LogicalKeyboardKey.arrowDown);
    expect(PageFocusHub.instance.active!.index, 3);
    await pressKey(tester, LogicalKeyboardKey.enter);
    expect(
      AudioPreferences.instance.uiSoundsEnabled,
      isFalse,
      reason: 'confirming a volume slider must not toggle interface sounds',
    );

    await pressKey(tester, LogicalKeyboardKey.escape);
    expect(find.byType(AudioSettingsPage), findsNothing);
    expect(PageFocusHub.instance.active!.count, 4);
    await pressKey(tester, LogicalKeyboardKey.escape);
    expect(find.byType(SettingsPage), findsNothing);
  });

  testWidgets('holding confirm/back does not duplicate or skip the Audio '
      'settings route', (tester) async {
    await pumpLibrary(tester);
    await openSettings(tester);
    await pressKey(tester, LogicalKeyboardKey.arrowDown);
    expect(PageFocusHub.instance.active!.index, 1);

    // Repeat while the push is still being scheduled: this used to queue the
    // same route a second time, making Back return to Audio again.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    expect(find.byType(AudioSettingsPage), findsOneWidget);

    // Repeated Escape should pop only the current route, not skip through the
    // settings page underneath it.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byType(AudioSettingsPage), findsNothing);
    expect(find.byType(SettingsPage), findsOneWidget);
  });

  testWidgets('keyboard moves through the trophy row, Enter is inert, and '
      'Escape returns to the index keeping focus', (tester) async {
    await pumpLibrary(tester);
    await openTrophies(tester);

    await pressKey(tester, LogicalKeyboardKey.enter);
    expect(find.byType(GameTrophiesPage), findsOneWidget);
    expect(PageFocusHub.instance.active!.count, 3);
    expect(PageFocusHub.instance.active!.index, 0);

    await pressKey(tester, LogicalKeyboardKey.arrowRight);
    await pressKey(tester, LogicalKeyboardKey.arrowRight);
    expect(PageFocusHub.instance.active!.index, 2);
    expect(
      find.byType(GameTrophiesPage),
      findsOneWidget,
      reason: 'Enter on a trophy card must not navigate away',
    );

    await pressKey(tester, LogicalKeyboardKey.arrowLeft);
    expect(PageFocusHub.instance.active!.index, 1);

    await pressKey(tester, LogicalKeyboardKey.escape);
    expect(find.byType(GameTrophiesPage), findsNothing);
    expect(find.byType(AchievementsPage), findsOneWidget);
    expect(PageFocusHub.instance.active!.count, _testGames.length);
    expect(
      PageFocusHub.instance.active!.index,
      0,
      reason: 'the game-card focus must survive popping back with Escape',
    );

    await pressKey(tester, LogicalKeyboardKey.escape);
    expect(find.byType(AchievementsPage), findsNothing);
    expect(find.byType(Library), findsOneWidget);
  });

  testWidgets('keyboard moves never leak into the home shell while a '
      'trophies page is open', (tester) async {
    await pumpLibrary(tester);
    expect(NavController.instance.isGamesActive, isTrue);
    expect(NavController.instance.gamesIndex, 0);

    await openTrophies(tester);
    // Opening via keyboard parked the home shell on the header zone first;
    // remember its state so we can prove the page never mutates it.
    final headerIndexAtOpen = NavController.instance.headerIndex;
    expect(NavController.instance.isHeaderActive, isTrue);

    await pressKey(tester, LogicalKeyboardKey.arrowUp);
    await pressKey(tester, LogicalKeyboardKey.arrowLeft);
    await pressKey(tester, LogicalKeyboardKey.arrowRight);
    await pressKey(tester, LogicalKeyboardKey.enter);
    expect(
      NavController.instance.gamesIndex,
      0,
      reason: 'home shell must not react while the trophies screen is open',
    );
    expect(NavController.instance.headerIndex, headerIndexAtOpen);

    await pressKey(tester, LogicalKeyboardKey.arrowDown);
    await pressKey(tester, LogicalKeyboardKey.escape);
    expect(find.byType(GameTrophiesPage), findsNothing);
    expect(
      NavController.instance.gamesIndex,
      0,
      reason: 'closing a subpage must leave the home shell untouched',
    );
    expect(NavController.instance.headerIndex, headerIndexAtOpen);
  });
}
