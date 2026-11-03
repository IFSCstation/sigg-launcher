import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sigg_launcher/screens/home/widgets/mock_games.dart';
import 'package:sigg_launcher/services/image_cache.dart';

const double _footerHeight = 44;
const double _separatorWidth = 20;
const double _leftPadding = 16;

class GamesRow extends StatefulWidget {
  const GamesRow({
    super.key,
    required this.games,
    this.selected,
    this.active = true,
    this.focusIndex = 0,
    this.scrollController,
    this.onGameTap,
    this.onSeeAllTap,
  });

  final List<GameEntry> games;
  final GameEntry? selected;

  /// Whether the row is the active navigation zone.
  final bool active;

  /// Cover index currently focused by the D-pad.
  final int focusIndex;

  final ScrollController? scrollController;
  final ValueChanged<GameEntry>? onGameTap;

  /// Opens the full library page from the trailing "Ver todos" card.
  final VoidCallback? onSeeAllTap;

  @override
  State<GamesRow> createState() => _GamesRowState();
}

class _GamesRowState extends State<GamesRow> {
  ScrollController? _ownedController;
  ScrollController get _controller =>
      widget.scrollController ?? (_ownedController ??= ScrollController());

  double _coverWidth = 0;

  @override
  void didUpdateWidget(covariant GamesRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusIndex != widget.focusIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureFocusedVisible();
        _preloadCovers();
      });
    }
  }

  void _preloadCovers() {
    if (_coverWidth <= 0 || widget.games.isEmpty) return;
    final size = Size(_coverWidth, _coverWidth / coverAspectRatio);
    ImagePreloader.preloadCovers(
      context,
      widget.games,
      widget.focusIndex,
      size,
      range: 2,
    );
  }

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  void _ensureFocusedVisible() {
    final controller = _controller;
    if (!controller.hasClients) return;
    final index = widget.focusIndex;
    // The trailing "Ver todos" card is one extra focusable cell.
    if (index < 0 || index > widget.games.length) return;

    final target =
        _leftPadding +
        index * (_coverWidth + _separatorWidth) +
        _coverWidth / 2 -
        controller.position.viewportDimension / 2;
    final targetClamped = target.clamp(
      0.0,
      controller.position.maxScrollExtent,
    );
    if ((targetClamped - controller.offset).abs() > 2) {
      controller.animateTo(
        targetClamped,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: widget.active ? 1.0 : 0.45,
      duration: const Duration(milliseconds: 200),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final coverHeight = (constraints.maxHeight - _footerHeight).clamp(
            80.0,
            300.0,
          );
          _coverWidth = coverHeight * coverAspectRatio;
          return ListView.separated(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: _leftPadding),
            itemCount: widget.games.length + 1,
            separatorBuilder: (context, index) =>
                const SizedBox(width: _separatorWidth),
            itemBuilder: (context, index) {
              if (index == widget.games.length) {
                return RepaintBoundary(
                  child: _SeeAllCard(
                    width: _coverWidth,
                    focused: widget.focusIndex == widget.games.length,
                    onTap: widget.onSeeAllTap,
                  ),
                );
              }
              final game = widget.games[index];
              return RepaintBoundary(
                child: GameCover(
                  game: game,
                  width: _coverWidth,
                  selected: identical(game, widget.selected),
                  onTap: () => widget.onGameTap?.call(game),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class GameCover extends StatefulWidget {
  const GameCover({
    super.key,
    required this.game,
    required this.width,
    this.selected = false,
    this.onTap,
  });

  final GameEntry game;
  final double width;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<GameCover> createState() => _GameCoverState();
}

class _GameCoverState extends State<GameCover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = math.max(1, (widget.width * devicePixelRatio).round());
    final cacheHeight = math.max(
      1,
      ((widget.width / coverAspectRatio) * devicePixelRatio).round(),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered ? 1.04 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: SizedBox(
            width: widget.width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: coverAspectRatio,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: widget.selected
                          ? Border.all(color: widget.game.color, width: 3)
                          : null,
                      boxShadow: [
                        if (widget.selected)
                          BoxShadow(
                            color: widget.game.color.withValues(alpha: 0.7),
                            blurRadius: 28,
                            spreadRadius: 4,
                          ),
                        if (_hovered)
                          BoxShadow(
                            color: widget.game.color.withValues(alpha: 0.5),
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
                                  widget.game.color,
                                  Color.lerp(
                                    widget.game.color,
                                    Colors.black,
                                    0.55,
                                  )!,
                                ],
                              ),
                            ),
                          ),
                          if (widget.game.coverPath != null)
                            Image.file(
                              File(widget.game.coverPath!),
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              cacheWidth: cacheWidth,
                              cacheHeight: cacheHeight,
                              filterQuality: FilterQuality.medium,
                              errorBuilder: (context, error, stackTrace) =>
                                  const SizedBox.shrink(),
                            )
                          else if (widget.game.imageAsset != null)
                            Image.asset(
                              widget.game.imageAsset!,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              cacheWidth: cacheWidth,
                              cacheHeight: cacheHeight,
                              filterQuality: FilterQuality.medium,
                            )
                          else if (widget.game.imageUrl != null)
                            Image.network(
                              widget.game.imageUrl!,
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
                  widget.game.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
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

/// Trailing card that opens the full library page. It is one extra cell in
/// the games row, so it gets the same hover/focus treatment as a game cover
/// (D-pad focus mirrors hover).
class _SeeAllCard extends StatefulWidget {
  const _SeeAllCard({required this.width, this.focused = false, this.onTap});

  final double width;
  final bool focused;
  final VoidCallback? onTap;

  @override
  State<_SeeAllCard> createState() => _SeeAllCardState();
}

class _SeeAllCardState extends State<_SeeAllCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
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
          child: SizedBox(
            width: widget.width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: coverAspectRatio,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: active
                          ? [
                              BoxShadow(
                                color: colorScheme.primary.withValues(
                                  alpha: 0.55,
                                ),
                                blurRadius: 24,
                                spreadRadius: 3,
                              ),
                            ]
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: colorScheme.surfaceContainerHighest,
                          border: Border.all(
                            color: active
                                ? colorScheme.primary
                                : colorScheme.outlineVariant,
                            width: active ? 3 : 2,
                          ),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.grid_view_rounded,
                                size: 44,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Ver todos',
                                style: textTheme.titleSmall?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ver todos',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
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
