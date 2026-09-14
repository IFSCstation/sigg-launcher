import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
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
          final cacheHeight =
              math.max(1, (constraints.maxHeight * dpr).round());

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
                Positioned.fill(child: art),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0, 0.3, 1],
                        colors: [
                          Colors.black.withValues(alpha: 0.45),
                          Colors.black.withValues(alpha: 0.15),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        stops: const [0, 0.35, 1],
                        colors: [
                          Colors.black.withValues(alpha: 0.72),
                          Colors.black.withValues(alpha: 0.28),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        stops: const [0, 0.45, 1],
                        colors: [
                          Colors.black.withValues(alpha: 0.6),
                          Colors.black.withValues(alpha: 0.15),
                          Colors.black.withValues(alpha: 0.3),
                        ],
                      ),
                    ),
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
                        fontWeight: FontWeight.w900,
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
                    SizedBox(
                      height: constraints.maxHeight * 0.04,
                    ),
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
                      fontWeight: FontWeight.w800,
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