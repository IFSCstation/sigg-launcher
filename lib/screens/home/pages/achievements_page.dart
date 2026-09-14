import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sigg_launcher/app_controller.dart';
import 'package:sigg_launcher/screens/home/pages/game_trophies_page.dart';
import 'package:sigg_launcher/screens/home/widgets/mock_games.dart';
import 'package:sigg_launcher/services/achievement_service.dart';
import 'package:sigg_launcher/services/game_loader.dart';

class AchievementsPage extends StatefulWidget {
  const AchievementsPage({super.key});

  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends State<AchievementsPage> {
  late Future<_TrophyIndex> _index;

  @override
  void initState() {
    super.initState();
    _index = _load();
  }

  Future<_TrophyIndex> _load() async {
    final games = await GameLoader(gamesFolder: kGamesFolder).load();
    final username = AppController.instance.currentUser.nickname;
    final service = AchievementService();

    final entries = <_GameTrophyEntry>[];
    for (final game in games) {
      final id = game.id;
      if (id == null) continue;
      try {
        final snapshot = await service.snapshot(id, username: username);
        entries.add(_GameTrophyEntry(game: game, snapshot: snapshot));
      } on SocketException {
        throw const AchievementUnavailable();
      } on AchievementException catch (e) {
        if (e.code == 'unknown_game') continue;
        throw const AchievementUnavailable();
      }
    }
    return _TrophyIndex(entries);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Troféus')),
      body: FutureBuilder<_TrophyIndex>(
        future: _index,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _Unavailable(onRetry: () {
              setState(() => _index = _load());
            });
          }
          final index = snapshot.data!;
          final totalEarned = index.earnedCount;
          final totalCount = index.totalCount;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.emoji_events,
                        size: 40,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$totalEarned / $totalCount troféus',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value:
                                    totalCount == 0 ? 0 : totalEarned / totalCount,
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
              if (index.entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text('Nenhum jogo com troféus ainda.'),
                  ),
                ),
              for (final entry in index.entries)
                Card(
                  clipBehavior: Clip.antiAlias,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => GameTrophiesPage(
                            game: entry.game,
                            snapshot: entry.snapshot,
                          ),
                        ),
                      );
                    },
                    child: Row(
                      children: [
                        _GameThumb(game: entry.game),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.game.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                '${entry.snapshot.earnedCount}/${entry.snapshot.totalCount} troféus',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                        const SizedBox(width: 8),
                      ],
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

class _TrophyIndex {
  const _TrophyIndex(this.entries);

  final List<_GameTrophyEntry> entries;

  int get earnedCount =>
      entries.fold(0, (sum, e) => sum + e.snapshot.earnedCount);
  int get totalCount =>
      entries.fold(0, (sum, e) => sum + e.snapshot.totalCount);
}

class _GameThumb extends StatelessWidget {
  const _GameThumb({required this.game});

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
          errorBuilder: (_, _, _) => _fallback,
        ),
      );
    }
    return _fallback;
  }

  Widget get _fallback => Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              game.color,
              Color.lerp(game.color, Colors.black, 0.45)!,
            ],
          ),
        ),
        child: Icon(game.icon, color: Colors.white),
      );
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