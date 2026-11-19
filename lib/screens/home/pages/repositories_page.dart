import 'package:material_ui/material_ui.dart';
import 'package:sigg_launcher/app_widget.dart';
import 'package:sigg_launcher/services/page_nav_controller.dart';
import 'package:sigg_launcher/services/repository_service.dart';

/// Manages the store's repository sources (Cydia/Sileo "sources"): the list
/// of local paths / http(s) URLs that point to JSON indexes of free
/// packages. Submenu conventions apply: transparent header, no back button
/// (B-back / Escape leaves the page). D-pad navigable: a vertical
/// [PageNavController] (row 0 = "Adicionar repositório", rows 1..n = the
/// source cards) is pushed onto [PageFocusHub]; Enter on the add row opens
/// the dialog, Enter on a failed row retries it. Input is suspended while
/// the add dialog is open so its TextField gets arrow/Enter keys back.
class RepositoriesPage extends StatefulWidget {
  const RepositoriesPage({super.key, this.service});

  /// Test seam: the repository client. Defaults to the real one.
  final RepositoryService? service;

  @override
  State<RepositoriesPage> createState() => _RepositoriesPageState();
}

const double _headerHeight = 96;

class _RepositoriesPageState extends State<RepositoriesPage> {
  late final RepositoryService _service = widget.service ?? RepositoryService();

  /// D-pad focus: vertical list of [1 add-card + N source cards]. Wired to
  /// the gamepad bridge + keyboard handler via [PageFocusHub].
  final PageNavController _nav = PageNavController(axis: Axis.vertical);
  final List<GlobalKey> _rowKeys = <GlobalKey>[];

  List<_RepoStatus> _statuses = const [];
  bool _loading = true;

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
    // Defer until after the rebuild so the focused row is laid out; calling
    // ensureVisible synchronously can hit an unlaid-out RenderBox.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _nav.index >= _rowKeys.length) return;
      final ctx = _rowKeys[_nav.index].currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  /// A / Start / Enter on the focused row: row 0 opens the add dialog, a
  /// failed source card retries its fetch, anything else is a no-op.
  void _onActivate() {
    final index = _nav.index;
    if (index == 0) {
      _addRepo();
      return;
    }
    final statusIndex = index - 1;
    if (statusIndex < 0 || statusIndex >= _statuses.length) return;
    final status = _statuses[statusIndex];
    if (status.hasSource && status.error != null) _load();
  }

  /// Keeps the row count (and keys) in sync with the source list.
  void _syncNav() {
    _rowKeys
      ..clear()
      ..addAll(List.generate(_statuses.length + 1, (_) => GlobalKey()));
    _nav.setCount(_statuses.length + 1);
  }

  void _load() {
    setState(() => _loading = true);

    final List<String> sources;
    try {
      sources = _service.listSources();
    } on RepoException catch (e) {
      setState(() {
        _loading = false;
        _statuses = [_RepoStatus.error('', e.message)];
      });
      _syncNav();
      return;
    }

    final statuses = <_RepoStatus>[
      for (final source in sources) _RepoStatus.loading(source),
    ];
    setState(() => _statuses = statuses);
    _syncNav();

    // Fetch each source sequentially: local files resolve instantly, http
    // sources stream in one by one and repaint as they land.
    for (var i = 0; i < sources.length; i++) {
      _service
          .fetch(sources[i])
          .then((repo) => _setResult(i, _RepoStatus.ok(sources[i], repo)))
          .catchError((Object e) {
            _setResult(i, _RepoStatus.error(sources[i], e.toString()));
          });
    }
    if (sources.isEmpty) setState(() => _loading = false);
  }

  void _setResult(int index, _RepoStatus status) {
    if (!mounted || index >= _statuses.length) return;
    setState(() {
      _statuses = [..._statuses]..[index] = status;
      _loading = _statuses.any((s) => s.loading);
    });
  }

  Future<void> _addRepo() async {
    // Suspend focus routing while the dialog is open: its TextField needs
    // arrow/Enter keys (the launcher's global keyboard handler consumes them
    // whenever a page controller is active), and the gamepad bridge must not
    // drive the list behind the dialog.
    PageFocusHub.instance.suspend();
    bool? added;
    try {
      added = await showDialog<bool>(
        context: context,
        builder: (context) => _AddRepoDialog(service: _service),
      );
    } finally {
      PageFocusHub.instance.resume();
    }
    if (added == true) _load();
  }

  void _removeRepo(_RepoStatus status) {
    try {
      _service.removeSource(status.source);
    } on RepoException catch (e) {
      _showError(e.message);
      return;
    }
    _load();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
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
        title: _ReposHeader(
          count: _statuses.length,
          refreshing: _loading,
          onRefresh: _loading ? null : _load,
        ),
        // Convention: submenus have no back button (B-back / Escape).
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.only(
          left: 16,
          top: _headerHeight + 8,
          right: 16,
          bottom: 24,
        ),
        children: [
          KeyedSubtree(
            key: _rowKeys[0],
            child: _AddRepoCard(
              focused: _nav.index == 0,
              onTap: () {
                _nav.focus(0);
                _addRepo();
              },
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < _statuses.length; i++) ...[
            KeyedSubtree(
              key: _rowKeys[i + 1],
              child: _RepoCard(
                status: _statuses[i],
                focused: _nav.index == i + 1,
                onTap: () => _nav.focus(i + 1),
                onRemove: _statuses[i].hasSource
                    ? () => _removeRepo(_statuses[i])
                    : null,
                onRetry: _statuses[i].hasSource ? _load : null,
              ),
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

/// Header row: big "Repositórios" title left, source count + refresh right —
/// same icon + column layout as the trophies header widget.
class _ReposHeader extends StatelessWidget {
  const _ReposHeader({
    required this.count,
    required this.refreshing,
    this.onRefresh,
  });

  final int count;
  final bool refreshing;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 0, 0),
            child: Text(
              'Repositórios',
              style: textTheme.headlineMedium?.copyWith(
                fontSize: 38,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
        const SizedBox(width: 32),
        SizedBox(
          width: 300,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$count ${count == 1 ? 'fonte' : 'fontes'}',
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'ativas',
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Índices JSON de pacotes gratuitos',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              refreshing
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  : IconButton(
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh, size: 28),
                      tooltip: 'Atualizar',
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Add repository" entry at the top of the list (same shape as the repo
/// cards below). [focused] mirrors hover so D-pad selection reads the same
/// as mouse hover.
class _AddRepoCard extends StatefulWidget {
  const _AddRepoCard({required this.onTap, this.focused = false});

  final VoidCallback onTap;
  final bool focused;

  @override
  State<_AddRepoCard> createState() => _AddRepoCardState();
}

class _AddRepoCardState extends State<_AddRepoCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final active = _hovered || widget.focused;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white.withValues(alpha: active ? 0.07 : 0.04),
            border: Border.all(
              color: Colors.white.withValues(alpha: active ? 0.16 : 0.09),
              width: active ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.primary
                      .withValues(alpha: 0.18),
                ),
                child: Icon(
                  Icons.add,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Adicionar repositório',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Caminho local ou URL de um índice .json',
                      style: textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One source: icon, name/author, path, package count — or the fetch error.
/// [focused] mirrors hover so D-pad selection reads the same as mouse hover.
class _RepoCard extends StatefulWidget {
  const _RepoCard({
    required this.status,
    this.focused = false,
    this.onTap,
    this.onRemove,
    this.onRetry,
  });

  final _RepoStatus status;
  final bool focused;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final VoidCallback? onRetry;

  @override
  State<_RepoCard> createState() => _RepoCardState();
}

class _RepoCardState extends State<_RepoCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final status = widget.status;
    final repo = status.repo;
    final failed = status.error != null;
    final active = _hovered || widget.focused;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white.withValues(alpha: active ? 0.07 : 0.04),
            border: Border.all(
              color: failed
                  ? colorScheme.error.withValues(alpha: active ? 0.8 : 0.5)
                  : Colors.white.withValues(alpha: active ? 0.16 : 0.09),
              width: failed || active ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                status.loading
                    ? Icons.hourglass_top
                    : failed
                    ? Icons.error_outline
                    : Icons.folder,
                size: 34,
                color: status.loading
                    ? colorScheme.onSurfaceVariant
                    : failed
                    ? colorScheme.error
                    : colorScheme.primary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      status.loading
                          ? status.source
                          : (repo?.name ?? status.source),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status.loading
                          ? 'Carregando…'
                          : failed
                          ? (status.error ?? '')
                          : '${repo!.author} · ${repo.packages.length} '
                                '${repo.packages.length == 1 ? 'pacote' : 'pacotes'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: failed
                            ? colorScheme.error
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (!status.loading && !failed) ...[
                      const SizedBox(height: 2),
                      Text(
                        status.source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.38),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (failed && widget.onRetry != null)
                IconButton(
                  onPressed: widget.onRetry,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Tentar novamente',
                ),
              if (widget.onRemove != null)
                IconButton(
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remover',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Text input + validation dialog. The source is fetched (and parsed)
/// before being persisted, so broken indexes are rejected up front.
class _AddRepoDialog extends StatefulWidget {
  const _AddRepoDialog({required this.service});

  final RepositoryService service;

  @override
  State<_AddRepoDialog> createState() => _AddRepoDialogState();
}

class _AddRepoDialogState extends State<_AddRepoDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final source = _controller.text.trim();
    if (source.isEmpty) {
      setState(() => _error = 'Informe um caminho ou URL.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.addSource(source); // Validates before persisting.
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on RepoException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Adicionar repositório'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              enabled: !_busy,
              onSubmitted: (_) => _confirm(),
              decoration: const InputDecoration(
                hintText: '/caminho/para/repositorio.json ou https://…',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: colorScheme.error, fontSize: 13),
              ),
            ] else ...[
              const SizedBox(height: 10),
              Text(
                'O arquivo deve conter um índice JSON de pacotes '
                '(veja docs/sample-repository.json). Tudo é gratuito.',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _confirm,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Adicionar'),
        ),
      ],
    );
  }
}

/// Per-source load state shown in the list.
class _RepoStatus {
  const _RepoStatus.loading(this.source) : repo = null, error = null;

  const _RepoStatus.ok(this.source, this.repo) : error = null;

  const _RepoStatus.error(this.source, this.error) : repo = null;

  final String source;
  final Repository? repo;
  final String? error;

  bool get loading => repo == null && error == null;

  bool get hasSource => source.isNotEmpty;
}
