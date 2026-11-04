# Plan: Software install/uninstall + App/Game categories

Status: steps 1–2 in progress; 3–9 pending.

## 1. Registry restructure — `lib/services/game_loader.dart`
- `kSoftwareFolder` = `--dart-define=SOFTWARE_FOLDER` or `$HOME/software`; derive `kGamesFolder = $SOFTWARE/games` and `kAppsFolder = $SOFTWARE/apps` (replaces `GAMES_FOLDER`).
- `GameLoader` scans **both** subfolders and tags each entry with a new `GameEntry.category` (`game` / `app`) based on which root it came from — no manifest change needed.
- Update call sites: `home.dart`, `library_page.dart`, `achievements_page.dart`, `test/header_nav_regression_test.dart`.
- **Manual migration** documented: `mv ~/games ~/software/games` (launcher looks empty until done). Follow-up (other repo): change `achievementd`'s default games dir to `~/software/games`.

## 2. Repository JSON extension — `repository_service.dart` + `docs/sample-repository.json`
Per-package new fields:
- `"url"` — **http(s) only**, points at the `.siggpkg`. Missing/invalid → package stays browse-only (CTA shows "Sem fonte de download.").
- `"category"` — `"game"` | `"app"` (default `"game"`); determines the install target subfolder.
- `section` keeps doing free-text row grouping ("Jogos", "DLCs e pacotes").

## 3. New installer — `lib/services/package_installer.dart` (adds `archive` dep)
- **Download**: streamed `HttpClient` to a temp file with progress callback + cancel.
- **Validate** (per `station-achievementd/docs/package-spec.md`): `manifest.json` at root (`package=="sigg-game"`, `pkg_version==1`, `game_id` slug == single payload folder name), required files (`metadata/game.json`, `metadata/achievements.toml`, `images/hero.*|cover.*|icon.*`), reject `..`/absolute paths/symlinks.
- **Install**: extract to `<software>/.staging/<id>/` → atomic `rename` into `~/software/{games,apps}/<id>`; copy the manifest to `<id>/metadata/package.json` so version/category/source travel with the payload (self-describing registry, no ledger to drift; `achievementd` ignores unknown files).
- **Idempotent**: same version → no-op; older → refuse (no silent downgrade).
- **Uninstall**: recursive delete of the folder; blocked while `GameRunState.running`; BGM stopped first.
- Test seam: injectable download function (tests feed fixture zips, no network).

## 4. Store UI — `store_page.dart`
- **Category chips** "Todos | Jogos | Apps" become grid row 0 (above the featured banner) — `GridPageNavController` rows = `[3, 1, ...sections]`, fully D-pad navigable; filtering re-derives sections.
- Card states: not installed → "Instalar"; installed → "INSTALADO" pill on the cover; installing → progress.
- **Card tap / Enter → detail dialog** (`_PackageDetailDialog`: name, version, source repo, category, description) with the state-aware action: **Instalar** / **Atualizar** / **Desinstalar**. Dialog uses the `PageFocusHub.suspend()/resume()` pattern.
- Featured "Instalar" CTA starts the install directly → progress dialog (LinearProgressIndicator + % + Cancelar), then SnackBar "«X» instalado." or the failure reason. `_showInstallSoon()` disappears.

## 5. Uninstall flow
Detail dialog → "Desinstalar" → confirm dialog ("Remover «X»? Os dados locais serão apagados.") → delete → SnackBar + store state refresh.

## 6. Post-install refresh — new `lib/services/software_registry.dart`
Tiny `ChangeNotifier` singleton bumped by the installer after install/uninstall; `Library` (home) and `LibraryPage` listen and re-run their load, so new games appear in the home row and grid without a restart.

## 7. Library category filter — `library_page.dart`
Same chips row ("Todos | Jogos | Apps", default Todos) as grid row 0; filters the grid. Apps launch through the exact same `GameLauncher` path (they carry `executable` in `game.json`). Home row shows both categories as-is.

## 8. Tests + docs
- New `test/package_installer_test.dart` (fixture zips via `archive`'s encoder: validation rejections, install, idempotency, uninstall).
- Update `store_nav_test.dart` (chips row + dialog activation), `library_page_nav_test.dart` (chips + filter), `repository_service_test.dart` (`url`/`category` parsing).
- `flutter analyze` clean; AGENTS.md + sample repo updated.

## 9. Deferred / follow-ups
- sha256 package verification.
- `package-spec.md` install-semantics update (games_dir → software root + category) — station-achievementd repo.
- `achievementd` default-dir change to `~/software/games` — station-achievementd repo.
- "Atualizar" flow beyond the basic version compare.
