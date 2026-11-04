import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sigg_launcher/services/software_category.dart';

/// Manifest listing every repository source the store knows about
/// (Cydia/Sileo "sources" model). Override with `--dart-define=REPOS_FILE=`.
///
/// Format: `{"repositories": ["<path-or-url>", ...]}` where each entry points
/// to a repository index JSON (see docs/sample-repository.json).
String get kReposFile {
  const override = String.fromEnvironment('REPOS_FILE');
  if (override.isNotEmpty) return override;
  final configHome = Platform.environment['XDG_CONFIG_HOME'];
  if (configHome != null && configHome.isNotEmpty) {
    return '$configHome/sigg_launcher/repos.json';
  }
  final home = Platform.environment['HOME'];
  return home == null
      ? 'repos.json'
      : '$home/.config/sigg_launcher/repos.json';
}

/// Friendly parse/validation error shown in the store and repos pages.
class RepoException implements Exception {
  const RepoException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A free package (game/app) advertised by a repository. Everything in the
/// store is free — there is no price or purchase flow by design.
class RepoPackage {
  const RepoPackage({
    required this.id,
    required this.name,
    required this.section,
    required this.icon,
    required this.color,
    required this.repoName,
    this.tagline,
    this.description,
    this.version,
    this.badge,
    this.url,
    this.category = SoftwareCategory.game,
    this.featured = false,
  });

  /// Package id (slug), e.g. "stellar-drift".
  final String id;

  final String name;
  final String? tagline;
  final String? description;
  final String? version;

  /// Section/category used to group the store rows, e.g. "Jogos".
  final String section;

  /// Material icon name resolved from the repo JSON ("icon" field).
  final IconData icon;

  /// Accent color ("#RRGGBB" in JSON), falls back to a palette by id hash.
  final Color color;

  /// Overlay pill on the cover ("NOVO", ...).
  final String? badge;

  /// http(s) URL of the `.siggpkg` payload. Null (missing or not http(s))
  /// means browse-only: the store shows the package but offers no install.
  final String? url;

  /// App/Game kind — decides which registry subfolder an install lands in
  /// (`~/software/games` vs `~/software/apps`).
  final SoftwareCategory category;

  /// Highlighted items lead the store as the featured banner.
  final bool featured;

  /// Display name of the repository that provides this package.
  final String repoName;
}

/// One repository index: metadata + the packages it provides.
class Repository {
  const Repository({
    required this.source,
    required this.name,
    required this.author,
    this.description,
    this.packages = const [],
  });

  /// Path or URL the index was loaded from (as typed by the user).
  final String source;

  final String name;
  final String author;
  final String? description;
  final List<RepoPackage> packages;
}

const _palette = <Color>[
  Color(0xFF7C4DFF),
  Color(0xFFE91E63),
  Color(0xFF4CAF50),
  Color(0xFF2196F3),
  Color(0xFF8D6E63),
  Color(0xFFF44336),
  Color(0xFF00BCD4),
  Color(0xFF9C27B0),
];

const _iconMap = <String, IconData>{
  'album': Icons.album,
  'air': Icons.air,
  'android': Icons.android,
  'auto_awesome': Icons.auto_awesome,
  'attractions': Icons.attractions,
  'bolt': Icons.bolt,
  'calendar_month': Icons.calendar_month,
  'code': Icons.code,
  'diamond': Icons.diamond,
  'directions_car': Icons.directions_car,
  'emoji_events': Icons.emoji_events,
  'extension': Icons.extension,
  'favorite': Icons.favorite,
  'forest': Icons.forest,
  'gavel': Icons.gavel,
  'lightbulb_outline': Icons.lightbulb_outline,
  'movie': Icons.movie,
  'music_note': Icons.music_note,
  'palette': Icons.palette,
  'public': Icons.public,
  'rocket_launch': Icons.rocket_launch,
  'science': Icons.science,
  'sports_esports': Icons.sports_esports,
  'sports_soccer': Icons.sports_soccer,
  'star': Icons.star,
  'terminal': Icons.terminal,
  'widgets': Icons.widgets,
  'workspace_premium': Icons.workspace_premium,
};

/// Loads repository indexes and persists the source list.
///
/// Manifest bookkeeping and local-file sources use synchronous IO on purpose
/// (tiny JSON files, and it keeps widget tests deterministic — no pending
/// futures in Flutter's fake-async zone). Only http(s) sources hit the real
/// event loop.
class RepositoryService {
  RepositoryService({String? manifestPath})
    : manifestPath = manifestPath ?? kReposFile;

  final String manifestPath;

  /// Sources as listed in the manifest, in order.
  List<String> listSources() {
    final file = File(manifestPath);
    if (!file.existsSync()) return const [];

    final Object? data;
    try {
      data = jsonDecode(file.readAsStringSync());
    } on FormatException {
      throw const RepoException('Manifesto inválido: JSON malformado.');
    }
    if (data is! Map<String, dynamic>) {
      throw const RepoException(
        'Manifesto inválido: o topo deve ser um objeto.',
      );
    }
    final list = data['repositories'];
    if (list == null) return const [];
    if (list is! List) {
      throw const RepoException(
        'Manifesto inválido: "repositories" deve ser uma lista.',
      );
    }
    return [
      for (final source in list)
        if (source is String && source.trim().isNotEmpty) source.trim(),
    ];
  }

  void addSource(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      throw const RepoException('Informe um caminho ou URL.');
    }
    fetchSync(trimmed); // Validate before persisting.
    final sources = listSources();
    if (sources.contains(trimmed)) {
      throw RepoException('Repositório já adicionado: $trimmed');
    }
    _writeSources([...sources, trimmed]);
  }

  void removeSource(String source) {
    _writeSources(listSources().where((s) => s != source).toList());
  }

  void _writeSources(List<String> sources) {
    final file = File(manifestPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({'repositories': sources}),
    );
  }

  /// Loads every source from the manifest, skipping broken ones (the repos
  /// page surfaces per-source errors; the store just shows what loaded).
  Future<List<Repository>> loadAll() async {
    final repos = <Repository>[];
    for (final source in listSources()) {
      try {
        repos.add(await fetch(source));
      } on RepoException {
        // Skipped; RepositoriesPage reports the error per source.
      } on SocketException {
        // Unreachable host — skipped like a broken index.
      } on HttpException {
        // Bad HTTP response — skipped like a broken index.
      }
    }
    return repos;
  }

  /// Fetches and parses one repository index (local path or http(s) URL).
  Future<Repository> fetch(String source) async {
    final uri = Uri.tryParse(source);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      final client = HttpClient()..connectionTimeout = const Duration(
        seconds: 10,
      );
      try {
        final request = await client.getUrl(uri);
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw RepoException('HTTP ${response.statusCode} ao buscar $source');
        }
        return _parse(source, await utf8.decoder.bind(response).join());
      } finally {
        client.close(force: true);
      }
    }
    return fetchSync(source);
  }

  /// Synchronous variant for local-file sources (also used by [addSource]
  /// to validate a source before persisting it).
  Repository fetchSync(String source) {
    final file = File(source);
    if (!file.existsSync()) {
      throw RepoException('Arquivo não encontrado: $source');
    }
    return _parse(source, file.readAsStringSync());
  }

  Repository _parse(String source, String raw) {
    final Object? data;
    try {
      data = jsonDecode(raw);
    } on FormatException {
      throw const RepoException('JSON malformado no repositório.');
    }
    if (data is! Map<String, dynamic>) {
      throw const RepoException('JSON inválido: o topo deve ser um objeto.');
    }

    final name = data['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const RepoException('JSON inválido: falta o campo "name".');
    }

    return Repository(
      source: source,
      name: name.trim(),
      author: data['author'] is String ? data['author'] as String : 'Desconhecido',
      description: data['description'] is String
          ? data['description'] as String
          : null,
      packages: [
        for (final entry in data['packages'] ?? const [])
          if (entry is Map) _parsePackage(entry, name.trim()),
      ],
    );
  }

  RepoPackage _parsePackage(Map<dynamic, dynamic> p, String repoName) {
    final name = p['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const RepoException('JSON inválido: pacote sem "name".');
    }
    final id = p['id'] is String && (p['id'] as String).isNotEmpty
        ? p['id'] as String
        : _slug(name);
    return RepoPackage(
      id: id,
      name: name.trim(),
      tagline: p['tagline'] is String ? p['tagline'] as String : null,
      description: p['description'] is String
          ? p['description'] as String
          : null,
      version: p['version'] is String
          ? p['version'] as String
          : p['version'] is num
          ? '${p['version']}'
          : null,
      section: p['section'] is String && (p['section'] as String).isNotEmpty
          ? p['section'] as String
          : 'Geral',
      icon: _iconFor(p['icon']),
      color: _colorFor(p['color'], id),
      badge: p['badge'] is String ? p['badge'] as String : null,
      url: _httpUrlOrNull(p['url']),
      category: _categoryFor(p['category'], id),
      featured: p['featured'] == true,
      repoName: repoName,
    );
  }

  /// Only http(s) URLs are install sources; a missing, empty, or non-http(s)
  /// value yields null so the package stays browse-only instead of failing
  /// the whole index.
  String? _httpUrlOrNull(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasAuthority) return null;
    return (uri.scheme == 'http' || uri.scheme == 'https') ? trimmed : null;
  }

  /// Defaults to [SoftwareCategory.game]; an explicit but unrecognized value
  /// is a hard error so typos ("jogo") don't silently mis-file packages.
  SoftwareCategory _categoryFor(Object? value, String id) {
    if (value == null) return SoftwareCategory.game;
    if (value is String && value.trim().isEmpty) return SoftwareCategory.game;
    final parsed = value is String ? SoftwareCategory.fromName(value) : null;
    if (parsed == null) {
      throw RepoException(
        'JSON inválido: "category" inválido no pacote "$id" '
        '(use "game" ou "app").',
      );
    }
    return parsed;
  }

  IconData _iconFor(Object? value) =>
      value is String ? (_iconMap[value] ?? Icons.widgets) : Icons.widgets;

  Color _colorFor(Object? value, String id) {
    if (value is String) {
      var hex = value.replaceFirst('#', '').trim();
      if (hex.length == 6) hex = 'FF$hex';
      if (hex.length == 8) {
        final parsed = int.tryParse(hex, radix: 16);
        if (parsed != null) return Color(parsed);
      }
    }
    return _palette[id.hashCode.abs() % _palette.length];
  }

  String _slug(String value) {
    final collapsed = value
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return collapsed.isEmpty ? 'pacote' : collapsed;
  }
}
