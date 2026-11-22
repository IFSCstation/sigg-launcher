import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sigg_launcher/screens/home/widgets/mock_games.dart';

const Color kTrophyGold = Color(0xFFF6C453);

/// Dark multi-stop scrim layered over hero/game art so overlaid text stays
/// readable (mirrors the home hero banner look).
class HeroScrimPainter extends CustomPainter {
  const HeroScrimPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    _paintGradient(
      canvas,
      rect,
      Alignment.topCenter,
      Alignment.bottomCenter,
      const [0, 0.3, 1],
      const [Color(0x73000000), Color(0x26000000), Colors.transparent],
    );
    _paintGradient(
      canvas,
      rect,
      Alignment.bottomCenter,
      Alignment.topCenter,
      const [0, 0.35, 1],
      const [Color(0xB8000000), Color(0x47000000), Colors.transparent],
    );
    _paintGradient(
      canvas,
      rect,
      Alignment.centerLeft,
      Alignment.centerRight,
      const [0, 0.45, 1],
      const [Color(0x99000000), Color(0x26000000), Color(0x4D000000)],
    );
  }

  void _paintGradient(
    Canvas canvas,
    Rect rect,
    Alignment begin,
    Alignment end,
    List<double> stops,
    List<Color> colors,
  ) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: begin,
        end: end,
        stops: stops,
        colors: colors,
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant HeroScrimPainter oldDelegate) => false;
}

/// Renders a game's hero art over a per-game gradient fallback, topped with
/// the [HeroScrimPainter] — the same layered look as the home hero banner.
/// [child] sits on top; its own height defines the banner height.
class GameBanner extends StatelessWidget {
  const GameBanner({
    super.key,
    required this.game,
    this.borderRadius,
    this.imageFit = BoxFit.cover,
    this.child,
  });

  final GameEntry game;
  final BorderRadius? borderRadius;

  /// How the hero art fills the banner. Use [BoxFit.contain] to show it whole.
  final BoxFit imageFit;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.zero;
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final cacheWidth = constraints.maxWidth.isFinite
            ? math.max(1, (constraints.maxWidth * dpr).round())
            : null;
        final cacheHeight = constraints.maxHeight.isFinite
            ? math.max(1, (constraints.maxHeight * dpr).round())
            : null;
        return ClipRRect(
          borderRadius: radius,
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Color(0xFF161B22)),
            child: Stack(
              children: [
                if (game.heroPath != null)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: Image.file(
                        File(game.heroPath!),
                        fit: imageFit,
                        gaplessPlayback: true,
                        cacheWidth: cacheWidth,
                        cacheHeight: cacheHeight,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                  ),
                const Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(painter: HeroScrimPainter()),
                  ),
                ),
                ?child,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Trophy badge: gold when earned, dimmed lock when not.
class TrophyEmblem extends StatelessWidget {
  const TrophyEmblem({
    super.key,
    required this.earned,
    this.size = 44,
    this.glow = false,
  });

  final bool earned;
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: earned
            ? kTrophyGold.withValues(alpha: 0.22)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
        border: Border.all(
          color: earned
              ? kTrophyGold.withValues(alpha: 0.65)
              : colorScheme.outlineVariant,
          width: 1.5,
        ),
        boxShadow: glow && earned
            ? [
                BoxShadow(
                  color: kTrophyGold.withValues(alpha: 0.5),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Icon(
        earned ? Icons.emoji_events : Icons.lock_outline,
        size: size * 0.52,
        color: earned ? kTrophyGold : colorScheme.outline,
      ),
    );
  }
}
