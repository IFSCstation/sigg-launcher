import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gamepads/gamepads.dart';
import 'package:sigg_launcher/screens/home/pages/achievements_page.dart';
import 'package:sigg_launcher/screens/home/pages/settings_page.dart';
import 'package:sigg_launcher/screens/home/pages/store_page.dart';
import 'package:sigg_launcher/screens/home/widgets/games_row.dart';
import 'package:sigg_launcher/screens/home/widgets/header.dart';
import 'package:sigg_launcher/screens/home/widgets/hero_banner.dart';
import 'package:sigg_launcher/screens/home/widgets/mock_games.dart';
import 'package:sigg_launcher/screens/home/widgets/user_switcher.dart';
import 'package:sigg_launcher/services/bgm_player.dart';
import 'package:sigg_launcher/services/game_launcher.dart';
import 'package:sigg_launcher/services/game_loader.dart';
import 'package:sigg_launcher/services/game_run_state.dart';
import 'package:sigg_launcher/services/gamepad_nav.dart';
import 'package:sigg_launcher/services/image_cache.dart';
import 'package:sigg_launcher/services/nav_controller.dart';

const double _gamesSectionMinHeight = 240;

class Library extends StatefulWidget {
  const Library({super.key, this.games, this.gamepadEvents});

  /// Pre-computed game list. Used by tests to inject a future resolved
  /// outside of Flutter's fake-async test zone; when null the screen loads
  /// games from the [kGamesFolder] itself.
  final Future<List<GameEntry>>? games;

  /// Gamepad event source. Used by tests to drive navigation with synthetic
  /// events; when null the real [Gamepads.normalizedEvents] stream is used.
  final Stream<NormalizedGamepadEvent>? gamepadEvents;

  @override
  State<Library> createState() => _LibraryState();
}

class _LibraryState extends State<Library> {
  late final Future<List<GameEntry>> _games;
  late final GamepadNavBridge _gamepadBridge;
  List<GameEntry> _gamesList = const [];
  final ValueNotifier<GameEntry?> _selected = ValueNotifier<GameEntry?>(null);
  final ValueNotifier<bool> _gamesActive = ValueNotifier<bool>(true);
  final ValueNotifier<int> _gamesIndex = ValueNotifier<int>(0);
  final ValueNotifier<bool> _headerActive = ValueNotifier<bool>(false);
  final ValueNotifier<int> _headerIndex = ValueNotifier<int>(0);
  bool _wasGameRunning = false;
  Size _heroSize = Size.zero;
  final ScrollController _gamesScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _games = (widget.games ??
            GameLoader(gamesFolder: kGamesFolder).load())
        .then((list) {
      _gamesList = list;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          NavController.instance.setGamesCount(list.length);
          if (list.isNotEmpty) _preloadAdjacent(list.first);
        }
      });
      return list;
    });
    NavController.instance.addListener(_onNavChanged);
    GameRunState.instance.addListener(_onRunStateChanged);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    NavController.instance.onActivate = _onActivate;
    _gamepadBridge = GamepadNavBridge(events: widget.gamepadEvents);
    GamepadStatus.instance.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) NavController.instance.setGamesCount(_gamesList.length);
    });
    _headerActive.value = NavController.instance.isHeaderActive;
    _headerIndex.value = NavController.instance.headerIndex;
  }

  @override
  void dispose() {
    NavController.instance.removeListener(_onNavChanged);
    GameRunState.instance.removeListener(_onRunStateChanged);
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    if (NavController.instance.onActivate == _onActivate) {
      NavController.instance.onActivate = null;
    }
    _gamepadBridge.dispose();
    GamepadStatus.instance.stop();
    _selected.dispose();
    _gamesActive.dispose();
    _gamesIndex.dispose();
    _headerActive.dispose();
    _headerIndex.dispose();
    _gamesScroll.dispose();
    super.dispose();
  }

  bool _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return false;
    }
    // Only drive navigation while Home is the active route; a pushed page
    // (store/settings/profile) must not leak keys into the launcher.
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return false;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        NavController.instance.moveUp();
        return true;
      case LogicalKeyboardKey.arrowDown:
        NavController.instance.moveDown();
        return true;
      case LogicalKeyboardKey.arrowLeft:
        NavController.instance.moveLeft();
        return true;
      case LogicalKeyboardKey.arrowRight:
        NavController.instance.moveRight();
        return true;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
      case LogicalKeyboardKey.space:
        NavController.instance.activate();
        return true;
      default:
        return false;
    }
  }

  void _onNavChanged() {
    if (!mounted) return;
    _gamesActive.value = NavController.instance.isGamesActive;
    _gamesIndex.value = NavController.instance.gamesIndex;
    _headerActive.value = NavController.instance.isHeaderActive;
    _headerIndex.value = NavController.instance.headerIndex;
    if (NavController.instance.isGamesActive) {
      final games = _snapshotData();
      final index = NavController.instance.gamesIndex;
      if (index >= 0 && index < games.length) {
        _selectGame(games[index]);
      }
    }
  }

  void _onRunStateChanged() {
    if (!mounted) return;
    final running = GameRunState.instance.running;
    if (_wasGameRunning && !running) {
      _resumeSelectedBgm();
    }
    _wasGameRunning = running;
  }

  void _resumeSelectedBgm() {
    final selected = _selected.value;
    if (selected == null) return;
    final bgm = selected.bgmPath;
    if (bgm != null) {
      BgmPlayer.instance.play(bgm);
    } else {
      BgmPlayer.instance.stop();
    }
  }

  void _onActivate() {
    if (!mounted) return;
    if (NavController.instance.isHeaderActive) {
      _activateHeader(NavController.instance.headerIndex);
    } else {
      _activateGame(_selected.value);
    }
  }

  void _activateHeader(int index) {
    switch (index) {
      case 0:
        showUserSwitcher(context);
        break;
      case 1:
        _openPage(const StorePage());
        break;
      case 2:
        _openPage(const AchievementsPage());
        break;
      case 3:
        _openPage(const SettingsPage());
        break;
    }
  }

  void _activateGame(GameEntry? game) {
    if (game == null) return;
    GameLauncher.launch(context, game);
  }

  List<GameEntry> _snapshotData() => _gamesList;

  void _selectGame(GameEntry game) {
    if (identical(_selected.value, game)) return;
    final previous = _selected.value;
    _selected.value = game;
    _preloadAdjacent(game);
    final prevHero = previous?.heroPath;
    if (prevHero != null &&
        prevHero != game.heroPath &&
        !_isNeighbor(previous, game)) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        PaintingBinding.instance.imageCache.evict(FileImage(File(prevHero)));
      });
    }
    final bgm = game.bgmPath;
    if (bgm != null) {
      BgmPlayer.instance.play(bgm);
    } else {
      BgmPlayer.instance.stop();
    }
  }

  bool _isNeighbor(GameEntry? previous, GameEntry game) {
    final games = _gamesList;
    if (games.isEmpty || previous == null) return false;
    final prevIndex = games.indexOf(previous);
    final index = games.indexOf(game);
    if (prevIndex < 0 || index < 0) return false;
    return (prevIndex - index).abs() <= 2;
  }

  void _preloadAdjacent(GameEntry game) {
    final games = _gamesList;
    if (games.isEmpty || _heroSize == Size.zero) return;
    final index = games.indexOf(game);
    if (index < 0) return;
    ImagePreloader.preloadHeroes(context, games, index, _heroSize, range: 2);
  }

  void _openPage(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ExcludeFocus(
        child: FutureBuilder<List<GameEntry>>(
          future: _games,
          builder: (context, snapshot) {
            final games = snapshot.data ?? mockGames;
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (games.isEmpty) {
              return const Center(
                child: Text('Nenhum jogo encontrado na pasta "games".'),
              );
            }

            return _FadeIn(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final ratioHeroHeight =
                      constraints.maxWidth / heroAspectRatio;
                  final maxHeroHeight =
                      (constraints.maxHeight - _gamesSectionMinHeight)
                          .clamp(0.0, double.infinity);
                  final heroHeight = math.min(ratioHeroHeight, maxHeroHeight);
                  _heroSize = Size(constraints.maxWidth, heroHeight);

                  return Column(
                    children: [
                      SizedBox(
                        height: heroHeight,
                        width: double.infinity,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ListenableBuilder(
                                listenable: _selected,
                                builder: (context, _) {
                                  final selected =
                                      _selected.value ?? games.first;
                                  return AnimatedSwitcher(
                                    duration:
                                        const Duration(milliseconds: 300),
                                    switchInCurve: Curves.easeOut,
                                    switchOutCurve: Curves.easeInOut,
                                    transitionBuilder: (child, animation) {
                                      return FadeTransition(
                                        opacity: animation,
                                        child: child,
                                      );
                                    },
                                    child: KeyedSubtree(
                                      key: ObjectKey(selected),
                                      child: HeroBanner(game: selected),
                                    ),
                                  );
                                },
                              ),
                            ),
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: ListenableBuilder(
                                listenable: Listenable.merge(
                                    [_headerActive, _headerIndex]),
                                builder: (context, _) {
                                  return Header(
                                    active: _headerActive.value,
                                    focusedIndex: _headerIndex.value,
                                    onStoreTap: () {
                                      NavController.instance
                                          .focusHeaderItem(1);
                                      _openPage(const StorePage());
                                    },
                                    onTrophiesTap: () {
                                      NavController.instance
                                          .focusHeaderItem(2);
                                      _openPage(const AchievementsPage());
                                    },
                                    onSettingsTap: () {
                                      NavController.instance
                                          .focusHeaderItem(3);
                                      _openPage(const SettingsPage());
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: ListenableBuilder(
                                    listenable: Listenable.merge(
                                        [_gamesActive, _gamesIndex, _selected]),
                                    builder: (context, _) {
                                      return GamesRow(
                                        games: games,
                                        selected:
                                            _selected.value ?? games.first,
                                        active: _gamesActive.value,
                                        focusIndex: _gamesIndex.value,
                                        scrollController: _gamesScroll,
                                        onGameTap: _selectGame,
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FadeIn extends StatefulWidget {
  const _FadeIn({required this.child});

  final Widget child;

  @override
  State<_FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<_FadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  )..forward();
  late final Animation<double> _opacity =
      CurvedAnimation(parent: _controller, curve: Curves.easeOut);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _opacity, child: widget.child);
  }
}