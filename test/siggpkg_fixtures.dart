import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
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

/// Catalog entry shaped like the store's repository JSON.
RepoPackage repoPackage({
  String id = 'stellar-drift',
  String name = 'Stellar Drift',
  String? url = 'https://example.com/stellar-drift.siggpkg',
  SoftwareCategory category = SoftwareCategory.game,
  bool featured = false,
  String section = 'Jogos',
  String version = '1.4.0',
}) => RepoPackage(
  id: id,
  name: name,
  section: section,
  icon: Icons.star,
  color: const Color(0xFF7C4DFF),
  repoName: 'Repo Teste',
  url: url,
  category: category,
  featured: featured,
  version: version,
);
