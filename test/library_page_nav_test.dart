import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamepads/gamepads.dart';
import 'package:sigg_launcher/app_widget.dart';
import 'package:sigg_launcher/screens/home/home.dart';
import 'package:sigg_launcher/screens/home/pages/library_page.dart';
import 'package:sigg_launcher/screens/home/widgets/mock_games.dart';
import 'package:sigg_launcher/services/bgm_player.dart';
import 'package:sigg_launcher/services/game_run_state.dart';
import 'package:sigg_launcher/services/gamepad_nav.dart';
import 'package:sigg_launcher/services/nav_controller.dart';
import 'package:sigg_launcher/services/page_nav_controller.dart';
import 'package:sigg_launcher/services/software_category.dart';
import 'package:sigg_launcher/services/ui_sounds.dart';

import 'gamepad_test_harness.dart';

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

/// Enough entries to wrap the grid into three rows at 800px wide.
List<GameEntry> _gridGames() => [
  for (var i = 0; i < 9; i++)
    GameEntry(
      'Game $i',
      'tagline',
      'genre',
      Icons.star,
      Color(0xFF000000 + i * 0x111111),
      id: 'game-$i',
    ),
];

Future<void> _settle(WidgetTester tester, [int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _pressKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await _settle(tester);
}

void main() {
  setUp(() async {
    installFakeGamepads();
    BgmPlayer.instance.debugDisable();
    UiSounds.instance.debugDisable();
    NavController.instance.debugReset();
    GameRunState.instance.debugReset();
    GamepadStatus.instance.debugReset();
    LauncherRouteObserver.instance.debugReset();
    PageFocusHub.instance.debugReset();
  });

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        navigatorObservers: [LauncherRouteObserver.instance],
        home: Library(games: Future.value(_testGames)),
      ),
    );
    await _settle(tester);
  }

  testWidgets('keyboard reaches the "Ver todos" card and opens the library '
      'page', (tester) async {
    await pumpHome(tester);
    expect(NavController.instance.gamesCount, _testGames.length + 1);

    // Two games + the trailing "Ver todos" cell.
    await _pressKey(tester, LogicalKeyboardKey.arrowRight);
    await _pressKey(tester, LogicalKeyboardKey.arrowRight);
    expect(NavController.instance.gamesIndex, _testGames.length);

    await _pressKey(tester, LogicalKeyboardKey.enter);
    expect(find.byType(LibraryPage), findsOneWidget);
    expect(find.text('Biblioteca'), findsOneWidget);
    expect(find.text('2 jogos'), findsNothing);
    expect(PageFocusHub.instance.active, isA<GridPageNavController>());

    await _pressKey(tester, LogicalKeyboardKey.escape);
    expect(find.byType(LibraryPage), findsNothing);
    expect(
      NavController.instance.gamesIndex,
      _testGames.length,
      reason: 'closing the page must leave the home cursor on "Ver todos"',
    );
  });

  testWidgets('tapping "Ver todos" opens the library page and parks home '
      'focus on the card', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await _settle(tester);

    expect(find.byType(LibraryPage), findsOneWidget);
    expect(NavController.instance.gamesIndex, _testGames.length);
  });

  testWidgets('keyboard moves through the library grid and Enter launches '
      'the focused game', (tester) async {
    await pumpHome(tester);
    await _pressKey(tester, LogicalKeyboardKey.arrowRight);
    await _pressKey(tester, LogicalKeyboardKey.arrowRight);
    await _pressKey(tester, LogicalKeyboardKey.enter);
    expect(find.byType(LibraryPage), findsOneWidget);

    // Row 0 is the category chips; down into the grid, then across to Beta.
    await _pressKey(tester, LogicalKeyboardKey.arrowDown);
    await _pressKey(tester, LogicalKeyboardKey.arrowRight);
    final grid = PageFocusHub.instance.active! as GridPageNavController;
    expect(grid.row, 1);
    expect(grid.col, 1);

    // Mock games have no executable, so the launcher reports it instead of
    // spawning a process — proof that Enter reached the focused card.
    await _pressKey(tester, LogicalKeyboardKey.enter);
    expect(
      find.text('Nenhum executável configurado para "Beta".'),
      findsOneWidget,
    );
  });

  testWidgets('library grid rows and columns follow the viewport and clamp '
      'at the edges', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    GameEntry? launched;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: LibraryPage(
          games: Future.value(_gridGames()),
          onLaunch: (game) => launched = game,
        ),
      ),
    );
    await _settle(tester);

    final grid = PageFocusHub.instance.active;
    expect(grid, isA<GridPageNavController>());
    final nav = grid! as GridPageNavController;
    // Row 0 = category chips (3 cells).
    expect(nav.row, 0);
    expect(nav.col, 0);

    // 800px wide => 4 covers per row; 9 games => grid rows [4, 4, 1] at
    // nav rows 1..3.
    nav.moveDown();
    await tester.pump();
    expect(nav.row, 1);

    for (var i = 0; i < 3; i++) {
      nav.moveRight();
    }
    await tester.pump();
    expect(nav.col, 3);
    nav.moveRight();
    expect(nav.col, 3, reason: 'no wrap at the row end');

    nav.moveDown();
    await tester.pump();
    expect(nav.row, 2);
    expect(nav.col, 3);

    // The last row holds a single cover, so the column clamps to it.
    nav.moveDown();
    await tester.pump();
    expect(nav.row, 3);
    expect(nav.col, 0);
    nav.moveRight();
    expect(nav.col, 0, reason: 'the short last row has nowhere to go');
    nav.moveDown();
    expect(nav.row, 3, reason: 'no wrap past the last row');

    nav.moveUp();
    await tester.pump();
    expect(nav.row, 2);
    expect(nav.col, 0);

    nav.activate();
    expect(launched?.title, 'Game 4');
  });

  testWidgets('tapping a library card launches it and moves the D-pad cursor', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    GameEntry? launched;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: LibraryPage(
          games: Future.value(_testGames),
          onLaunch: (game) => launched = game,
        ),
      ),
    );
    await _settle(tester);

    final nav = PageFocusHub.instance.active! as GridPageNavController;
    nav.moveDown(); // Row 0 is the chips; into the grid.
    nav.moveRight();
    await tester.pump();
    expect(nav.row, 1);
    expect(nav.col, 1);

    await tester.tap(find.text('Alpha'));
    await tester.pump();
    expect(launched?.title, 'Alpha');
    expect(nav.row, 1);
    expect(nav.col, 0);
  });

  testWidgets('gamepad d-pad/A drive the library page and B backs out', (
    tester,
  ) async {
    final ctrl = StreamController<NormalizedGamepadEvent>.broadcast();
    addTearDown(ctrl.close);
    final navKey = GlobalKey<NavigatorState>();
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    GameEntry? launched;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        navigatorKey: navKey,
        navigatorObservers: [LauncherRouteObserver.instance],
        home: const Scaffold(body: SizedBox()),
      ),
    );
    final bridge = GamepadNavBridge(events: ctrl.stream);
    addTearDown(bridge.dispose);
    navKey.currentState!.push(
      MaterialPageRoute(
        builder: (_) => LibraryPage(
          games: Future.value(_testGames),
          onLaunch: (game) => launched = game,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nav = PageFocusHub.instance.active! as GridPageNavController;
    expect(nav.row, 0);
    expect(nav.col, 0);

    // Row 0 = chips: down into the grid first, then right to Beta.
    ctrl.add(buttonEvent(GamepadButton.dpadDown, 1));
    await tester.pump();
    ctrl.add(buttonEvent(GamepadButton.dpadDown, 0));
    await _settle(tester);
    expect(nav.row, 1);

    ctrl.add(buttonEvent(GamepadButton.dpadRight, 1));
    await tester.pump();
    ctrl.add(buttonEvent(GamepadButton.dpadRight, 0));
    await _settle(tester);
    expect(nav.col, 1);

    ctrl.add(buttonEvent(GamepadButton.a, 1));
    await tester.pump();
    ctrl.add(buttonEvent(GamepadButton.a, 0));
    await _settle(tester);
    expect(launched?.title, 'Beta');

    ctrl.add(buttonEvent(GamepadButton.b, 1));
    await tester.pump();
    ctrl.add(buttonEvent(GamepadButton.b, 0));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryPage), findsNothing);
    expect(PageFocusHub.instance.active, isNull);
  });

  testWidgets('the library controller pops from the hub when the page closes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: LibraryPage(games: Future.value(_testGames)),
      ),
    );
    await _settle(tester);
    expect(PageFocusHub.instance.active, isNotNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(PageFocusHub.instance.active, isNull);
  });

  testWidgets('category chips filter the library grid (row 0 of the D-pad '
      'grid)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final mixed = <GameEntry>[
      const GameEntry(
        'Alpha',
        'tagline',
        'genre',
        Icons.star,
        Color(0xFFFF5252),
        id: 'alpha',
      ),
      const GameEntry(
        'Calc',
        'tagline',
        'utility',
        Icons.calculate,
        Color(0xFF69F0AE),
        id: 'calc',
        category: SoftwareCategory.app,
      ),
    ];
    GameEntry? launched;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: LibraryPage(
          games: Future.value(mixed),
          onLaunch: (game) => launched = game,
        ),
      ),
    );
    await _settle(tester);

    final nav = PageFocusHub.instance.active! as GridPageNavController;
    expect(nav.row, 0);
    expect(find.text('Todos'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Calc'), findsOneWidget);

    // Row 0, col 2 = "Apps": only the app survives.
    nav.moveRight();
    nav.moveRight();
    expect(nav.col, 2);
    nav.activate();
    await _settle(tester);
    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Calc'), findsOneWidget);
    // The grid re-derived to a single cell (row 1); Enter launches the app.
    expect(nav.row, 0, reason: 'focus stays on the active chip');
    nav.moveDown();
    expect(nav.row, 1);
    expect(nav.col, 0);
    nav.activate();
    expect(launched?.id, 'calc');

    // "Todos" (col 0) brings everything back.
    nav.moveUp();
    nav.moveLeft();
    nav.moveLeft();
    expect(nav.col, 0);
    nav.activate();
    await _settle(tester);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Calc'), findsOneWidget);
  });
}
