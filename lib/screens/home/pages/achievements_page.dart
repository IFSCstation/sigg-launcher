import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sigg_launcher/app_widget.dart';
import 'package:sigg_launcher/screens/home/pages/game_trophies_page.dart';
import 'package:sigg_launcher/screens/home/widgets/mock_games.dart';
import 'package:sigg_launcher/screens/home/widgets/trophy_widgets.dart';
import 'package:sigg_launcher/services/achievement_service.dart';
import 'package:sigg_launcher/services/game_loader.dart';
import 'package:sigg_launcher/services/page_nav_controller.dart';

class AchievementsPage extends StatefulWidget {
  const AchievementsPage({super.key, this.games, this.service});

  /// Pre-computed game list (injected by Home for tests/consistency); when
  /// null the page loads from the [kSoftwareFolder] registry itself.
  final Future<List<GameEntry>>? games;

  /// Test seam: the achievement daemon client. Defaults to the real one.
  final AchievementService? service;

  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

/// Height of the trophies submenu header (deliberately taller than a stock
/// toolbar so the library progress reads as part of the header).
const double _headerHeight = 96;

class _AchievementsPageState extends State<AchievementsPage> {
  final PageNavController _nav = PageNavController();
  List<_GameTrophyEntry> _entries = const [];
  List<GlobalKey>? _cardKeys;
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
    _nav.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final entries = await _fetch();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _entries = entries;
        _cardKeys = List.generate(entries.length, (_) => GlobalKey());
      });
      _nav.setCount(entries.length);
    } on AchievementUnavailable {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<List<_GameTrophyEntry>> _fetch() async {
    final games = await (widget.games ??
        GameLoader(
          gamesFolder: kGamesFolder,
          appsFolder: kAppsFolder,
        ).load());
    final service = widget.service ?? AchievementService();

    final entries = <_GameTrophyEntry>[];
    for (final game in games) {
      final id = game.id;
      if (id == null) continue;
      try {
        final snapshot = await service.snapshot(id);
        entries.add(_GameTrophyEntry(game: game, snapshot: snapshot));
      } on SocketException {
        throw const AchievementUnavailable();
      } on AchievementException catch (e) {
        if (e.code == 'unknown_game') continue;
        throw const AchievementUnavailable();
      }
    }
    return entries;
  }

  void _onNavChanged() {
    if (!mounted) return;
    setState(() {});
    final keys = _cardKeys;
    if (keys == null) return;
    final index = _nav.index;
    if (index < 0 || index >= keys.length) return;
    final ctx = keys[index].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  void _activateFocused() {
    final index = _nav.index;
    if (index < 0 || index >= _entries.length) return;
    _openGame(_entries[index]);
  }

  void _openGame(_GameTrophyEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            GameTrophiesPage(game: entry.game, snapshot: entry.snapshot),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int earnedCount = 0;
    int totalCount = 0;
    for (final e in _entries) {
      earnedCount += e.snapshot.earnedCount;
      totalCount += e.snapshot.totalCount;
    }

    return Scaffold(
      backgroundColor: kScreenBackground,
      // Body paints under the transparent AppBar so the header reads as a
      // floating see-through overlay over scrolling content.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        toolbarHeight: _headerHeight,
        title: _TrophiesHeader(earned: earnedCount, total: totalCount),
        // Convention: submenus have no back button (B-back / Escape); the
        // header is transparent so the screen's background shows through.
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
    if (_error) return _Unavailable(onRetry: _load);
    if (_entries.isEmpty) {
      return ListView(
        padding: EdgeInsets.only(
          left: 16,
          top: _headerHeight + 8,
          right: 16,
          bottom: 24,
        ),
        children: const [_EmptyTrophies()],
      );
    }

    return ListView(
      padding: EdgeInsets.only(
        left: 16,
        top: _headerHeight + 8,
        right: 16,
        bottom: 24,
      ),
      children: [
        for (var i = 0; i < _entries.length; i++)
          _GameTrophyCard(
            key: _cardKeys![i],
            entry: _entries[i],
            focused: _nav.index == i,
            onTap: () => _openGame(_entries[i]),
          ),
      ],
    );
  }
}

class _TrophiesHeader extends StatelessWidget {
  const _TrophiesHeader({required this.earned, required this.total});

  final int earned;
  final int total;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final progress = total == 0 ? 0.0 : earned / total;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 0, 0),
                child: Text(
                  'Troféus',
                  style: textTheme.headlineMedium?.copyWith(
                    fontSize: 38,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 32),
        SizedBox(
          width: 300,
          child: Row(
            children: [
              const Icon(Icons.emoji_events, size: 40, color: kTrophyGold),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$earned / $total troféus',
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${(progress * 100).round()}%',
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: kTrophyGold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 7,
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                        color: kTrophyGold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GameTrophyCard extends StatefulWidget {
  const _GameTrophyCard({
    super.key,
    required this.entry,
    required this.focused,
    required this.onTap,
  });

  final _GameTrophyEntry entry;
  final bool focused;
  final VoidCallback onTap;

  @override
  State<_GameTrophyCard> createState() => _GameTrophyCardState();
}

class _GameTrophyCardState extends State<_GameTrophyCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final entry = widget.entry;
    final game = entry.game;
    final snapshot = entry.snapshot;
    final complete =
        snapshot.totalCount > 0 && snapshot.earnedCount == snapshot.totalCount;
    final focused = widget.focused;
    final progress = snapshot.totalCount == 0
        ? 0.0
        : snapshot.earnedCount / snapshot.totalCount;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered ? 1.015 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.white.withValues(alpha: _hovered ? 0.07 : 0.04),
              border: Border.all(
                color: focused
                    ? game.color
                    : Colors.white.withValues(alpha: _hovered ? 0.16 : 0.09),
                width: focused ? 3 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _GameThumb(game: game),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                game.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  shadows: const [
                                    Shadow(
                                      color: Colors.black54,
                                      blurRadius: 8,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (complete) ...[
                              const SizedBox(width: 8),
                              const _CompletePill(),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${snapshot.earnedCount}/${snapshot.totalCount} troféus',
                          style: textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 6,
                            backgroundColor: Colors.black.withValues(
                              alpha: 0.4,
                            ),
                            color: complete ? kTrophyGold : game.color,
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
        ),
      ),
    );
  }
}

class _CompletePill extends StatelessWidget {
  const _CompletePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: kTrophyGold,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: kTrophyGold.withValues(alpha: 0.5),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: const Text(
        'Completo!',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Color(0xFF201A0A),
        ),
      ),
    );
  }
}

class _GameThumb extends StatelessWidget {
  const _GameThumb({required this.game});

  final GameEntry game;

  @override
  Widget build(BuildContext context) {
    final iconPath = game.iconPath;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: iconPath != null
            ? Image.file(
                File(iconPath),
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallback,
              )
            : _fallback,
      ),
    );
  }

  Widget get _fallback => Container(
    width: 56,
    height: 56,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: game.color),
    child: Icon(game.icon, color: Colors.white),
  );
}

class _EmptyTrophies extends StatelessWidget {
  const _EmptyTrophies();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const TrophyEmblem(earned: false, size: 72),
          const SizedBox(height: 20),
          Text(
            'Nenhum jogo com troféus ainda.',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Complete desafios nos jogos da biblioteca para ganhar troféus.',
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

class _GameTrophyEntry {
  const _GameTrophyEntry({required this.game, required this.snapshot});

  final GameEntry game;
  final GameSnapshot snapshot;
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onRetry});

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
          const Text('Serviço de troféus indisponível.'),
          const SizedBox(height: 4),
          Text(
            'O daemon achievementd não está ativo.',
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

class AchievementUnavailable implements Exception {
  const AchievementUnavailable();
}
