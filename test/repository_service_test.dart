import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigg_launcher/services/repository_service.dart';
import 'package:sigg_launcher/services/software_category.dart';

void main() {
  late Directory tempDir;
  late String manifestPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sigg_repos_test');
    manifestPath = '${tempDir.path}/repos.json';
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  String writeRepo(String name, Map<String, Object?> data) {
    final path = '${tempDir.path}/$name';
    File(path).writeAsStringSync(jsonEncode(data));
    return path;
  }

  Map<String, Object?> validRepo({List<Object?> packages = const []}) => {
    'name': 'Repo de Teste',
    'author': 'Tester',
    'description': 'Repo para testes',
    'packages': packages,
  };

  RepositoryService service() => RepositoryService(manifestPath: manifestPath);

  group('RepositoryService.parse', () {
    test('parses packages with defaults and explicit fields', () {
      final path = writeRepo('repo.json', validRepo(packages: [
        {
          'id': 'stellar-drift',
          'name': 'Stellar Drift',
          'tagline': 'Corrida cósmica.',
          'version': 1.5,
          'icon': 'rocket_launch',
          'color': '#7C4DFF',
          'featured': true,
        },
        {'name': 'Sem Id'},
      ]));

      final repo = service().fetchSync(path);

      expect(repo.name, 'Repo de Teste');
      expect(repo.author, 'Tester');
      expect(repo.packages, hasLength(2));

      final first = repo.packages[0];
      expect(first.id, 'stellar-drift');
      expect(first.version, '1.5'); // num coerced to string
      expect(first.section, 'Geral'); // default section
      expect(first.icon, Icons.rocket_launch);
      expect(first.color, const Color(0xFF7C4DFF));
      expect(first.featured, isTrue);
      expect(first.repoName, 'Repo de Teste');

      final second = repo.packages[1];
      expect(second.id, 'sem-id'); // slugified from name
      expect(second.icon, Icons.widgets); // unknown/missing icon fallback
      expect(second.featured, isFalse);
    });

    test('parses url and category; defaults and validates each', () {
      final path = writeRepo('url-category.json', validRepo(packages: [
        {
          'name': 'Com Tudo',
          'url': 'https://repositorio.example/pkgs/com-tudo.siggpkg',
          'category': 'app',
        },
        {'name': 'Padrões'},
        {'name': 'Url Local', 'url': '/home/lab/pkgs/nao-http.siggpkg'},
        {'name': 'Url Malformada', 'url': 'ht!tp://::'},
      ]));

      final repo = service().fetchSync(path);

      final full = repo.packages[0];
      expect(full.url, 'https://repositorio.example/pkgs/com-tudo.siggpkg');
      expect(full.category, SoftwareCategory.app);

      // Defaults: no url (browse-only) and game category.
      final defaults = repo.packages[1];
      expect(defaults.url, isNull);
      expect(defaults.category, SoftwareCategory.game);

      // Non-http(s) URLs are dropped rather than failing the index.
      expect(repo.packages[2].url, isNull);
      expect(repo.packages[3].url, isNull);
      expect(repo.packages[3].category, SoftwareCategory.game);
    });

    test('rejects an explicit but unrecognized category', () {
      final path = writeRepo('bad-category.json', validRepo(packages: [
        {'name': 'Typo', 'category': 'jogo'},
      ]));

      expect(() => service().fetchSync(path), throwsA(isA<RepoException>()));
    });

    test('rejects malformed JSON and missing name', () {
      final bad = '${tempDir.path}/bad.json';
      File(bad).writeAsStringSync('{not json');
      expect(() => service().fetchSync(bad), throwsA(isA<RepoException>()));

      final noName = writeRepo('no-name.json', {'packages': []});
      expect(() => service().fetchSync(noName), throwsA(isA<RepoException>()));

      expect(
        () => service().fetchSync('${tempDir.path}/missing.json'),
        throwsA(isA<RepoException>()),
      );
    });
  });

  group('RepositoryService manifest', () {
    test('missing manifest yields no sources', () {
      expect(service().listSources(), isEmpty);
    });

    test('addSource validates, dedupes and persists; removeSource prunes',
        () {
      final repoPath = writeRepo('repo.json', validRepo());
      final svc = service();

      svc.addSource(repoPath);
      expect(svc.listSources(), [repoPath]);

      // Duplicate rejected.
      expect(() => svc.addSource(repoPath), throwsA(isA<RepoException>()));
      // Broken source rejected before persisting.
      expect(
        () => svc.addSource('${tempDir.path}/nope.json'),
        throwsA(isA<RepoException>()),
      );
      expect(svc.listSources(), [repoPath]);

      // Manifest is a JSON object with a repositories list.
      final manifest =
          jsonDecode(File(manifestPath).readAsStringSync()) as Map;
      expect(manifest['repositories'], [repoPath]);

      svc.removeSource(repoPath);
      expect(svc.listSources(), isEmpty);
    });

    test('loadAll skips broken sources and merges packages', () async {
      final goodPath = writeRepo('good.json', validRepo(packages: [
        {'name': 'Jogo A'},
        {'name': 'Jogo B', 'section': 'Jogos'},
      ]));
      final brokenPath = writeRepo('broken.json', {'oops': true});
      // Bypass addSource (which validates before persisting, by design) to
      // exercise loadAll's own broken-source tolerance.
      File(manifestPath).writeAsStringSync(
        jsonEncode({
          'repositories': [brokenPath, goodPath],
        }),
      );

      final list = await service().loadAll();
      expect(list, hasLength(1));
      expect(list.single.name, 'Repo de Teste');
      expect(list.single.packages.map((p) => p.name), ['Jogo A', 'Jogo B']);
    });
  });
}
