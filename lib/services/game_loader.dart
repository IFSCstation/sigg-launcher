import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sigg_launcher/screens/home/widgets/mock_games.dart';

const String kGamesFolder = String.fromEnvironment(
  'GAMES_FOLDER',
  defaultValue: 'games',
);

const _loadPalette = <Color>[
  Color(0xFF7C4DFF),
  Color(0xFFE91E63),
  Color(0xFF4CAF50),
  Color(0xFF2196F3),
  Color(0xFF8D6E63),
  Color(0xFFF44336),
  Color(0xFF00BCD4),
  Color(0xFF9C27B0),
];

const _animatedExtensions = <String>['gif', 'webp'];
const _staticExtensions = <String>['png', 'jpg', 'jpeg'];
const _soundExtensions = <String>['ogg', 'mp3', 'wav', 'm4a'];

class GameLoader {
  const GameLoader({required this.gamesFolder});

  final String gamesFolder;

  Future<List<GameEntry>> load({List<GameEntry> fallback = mockGames}) async {
    final root = Directory(gamesFolder);
    if (!await root.exists()) return List.of(fallback);

    final games = <GameEntry>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final heroPath = _findImage(entity.path, 'hero');
      final coverPath = _findImage(entity.path, 'cover');
      if (heroPath == null || coverPath == null) continue;

      final folderName = entity.path.split(Platform.pathSeparator).last;
      games.add(_buildEntry(folderName, heroPath, coverPath));
    }

    games.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return games.isEmpty ? List.of(fallback) : games;
  }

  String? _findImage(String folderPath, String name) {
    for (final ext in [..._animatedExtensions, ..._staticExtensions]) {
      final path = '$folderPath/$name.$ext';
      if (File(path).existsSync()) return _abs(path);
    }
    return null;
  }

  String? _findFile(String folderPath, String name, List<String> extensions) {
    for (final ext in extensions) {
      final path = '$folderPath/$name.$ext';
      if (File(path).existsSync()) return _abs(path);
    }
    return null;
  }

  String _abs(String path) => File(path).absolute.path;

  GameEntry _buildEntry(String folderName, String heroPath, String coverPath) {
    final folder = Directory(File(heroPath).parent.path);
    final info = _readGameJson('${folder.path}/game.json');

    final bgmPath = info['bgm'] != null
        ? (_resolveBgm(folder.path, info['bgm']) ??
            _findFile(folder.path, 'bgm', _soundExtensions))
        : _findFile(folder.path, 'bgm', _soundExtensions);

    return GameEntry(
      info['name'] ?? folderName,
      info['tagline'] ?? info['description'] ?? 'Pronto para jogar.',
      info['genre'] ?? 'Jogo',
      Icons.sports_esports,
      _colorFor(folderName),
      description: info['description'],
      heroPath: heroPath,
      coverPath: coverPath,
      bgmPath: bgmPath,
      executable: info['executable'],
    );
  }

  String? _resolveBgm(String folderPath, String? customName) {
    if (customName != null) {
      final path = '$folderPath/$customName';
      if (File(path).existsSync()) return _abs(path);
    }
    return null;
  }

  Map<String, String?> _readGameJson(String path) {
    final file = File(path);
    if (!file.existsSync()) return const {};

    try {
      final data = jsonDecode(file.readAsStringSync());
      if (data is! Map<String, dynamic>) return const {};
      return {
        'name': _asString(data['name']),
        'tagline': _asString(data['tagline']),
        'description': _asString(data['description']),
        'genre': _asString(data['genre']),
        'bgm': _asString(data['bgm']),
        'executable': _asString(data['executable']),
      };
    } on FormatException {
      return const {};
    }
  }

  String? _asString(Object? value) => value is String ? value : null;

  Color _colorFor(String title) =>
      _loadPalette[title.hashCode.abs() % _loadPalette.length];
}