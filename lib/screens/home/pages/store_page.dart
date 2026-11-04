import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sigg_launcher/app_widget.dart';
import 'package:sigg_launcher/screens/home/pages/repositories_page.dart';
import 'package:sigg_launcher/screens/home/widgets/mock_games.dart';
import 'package:sigg_launcher/screens/home/widgets/trophy_widgets.dart';
import 'package:sigg_launcher/services/bgm_player.dart';
import 'package:sigg_launcher/services/page_nav_controller.dart';
import 'package:sigg_launcher/services/package_installer.dart';
import 'package:sigg_launcher/services/repository_service.dart';
import 'package:sigg_launcher/services/software_category.dart';

/// IFSCstation Store: a Cydia/Sileo-style package store where every game/app
/// is free. The catalog comes from user-added JSON repositories (sources) —
/// see [RepositoryService]. Visual language mirrors the rest of the shell:
/// dark background, no AppBar, a featured banner using the home hero treatment
/// (color gradient + `HeroScrimPainter` scrim + white CTA), and cover rows
/// that copy the home `GameCover` card. Packages install through
/// [PackageInstaller] (download → validate → atomic rename into the
/// registry); installed packages are uninstalled from the detail dialog.
/// Row 0 of the D-pad grid is the "Todos/Jogos/Apps" category filter.
class StorePage extends StatefulWidget {
  const StorePage({super.key, this.service, this.packages, this.installer});

  /// Test seam: pre-computed package list; when null the page loads from
  /// the repositories listed in the service's manifest.
  final Future<List<RepoPackage>>? packages;

  /// Test seam: the repository client. Defaults to the real one.
  final RepositoryService? service;

  /// Test seam: the package installer. Defaults to the real one writing
  /// into `~/software`.
  final PackageInstaller? installer;

  @override
  State<StorePage> createState() => _StorePageState();
}

const double _coverWidth = 150;
const double _coverHeight = _coverWidth / coverAspectRatio;

/// Title + version lines under each cover (8 gap + title + version).
const double _coverLabelHeight = 50;

class _StorePageState extends State<StorePage> {
  /// D-pad/keyboard grid: row 0 = the category chips ("Todos/Jogos/Apps"),
  /// row 1 = the featured banner (single cell, only while a filter shows
  /// packages), rows 2..n = the section cover rows. Wired to both the
  /// gamepad bridge and the Launcher's keyboard handler via [PageFocusHub].
  final GridPageNavController _nav = GridPageNavController();
  final List<GlobalKey> _rowKeys = <GlobalKey>[];
  final List<List<GlobalKey>> _cellKeys = <List<GlobalKey>>[];

  /// Row 0 chips: label + the category they filter by (null = "Todos").
  static const _filterOptions = <(String, SoftwareCategory?)>[
    ('Todos', null),
    ('Jogos', SoftwareCategory.game),
    ('Apps', SoftwareCategory.app),
  ];

  late final PackageInstaller _installer =
      widget.installer ?? PackageInstaller();

  bool _loading = true;
  bool _error = false;
  List<RepoPackage> _packages = const [];

  /// Packages matching the active category filter — what the grid renders.
  List<RepoPackage> _visible = const [];

  /// Ids currently present in the registry (drives pills + CTA states).
  final Set<String> _installed = <String>{};

  SoftwareCategory? _filter; // null = "Todos".

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

  /// A / Start / Enter on the focused cell: applies a category chip (row 0),
  /// mirrors the featured CTA (row 1), or opens the package detail dialog
  /// (section rows). On the empty/error states it mirrors the visible CTA
  /// (open the sources manager / retry) so gamepad users aren't stranded.
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
      final col = _nav.col.clamp(0, _filterOptions.length - 1);
      _applyFilter(_filterOptions[col].$2);
      return;
    }
    if (_nav.row == 1) {
      _onFeaturedCta();
      return;
    }
    final sectionIndex = _nav.row - 2;
    if (sectionIndex < 0 || sectionIndex >= _sections.length) return;
    final items = _sections[sectionIndex].items;
    if (_nav.col < 0 || _nav.col >= items.length) return;
    _openDetail(items[_nav.col]);
  }

  List<_StoreSection> _sections = const [];

  /// Filters the grid to [filter] (null = all categories). Re-derives the
  /// nav rows so Up/Down can't walk into rows that no longer exist.
  void _applyFilter(SoftwareCategory? filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
    _syncNav();
  }

  /// Featured item of the current filter: first `featured` flag, else the
  /// first visible package (mirrors the old banner behavior).
  RepoPackage? get _featured {
    if (_visible.isEmpty) return null;
    for (final package in _visible) {
      if (package.featured) return package;
    }
    return _visible.first;
  }

  /// Featured CTA / Enter on the banner: install when possible, otherwise
  /// open the detail dialog (which explains why / offers the uninstall).
  void _onFeaturedCta() {
    final featured = _featured;
    if (featured == null) return;
    if (_installed.contains(featured.id)) {
      _openDetail(featured);
    } else {
      _install(featured);
    }
  }

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
            _refreshInstalled();
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
          _refreshInstalled();
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

  /// Re-derives sections + grid dimensions after a (re)load or a category
  /// filter change. Empty while loading/errored/empty so moves and activate
  /// become no-ops.
  void _syncNav() {
    if (_loading || _error || _packages.isEmpty) {
      _sections = const [];
      _visible = const [];
      _rowKeys.clear();
      _cellKeys.clear();
      _nav.setRows(const []);
      return;
    }
    final filter = _filter;
    _visible = filter == null
        ? _packages
        : [for (final p in _packages) if (p.category == filter) p];
    _sections = _sectionsOf(_visible);

    // Row 0 = category chips; row 1 = the featured banner (only while the
    // filter shows at least one package); rows 2.. = section cover rows.
    final hasFeatured = _visible.isNotEmpty;
    _rowKeys
      ..clear()
      ..addAll(
        List.generate(
          1 + (hasFeatured ? 1 : 0) + _sections.length,
          (_) => GlobalKey(),
        ),
      );
    _cellKeys
      ..clear()
      ..add([
        for (var i = 0; i < _filterOptions.length; i++) GlobalKey(),
      ]);
    if (hasFeatured) _cellKeys.add(<GlobalKey>[GlobalKey()]);
    for (final section in _sections) {
      _cellKeys.add([
        for (var i = 0; i < section.items.length; i++) GlobalKey(),
      ]);
    }
    _nav.setRows([
      _filterOptions.length,
      if (hasFeatured) 1,
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

  /// Recomputes which catalog ids exist in the registry (cheap stat calls).
  void _refreshInstalled() {
    final installed = <String>{};
    for (final package in _packages) {
      if (_installer.isInstalled(package.id)) installed.add(package.id);
    }
    if (!mounted) return;
    setState(() {
      _installed
        ..clear()
        ..addAll(installed);
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  /// Opens the package detail dialog (suspend focus routing like every other
  /// dialog) and runs whatever action it returns.
  Future<void> _openDetail(RepoPackage package) async {
    PageFocusHub.instance.suspend();
    _DetailAction? action;
    try {
      action = await showDialog<_DetailAction>(
        context: context,
        builder: (_) => _PackageDetailDialog(
          package: package,
          installed: _installed.contains(package.id),
          installedVersion: _installer.installedVersion(package.id),
        ),
      );
    } finally {
      PageFocusHub.instance.resume();
    }
    if (!mounted || action == null) return;
    switch (action) {
      case _DetailAction.install:
      case _DetailAction.update:
        await _install(package);
      case _DetailAction.uninstall:
        await _confirmUninstall(package);
    }
  }

  /// Runs the download→validate→install pipeline behind a progress dialog.
  /// The dialog settles with an [InstallOutcome], an [InstallException] or
  /// null (cancelled); each case maps to its own SnackBar (silent cancel).
  Future<void> _install(RepoPackage package) async {
    if (package.url == null) {
      _showMessage('"${package.name}" não tem fonte de download.');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    Object? result;
    // Suspend while the dialog is up: it has buttons the D-pad must not
    // route past into the page behind (same contract as the add-source
    // dialog, minus the TextField).
    PageFocusHub.instance.suspend();
    try {
      result = await showDialog<Object>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _InstallProgressDialog(
          installer: _installer,
          package: package,
        ),
      );
    } finally {
      PageFocusHub.instance.resume();
    }
    if (!mounted) return;
    _refreshInstalled();
    if (result == null) return; // Cancelled (or B-back closed the dialog).
    if (result is InstallException) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(result.message),
            duration: const Duration(seconds: 3),
          ),
        );
      return;
    }
    final outcome = result as InstallOutcome;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(switch (outcome) {
            InstallOutcome.installed => '${package.name} instalado.',
            InstallOutcome.updated => '${package.name} atualizado.',
            InstallOutcome.unchanged => '${package.name} já está atualizado.',
          }),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  /// Confirm-then-delete for the detail dialog's "Desinstalar". Stops the
  /// BGM first so no track is streaming from the files being removed.
  Future<void> _confirmUninstall(RepoPackage package) async {
    PageFocusHub.instance.suspend();
    bool confirmed;
    try {
      confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text('Desinstalar ${package.name}?'),
              content: const Text(
                'Os dados locais deste pacote serão apagados. '
                'Esta ação não pode ser desfeita.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Desinstalar'),
                ),
              ],
            ),
          ) ??
          false;
    } finally {
      PageFocusHub.instance.resume();
    }
    if (!confirmed || !mounted) return;

    await BgmPlayer.instance.stop();
    try {
      final removed = _installer.uninstall(package.id);
      _refreshInstalled();
      _showMessage(
        removed
            ? '${package.name} desinstalado.'
            : '${package.name} não estava instalado.',
      );
    } on InstallException catch (e) {
      _showMessage(e.message);
    } on FileSystemException {
      _showMessage('Não foi possível remover "${package.name}".');
    }
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

    final featured = _featured;
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
              // Row 0: category chips ("Todos | Jogos | Apps").
              KeyedSubtree(
                key: _rowKeys[0],
                child: Row(
                  children: [
                    for (var i = 0; i < _filterOptions.length; i++)
                      KeyedSubtree(
                        key: _cellKeys[0][i],
                        child: Padding(
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
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (featured != null)
                KeyedSubtree(
                  key: _rowKeys[1],
                  child: KeyedSubtree(
                    key: _cellKeys[1][0],
                    child: _FeaturedCard(
                      item: featured,
                      focused: _nav.row == 1,
                      installed: _installed.contains(featured.id),
                      // The white CTA installs (or shows details when the
                      // package is already in the registry).
                      onInstall: _onFeaturedCta,
                      // Tapping the banner opens the detail dialog — the
                      // same target as tapping a cover card.
                      onTap: () {
                        _nav.focusCell(1, 0);
                        _openDetail(featured);
                      },
                    ),
                  ),
                )
              else
                // A category filter with no matches: the chips stay (row 0)
                // so the user can pick another one.
                _EmptyCategory(filter: _filter),
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
    final rowIndex = sectionIndex + 2; // 0 = chips, 1 = featured.
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
                        installed: _installed.contains(item.id),
                        focused: _nav.row == rowIndex && _nav.col == col,
                        // Tap opens the detail dialog (install/uninstall
                        // live there) and moves the D-pad focus to the card.
                        onTap: () {
                          _nav.focusCell(rowIndex, col);
                          _openDetail(item);
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
/// hover so D-pad selection reads the same as mouse hover. [installed] adds
/// the green "INSTALADO" pill so state is visible without opening the
/// detail dialog.
class _StoreCoverCard extends StatefulWidget {
  const _StoreCoverCard({
    required this.item,
    this.installed = false,
    this.focused = false,
    this.onTap,
  });

  final RepoPackage item;
  final bool installed;
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
                        if (widget.installed)
                          const Positioned(
                            top: 8,
                            right: 8,
                            child: _TagPill(
                              label: 'INSTALADO',
                              color: Color(0xFF4CAF50),
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
/// D-pad selection reads the same as mouse hover; tapping the banner opens
/// the detail dialog, and the CTA is state-aware: "Instalar" (download),
/// "Detalhes" (already installed → dialog with the uninstall) or a disabled
/// "Indisponível" (package without a `url`).
class _FeaturedCard extends StatefulWidget {
  const _FeaturedCard({
    required this.item,
    this.installed = false,
    this.focused = false,
    this.onInstall,
    this.onTap,
  });

  final RepoPackage item;
  final bool installed;
  final bool focused;

  /// CTA action — wired to install-or-details by the page.
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
                            Row(
                              children: [
                                const _TagPill(
                                  label: 'DESTAQUE',
                                  color: Colors.white,
                                ),
                                if (widget.installed) ...[
                                  const SizedBox(width: 8),
                                  const _TagPill(
                                    label: 'INSTALADO',
                                    color: Color(0xFF4CAF50),
                                  ),
                                ],
                              ],
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
                      // White CTA mirrors the home hero's Play button;
                      // disabled when there's nothing to do (no url and not
                      // installed).
                      FilledButton.icon(
                        onPressed:
                            (widget.installed || item.url != null)
                                ? widget.onInstall
                                : null,
                        icon: Icon(
                          widget.installed
                              ? Icons.info_outline
                              : Icons.download,
                        ),
                        label: Text(
                          widget.installed
                              ? 'Detalhes'
                              : (item.url != null
                                    ? 'Instalar'
                                    : 'Indisponível'),
                        ),
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
              color: Colors.white.withValues(alpha: widget.selected ? 0.16 : 0.05),
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

/// Shown when a category filter matches nothing: the chips (row 0) stay on
/// screen so the D-pad user can pick another category.
class _EmptyCategory extends StatelessWidget {
  const _EmptyCategory({required this.filter});

  final SoftwareCategory? filter;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final singular = filter?.singularLabel.toLowerCase() ?? 'pacote';
    return Padding(
      padding: const EdgeInsets.only(top: 48, bottom: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.filter_alt_off, size: 56, color: colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            'Nenhum $singular nesta categoria.',
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

/// Which action the detail dialog asked for (the dialog itself only returns
/// a request; the page runs the install/uninstall with its own dialogs).
enum _DetailAction { install, update, uninstall }

/// Package detail: metadata + the state-aware action. Not installed →
/// "Instalar" (or a disabled hint when the package has no `url`); installed
/// → "Atualizar" when the versions differ, plus "Desinstalar".
class _PackageDetailDialog extends StatelessWidget {
  const _PackageDetailDialog({
    required this.package,
    required this.installed,
    this.installedVersion,
  });

  final RepoPackage package;
  final bool installed;
  final String? installedVersion;

  /// Whether the repo version differs from the installed one (unknown
  /// installed versions — manual drops — count as updatable).
  bool get _canUpdate =>
      installed &&
      (installedVersion == null ||
          (package.version != null &&
              compareVersions(package.version!, installedVersion!) != 0));

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      backgroundColor: kScreenBackground,
      surfaceTintColor: Colors.transparent,
      title: Row(
        children: [
          Icon(package.icon, color: package.color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              package.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (package.tagline != null || package.description != null)
              Text(
                package.tagline ?? package.description!,
                style: textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            const SizedBox(height: 14),
            _infoRow('Categoria', package.category.singularLabel),
            _infoRow('Versão', package.version ?? '—'),
            _infoRow(
              'Instalado',
              installed ? (installedVersion ?? 'sim') : 'não',
            ),
            _infoRow('Fonte', package.repoName),
            if (package.url == null) ...[
              const SizedBox(height: 10),
              Text(
                'Sem fonte de download — este pacote só pode ser navegado.',
                style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!installed && package.url != null)
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(_DetailAction.install),
            icon: const Icon(Icons.download),
            label: const Text('Instalar'),
          )
        else if (installed) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(_DetailAction.uninstall),
            child: const Text('Desinstalar'),
          ),
          if (_canUpdate)
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(_DetailAction.update),
              icon: const Icon(Icons.system_update),
              label: const Text('Atualizar'),
            ),
        ] else
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Modal install progress: phase label + bar (+ % when the size is known)
/// and a Cancelar button. Settles with the [InstallOutcome], the
/// [InstallException], or null on cancel — the page maps those to SnackBars.
class _InstallProgressDialog extends StatefulWidget {
  const _InstallProgressDialog({required this.installer, required this.package});

  final PackageInstaller installer;
  final RepoPackage package;

  @override
  State<_InstallProgressDialog> createState() => _InstallProgressDialogState();
}

class _InstallProgressDialogState extends State<_InstallProgressDialog> {
  final ValueNotifier<({InstallPhase phase, double fraction})> _progress =
      ValueNotifier((phase: InstallPhase.downloading, fraction: -1.0));

  bool _cancelRequested = false;
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    // If the route went away without our pop (B-back), ask the installer to
    // stop at its next checkpoint so no orphan install keeps running.
    if (!_settled) _cancelRequested = true;
    _progress.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    try {
      final outcome = await widget.installer.install(
        widget.package,
        onProgress: (phase, fraction) {
          _progress.value = (phase: phase, fraction: fraction);
        },
        isCancelled: () => _cancelRequested,
      );
      _settle(outcome);
    } on InstallCancelled {
      _settle(null);
    } on InstallException catch (e) {
      _settle(e);
    } catch (e) {
      _settle(InstallException('Falha inesperada ao instalar: $e'));
    }
  }

  void _settle(Object? result) {
    if (_settled || !mounted) return;
    _settled = true;
    Navigator.of(context).pop(result);
  }

  String _phaseLabel(InstallPhase phase) => switch (phase) {
    InstallPhase.downloading => 'Baixando…',
    InstallPhase.extracting => 'Validando e extraindo…',
    InstallPhase.finalizing => 'Finalizando…',
  };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      backgroundColor: kScreenBackground,
      surfaceTintColor: Colors.transparent,
      title: Text('Instalando ${widget.package.name}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: ValueListenableBuilder<({InstallPhase phase, double fraction})>(
          valueListenable: _progress,
          builder: (context, value, _) {
            final determinate = value.fraction >= 0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _phaseLabel(value.phase),
                  style: textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: determinate ? value.fraction : null,
                    minHeight: 8,
                  ),
                ),
                if (determinate) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${(value.fraction * 100).round()}%',
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _cancelRequested
              ? null
              : () => setState(() => _cancelRequested = true),
          child: Text(_cancelRequested ? 'Cancelando…' : 'Cancelar'),
        ),
      ],
    );
  }
}
