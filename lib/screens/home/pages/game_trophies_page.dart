import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:sigg_launcher/app_widget.dart';
import 'package:sigg_launcher/screens/home/widgets/mock_games.dart';
import 'package:sigg_launcher/screens/home/widgets/trophy_widgets.dart';
import 'package:sigg_launcher/services/achievement_service.dart';
import 'package:sigg_launcher/services/page_nav_controller.dart';

class GameTrophiesPage extends StatefulWidget {
  const GameTrophiesPage({
    super.key,
    required this.game,
    required this.snapshot,
  });

  final GameEntry game;
  final GameSnapshot snapshot;

  @override
  State<GameTrophiesPage> createState() => _GameTrophiesPageState();
}

class _GameTrophiesPageState extends State<GameTrophiesPage> {
  final PageNavController _nav = PageNavController(axis: Axis.horizontal);
  late final List<GlobalKey> _rowKeys = List.generate(
    widget.snapshot.trophies.length,
    (_) => GlobalKey(),
  );

  /// Trophies ordered earned-first (unlocked always lead the row). Built as
  /// two stable groups so ties keep the daemon's original ordering.
  late final List<Trophy> _trophies = [
    ...widget.snapshot.trophies.where((t) => t.earned),
    ...widget.snapshot.trophies.where((t) => !t.earned),
  ];

  @override
  void initState() {
    super.initState();
    PageFocusHub.instance.push(_nav);
    _nav.onActivate = () {};
    _nav.addListener(_onNavChanged);
    _nav.setCount(_trophies.length);
  }

  @override
  void dispose() {
    PageFocusHub.instance.pop(_nav);
    _nav.removeListener(_onNavChanged);
    _nav.dispose();
    super.dispose();
  }

  void _onNavChanged() {
    if (!mounted) return;
    setState(() {});
    final index = _nav.index;
    if (index < 0 || index >= _rowKeys.length) return;
    // Defer until after the rebuild so the focused card is laid out; calling
    // ensureVisible synchronously can hit an unlaid-out RenderBox.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _rowKeys[index].currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.1,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kScreenBackground,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // The trophy row is an expanded element: below the fixed 380px hero
          // it fills down to the bottom of the viewport, and its cards
          // stretch to that height.
          final fillHeight = math.max(220.0, constraints.maxHeight - 380);
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: GameBanner(
                  game: widget.game,
                  child: SizedBox(
                    height: 380,
                    child: _HeroContent(
                      game: widget.game,
                      snapshot: widget.snapshot,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  // Horizontal scroll guarantees a single row; never wraps.
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    height: fillHeight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < _trophies.length; i++) ...[
                            if (i > 0) const SizedBox(width: 10),
                            SizedBox(
                              width: 250,
                              child: _TrophyCard(
                                key: _rowKeys[i],
                                trophy: _trophies[i],
                                focused: _nav.index == i,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeroContent extends StatelessWidget {
  const _HeroContent({required this.game, required this.snapshot});

  final GameEntry game;
  final GameSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final progress = snapshot.totalCount == 0
        ? 0.0
        : snapshot.earnedCount / snapshot.totalCount;
    final complete =
        snapshot.totalCount > 0 && snapshot.earnedCount == snapshot.totalCount;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                game.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  shadows: const [
                    Shadow(
                      color: Colors.black54,
                      blurRadius: 10,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${snapshot.earnedCount}/${snapshot.totalCount} troféus',
                  style: textTheme.titleLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: Colors.black.withValues(alpha: 0.4),
                    color: complete ? kTrophyGold : game.color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TrophyCard extends StatefulWidget {
  const _TrophyCard({super.key, required this.trophy, required this.focused});

  final Trophy trophy;
  final bool focused;

  @override
  State<_TrophyCard> createState() => _TrophyCardState();
}

class _TrophyCardState extends State<_TrophyCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final trophy = widget.trophy;
    final isEarned = trophy.earned;
    final focused = widget.focused;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: isEarned
              ? kTrophyGold.withValues(alpha: _hovered || focused ? 0.14 : 0.08)
              : Colors.white.withValues(
                  alpha: _hovered || focused ? 0.06 : 0.03,
                ),
          border: Border.all(
            color: focused
                ? Colors.white
                : isEarned
                ? kTrophyGold.withValues(alpha: _hovered ? 0.55 : 0.35)
                : Colors.white.withValues(alpha: _hovered ? 0.12 : 0.06),
            width: focused ? 2.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            TrophyEmblem(
              earned: isEarned,
              size: 44,
              glow: isEarned && (_hovered || focused),
            ),
            const SizedBox(height: 18),
            Text(
              trophy.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleLarge?.copyWith(
                color: isEarned ? Colors.white : colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                _subtitle(trophy),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyLarge?.copyWith(
                  color: isEarned
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.onSurface,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: _PointsPill(points: trophy.points, earned: isEarned),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(Trophy trophy) {
    final needsEvents = trophy.needsEvents;
    if (!trophy.earned && needsEvents.isNotEmpty) {
      final parts = needsEvents.map((req) {
        final current = trophy.counters[req.event] ?? 0;
        return '$current / ${req.needed} ${req.event}';
      });
      return '${trophy.description}\n${parts.join(' · ')}';
    }
    return trophy.description;
  }
}

class _PointsPill extends StatelessWidget {
  const _PointsPill({required this.points, required this.earned});

  final int points;
  final bool earned;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: earned
            ? kTrophyGold.withValues(alpha: 0.24)
            : Colors.white.withValues(alpha: 0.08),
        border: Border.all(
          color: earned
              ? kTrophyGold.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.14),
        ),
      ),
      child: Text(
        '+$points pts',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: earned ? kTrophyGold : Colors.white.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
