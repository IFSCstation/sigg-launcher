import 'package:flutter/material.dart';
import 'package:sigg_launcher/screens/home/pages/game_trophies_page.dart';
import 'package:sigg_launcher/screens/home/pages/mock_trophies.dart';

class AchievementsPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalEarned = mockGames.fold<int>(0, (sum, g) => sum + g.earnedCount);
    final totalCount = mockGames.fold<int>(0, (sum, g) => sum + g.trophies.length);

    return Scaffold(
      appBar: AppBar(title: const Text("Trophies")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.emoji_events, size: 40, color: colorScheme.primary),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$totalEarned / $totalCount trophies',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: totalCount == 0 ? 0 : totalEarned / totalCount,
                            minHeight: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final game in mockGames)
            Card(
              clipBehavior: Clip.antiAlias,
              margin: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => GameTrophiesPage(game: game)),
                  );
                },
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [game.color, Color.lerp(game.color, Colors.black, 0.45)!],
                        ),
                      ),
                      child: Icon(game.icon, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(game.title, style: Theme.of(context).textTheme.titleMedium),
                          Text(
                            '${game.earnedCount}/${game.trophies.length} trophies',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(onPressed: null, icon: const Icon(Icons.chevron_right)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}