import 'package:flutter/material.dart';
import 'dart:io';
import 'package:sigg_launcher/screens/home/widgets/mock_games.dart';
import 'package:sigg_launcher/services/achievement_service.dart';

const Color _gold = Color(0xFFF6C453);

class _TrophyHeaderIcon extends StatelessWidget {
  const _TrophyHeaderIcon({required this.game});

  final GameEntry game;

  @override
  Widget build(BuildContext context) {
    final iconPath = game.iconPath;
    if (iconPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(iconPath),
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              const Icon(Icons.emoji_events, size: 64, color: _gold),
        ),
      );
    }
    return const Icon(Icons.emoji_events, size: 64, color: _gold);
  }
}

class GameTrophiesPage extends StatelessWidget {
  const GameTrophiesPage({super.key, required this.game, required this.snapshot});

  final GameEntry game;
  final GameSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final trophies = snapshot.trophies;
    final progress =
        snapshot.totalCount == 0 ? 0.0 : snapshot.earnedCount / snapshot.totalCount;

    return Scaffold(
      appBar: AppBar(title: Text(game.title)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [const Color(0xFF1B5E20), const Color(0xFF0D3B0F)],
              ),
            ),
            child: Row(
              children: [
                _TrophyHeaderIcon(game: game),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        game.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${snapshot.earnedCount}/${snapshot.totalCount} troféus',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: progress, minHeight: 8),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: trophies.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, index) {
                final trophy = trophies[index];
                final isEarned = trophy.earned;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isEarned
                        ? _gold.withValues(alpha: 0.25)
                        : colorScheme.surfaceContainerHighest,
                    foregroundColor: isEarned ? _gold : colorScheme.outline,
                    child: Icon(
                      isEarned ? Icons.emoji_events : Icons.lock_outline,
                    ),
                  ),
                  title: Text(
                    trophy.title,
                    style: TextStyle(
                      color: isEarned ? null : colorScheme.outline,
                      fontWeight: isEarned ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  subtitle: Text(
                    _subtitle(trophy),
                    style: TextStyle(
                      color: isEarned ? colorScheme.onSurfaceVariant : colorScheme.outline,
                    ),
                  ),
                  trailing: trophy.points > 0
                      ? Text(
                          '${trophy.points} pts',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : null,
                );
              },
            ),
          ),
        ],
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