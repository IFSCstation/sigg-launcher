import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigg_launcher/app_widget.dart';
import 'package:sigg_launcher/screens/home/pages/repositories_page.dart';
import 'package:sigg_launcher/screens/home/pages/store_page.dart';
import 'package:sigg_launcher/services/page_nav_controller.dart';
import 'package:sigg_launcher/services/repository_service.dart';
import 'package:sigg_launcher/services/ui_sounds.dart';

/// Store/repositories keyboard+D-pad navigation. The pages push their focus
/// controllers onto [PageFocusHub]; the Launcher's keyboard handler and the
/// gamepad bridge both drive whichever controller the hub reports as active,
/// so these tests speak through the hub exactly like the input layer does.
void main() {
  setUp(() {
    UiSounds.instance.debugDisable();
    PageFocusHub.instance.debugReset();
  });

  /// Two sections: "Jogos" (3 covers) + "Apps" (1 cover) → grid rows
  /// [1 (featured), 3, 1].
  List<RepoPackage> mockPackages() => const [
        RepoPackage(
          id: 'alpha',
          name: 'Alpha',
          section: 'Jogos',
          icon: Icons.star,
          color: Color(0xFFFF5252),
          repoName: 'Loja Teste',
          featured: true,
        ),
        RepoPackage(
          id: 'beta',
          name: 'Beta',
          section: 'Jogos',
          icon: Icons.casino,
          color: Color(0xFF7C4DFF),
          repoName: 'Loja Teste',
        ),
        RepoPackage(
          id: 'gamma',
          name: 'Gamma',
          section: 'Jogos',
          icon: Icons.sports_esports,
          color: Color(0xFF18FFFF),
          repoName: 'Loja Teste',
        ),
        RepoPackage(
          id: 'delta',
          name: 'Delta',
          section: 'Apps',
          icon: Icons.calculate,
          color: Color(0xFF69F0AE),
          repoName: 'Loja Teste',
        ),
      ];

  Future<void> pumpStore(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: StorePage(packages: Future.value(mockPackages())),
      ),
    );
    // Let the injected future resolve and the catalog render.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('the store pushes a grid controller sized to its sections and '
      'routes Enter to the install hint', (tester) async {
    await pumpStore(tester);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Gerenciar fontes'), findsOneWidget);

    final nav = PageFocusHub.instance.active;
    expect(nav, isA<GridPageNavController>());
    final grid = nav! as GridPageNavController;
    expect(grid.row, 0);
    expect(grid.col, 0);

    // Featured row is a single cell: Right must not move.
    grid.moveRight();
    expect(grid.row, 0);
    expect(grid.col, 0);

    // Down into "Jogos": Left/Right walk the three covers.
    grid.moveDown();
    expect(grid.row, 1);
    expect(grid.col, 0);
    grid.moveRight();
    expect(grid.col, 1);
    grid.moveLeft();
    expect(grid.col, 0);
    grid.moveLeft();
    expect(grid.col, 0, reason: 'no wrap at the row start');

    // Down into "Apps" clamps the column to that row's single cell.
    grid.moveRight();
    grid.moveRight();
    expect(grid.col, 2);
    grid.moveDown();
    expect(grid.row, 2);
    expect(grid.col, 0, reason: 'column clamps to the shorter target row');
    grid.moveDown();
    expect(grid.row, 2, reason: 'no wrap past the last row');

    // Up back to "Jogos" re-clamps into the wider row.
    grid.moveUp();
    expect(grid.row, 1);
    expect(grid.col, 0);

    // Enter/activate on a cover shows the install hint (not implemented yet).
    grid.activate();
    await tester.pump();
    expect(find.text('A instalação de pacotes chega em breve.'), findsOneWidget);
  });

  testWidgets('the store controller pops from the hub when the page closes',
      (tester) async {
    await pumpStore(tester);
    expect(PageFocusHub.instance.active, isNotNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(
      PageFocusHub.instance.active,
      isNull,
      reason: 'a closed store must stop owning D-pad input',
    );
  });

  testWidgets('empty catalog: Enter mirrors the visible CTA (open the '
      'sources manager) instead of doing nothing', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Temp manifest so the sources manager the CTA opens never touches the
    // real ~/.config config (or fires real http fetches).
    final dir = Directory.systemTemp.createTempSync('sigg_store_nav_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final service = RepositoryService(
      manifestPath: '${dir.path}/repos.json',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: StorePage(
          service: service,
          packages: Future.value(const []),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nenhum repositório adicionado.'), findsOneWidget);

    // Keyboard/gamepad users can't Tab to the CTA (Enter is consumed by the
    // focus hub), so activate must open the sources manager itself.
    PageFocusHub.instance.active!.activate();
    await tester.pumpAndSettle();
    expect(find.byType(RepositoriesPage), findsOneWidget);
  });

  testWidgets('repositories page: vertical focus covers the add card and '
      'source rows, and the add dialog suspends input routing', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Point the service at a temp manifest with one valid local source so
    // the list has the add card (row 0) + one repo card (row 1).
    final dir = Directory.systemTemp.createTempSync('sigg_repos_nav_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final index = File('${dir.path}/repo.json')
      ..writeAsStringSync(
        '{"name": "Loja Teste", "author": "IFSC", "packages": []}',
      );
    final manifest = File('${dir.path}/repos.json')
      ..writeAsStringSync('{"repositories": ["${index.path}"]}');

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: RepositoriesPage(
          service: RepositoryService(manifestPath: manifest.path),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final nav = PageFocusHub.instance.active;
    expect(nav, isNotNull);
    expect(nav!.count, 2, reason: 'add card + one source row');
    expect(nav.index, 0);

    nav.moveDown();
    await tester.pump();
    expect(nav.index, 1);
    nav.moveUp();
    await tester.pump();
    expect(nav.index, 0);

    // Enter on the add row opens the dialog AND suspends the hub, so the
    // TextField gets arrows/Enter back from the global keyboard handler.
    nav.activate();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      PageFocusHub.instance.active,
      isNull,
      reason: 'routing must be suspended while the dialog has text input',
    );

    // Closing the dialog resumes routing on the same page.
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(PageFocusHub.instance.active, isNotNull);
    expect(PageFocusHub.instance.active!.index, 0);
  });
}
