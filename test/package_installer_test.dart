import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigg_launcher/services/game_run_state.dart';
import 'package:sigg_launcher/services/package_installer.dart';
import 'package:sigg_launcher/services/repository_service.dart';
import 'package:sigg_launcher/services/software_category.dart';

/// Builds an in-memory `.siggpkg` (root `manifest.json` + one payload folder)
/// with knobs for the spec violations the installer must reject.
List<int> buildSiggpkg({
  String gameId = 'stellar-drift',
  String manifestGameId = 'stellar-drift',
  String version = '1.4.0',
  String manifestPackage = 'sigg-game',
  int pkgVersion = 1,
  bool includeManifest = true,
  List<String> skipFiles = const [],
  List<String> extraEntries = const [],
  bool symlink = false,
}) {
  final archive = Archive();
  if (includeManifest) {
    archive.add(
      ArchiveFile.string('manifest.json', jsonEncode({
        'package': manifestPackage,
        'pkg_version': pkgVersion,
        'game_id': manifestGameId,
        'name': 'Stellar Drift',
        'version': version,
        'exec': 'bin/game.x86_64',
      })),
    );
  }
  final payload = <String, String>{
    '$gameId/metadata/game.json': '{"name":"Stellar Drift"}',
    '$gameId/metadata/achievements.toml': '[trophy]',
    '$gameId/images/hero.png': 'hero-bytes',
    '$gameId/images/cover.png': 'cover-bytes',
    '$gameId/images/icon.png': 'icon-bytes',
    '$gameId/bin/game.x86_64': 'binary-bytes',
  };
  for (final entry in payload.entries) {
    if (skipFiles.contains(entry.key)) continue;
    archive.add(ArchiveFile.string(entry.key, entry.value));
  }
  for (final name in extraEntries) {
    archive.add(ArchiveFile.string(name, 'evil-bytes'));
  }
  if (symlink) {
    archive.add(ArchiveFile.symlink('$gameId/bin/link', '../../../etc/passwd'));
  }
  return ZipEncoder().encodeBytes(archive);
}

/// Downloader seam: serves [bytes] from memory instead of the network.
PackageDownloader fakeDownloader(List<int> bytes) =>
    (url, destPath, {onProgress, isCancelled}) async {
      File(destPath).writeAsBytesSync(bytes);
      onProgress?.call(1.0);
    };

PackageDownloader failingDownloader(String message) =>
    (url, destPath, {onProgress, isCancelled}) async {
      throw InstallException(message);
    };

RepoPackage repoPackage({
  String id = 'stellar-drift',
  String? url = 'https://example.com/stellar-drift.siggpkg',
  SoftwareCategory category = SoftwareCategory.game,
}) => RepoPackage(
  id: id,
  name: 'Stellar Drift',
  section: 'Jogos',
  icon: Icons.star,
  color: const Color(0xFF7C4DFF),
  repoName: 'Repo Teste',
  url: url,
  category: category,
  version: '1.4.0',
);

void main() {
  late Directory tempDir;
  late String softwareFolder;

  PackageInstaller installerWith(List<int> bytes) => PackageInstaller(
    softwareFolder: softwareFolder,
    downloader: fakeDownloader(bytes),
  );

  /// The default installer: valid v1.4.0 payload.
  PackageInstaller installer() => installerWith(buildSiggpkg());

  String installedDir(String id) => '$softwareFolder/games/$id';

  void expectStagingClean() {
    final staging = Directory('$softwareFolder/.staging');
    if (staging.existsSync()) {
      expect(staging.listSync(), isEmpty, reason: 'staging must be swept');
    }
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sigg_installer_test');
    softwareFolder = '${tempDir.path}/software';
    GameRunState.instance.debugReset();
  });

  tearDown(() {
    GameRunState.instance.debugReset();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('install', () {
    test('valid game lands in games/ with manifest copy and clean staging',
        () async {
      final outcome = await installer().install(repoPackage());

      expect(outcome, InstallOutcome.installed);
      expect(installer().isInstalled('stellar-drift'), isTrue);
      expect(
        File('${installedDir('stellar-drift')}/metadata/game.json')
            .readAsStringSync(),
        '{"name":"Stellar Drift"}',
      );
      expect(
        File('${installedDir('stellar-drift')}/images/hero.png').existsSync(),
        isTrue,
      );
      // The manifest travels with the payload as package.json.
      expect(installer().installedVersion('stellar-drift'), '1.4.0');
      expectStagingClean();
    });

    test('category app lands in apps/ instead of games/', () async {
      final outcome = await installer().install(
        repoPackage(category: SoftwareCategory.app),
      );

      expect(outcome, InstallOutcome.installed);
      expect(
        Directory('$softwareFolder/apps/stellar-drift').existsSync(),
        isTrue,
      );
      expect(Directory(installedDir('stellar-drift')).existsSync(), isFalse);
    });

    test('reports progress phases in order', () async {
      final phases = <InstallPhase>[];
      await installer().install(
        repoPackage(),
        onProgress: (phase, fraction) => phases.add(phase),
      );

      expect(phases, isNotEmpty);
      expect(phases.first, InstallPhase.downloading);
      expect(phases, contains(InstallPhase.extracting));
      expect(phases.last, InstallPhase.finalizing);
    });

    test('same version re-install is a no-op that keeps local files',
        () async {
      await installer().install(repoPackage());
      final marker = File('${installedDir('stellar-drift')}/local-save.dat')
        ..writeAsStringSync('progress');
      // A payload without the marker (fresh bytes) must not replace it.
      final outcome = await installer().install(repoPackage());

      expect(outcome, InstallOutcome.unchanged);
      expect(marker.readAsStringSync(), 'progress');
      expectStagingClean();
    });

    test('a newer version replaces the installed one', () async {
      await installerWith(buildSiggpkg(version: '1.0.0')).install(
        repoPackage(),
      );
      expect(installer().installedVersion('stellar-drift'), '1.0.0');

      final outcome = await installerWith(
        buildSiggpkg(version: '2.0.0'),
      ).install(repoPackage());

      expect(outcome, InstallOutcome.updated);
      expect(installer().installedVersion('stellar-drift'), '2.0.0');
    });

    test('refuses to downgrade and leaves the install untouched', () async {
      await installerWith(buildSiggpkg(version: '2.0.0')).install(
        repoPackage(),
      );

      await expectLater(
        installerWith(buildSiggpkg(version: '1.0.0')).install(repoPackage()),
        throwsA(isA<InstallException>()),
      );
      expect(installer().installedVersion('stellar-drift'), '2.0.0');
      expectStagingClean();
    });

    test('fails fast without a url', () async {
      await expectLater(
        installer().install(repoPackage(url: null)),
        throwsA(isA<InstallException>()),
      );
      expect(installer().isInstalled('stellar-drift'), isFalse);
    });

    test('propagates downloader failures and sweeps staging', () async {
      final broken = PackageInstaller(
        softwareFolder: softwareFolder,
        downloader: failingDownloader('Servidor respondeu HTTP 404.'),
      );

      await expectLater(
        broken.install(repoPackage()),
        throwsA(
          isA<InstallException>().having(
            (e) => e.message,
            'message',
            contains('404'),
          ),
        ),
      );
      expect(installer().isInstalled('stellar-drift'), isFalse);
      expectStagingClean();
    });

    test('cancellation aborts after download and sweeps staging', () async {
      await expectLater(
        installer().install(repoPackage(), isCancelled: () => true),
        throwsA(isA<InstallCancelled>()),
      );
      expect(installer().isInstalled('stellar-drift'), isFalse);
      expectStagingClean();
    });

    test('install is blocked while a game is running', () async {
      GameRunState.instance.setRunning(true);

      await expectLater(
        installer().install(repoPackage()),
        throwsA(isA<InstallException>()),
      );
      expect(installer().isInstalled('stellar-drift'), isFalse);
    });
  });

  group('install validation (package-spec.md)', () {
    Future<void> expectRejected(List<int> bytes) async {
      await expectLater(
        installerWith(bytes).install(repoPackage()),
        throwsA(isA<InstallException>()),
      );
      expect(installer().isInstalled('stellar-drift'), isFalse);
      expectStagingClean();
    }

    test('rejects a package without a root manifest.json', () async {
      await expectRejected(buildSiggpkg(includeManifest: false));
    });

    test('rejects a manifest whose package/pkg_version is wrong', () async {
      await expectRejected(buildSiggpkg(manifestPackage: 'not-a-sigg-game'));
      await expectRejected(buildSiggpkg(pkgVersion: 99));
    });

    test('rejects a non-slug game_id', () async {
      await expectRejected(buildSiggpkg(manifestGameId: '../evil'));
    });

    test('rejects a game_id that differs from the repository id', () async {
      await expectRejected(buildSiggpkg(manifestGameId: 'other-game'));
    });

    test('rejects entries outside the manifest/payload (path traversal)',
        () async {
      await expectRejected(buildSiggpkg(extraEntries: ['../evil.txt']));
      await expectRejected(buildSiggpkg(extraEntries: ['evil.txt']));
      // Nothing may escape the registry root.
      expect(File('${tempDir.path}/evil.txt').existsSync(), isFalse);
      expect(File('$softwareFolder/evil.txt').existsSync(), isFalse);
    });

    test('rejects symlink entries', () async {
      await expectRejected(buildSiggpkg(symlink: true));
    });

    test('rejects payloads missing required files', () async {
      await expectRejected(
        buildSiggpkg(skipFiles: ['stellar-drift/images/icon.png']),
      );
      await expectRejected(
        buildSiggpkg(skipFiles: ['stellar-drift/metadata/achievements.toml']),
      );
      await expectRejected(
        buildSiggpkg(skipFiles: ['stellar-drift/metadata/game.json']),
      );
    });

    test('rejects a corrupt zip', () async {
      await expectRejected([1, 2, 3, 4, 5, 6, 7, 8]);
    });
  });

  group('uninstall', () {
    test('removes the installed folder and reports presence', () async {
      await installer().install(repoPackage());

      expect(installer().uninstall('stellar-drift'), isTrue);
      expect(installer().isInstalled('stellar-drift'), isFalse);
      expect(Directory(installedDir('stellar-drift')).existsSync(), isFalse);
      // Second call finds nothing.
      expect(installer().uninstall('stellar-drift'), isFalse);
    });

    test('rejects ids that could escape the registry', () async {
      expect(
        () => installer().uninstall('../games'),
        throwsA(isA<InstallException>()),
      );
    });

    test('is blocked while a game is running', () async {
      await installer().install(repoPackage());
      GameRunState.instance.setRunning(true);

      expect(
        () => installer().uninstall('stellar-drift'),
        throwsA(isA<InstallException>()),
      );
      expect(installer().isInstalled('stellar-drift'), isTrue);
    });
  });

  group('compareVersions', () {
    test('orders numeric segments numerically', () {
      expect(compareVersions('1.10.0', '1.9.0'), greaterThan(0));
      expect(compareVersions('1.0.0', '1.0.1'), lessThan(0));
      expect(compareVersions('2.0.0', '2.0.0'), 0);
      expect(compareVersions('1.0', '1.0.0'), 0); // Trailing zeros ignored.
    });

    test('falls back to string compare for non-numeric segments', () {
      expect(compareVersions('1.0.0-beta', '1.0.0'), isNot(0));
      expect(compareVersions('abc', 'abc'), 0);
    });
  });
}
