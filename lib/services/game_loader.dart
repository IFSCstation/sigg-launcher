import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:sigg_launcher/screens/home/widgets/mock_games.dart';
import 'package:sigg_launcher/services/software_category.dart';

/// Parent software registry root. Override with
/// `--dart-define=SOFTWARE_FOLDER=...`. Contains the two typed subfolders
/// [kGamesFolder] and [kAppsFolder].
String get kSoftwareFolder {
  const override = String.fromEnvironment('SOFTWARE_FOLDER');
  if (override.isNotEmpty) return override;
  final home = Platform.environment['HOME'];
  return home == null ? 'software' : '$home/software';
}

/// Games subfolder: `~/software/games/<GameID>/` (the registry achievementd
/// reads). Migrated manually from the old `~/games` layout.
String get kGamesFolder => '$kSoftwareFolder/games';

/// Apps subfolder: `~/software/apps/<AppID>/` (same typed layout as games).
String get kAppsFolder => '$kSoftwareFolder/apps';

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
  const GameLoader({required this.gamesFolder, required this.appsFolder});

  /// `~/software/games` — the game registry (also read by achievementd).
  final String gamesFolder;

  /// `~/software/apps` — the app registry (same typed layout).
  final String appsFolder;

  /// Scans both registry subfolders; the subfolder a package lives in is what
  /// marks it as [SoftwareCategory.game] or [SoftwareCategory.app].
  Future<List<GameEntry>> load({List<GameEntry> fallback = mockGames}) async {
    final games = <GameEntry>[];
    await _scan(Directory(gamesFolder), SoftwareCategory.game, games);
    await _scan(Directory(appsFolder), SoftwareCategory.app, games);

    games.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return games.isEmpty ? List.of(fallback) : games;
  }

  Future<void> _scan(
    Directory root,
    SoftwareCategory category,
    List<GameEntry> out,
  ) async {
    if (!await root.exists()) return;

    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final id = entity.path.split(Platform.pathSeparator).last;
      if (!_isSlug(id)) continue;

      final imagesDir = '${entity.path}/images';
      final heroPath = _findImage(imagesDir, 'hero');
      final coverPath = _findImage(imagesDir, 'cover');
      final iconPath = _findImage(imagesDir, 'icon');
      if (heroPath == null || coverPath == null) continue;

      out.add(
        _buildEntry(entity.path, id, heroPath, coverPath, iconPath, category),
      );
    }
  }

  bool _isSlug(String value) =>
      value.isNotEmpty &&
      value.codeUnits.every(
        (u) =>
            (u >= 0x61 && u <= 0x7a) || (u >= 0x30 && u <= 0x39) || u == 0x2d,
      );

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

  GameEntry _buildEntry(
    String folderPath,
    String id,
    String heroPath,
    String coverPath,
    String? iconPath,
    SoftwareCategory category,
  ) {
    final info = _readGameJson('$folderPath/metadata/game.json');

    final mediaDir = '$folderPath/media';
    final bgmPath = _findFile(mediaDir, 'bgm', _soundExtensions);

    return GameEntry(
      info['name'] ?? id,
      info['tagline'] ?? info['description'] ?? 'Pronto para jogar.',
      info['genre'] ?? category.singularLabel,
      Icons.sports_esports,
      _colorFor(id),
      id: id,
      category: category,
      description: info['description'],
      heroPath: heroPath,
      coverPath: coverPath,
      iconPath: iconPath,
      bgmPath: bgmPath,
      executable: info['executable'],
    );
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
