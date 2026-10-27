import 'package:flutter/material.dart';
import 'package:sigg_launcher/app_widget.dart';
import 'package:sigg_launcher/screens/home/pages/repositories_page.dart';
import 'package:sigg_launcher/screens/home/widgets/mock_games.dart';
import 'package:sigg_launcher/screens/home/widgets/trophy_widgets.dart';
import 'package:sigg_launcher/services/page_nav_controller.dart';
import 'package:sigg_launcher/services/repository_service.dart';

/// IFSCstation Store: a Cydia/Sileo-style package store where every game/app
/// is free. The catalog comes from user-added JSON repositories (sources) —
/// see [RepositoryService]. Visual language mirrors the rest of the shell:
/// dark background, no AppBar, a featured banner using the home hero treatment
/// (color gradient + `HeroScrimPainter` scrim + white CTA), and cover rows
/// that copy the home `GameCover` card. Installing packages is not
/// implemented yet; CTAs only hint at it.
class StorePage extends StatefulWidget {
  const StorePage({super.key, this.service, this.packages});

  /// Test seam: pre-computed package list; when null the page loads from
  /// the repositories listed in the service's manifest.
  final Future<List<RepoPackage>>? packages;

  /// Test seam: the repository client. Defaults to the real one.
  final RepositoryService? service;

  @override
  State<StorePage> createState() => _StorePageState();
}

const double _coverWidth = 150;
const double _coverHeight = _coverWidth / coverAspectRatio;

/// Title + version lines under each cover (8 gap + title + version).
const double _coverLabelHeight = 50;

class _StorePageState extends State<StorePage> {
  /// D-pad/keyboard grid: row 0 = the featured banner (single cell), rows
  /// 1..n = the section cover rows. Wired to both the gamepad bridge and
  /// the Launcher's keyboard handler via [PageFocusHub].
  final GridPageNavController _nav = GridPageNavController();
  final List<GlobalKey> _rowKeys = <GlobalKey>[];
  final List<List<GlobalKey>> _cellKeys = <List<GlobalKey>>[];

  bool _loading = true;
  bool _error = false;
  List<RepoPackage> _packages = const [];

  @override
  void initState() {
    super.initState();
    PageFocusHub.instance.push(_nav);
    _nav.onActivate = _onActivate;
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

  void _onNavChanged() {
    if (!mounted) return;
    setState(() {});
    // Defer until after the rebuild so the focused cell is laid out; calling
    // ensureVisible synchronously can hit an unlaid-out RenderBox.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final row = _nav.row;
      final col = _nav.col;
      if (row < 0 || row >= _rowKeys.length) return;
      final rowCtx = _rowKeys[row].currentContext;
      if (rowCtx != null) {
        Scrollable.ensureVisible(
          rowCtx,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
      if (row < _cellKeys.length && col < _cellKeys[row].length) {
        final cellCtx = _cellKeys[row][col].currentContext;
        if (cellCtx != null) {
          Scrollable.ensureVisible(
            cellCtx,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  /// A / Start / Enter on the focused card: same action as tapping it. On
  /// the empty/error states it mirrors the visible CTA (open the sources
  /// manager / retry) so gamepad users aren't stranded without a mouse.
  void _onActivate() {
    if (_packages.isEmpty) {
      if (_loading) return;
      if (_error) {
        _load();
      } else {
        _openRepos();
      }
      return;
    }
    if (_nav.row == 0) {
      _showInstallSoon();
      return;
    }
    final sectionIndex = _nav.row - 1;
    if (sectionIndex < 0 || sectionIndex >= _sections.length) return;
    final items = _sections[sectionIndex].items;
    if (_nav.col < 0 || _nav.col >= items.length) return;
    _showInstallSoon();
  }

  List<_StoreSection> _sections = const [];

  void _load() {
    setState(() {
      _loading = true;
      _error = false;
    });
    final injected = widget.packages;
    if (injected != null) {
      injected
          .then((packages) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _packages = packages;
            });
            _syncNav();
          })
          .catchError((Object _) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _error = true;
            });
            _syncNav();
          });
      return;
    }
    final service = widget.service ?? RepositoryService();
    service
        .loadAll()
        .then((repos) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _packages = [for (final repo in repos) ...repo.packages];
          });
          _syncNav();
        })
        .catchError((Object _) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = true;
          });
          _syncNav();
        });
  }

  /// Re-derives sections + grid dimensions after a (re)load. Empty while
  /// loading/errored/empty so moves and activate become no-ops.
  void _syncNav() {
    if (_loading || _error || _packages.isEmpty) {
      _sections = const [];
      _nav.setRows(const []);
      return;
    }
    _sections = _sectionsOf(_packages);
    _rowKeys
      ..clear()
      ..addAll(List.generate(_sections.length + 1, (_) => GlobalKey()));
    _cellKeys
      ..clear()
      ..add(<GlobalKey>[GlobalKey()]); // Featured row: one cell.
    for (final section in _sections) {
      _cellKeys.add([
        for (var i = 0; i < section.items.length; i++) GlobalKey(),
      ]);
    }
    _nav.setRows([
      1, // Featured row.
      for (final section in _sections) section.items.length,
    ]);
  }

  Future<void> _openRepos() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RepositoriesPage(service: widget.service),
      ),
    );
    // Reload so packages added/removed in the repos page show up on return.
    if (mounted) _load();
  }

  void _showInstallSoon() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('A instalação de pacotes chega em breve.'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kScreenBackground,
      body: _buildBody(),
      // Keep source management available without bringing back a title/header
      // bar. The empty state already has its own add-source CTA.
      floatingActionButton: !_loading && !_error && _packages.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _openRepos,
              icon: const Icon(Icons.folder_shared),
              label: const Text('Gerenciar fontes'),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error) return _StoreUnavailable(onRetry: _load);
    if (_packages.isEmpty) {
      return _EmptyStore(onAddRepos: _openRepos);
    }

    final featured = _packages.firstWhere(
      (p) => p.featured,
      orElse: () => _packages.first,
    );
    final sections = _sections;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(
            left: 16,
            top: 24,
            right: 16,
            bottom: 96,
          ),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              KeyedSubtree(
                key: _rowKeys[0],
                child: KeyedSubtree(
                  key: _cellKeys[0][0],
                  child: _FeaturedCard(
                    item: featured,
                    focused: _nav.row == 0,
                    onInstall: _showInstallSoon,
                    // Tap keeps its old action (install hint) and also moves
                    // D-pad focus, like tapping a home cover selects the game.
                    onTap: () {
                      _nav.focusCell(0, 0);
                      _showInstallSoon();
                    },
                  ),
                ),
              ),
              for (
                var sectionIndex = 0;
                sectionIndex < sections.length;
                sectionIndex++
              )
                _buildRow(sectionIndex, sections[sectionIndex]),
            ]),
          ),
        ),
      ],
    );
  }

  /// One section: header + horizontally scrolling cover row, keyed so the
  /// D-pad focus can scroll itself into view on both axes.
  Widget _buildRow(int sectionIndex, _StoreSection section) {
    final rowIndex = sectionIndex + 1;
    return KeyedSubtree(
      key: _rowKeys[rowIndex],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          _SectionHeader(title: section.title),
          const SizedBox(height: 12),
          SizedBox(
            height: _coverHeight + _coverLabelHeight,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: section.items.length,
              itemBuilder: (context, col) {
                final item = section.items[col];
                return KeyedSubtree(
                  key: _cellKeys[rowIndex][col],
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    // Horizontal ListView children get unbounded width, so
                    // the card needs the same fixed cover width the old row
                    // gave it (its inner Column also relies on the bounded
                    // height from the SizedBox above).
                    child: SizedBox(
                      width: _coverWidth,
                      child: _StoreCoverCard(
                        item: item,
                        focused: _nav.row == rowIndex && _nav.col == col,
                        // Tap keeps its old action (install hint) and also
                        // moves D-pad focus to the tapped card.
                        onTap: () {
                          _nav.focusCell(rowIndex, col);
                          _showInstallSoon();
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<_StoreSection> _sectionsOf(List<RepoPackage> packages) {
    final order = <String>[];
    final bySection = <String, List<RepoPackage>>{};
    for (final p in packages) {
      final list = bySection[p.section];
      if (list == null) {
        bySection[p.section] = [p];
        order.add(p.section);
      } else {
        list.add(p);
      }
    }
    return [for (final title in order) _StoreSection(title, bySection[title]!)];
  }
}

/// Section title above each cover row.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 0),
      child: Text(
        title,
        style: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _StoreSection {
  const _StoreSection(this.title, this.items);

  final String title;
  final List<RepoPackage> items;
}

/// Portrait cover card: gradient + icon "art" (repo packages carry no cover
/// images), hover/focus border+glow+scale copied from the home `GameCover`,
/// and title + version below like the cover title on Home. [focused] mirrors
/// hover so D-pad selection reads the same as mouse hover.
class _StoreCoverCard extends StatefulWidget {
  const _StoreCoverCard({required this.item, this.focused = false, this.onTap});

  final RepoPackage item;
  final bool focused;
  final VoidCallback? onTap;

  @override
  State<_StoreCoverCard> createState() => _StoreCoverCardState();
}

class _StoreCoverCardState extends State<_StoreCoverCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final item = widget.item;
    final active = _hovered || widget.focused;

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
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: active
                        ? Border.all(color: item.color, width: 3)
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                      if (active)
                        BoxShadow(
                          color: item.color.withValues(alpha: 0.5),
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
                        // Same gradient fallback as the home covers.
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                item.color,
                                Color.lerp(item.color, Colors.black, 0.55)!,
                              ],
                            ),
                          ),
                        ),
                        Center(
                          child: Icon(
                            item.icon,
                            size: 56,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                        if (item.badge != null)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: _TagPill(
                              label: item.badge!,
                              color: item.color,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                item.version != null ? 'v${item.version}' : item.repoName,
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

/// Featured banner: the home hero treatment applied to a store item (color
/// gradient base, large icon "art", `HeroScrimPainter` scrim for readable
/// text, white CTA button like the hero's Play). [focused] mirrors hover so
/// D-pad selection reads the same as mouse hover; tapping the banner moves
/// focus to it (like tapping a home cover selects the game).
class _FeaturedCard extends StatefulWidget {
  const _FeaturedCard({
    required this.item,
    this.focused = false,
    this.onInstall,
    this.onTap,
  });

  final RepoPackage item;
  final bool focused;
  final VoidCallback? onInstall;
  final VoidCallback? onTap;

  @override
  State<_FeaturedCard> createState() => _FeaturedCardState();
}

class _FeaturedCardState extends State<_FeaturedCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final item = widget.item;
    final active = _hovered || widget.focused;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: active ? 1.01 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 210,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: active ? Border.all(color: item.color, width: 3) : null,
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: item.color.withValues(alpha: 0.45),
                        blurRadius: 28,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Same base gradient as the home hero banner.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color.lerp(item.color, Colors.black, 0.35)!,
                        Color.lerp(item.color, Colors.black, 0.7)!,
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 32,
                  top: 0,
                  bottom: 0,
                  child: Icon(
                    item.icon,
                    size: 170,
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
                const Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(painter: HeroScrimPainter()),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _TagPill(
                              label: 'DESTAQUE',
                              color: Colors.white,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                                shadows: const [
                                  Shadow(
                                    color: Colors.black54,
                                    blurRadius: 10,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 560),
                              child: Text(
                                item.tagline ?? item.description ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodyLarge?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  shadows: const [
                                    Shadow(
                                      color: Colors.black87,
                                      blurRadius: 8,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              [
                                if (item.version != null) 'v${item.version}',
                                item.repoName,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleSmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      // White CTA mirrors the home hero's Play button.
                      FilledButton.icon(
                        onPressed: widget.onInstall,
                        icon: const Icon(Icons.download),
                        label: const Text('Instalar'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 16,
                          ),
                          textStyle: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Translucent pill badge (same shape as the trophy points pill) used for
/// "DESTAQUE" / "NOVO" tags.
class _TagPill extends StatelessWidget {
  const _TagPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: color,
        ),
      ),
    );
  }
}

class _EmptyStore extends StatelessWidget {
  const _EmptyStore({required this.onAddRepos});

  final VoidCallback onAddRepos;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_shared, size: 72, color: colorScheme.outline),
          const SizedBox(height: 20),
          Text(
            'Nenhum repositório adicionado.',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Adicione fontes JSON para ver os jogos e apps gratuitos.',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAddRepos,
            icon: const Icon(Icons.add),
            label: const Text('Adicionar repositório'),
          ),
        ],
      ),
    );
  }
}

class _StoreUnavailable extends StatelessWidget {
  const _StoreUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 56, color: colorScheme.outline),
          const SizedBox(height: 16),
          const Text('Não foi possível carregar os repositórios.'),
          const SizedBox(height: 4),
          Text(
            'Confira os repositórios na tela de gerenciamento.',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
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
