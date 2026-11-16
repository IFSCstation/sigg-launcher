import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:sigg_launcher/app_widget.dart';
import 'package:sigg_launcher/screens/home/widgets/mock_games.dart';
import 'package:sigg_launcher/services/game_launcher.dart';
import 'package:sigg_launcher/services/game_loader.dart';
import 'package:sigg_launcher/services/page_nav_controller.dart';
import 'package:sigg_launcher/services/software_category.dart';
import 'package:sigg_launcher/services/software_registry.dart';

/// Full game library reached from the "Ver todos" card on Home. Shows every
/// game in the registry as a grid of covers (same cover treatment as the home
/// row) and launches the focused one. Follows the submenu conventions: dark
/// background, transparent header, no back button (B / Escape leaves the
/// page). D-pad/keyboard input goes through a [GridPageNavController] pushed
/// onto [PageFocusHub]: row 0 is the "Todos/Jogos/Apps" category filter,
/// rows 1..n are the cover grid.
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

/// Grid content padding (the header + chips row live outside the grid, in a
/// Column above it).
const EdgeInsets _gridPadding = EdgeInsets.fromLTRB(16, 8, 16, 32);

/// Room under each cover for the title + genre lines.
const double _cardLabelHeight = 50;

class _LibraryPageState extends State<LibraryPage> {
  /// D-pad/keyboard grid: row 0 = category chips ("Todos/Jogos/Apps"), rows
  /// 1..n = rows of covers, columns derived from the viewport.
  final GridPageNavController _nav = GridPageNavController();
  final List<GlobalKey> _cellKeys = <GlobalKey>[];

  /// Row 0 chips: label + the category they filter by (null = "Todos").
  static const _filterOptions = <(String, SoftwareCategory?)>[
    ('Todos', null),
    ('Jogos', SoftwareCategory.game),
    ('Apps', SoftwareCategory.app),
  ];

  List<GameEntry> _games = const [];

  /// Packages matching the active category filter — what the grid renders.
  List<GameEntry> _visible = const [];
  SoftwareCategory? _filter; // null = "Todos"

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
    // A store install/uninstall re-scans the registry so the grid picks up
    // new software without leaving the page.
    SoftwareRegistry.instance.addListener(_onRegistryChanged);
    _load();
  }

  @override
  void dispose() {
    SoftwareRegistry.instance.removeListener(_onRegistryChanged);
    PageFocusHub.instance.pop(_nav);
    _nav.removeListener(_onNavChanged);
    _nav.onActivate = null;
    _nav.dispose();
    super.dispose();
  }

  void _onRegistryChanged() => _load();

  Future<void> _load() async {
    setState(() {
      // A registry refresh keeps the current grid up (no spinner flash);
      // only the first load has nothing to show yet.
      _loading = _games.isEmpty;
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
        _deriveVisible();
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

  /// Recomputes which entries the active category filter shows and re-keys
  /// the grid cells (fresh keys keep stale focused state off new entries).
  void _deriveVisible() {
    final filter = _filter;
    _visible = filter == null
        ? _games
        : [for (final game in _games) if (game.category == filter) game];
    _cellKeys
      ..clear()
      ..addAll(List.generate(_visible.length, (_) => GlobalKey()));
  }

  /// Filters the grid to [filter] (null = all categories). Re-derives the
  /// nav rows so Up/Down can't walk into rows that no longer exist.
  void _applyFilter(SoftwareCategory? filter) {
    if (_filter == filter) return;
    setState(() {
      _filter = filter;
      _deriveVisible();
    });
    _syncNav();
  }

  /// Rebuilds the grid dimensions for the current column count. Empty while
  /// loading/errored/empty so moves and activate become no-ops; the chips
  /// row stays navigable whenever the catalog itself has loaded, even when
  /// the filter matches nothing (so the user can pick another category).
  void _syncNav() {
    if (_loading || _error || _games.isEmpty) {
      _rows = const [];
      _nav.setRows(const []);
      return;
    }
    if (_columns <= 0) {
      // Not laid out yet: expose only the chips row so Enter works, then
      // [_syncColumns] re-runs this with the full grid.
      _rows = [_filterOptions.length];
      _nav.setRows(_rows);
      return;
    }
    final rows = <int>[
      _filterOptions.length, // Row 0: category chips.
      if (_visible.isNotEmpty)
        for (var start = 0; start < _visible.length; start += _columns)
          math.min(_columns, _visible.length - start),
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

  /// Grid-cell index for a nav position, or -1 for the chips row (row 0)
  /// and out-of-range positions. [_rows] includes the chips row at index 0.
  int _indexFor(int row, int col) {
    if (row < 1 || row >= _rows.length) return -1;
    if (col < 0 || col >= _rows[row]) return -1;
    var index = 0;
    for (var i = 1; i < row; i++) {
      index += _rows[i];
    }
    return index + col;
  }

  void _activateFocused() {
    if (_nav.row == 0) {
      final col = _nav.col.clamp(0, _filterOptions.length - 1);
      _applyFilter(_filterOptions[col].$2);
      return;
    }
    final index = _indexFor(_nav.row, _nav.col);
    if (index < 0 || index >= _visible.length) return;
    _launch(_visible[index]);
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

    // Header space (transparent AppBar overlays the body) + the category
    // chips row (grid row 0 for the D-pad), then the cover grid.
    return Column(
      children: [
        const SizedBox(height: _headerHeight),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              for (var i = 0; i < _filterOptions.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _CategoryChip(
                    label: _filterOptions[i].$1,
                    selected: _filter == _filterOptions[i].$2,
                    focused: _nav.row == 0 && _nav.col == i,
                    onTap: () {
                      _nav.focusCell(0, i);
                      _applyFilter(_filterOptions[i].$2);
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: _buildGrid()),
      ],
    );
  }

  Widget _buildGrid() {
    // A filter with no matches: keep the chips on screen (they live above
    // this area) so the user can pick another category.
    if (_visible.isEmpty) return const _EmptyCategory();

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
          itemCount: _visible.length,
          itemBuilder: (context, index) {
            final game = _visible[index];
            // Row 0 of the nav grid is the chips row, so grid row = index
            // row + 1.
            final navRow = index ~/ columns + 1;
            return KeyedSubtree(
              key: _cellKeys[index],
              child: _LibraryGameCard(
                game: game,
                width: cardWidth,
                focused: _nav.row == navRow && _nav.col == index % columns,
                // Tap keeps the home-row behavior (select) and launches the
                // game, while moving the D-pad cursor to the tapped card.
                onTap: () {
                  _nav.focusCell(navRow, index % columns);
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

/// Rounded filter chip for the "Todos | Jogos | Apps" row (grid row 0).
/// [selected] shows the active category; [focused] mirrors hover so D-pad
/// selection reads the same as mouse hover (same contract as the cards).
class _CategoryChip extends StatefulWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.focused,
    this.onTap,
  });

  final String label;
  final bool selected;
  final bool focused;
  final VoidCallback? onTap;

  @override
  State<_CategoryChip> createState() => _CategoryChipState();
}

class _CategoryChipState extends State<_CategoryChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || widget.focused;
    final textTheme = Theme.of(context).textTheme;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: active ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: Colors.white.withValues(
                alpha: widget.selected ? 0.16 : 0.05,
              ),
              border: Border.all(
                color: active
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.28),
                width: active ? 2 : 1,
              ),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.22),
                        blurRadius: 14,
                      ),
                    ]
                  : null,
            ),
            child: Text(
              widget.label,
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: widget.selected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.65),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when the category filter matches nothing: the chips row stays on
/// screen (it lives above this area) so the D-pad user can pick another
/// category.
class _EmptyCategory extends StatelessWidget {
  const _EmptyCategory();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.filter_alt_off, size: 56, color: colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            'Nenhum item nesta categoria.',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Escolha outra categoria acima.',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
