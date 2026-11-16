import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigg_launcher/app_widget.dart';
import 'package:sigg_launcher/screens/home/pages/repositories_page.dart';
import 'package:sigg_launcher/screens/home/pages/store_page.dart';
import 'package:sigg_launcher/services/package_installer.dart';
import 'package:sigg_launcher/services/page_nav_controller.dart';
import 'package:sigg_launcher/services/repository_service.dart';
import 'package:sigg_launcher/services/software_category.dart';
import 'package:sigg_launcher/services/ui_sounds.dart';

import 'siggpkg_fixtures.dart';

/// Store/repositories keyboard+D-pad navigation. The pages push their focus
/// controllers onto [PageFocusHub]; the Launcher's keyboard handler and the
/// gamepad bridge both drive whichever controller the hub reports as active,
/// so these tests speak through the hub exactly like the input layer does.
void main() {
  setUp(() {
    UiSounds.instance.debugDisable();
    PageFocusHub.instance.debugReset();
  });

  /// Two sections: "Jogos" (3 covers) + "Apps" (1 cover) → with the
  /// category chips (row 0) + featured banner (row 1) the grid is
  /// [3 chips, 1 featured, 3, 1].
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
          category: SoftwareCategory.app,
        ),
      ];

  Future<void> pumpStore(WidgetTester tester, {PackageInstaller? installer}) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: StorePage(
          packages: Future.value(mockPackages()),
          installer: installer,
        ),
      ),
    );
    // Let the injected future resolve and the catalog render.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('the store grid is chips + featured + sections and Enter on a '
      'cover opens the package detail dialog', (tester) async {
    await pumpStore(tester);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Gerenciar fontes'), findsOneWidget);
    expect(find.text('Todos'), findsOneWidget);
    expect(find.text('Jogos'), findsWidgets); // Chip + section header.
    expect(find.text('Apps'), findsWidgets);

    final nav = PageFocusHub.instance.active;
    expect(nav, isA<GridPageNavController>());
    final grid = nav! as GridPageNavController;
    expect(grid.row, 0);
    expect(grid.col, 0);

    // Row 0 = category chips (3 cells): Left/Right walk them, no wrap.
    grid.moveRight();
    expect(grid.row, 0);
    expect(grid.col, 1);
    grid.moveRight();
    expect(grid.col, 2);
    grid.moveRight();
    expect(grid.col, 2, reason: 'no wrap at the row end');
    grid.moveLeft();
    expect(grid.col, 1);
    grid.moveLeft();
    grid.moveLeft();
    expect(grid.col, 0, reason: 'no wrap at the row start');

    // Row 1 = featured banner (single cell): Right must not move.
    grid.moveDown();
    expect(grid.row, 1);
    grid.moveRight();
    expect(grid.row, 1);
    expect(grid.col, 0);

    // Down into "Jogos": Left/Right walk the three covers.
    grid.moveDown();
    expect(grid.row, 2);
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
    expect(grid.row, 3);
    expect(grid.col, 0, reason: 'column clamps to the shorter target row');
    grid.moveDown();
    expect(grid.row, 3, reason: 'no wrap past the last row');

    // Up back to "Jogos" re-clamps into the wider row.
    grid.moveUp();
    expect(grid.row, 2);
    expect(grid.col, 0);

    // Enter/activate on a cover opens the detail dialog (mock packages have
    // no url, so the dialog shows the "no download source" notice).
    grid.activate();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Alpha'),
      ),
      findsOneWidget,
    );
    expect(
      find.text('Sem fonte de download — este pacote só pode ser navegado.'),
      findsOneWidget,
    );
    expect(
      PageFocusHub.instance.active,
      isNull,
      reason: 'routing is suspended while the detail dialog is open',
    );

    // Closing the dialog resumes routing on the same page.
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(PageFocusHub.instance.active, isNotNull);
  });

  testWidgets('the category chips filter the grid rows', (tester) async {
    await pumpStore(tester);
    final grid = PageFocusHub.instance.active! as GridPageNavController;

    // Row 0, col 2 = "Apps": activate filters to the Apps section only.
    grid.moveRight();
    grid.moveRight();
    grid.activate();
    await tester.pumpAndSettle();

    // Delta (the app) stays; the game covers are gone from the tree.
    expect(find.text('Delta'), findsWidgets);
    expect(find.text('Alpha'), findsNothing);
    // Featured row shows the only app; sections re-derived to [Apps: 1].
    grid.moveDown();
    expect(grid.row, 1);
    grid.moveDown();
    expect(grid.row, 2);
    grid.moveDown();
    expect(grid.row, 2, reason: 'filtered grid has no third section row');

    // Back to "Todos" restores every package (focus clamped back to col 0).
    grid.moveUp();
    grid.moveUp();
    grid.moveUp();
    expect(grid.row, 0);
    expect(grid.col, 0, reason: 'column clamps onto the chips row');
    grid.activate();
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsWidgets);
    expect(find.text('Delta'), findsWidgets);
  });

  testWidgets('install and uninstall lifecycle: detail dialog → progress → '
      'snackbar → INSTALADO pill → confirm removal', (tester) async {
    // Real installer writing into a temp registry, fed a fixture payload by
    // the fake downloader (no network).
    final tempDir = Directory.systemTemp.createTempSync('sigg_store_install');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    // Download gated behind a completer so the progress dialog stays up
    // (and the hub stays suspended) until the test says so.
    final gate = Completer<void>();
    final installer = PackageInstaller(
      softwareFolder: '${tempDir.path}/software',
      downloader: (url, destPath, {onProgress, isCancelled}) async {
        await gate.future;
        File(destPath).writeAsBytesSync(buildSiggpkg(gameId: 'alpha', manifestGameId: 'alpha'));
        onProgress?.call(1.0);
      },
    );

    // Same catalog, but Alpha carries a download url (browse-only mocks
    // can't install).
    final packages = [
      for (final p in mockPackages())
        p.id == 'alpha'
            ? RepoPackage(
                id: p.id,
                name: p.name,
                section: p.section,
                icon: p.icon,
                color: p.color,
                repoName: p.repoName,
                featured: p.featured,
                url: 'https://example.com/alpha.siggpkg',
              )
            : p,
    ];

    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: StorePage(packages: Future.value(packages), installer: installer),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final grid = PageFocusHub.instance.active! as GridPageNavController;

    // Row 1 = featured (Alpha): Enter starts the install behind a progress
    // dialog (hub suspended while it's up).
    grid.moveDown();
    expect(grid.row, 1);
    grid.activate();
    await tester.pump();
    expect(find.text('Instalando Alpha'), findsOneWidget);
    expect(PageFocusHub.instance.active, isNull);

    // Release the download: the install settles into the success snackbar
    // and the INSTALADO pill.
    gate.complete();
    // Default 100ms steps: the snackbar's 2s auto-dismiss timer never fires
    // mid-settle (a 3s step would skip past it).
    await tester.pumpAndSettle();
    expect(find.text('Alpha instalado.'), findsOneWidget);
    expect(find.text('INSTALADO'), findsWidgets);
    expect(PageFocusHub.instance.active, isNotNull);
    expect(
      Directory('${tempDir.path}/software/games/alpha').existsSync(),
      isTrue,
      reason: 'the payload landed in the games registry',
    );

    // Featured CTA now reads "Detalhes" and opens the detail dialog, which
    // offers the uninstall.
    grid.activate();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Desinstalar'), findsOneWidget);
    await tester.tap(find.text('Desinstalar'));
    await tester.pumpAndSettle();

    // Confirm dialog → removal → success snackbar, pill gone.
    expect(find.text('Desinstalar Alpha?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Desinstalar'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha desinstalado.'), findsOneWidget);
    expect(find.text('INSTALADO'), findsNothing);
    expect(
      Directory('${tempDir.path}/software/games/alpha').existsSync(),
      isFalse,
    );
    expect(
      PageFocusHub.instance.active,
      isNotNull,
      reason: 'routing resumes after every dialog closes',
    );
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
