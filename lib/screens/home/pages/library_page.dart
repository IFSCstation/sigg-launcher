import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sigg_launcher/app_widget.dart';
import 'package:sigg_launcher/screens/home/widgets/mock_games.dart';
import 'package:sigg_launcher/services/game_launcher.dart';
import 'package:sigg_launcher/services/game_loader.dart';
import 'package:sigg_launcher/services/page_nav_controller.dart';

/// Full game library reached from the "Ver todos" card on Home. Shows every
/// game in the registry as a grid of covers (same cover treatment as the home
/// row) and launches the focused one. Follows the submenu conventions: dark
/// background, transparent header, no back button (B / Escape leaves the
/// page). D-pad/keyboard input goes through a [GridPageNavController] pushed
/// onto [PageFocusHub].
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, this.games, this.onLaunch});

  /// Pre-computed game list (injected by Home for tests/consistency); when
  /// null the page loads from the [kSoftwareFolder] registry itself.
  final Future<List<GameEntry>>? games;

  /// Test seam: replaces [GameLauncher.launch] so widget tests can assert the
  /// focused game without spawning a real process.
  final ValueChanged<GameEntry>? onLaunch;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

const double _headerHeight = 96;
const double _cardMinWidth = 150;
const double _gridGap = 16;
const EdgeInsets _gridPadding = EdgeInsets.fromLTRB(
  16,
  _headerHeight + 8,
  16,
  32,
);

/// Room under each cover for the title + genre lines.
const double _cardLabelHeight = 50;

class _LibraryPageState extends State<LibraryPage> {
  /// D-pad/keyboard grid: rows of covers, columns derived from the viewport.
  final GridPageNavController _nav = GridPageNavController();
  final List<GlobalKey> _cellKeys = <GlobalKey>[];

  List<GameEntry> _games = const [];
  List<int> _rows = const [];
  int _columns = 0;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    PageFocusHub.instance.push(_nav);
    _nav.onActivate = _activateFocused;
    _nav.addListener(_onNavChanged);
    _load();
  }

  @override
  void dispose() {
    PageFocusHub.instance.pop(_nav);
    _nav.removeListener(_onNavChanged);
    _nav.onActivate = null;
    _nav.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final games = await (widget.games ??
          GameLoader(
            gamesFolder: kGamesFolder,
            appsFolder: kAppsFolder,
          ).load());
      if (!mounted) return;
      setState(() {
        _loading = false;
        _games = games;
        _cellKeys
          ..clear()
          ..addAll(List.generate(games.length, (_) => GlobalKey()));
      });
      _syncNav();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  /// Rebuilds the grid dimensions for the current column count. Empty while
  /// loading/errored/empty so moves and activate become no-ops.
  void _syncNav() {
    if (_loading || _error || _games.isEmpty || _columns <= 0) {
      _rows = const [];
      _nav.setRows(const []);
      return;
    }
    final rows = <int>[
      for (var start = 0; start < _games.length; start += _columns)
        math.min(_columns, _games.length - start),
    ];
    _rows = rows;
    _nav.setRows(rows);
  }

  /// Column count comes from the actual viewport, so the D-pad grid matches
  /// what is painted. Deferred to after the frame because [setRows] notifies
  /// listeners (which rebuild the page).
  void _syncColumns(int columns) {
    if (columns == _columns) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || columns == _columns) return;
      setState(() => _columns = columns);
      _syncNav();
    });
  }

  void _onNavChanged() {
    if (!mounted) return;
    setState(() {});
    // Defer until after the rebuild so the focused cell is laid out; calling
    // ensureVisible synchronously can hit an unlaid-out RenderBox.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = _indexFor(_nav.row, _nav.col);
      if (index < 0 || index >= _cellKeys.length) return;
      final ctx = _cellKeys[index].currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  int _indexFor(int row, int col) {
    if (row < 0 || row >= _rows.length) return -1;
    if (col < 0 || col >= _rows[row]) return -1;
    var index = 0;
    for (var i = 0; i < row; i++) {
      index += _rows[i];
    }
    return index + col;
  }

  void _activateFocused() {
    final index = _indexFor(_nav.row, _nav.col);
    if (index < 0 || index >= _games.length) return;
    _launch(_games[index]);
  }

  void _launch(GameEntry game) {
    final onLaunch = widget.onLaunch;
    if (onLaunch != null) {
      onLaunch(game);
      return;
    }
    GameLauncher.launch(context, game);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kScreenBackground,
      // Body paints under the transparent AppBar so the header reads as a
      // floating see-through overlay over scrolling content.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        toolbarHeight: _headerHeight,
        title: const _LibraryHeader(),
        // Convention: submenus have no back button (B-back / Escape).
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error) return _LibraryUnavailable(onRetry: _load);
    if (_games.isEmpty) return const _EmptyLibrary();

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = math.max(
          1,
          ((constraints.maxWidth - _gridPadding.horizontal + _gridGap) /
                  (_cardMinWidth + _gridGap))
              .floor(),
        );
        _syncColumns(columns);
        final cardWidth =
            (constraints.maxWidth -
                _gridPadding.horizontal -
                (columns - 1) * _gridGap) /
            columns;
        final cardHeight = cardWidth / coverAspectRatio + _cardLabelHeight;

        return GridView.builder(
          padding: _gridPadding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: _gridGap,
            mainAxisSpacing: _gridGap,
            mainAxisExtent: cardHeight,
          ),
          itemCount: _games.length,
          itemBuilder: (context, index) {
            final game = _games[index];
            return KeyedSubtree(
              key: _cellKeys[index],
              child: _LibraryGameCard(
                game: game,
                width: cardWidth,
                focused:
                    _nav.row == index ~/ columns && _nav.col == index % columns,
                // Tap keeps the home-row behavior (select) and launches the
                // game, while moving the D-pad cursor to the tapped card.
                onTap: () {
                  _nav.focusCell(index ~/ columns, index % columns);
                  _launch(game);
                },
              ),
            );
          },
        );
      },
    );
  }
}

/// Header: big "Biblioteca" title, matching the trophies/repositories headers.
class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 0, 0),
      child: Text(
        'Biblioteca',
        style: textTheme.headlineMedium?.copyWith(
          fontSize: 38,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Portrait cover card: same gradient/art, hover/focus border+glow+scale as
/// the home `GameCover`, plus the genre line used by the store cards.
class _LibraryGameCard extends StatefulWidget {
  const _LibraryGameCard({
    required this.game,
    required this.width,
    required this.focused,
    required this.onTap,
  });

  final GameEntry game;

  /// Laid-out card width, used to size the image decode cache.
  final double width;
  final bool focused;
  final VoidCallback onTap;

  @override
  State<_LibraryGameCard> createState() => _LibraryGameCardState();
}

class _LibraryGameCardState extends State<_LibraryGameCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final game = widget.game;
    final active = _hovered || widget.focused;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = math.max(1, (widget.width * devicePixelRatio).round());
    final cacheHeight = math.max(
      1,
      ((widget.width / coverAspectRatio) * devicePixelRatio).round(),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: active ? 1.04 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: active
                        ? Border.all(color: game.color, width: 3)
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                      if (active)
                        BoxShadow(
                          color: game.color.withValues(alpha: 0.5),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                game.color,
                                Color.lerp(game.color, Colors.black, 0.55)!,
                              ],
                            ),
                          ),
                        ),
                        if (game.coverPath != null)
                          Image.file(
                            File(game.coverPath!),
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            cacheWidth: cacheWidth,
                            cacheHeight: cacheHeight,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (context, error, stackTrace) =>
                                const SizedBox.shrink(),
                          )
                        else if (game.imageAsset != null)
                          Image.asset(
                            game.imageAsset!,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            cacheWidth: cacheWidth,
                            cacheHeight: cacheHeight,
                            filterQuality: FilterQuality.medium,
                          )
                        else if (game.imageUrl != null)
                          Image.network(
                            game.imageUrl!,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            cacheWidth: cacheWidth,
                            cacheHeight: cacheHeight,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (context, error, stackTrace) =>
                                const SizedBox.shrink(),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                game.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                game.genre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.38),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videogame_asset_off, size: 72, color: colorScheme.outline),
          const SizedBox(height: 20),
          Text(
            'Nenhum jogo encontrado na pasta "games".',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Adicione jogos ao registro para vê-los aqui.',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryUnavailable extends StatelessWidget {
  const _LibraryUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 56, color: colorScheme.outline),
          const SizedBox(height: 16),
          const Text('Não foi possível carregar a biblioteca.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}
