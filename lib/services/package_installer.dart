import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import 'package:sigg_launcher/services/game_loader.dart';
import 'package:sigg_launcher/services/game_run_state.dart';
import 'package:sigg_launcher/services/repository_service.dart';
import 'package:sigg_launcher/services/software_category.dart';
import 'package:sigg_launcher/services/software_registry.dart';

/// Install phases reported to the UI (labels are pt-BR).
enum InstallPhase { downloading, extracting, finalizing }

/// Progress callback: [fraction] is 0..1, or -1 while the total size is
/// unknown (indeterminate progress bar).
typedef InstallProgress = void Function(InstallPhase phase, double fraction);

/// Download seam so tests can feed fixture zips without a network. Writes
/// the payload to [destPath]; reports download progress and honors
/// [isCancelled] between chunks.
typedef PackageDownloader = Future<void> Function(
  String url,
  String destPath, {
  void Function(double fraction)? onProgress,
  bool Function()? isCancelled,
});

/// User-facing install/uninstall failure; [message] is pt-BR copy ready for a
/// SnackBar.
class InstallException implements Exception {
  const InstallException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when the user cancels an install; the UI swallows it (no error
/// SnackBar, just close the progress dialog).
class InstallCancelled implements Exception {
  const InstallCancelled();
}

/// What an install actually did — the store picks the SnackBar copy from it.
enum InstallOutcome {
  /// Fresh install (nothing was there before).
  installed,

  /// Replaced an existing install with a different version (or one whose
  /// version we couldn't determine).
  updated,

  /// Already installed at the same version — nothing was touched.
  unchanged,
}

/// Installs/uninstalls `.siggpkg` payloads into the `~/software` registry,
/// conforming to the spec in `station-achievementd/docs/package-spec.md`:
/// validate the zip (manifest + required files, no traversal/symlinks),
/// extract to a staging folder inside the registry root, then atomically
/// rename into `games/<id>` or `apps/<id>` (same filesystem → rename is
/// atomic). The manifest is preserved as `metadata/package.json` so the
/// installed version travels with the payload.
class PackageInstaller {
  PackageInstaller({String? softwareFolder, PackageDownloader? downloader})
    : softwareFolder = softwareFolder ?? kSoftwareFolder,
      _download = downloader ?? downloadHttpPackage;

  /// Registry root (`~/software` unless overridden).
  final String softwareFolder;

  final PackageDownloader _download;

  String get gamesFolder => '$softwareFolder/games';

  String get appsFolder => '$softwareFolder/apps';

  /// Staging root — names start with `.`, so `GameLoader`'s slug check
  /// never picks leftovers up as software.
  String get _stagingRoot => '$softwareFolder/.staging';

  /// Path of the installed folder for [id] (either subfolder), or null.
  String? installedPath(String id) {
    final games = '$gamesFolder/$id';
    if (Directory(games).existsSync()) return games;
    final apps = '$appsFolder/$id';
    if (Directory(apps).existsSync()) return apps;
    return null;
  }

  bool isInstalled(String id) => installedPath(id) != null;

  /// Installed version from `metadata/package.json`; null when not installed
  /// or when the package was put in place manually (no manifest copy).
  String? installedVersion(String id) {
    final path = installedPath(id);
    if (path == null) return null;
    final file = File('$path/metadata/package.json');
    if (!file.existsSync()) return null;
    try {
      final data = jsonDecode(file.readAsStringSync());
      if (data is! Map<String, dynamic>) return null;
      final version = data['version'];
      return version is String && version.isNotEmpty ? version : null;
    } on FormatException {
      return null;
    }
  }

  /// Downloads, validates and installs [package] into the subfolder its
  /// category points at. Throws [InstallException] on failure,
  /// [InstallCancelled] when [isCancelled] returns true.
  Future<InstallOutcome> install(
    RepoPackage package, {
    InstallProgress? onProgress,
    bool Function()? isCancelled,
  }) async {
    final url = package.url;
    if (url == null) {
      throw InstallException(
        '"${package.name}" não tem fonte de download (campo "url").',
      );
    }
    if (GameRunState.instance.running) {
      throw const InstallException(
        'Feche o jogo em execução antes de instalar.',
      );
    }

    final staging = Directory(
      '$_stagingRoot/${package.id}-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      staging.createSync(recursive: true);

      // 1. Download the payload into staging (same filesystem as the final
      // destination, so the later rename stays atomic).
      onProgress?.call(InstallPhase.downloading, -1);
      final archivePath = '${staging.path}/payload.siggpkg';
      await _download(
        url,
        archivePath,
        onProgress: (fraction) =>
            onProgress?.call(InstallPhase.downloading, fraction),
        isCancelled: isCancelled,
      );
      _checkCancelled(isCancelled);

      // 2. Validate the spec and extract the payload folder into staging.
      onProgress?.call(InstallPhase.extracting, -1);
      final bytes = File(archivePath).readAsBytesSync();
      File(archivePath).deleteSync(); // Free space before extracting.
      final manifest = _validate(bytes, package, staging.path);
      final gameId = manifest['game_id'] as String;
      final incoming = manifest['version'] as String;

      _checkCancelled(isCancelled);

      // 3. Compare with whatever is installed before touching it.
      final installedIdPath = installedPath(package.id);
      var outcome = InstallOutcome.installed;
      if (installedIdPath != null) {
        final current = installedVersion(package.id);
        if (current != null && compareVersions(incoming, current) == 0) {
          return InstallOutcome.unchanged; // Staging cleaned in `finally`.
        }
        if (current != null && compareVersions(incoming, current) < 0) {
          throw InstallException(
            'Versão mais nova ($current) já está instalada em '
            '"${package.name}" — não é possível rebaixar.',
          );
        }
        outcome = InstallOutcome.updated;
        // Remove the old copy first (it may sit in the other subfolder if
        // the package's category changed between installs).
        Directory(installedIdPath).deleteSync(recursive: true);
      }

      // 4. Atomic rename into the registry; overwrite a leftover target so
      // the rename can't fail on an existing directory.
      onProgress?.call(InstallPhase.finalizing, -1);
      final targetParent = package.category == SoftwareCategory.app
          ? appsFolder
          : gamesFolder;
      Directory(targetParent).createSync(recursive: true);
      final target = '$targetParent/$gameId';
      final targetDir = Directory(target);
      if (targetDir.existsSync()) targetDir.deleteSync(recursive: true);
      Directory('${staging.path}/$gameId').renameSync(target);
      // `unchanged` touched nothing, so only real mutations notify listeners
      // (home/library re-scan the registry).
      if (outcome != InstallOutcome.unchanged) {
        SoftwareRegistry.instance.notifyChanged();
      }
      return outcome;
    } on InstallCancelled {
      rethrow;
    } on InstallException {
      rethrow;
    } on FormatException catch (e) {
      // Includes ArchiveException (a FormatException subclass).
      throw InstallException('Pacote inválido: ${e.message}');
    } on FileSystemException catch (e) {
      throw InstallException(
        'Erro de arquivo ao instalar: ${e.message.isEmpty ? e.path : e.message}',
      );
    } catch (e) {
      throw InstallException('Falha inesperada ao instalar: $e');
    } finally {
      // Staging always goes away — success (payload was renamed out of it),
      // failure, or cancellation alike.
      if (staging.existsSync()) {
        try {
          staging.deleteSync(recursive: true);
        } on FileSystemException {
          // Leftover for the next install to sweep; never mask the outcome.
        }
      }
    }
  }

  /// Removes the installed folder for [id]. Returns false when nothing is
  /// installed for that id.
  bool uninstall(String id) {
    if (GameRunState.instance.running) {
      throw const InstallException(
        'Feche o jogo em execução antes de desinstalar.',
      );
    }
    if (!_isSlug(id)) {
      throw InstallException('Id inválido: "$id".');
    }
    final path = installedPath(id);
    if (path == null) return false;
    Directory(path).deleteSync(recursive: true);
    SoftwareRegistry.instance.notifyChanged();
    return true;
  }

  /// Decodes + validates [bytes] per the `.siggpkg` spec and extracts the
  /// payload into [stagingDir] (the install's working directory). Returns
  /// the validated manifest; `game_id` is guaranteed to equal
  /// [RepoPackage.id] so the store's installed-state checks line up.
  Map<String, dynamic> _validate(
    List<int> bytes,
    RepoPackage package,
    String stagingDir,
  ) {
    final archive = ZipDecoder().decodeBytes(bytes, throwOnError: true);

    // Manifest at the archive root.
    final manifestFile = archive.files.where((f) => f.name == 'manifest.json');
    if (manifestFile.isEmpty) {
      throw const InstallException('Pacote inválido: falta "manifest.json".');
    }
    final manifest = _parseManifest(manifestFile.single.content);
    final gameId = manifest['game_id'] as String;
    if (gameId != package.id) {
      throw InstallException(
        'Pacote inconsistente: o manifest declara "$gameId" mas o '
        'repositório lista "${package.id}".',
      );
    }

    // Every entry must be the manifest or live under the payload folder —
    // anything else (absolute paths, "..", stray top-level files) is
    // rejected before a single byte is written.
    for (final entry in archive.files) {
      final name = entry.name.replaceAll('\\', '/');
      final segments = name.split('/');
      if (segments.contains('..') || name.startsWith('/')) {
        throw InstallException('Pacote inválido: caminho suspeito "$name".');
      }
      if (entry.isSymbolicLink || (entry.mode & 0xf000) == 0xa000) {
        throw InstallException(
          'Pacote inválido: links simbólicos não são permitidos.',
        );
      }
      final first = segments.first;
      if (first == 'manifest.json') {
        if (name != 'manifest.json') {
          throw InstallException(
            'Pacote inválido: "manifest.json" aninhado em "$name".',
          );
        }
      } else if (first != gameId) {
        throw InstallException(
          'Pacote inválido: entrada estranha "$name".',
        );
      }
    }

    // Required files (spec §3).
    bool hasFile(String relative) => archive.files.any(
      (f) => f.name.replaceAll('\\', '/') == '$gameId/$relative',
    );
    bool hasImage(String stem, List<String> extensions) => archive.files.any(
      (f) {
        final name = f.name.replaceAll('\\', '/');
        if (!name.startsWith('$gameId/images/$stem.')) return false;
        final ext = name.split('.').last.toLowerCase();
        return extensions.contains(ext);
      },
    );

    const staticExts = ['png', 'jpg', 'jpeg'];
    const animatedExts = ['gif', 'webp'];
    final heroExts = [...animatedExts, ...staticExts];
    if (!hasFile('metadata/game.json')) {
      throw const InstallException(
        'Pacote inválido: falta "metadata/game.json".',
      );
    }
    if (!hasFile('metadata/achievements.toml')) {
      throw const InstallException(
        'Pacote inválido: falta "metadata/achievements.toml".',
      );
    }
    if (!hasImage('hero', heroExts)) {
      throw const InstallException('Pacote inválido: falta "images/hero.*".');
    }
    if (!hasImage('cover', heroExts)) {
      throw const InstallException('Pacote inválido: falta "images/cover.*".');
    }
    if (!hasImage('icon', staticExts)) {
      throw const InstallException('Pacote inválido: falta "images/icon.*".');
    }

    // Extract: names are already proven to stay under staging.
    for (final entry in archive.files) {
      final name = entry.name.replaceAll('\\', '/');
      if (name == 'manifest.json') continue; // Not part of the payload.
      final destPath = '$stagingDir/$name';
      if (entry.isDirectory || name.endsWith('/')) {
        Directory(destPath).createSync(recursive: true);
        continue;
      }
      final dest = File(destPath);
      dest.parent.createSync(recursive: true);
      dest.writeAsBytesSync(entry.content);
    }

    // Keep the manifest with the payload as `metadata/package.json` so the
    // installed version survives without a separate ledger file. (The zip's
    // root manifest is not copied into the payload by the spec.)
    final payloadMeta = File('$stagingDir/$gameId/metadata/package.json');
    payloadMeta.parent.createSync(recursive: true);
    payloadMeta.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(manifest),
    );

    // Belt and braces: nothing extracted may be a symlink on disk either.
    final payloadRoot = Directory('$stagingDir/$gameId');
    for (final entity in payloadRoot.listSync(recursive: true)) {
      if (entity is Link) {
        throw InstallException(
          'Pacote inválido: link simbólico "${entity.path}".',
        );
      }
    }

    return manifest;
  }

  Map<String, dynamic> _parseManifest(List<int> bytes) {
    final Object? data;
    try {
      data = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const InstallException(
        'Pacote inválido: "manifest.json" não é JSON válido.',
      );
    }
    if (data is! Map<String, dynamic>) {
      throw const InstallException(
        'Pacote inválido: o topo do "manifest.json" deve ser um objeto.',
      );
    }
    if (data['package'] != 'sigg-game') {
      throw const InstallException(
        'Pacote inválido: "package" deve ser "sigg-game".',
      );
    }
    if (data['pkg_version'] != 1) {
      throw const InstallException(
        'Pacote inválido: "pkg_version" não suportado '
        '(esperado 1).',
      );
    }
    final gameId = data['game_id'];
    if (gameId is! String || !_isSlug(gameId)) {
      throw const InstallException(
        'Pacote inválido: "game_id" deve ser um slug [a-z0-9-]+.',
      );
    }
    if (data['name'] is! String || (data['name'] as String).trim().isEmpty) {
      throw const InstallException('Pacote inválido: falta "name".');
    }
    if (data['version'] is! String ||
        (data['version'] as String).trim().isEmpty) {
      throw const InstallException('Pacote inválido: falta "version".');
    }
    final exec = data['exec'];
    if (exec != null && exec is! String) {
      throw const InstallException(
        'Pacote inválido: "exec" deve ser uma string.',
      );
    }
    return data;
  }

  /// Throws [InstallCancelled] when the UI's cancel flag is set.
  void _checkCancelled(bool Function()? isCancelled) {
    if (isCancelled?.call() == true) throw const InstallCancelled();
  }

  bool _isSlug(String value) =>
      value.isNotEmpty &&
      value.codeUnits.every(
        (u) =>
            (u >= 0x61 && u <= 0x7a) || (u >= 0x30 && u <= 0x39) || u == 0x2d,
      );
}

/// Numeric-ish dotted-version compare ("1.10.0" > "1.9.0"); non-numeric
/// segments fall back to string compare so odd versions still order
/// deterministically. Returns <0, 0 or >0.
int compareVersions(String a, String b) {
  final pa = a.split('.');
  final pb = b.split('.');
  final length = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < length; i++) {
    // Missing trailing segments count as 0 ("1.0" == "1.0.0").
    final sa = i < pa.length ? pa[i] : '';
    final sb = i < pb.length ? pb[i] : '';
    final na = sa.isEmpty ? 0 : int.tryParse(sa);
    final nb = sb.isEmpty ? 0 : int.tryParse(sb);
    final cmp = na != null && nb != null
        ? na.compareTo(nb)
        : sa.compareTo(sb);
    if (cmp != 0) return cmp;
  }
  return 0;
}

/// Default [PackageDownloader]: streamed http(s) download with progress.
Future<void> downloadHttpPackage(
  String url,
  String destPath, {
  void Function(double fraction)? onProgress,
  bool Function()? isCancelled,
}) async {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !uri.hasAuthority ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    throw InstallException('URL de download inválida: $url');
  }
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw InstallException(
        'Servidor respondeu HTTP ${response.statusCode} ao baixar o pacote.',
      );
    }
    final total = response.contentLength; // -1 when unknown → indeterminate.
    final sink = File(destPath).openWrite();
    var received = 0;
    try {
      await for (final chunk in response) {
        if (isCancelled?.call() == true) throw const InstallCancelled();
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  } on SocketException {
    throw const InstallException(
      'Falha de conexão ao baixar o pacote. Verifique a rede.',
    );
  } on HttpException catch (e) {
    throw InstallException('Erro de rede ao baixar o pacote: ${e.message}');
  } finally {
    client.close(force: true);
  }
}
