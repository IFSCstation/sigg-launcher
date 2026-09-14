import 'dart:convert';
import 'dart:io';

const int _protocolVersion = 1;

class AchievementException implements Exception {
  const AchievementException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'AchievementException($code): $message';
}

class EventRequirement {
  const EventRequirement(this.event, this.needed);

  final String event;
  final int needed;
}

class Trophy {
  const Trophy({
    required this.id,
    required this.title,
    required this.description,
    required this.points,
    required this.earned,
    this.unlockedAt,
    this.needsEvents = const [],
    this.counters = const {},
  });

  final String id;
  final String title;
  final String description;
  final int points;
  final bool earned;
  final String? unlockedAt;
  final List<EventRequirement> needsEvents;
  final Map<String, int> counters;

  static Trophy fromJson(Map<String, dynamic> json) {
    return Trophy(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      points: (json['points'] as num?)?.toInt() ?? 0,
      earned: json['earned'] as bool? ?? false,
      unlockedAt: json['unlocked_at'] as String?,
      needsEvents: [
        for (final entry in (json['needs_events'] as List? ?? []))
          EventRequirement(
            (entry as Map<String, dynamic>)['event'] as String? ?? '',
            (entry['needed'] as num?)?.toInt() ?? 0,
          ),
      ],
      counters: {
        for (final entry in (json['counters'] as Map<String, dynamic>? ?? {})
            .entries)
          entry.key: (entry.value as num).toInt(),
      },
    );
  }
}

class GameSnapshot {
  const GameSnapshot({
    required this.game,
    required this.user,
    required this.earnedCount,
    required this.totalCount,
    required this.trophies,
  });

  final String game;
  final String user;
  final int earnedCount;
  final int totalCount;
  final List<Trophy> trophies;

  static GameSnapshot fromJson(Map<String, dynamic> json) {
    return GameSnapshot(
      game: json['game'] as String? ?? '',
      user: json['user'] as String? ?? '',
      earnedCount: (json['earned_count'] as num?)?.toInt() ?? 0,
      totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
      trophies: [
        for (final trophy in (json['trophies'] as List? ?? []))
          Trophy.fromJson(trophy as Map<String, dynamic>),
      ],
    );
  }
}

class AchievementService {
  AchievementService({String? socketPath})
      : socketPath = socketPath ?? defaultSocketPath();

  final String socketPath;

  static String defaultSocketPath() {
    final runtimeDir = Platform.environment['XDG_RUNTIME_DIR'];
    final base = runtimeDir == null || runtimeDir.isEmpty
        ? Platform.environment['TMPDIR'] ?? '/tmp'
        : runtimeDir;
    return '$base/achievementd/achievementd.sock';
  }

  Future<GameSnapshot> snapshot(String game, {String? username}) async {
    final result = await _request({
      'method': 'snapshot',
      'params': {'game': game, 'username': username},
    });
    return GameSnapshot.fromJson(result);
  }

  Future<Map<String, dynamic>> _request(Map<String, dynamic> body) async {
    final socket =
        await Socket.connect(InternetAddress(socketPath, type: InternetAddressType.unix), 0);
    try {
      socket.add(
        utf8.encode('${jsonEncode({'v': _protocolVersion, ...body})}\n'),
      );
      await socket.flush();

      final chunks = <int>[];
      await for (final chunk in socket) {
        chunks.addAll(chunk);
        if (chunks.contains(0x0a)) break;
      }
      final line = utf8.decode(chunks).trim();
      if (line.isEmpty) {
        throw const AchievementException('internal', 'empty response from daemon');
      }
      final decoded = jsonDecode(line) as Map<String, dynamic>;
      if (decoded['ok'] != true) {
        final error = decoded['error'] as Map<String, dynamic>? ?? const {};
        throw AchievementException(
          error['code'] as String? ?? 'internal',
          error['message'] as String? ?? 'daemon error',
        );
      }
      return decoded['result'] as Map<String, dynamic>? ?? const {};
    } finally {
      socket.destroy();
    }
  }
}