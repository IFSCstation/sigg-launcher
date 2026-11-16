import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:sigg_launcher/screens/home/widgets/mock_games.dart';
import 'package:sigg_launcher/services/game_launcher.dart';

class HeroBanner extends StatelessWidget {
  const HeroBanner({super.key, required this.game});

  final GameEntry game;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final cacheWidth = math.max(1, (constraints.maxWidth * dpr).round());
          final cacheHeight = math.max(
            1,
            (constraints.maxHeight * dpr).round(),
          );

          final Widget? art = game.heroPath != null
              ? Image.file(
                  File(game.heroPath!),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  cacheWidth: cacheWidth,
                  cacheHeight: cacheHeight,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                )
              : game.imageAsset != null
              ? Image.asset(
                  game.imageAsset!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  cacheWidth: cacheWidth,
                  cacheHeight: cacheHeight,
                  filterQuality: FilterQuality.medium,
                )
              : game.imageUrl != null
              ? Image.network(
                  game.imageUrl!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  cacheWidth: cacheWidth,
                  cacheHeight: cacheHeight,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                )
              : null;

          return Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color.lerp(game.color, Colors.black, 0.35)!,
                      Color.lerp(game.color, Colors.black, 0.7)!,
                    ],
                  ),
                ),
              ),
              if (art != null) ...[
                Positioned.fill(child: RepaintBoundary(child: art)),
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(painter: _HeroScrimPainter()),
                  ),
                ),
              ],
              Padding(
                padding: EdgeInsets.fromLTRB(
                  constraints.maxWidth * 0.05,
                  constraints.maxHeight * 0.14,
                  constraints.maxWidth * 0.05,
                  constraints.maxHeight * 0.07,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      game.title,
                      style: textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                        shadows: const [
                          Shadow(
                            color: Colors.black45,
                            blurRadius: 12,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: constraints.maxHeight * 0.04),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth * 0.5,
                      ),
                      child: Text(
                        game.description ?? game.tagline,
                        style: textTheme.bodyLarge?.copyWith(
                          color: Colors.white,
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
                  ],
                ),
              ),
              Positioned(
                right: constraints.maxWidth * 0.05,
                bottom: constraints.maxHeight * 0.1,
                child: FilledButton.icon(
                  onPressed: () => GameLauncher.launch(context, game),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
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
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeroScrimPainter extends CustomPainter {
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
  bool shouldRepaint(covariant _HeroScrimPainter oldDelegate) => false;
}
