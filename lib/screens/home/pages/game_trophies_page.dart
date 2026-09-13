import 'package:flutter/material.dart';
import 'package:sigg_launcher/screens/home/pages/mock_trophies.dart';

class GameTrophiesPage extends StatelessWidget {
  const new({super.key, required this.game});

  final GameEntry game;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = game.trophies.isEmpty ? 0.0 : game.earnedCount / game.trophies.length;

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
                colors: [game.color, Color.lerp(game.color, Colors.black, 0.55)!],
              ),
            ),
            child: Row(
              children: [
                Icon(game.icon, size: 64, color: Colors.white),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        game.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${game.earnedCount}/${game.trophies.length} trophies earned',
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
              itemCount: game.trophies.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, index) {
                final trophy = game.trophies[index];
                final isEarned = trophy.isEarned;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isEarned
                        ? trophy.color.withValues(alpha: 0.25)
                        : colorScheme.surfaceContainerHighest,
                    foregroundColor: isEarned ? trophy.color : colorScheme.outline,
                    child: Icon(trophy.icon),
                  ),
                  title: Text(
                    trophy.title,
                    style: TextStyle(
                      color: isEarned ? null : colorScheme.outline,
                      fontWeight: isEarned ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  subtitle: Text(
                    trophy.description,
                    style: TextStyle(
                      color: isEarned ? colorScheme.onSurfaceVariant : colorScheme.outline,
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
}