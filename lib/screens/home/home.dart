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
import 'package:sigg_launcher/services/gamepad_nav.dart';
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
  GameEntry? _selected;
  final ScrollController _gamesScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _games = (widget.games ?? const GameLoader(gamesFolder: kGamesFolder).load())
        .then((list) {
      _gamesList = list;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          NavController.instance.setGamesCount(list.length);
        }
      });
      return list;
    });
    NavController.instance.addListener(_onNavChanged);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    NavController.instance.onActivate = _onActivate;
    _gamepadBridge = GamepadNavBridge(events: widget.gamepadEvents);
    GamepadStatus.instance.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) NavController.instance.setGamesCount(_gamesList.length);
    });
  }

  @override
  void dispose() {
    NavController.instance.removeListener(_onNavChanged);
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    if (NavController.instance.onActivate == _onActivate) {
      NavController.instance.onActivate = null;
    }
    _gamepadBridge.dispose();
    GamepadStatus.instance.stop();
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
    setState(() {});
    if (NavController.instance.isGamesActive) {
      final games = _snapshotData();
      final index = NavController.instance.gamesIndex;
      if (index >= 0 && index < games.length) {
        _selectGame(games[index]);
      }
    }
  }

  void _onActivate() {
    if (!mounted) return;
    if (NavController.instance.isHeaderActive) {
      _activateHeader(NavController.instance.headerIndex);
    } else {
      _activateGame(_selected);
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
    if (identical(game, _selected)) return;
    setState(() => _selected = game);
    final bgm = game.bgmPath;
    if (bgm != null) {
      BgmPlayer.instance.play(bgm);
    } else {
      BgmPlayer.instance.stop();
    }
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

          final selected = _selected ?? games.first;
          return LayoutBuilder(
            builder: (context, constraints) {
              final ratioHeroHeight =
                  constraints.maxWidth / heroAspectRatio;
              final maxHeroHeight =
                  (constraints.maxHeight - _gamesSectionMinHeight)
                      .clamp(0.0, double.infinity);
              final heroHeight = math.min(ratioHeroHeight, maxHeroHeight);

              return Column(
                children: [
                  SizedBox(
                    height: heroHeight,
                    width: double.infinity,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
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
                          ),
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Header(
                            active: NavController.instance.isHeaderActive,
                            focusedIndex:
                                NavController.instance.headerIndex,
                            onStoreTap: () {
                              NavController.instance.focusHeaderItem(1);
                              _openPage(const StorePage());
                            },
                            onTrophiesTap: () {
                              NavController.instance.focusHeaderItem(2);
                              _openPage(const AchievementsPage());
                            },
                            onSettingsTap: () {
                              NavController.instance.focusHeaderItem(3);
                              _openPage(const SettingsPage());
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
                              child: GamesRow(
                                games: games,
                                selected: selected,
                                active: NavController.instance.isGamesActive,
                                focusIndex: NavController.instance.gamesIndex,
                                scrollController: _gamesScroll,
                                onGameTap: _selectGame,
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
          );
        },
      ),
      ),
    );
  }
}