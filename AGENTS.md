# AGENTS.md

Guidance for agents and humans working on `sigg_launcher`, a Flutter (Linux/GTK) desktop app: a PS3 XMB-style game launcher shell ("IFSCstation") for a school lab. UI copy is Brazilian Portuguese.

## Commands
- `flutter analyze` — MUST run after any code change; the repo must stay clean.
- `flutter build linux --debug` — produces `build/linux/x64/debug/bundle/sigg_launcher`. Run after changing Dart or anything under `linux/` (native changes require a full rebuild to take effect).
- The on-screen FPS/raster overlay (`lib/services/fps_counter.dart`, shows live FPS, avg build/raster ms, p95 raster, dropped frames in the last second) is enabled at **runtime** with `./sigg_launcher --fps-overlay`, or the `SIGG_FPS_OVERLAY` env var, or the `--dart-define=FPS_OVERLAY=true` build flag (in falling-precedence order; the last two also work since the env check is `Platform.environment`). `FPS_OVERLAY` targets the home shell via the `AppWidget`; independent of the `PERF_LOG` console harness. `build-pi.sh` accepts `--fps-overlay` to bake the define for Pi builds.
- `--fullscreen` exec flag starts the GTK window fullscreen (`linux/runner/my_application.cc`); equivalent to setting the `SIGG_FULLSCREEN` env var. On the Pi pair it with a 720p KMS mode so wlroots/labwc uses direct scan-out (see `docs/performance.md`). Without either the window stays 1280×720 with the CSD header.
- To run: `flutter run -d linux` or launch the built bundle directly.
- **ARM64 (Raspberry Pi 4) build**: manual GitHub Action `.github/workflows/build-linux-arm64.yml` → `workflow_dispatch` on `ubuntu-24.04-arm`. Installs Flutter with a shallow `git clone --branch` of a pinned tag (default `3.47.4`, Dart 3.13 — the min that satisfies `sdk: ^3.13.0`) because `subosito/flutter-action` can't resolve stable+arm64 (its issue #345: "Unable to determine Flutter version ... architecture: arm64"); arm64 Linux engine artifacts ARE published for stable 3.47.x, so the manual clone works. The runner apt step also installs `libgstreamer1.0-dev` + `libgstreamer-plugins-base1.0-dev` (the `audioplayers_linux` plugin fails `pkg_check_modules` at CMake time without them). Then `flutter build linux --release` (output `build/linux/arm64/release/bundle`), `strip`s the binary, and uploads a `sigg_launcher-linux-arm64.tar.gz` artifact (bundle + `run.sh`, which execs the bundle with the `launcher-args` `workflow_dispatch` input, e.g. `--fullscreen --fps-overlay`). Runs as a native **Wayland** client on RPi OS Bookworm+ (labwc default); flutter-pi is NOT used (DRM/KMS only, conflicts with a Wayland compositor). On a private repo the arm64 hosted runners bill minutes; switch the label to `[self-hosted, linux, arm64]` if that matters.
- Hot reload does **NOT** load new native plugins or the custom GTK method channel — after plugin/native changes, fully stop and relaunch (see Quirks).

## Architecture
- `lib/main.dart` — awaits `AppController.instance.loadUsers()` before `runApp`.
- `lib/app_widget.dart` — `MaterialApp`, single route `/` → `Library`; theme defined here (`kScreenBackground = Color(0xFF0E1116)`, `focusColor: Colors.transparent`).
- `lib/app_controller.dart` — ChangeNotifier singleton holding `users` + `currentUser`; rebuilt via `AnimatedBuilder` in `AppWidget`.
- `lib/screens/home/home.dart` — `Library` screen. No vertical scroll; single fixed 1280x720 viewport (GTK header bar shrinks the Flutter viewheight, so layout uses `LayoutBuilder`). Owns `_selected` game, nav wiring, BGM trigger.
- Widgets (`lib/screens/home/widgets/`): `header.dart`, `hero_banner.dart`, `games_row.dart` (+ `GameCover`, "Ver todos" card), `user_switcher.dart`, `user_widget.dart`, `clock.dart`, mock data (`mock_games.dart`, `mock_users.dart`).
- Sub-pages: `lib/screens/home/pages/` (store, trophies, settings, achievements).
- Services (`lib/services/`): `game_loader.dart`, `achievement_service.dart`, `bgm_player.dart`, `game_launcher.dart`, `nav_controller.dart`, `gamepad_nav.dart`, `avatar_loader.dart`, `window_service.dart`, `perf_logger.dart`, `fps_counter.dart`.

## Content model (runtime, not assets)
- Games live in the centralized registry `~/games/<GameID>/` (`$HOME/games`), the same registry `achievementd` reads. Override the root via `--dart-define=GAMES_FOLDER=...`. `<GameID>` must match the slug rules `[a-z0-9-]+`.
- Typed subfolder layout per game:
  ```
  ~/games/<GameID>/
  ├── metadata/
  │   ├── game.json          # name, tagline, description, genre, executable
  │   └── achievements.toml  # trophy definitions (read by achievementd)
  ├── images/
  │   ├── hero.*             # required, ~1900×620 (gif/webp animated preferred)
  │   ├── cover.*            # required, 600×900
  │   └── icon.*             # required, square ~512×512 (Discord RPC + trophies tab)
  ├── media/
  │   └── bgm.*              # optional: ogg/mp3/wav/m4a
  └── bin/                   # optional self-contained executables
  ```
- `GameLoader` skips folders with a non-slug id or missing hero+cover; if no games load at all the UI falls back to `mockGames` and `defaultMockUsers` (in-code mock data).
- `avatars/` folder: user profile images (`png`/`webp`/`jpg`/`jpeg`/`gif`), overridable via `--dart-define=AVATARS_FOLDER=...`. Avatars are assigned randomly to mock users at startup; fall back to colored icons if the folder is empty.
- `~/games/<GameID>/*` image/content mirrors the `.siggpkg` payload spec in `station-achievementd/docs/package-spec.md`. The launcher does NOT ship its own `games/` folder — the registry at `~/games` is the single source of game assets.

## Trophies & achievementd
- `AchievementsPage`/`GameTrophiesPage` (lib/screens/home/pages/) fetch real trophy state from the `achievementd` daemon (not mocks). `lib/services/achievement_service.dart` speaks the daemon's JSON-lines IPC: `{"v":1,"method":"snapshot","params":{"game":<GameID>,"username":<nickname>}}` over the unix socket at `$XDG_RUNTIME_DIR/achievementd/achievementd.sock`.
- `username` is the current SIGG profile identity (`AppController.currentUser`; nickname placeholder until a real user-management system lands). Each profile keeps its own unlock state in the daemon store.
- If the daemon socket is unreachable the page shows an "Serviço de troféus indisponível" state with a retry button; games the daemon doesn't know (no `achievements.toml`) are omitted.

## Navigation (D-pad)
- Input is abstracted: `NavController` (ChangeNotifier singleton) holds focus state; the keyboard listener in `home.dart` (global `HardwareKeyboard.instance.addHandler`) maps arrows + Enter/Space onto it. The gamepad input source maps onto the same methods (`lib/services/gamepad_nav.dart`).
- Two zones: `header` (profile/store/trophies/settings) and `games` (cover row). Hero and Play button are deliberately NOT focusable (mouse-only).
- The whole Library body is wrapped in `ExcludeFocus`: hardware focus is inert on the home shell so Enter/Space can never natively activate a focused button (the hero Play `FilledButton` would otherwise react to Enter alongside the NavController, dual-launching the game). Sub-pages (store/settings/etc.) are separate routes and keep normal focus.
- Clicking a header item calls `NavController.focusHeaderItem(index)` (sets zone + index) so a later Enter re-activates the clicked item.
- `Library` accepts optional injected `games` future and `gamepadEvents` stream (used by widget tests running outside Flutter's fake-async zone / with synthetic input).
- Left/Right move within a zone, stopping at edges (no wrap). Up/Down toggle zones. Enter/Space = confirm: launches the selected game (XMB-style) or triggers the focused header action. Moving across covers also updates the hero art + plays that game's BGM.
- The inactive zone dims to 45% opacity (`AnimatedOpacity`).
- Header focus indicator is ONE shared `AnimatedPositioned` ring that slides between items (positions derived from `GlobalKey`s relative to a Stack). Two ring bugs were fixed: (1) the border was overpainted by button surfaces — the child is inset via padding / ring is a separate top layer; (2) Flutter's native Material focus highlight rendered a second ring — header content is wrapped in `ExcludeFocus` and theme `focusColor` is transparent. The ring must be clamped to the Stack and the Row needs internal bottom padding so it doesn't overflow the header height.

## Gamepad input
- Backed by the `gamepads` package (native Linux plugin `gamepads_linux`, reads evdev, SDL GameController DB + Xbox-fallback normalization). `flutter_gamepads` was considered and deliberately NOT used — everything is mapped in-house.
- `GamepadNavBridge` (lib/services/gamepad_nav.dart) listens to `Gamepads.normalizedEvents` (injectable for tests) and maps to `NavController`: D-pad + left stick drive moves, A and Start confirm, B is a no-op on the home shell.
- Directions auto-repeat while held (initial 350ms, then every 120ms) to match OS keyboard auto-repeat. Sticks use a 0.5 threshold; Y axis is down=-1 / up=+1 (package convention).
- `LauncherRouteObserver` (registered as `navigatorObservers` in `app_widget.dart`) tracks whether the `/` route is on top (`isHomeTop`). The bridge only feeds the home shell while home is top; otherwise B issues `maybePop()` so it closes sub-pages and the profile switcher dialog. This gates gamepad input from leaking into home while a page/dialog is open.
- **Running game gating**: `GameRunState` (ChangeNotifier singleton, lib/services/game_run_state.dart) tracks whether a game process is alive. `GameLauncher` sets it `true` after `Process.start` succeeds and `false` on `exitCode`. The bridge early-returns on every event while `running` (moves, A/Start confirm, and B-back are all ignored) and cancels any active held-direction repeat timers on the transition, so holding the controller through a launch can't auto-scroll the hidden launcher or leave a stale repeat running when the game closes. Keyboard input is unaffected (the gate lives only in the bridge). Hidden window: `gamepads_linux` reads `/dev/input` directly, so events keep flowing to the launcher while a game has focus — the gate exists precisely for that.
- `GamepadStatus` (ChangeNotifier singleton) polls `Gamepads.list()` (every 2s) + refreshes on new device ids; header shows a `GamepadIndicator` (dims `Icons.sports_esports`, tooltip = controller names) next to the clock.
- Sub-pages are NOT yet gamepad-focusable (D-pad there = follow-up; B-back works). Gamepad mapping does not affect the keyboard path.
- **DualShock 4 (054c:09cc) mapping must be corrected at startup**: the gamepads bundled SDL DB collapses all `054c:09cc` entries into one `(vid,pid,platform)` key, last entry wins, and that last entry (`a:b1`) is wrong for the hid-playstation joystick numbering this DS4 v2 exposes over Bluetooth (js0=Cross, js1=Circle, js2=Triangle, js3=Square) — without the fix confirm became Circle and back became Triangle. `main()` calls `registerSonyMappingOverrides()` (lib/services/gamepad_nav.dart) which `ControllerDatabase.loadSdlMappings()`s the correct `a:b0,b:b1…` SDL entry, and must run BEFORE the first raw event resolves/locks-in a per-device mapping (GamepadNormalizer caches it on first event). Verified on hardware: kernel numbers circles as js1 so the fix yields Cross=confirm, Circle=back. Regression tests in `test/sony_ds4_mapping_test.dart` (lookup + normalizer through raw js keys, no fake platform needed).
- Tests: `test/gamepad_test_harness.dart` provides `FakeGamepadsPlatform` + synthetic event builders; `test/gamepad_nav_test.dart` drives nav via an injected event stream. Every widget test that can hit a gamepad stream must call `installFakeGamepads()` in `setUp` (else `MissingPluginException`).

## Launching games
- `GameLauncher.launch(context, game)` runs `sh -c '<executable>'` via `Process.start`.
- If `executable` is an existing file it is run **from its own directory** (`workingDirectory = parent`); many games (e.g. FNF/lime) fail to find assets otherwise.
- Full command strings work: `wine /path/to/Game.exe`, `steam steam://rungameid/NNN`.
- stdout/stderr are drained (chatty games like FNF would otherwise block on a full pipe); a 3s early-exit watch reports a SnackBar on quick startup failures (wrong path/missing command).
- On launch the launcher window hides via the GTK method channel (`WindowService`); when the process exits it shows again with a short delay so the game window isn't focus-stolen at close.
- A wrong/short-lived launcher (e.g. `steam steam://...`) will re-show the window before the game actually appears — expected, not a bug.

## BGM
- `BgmPlayer` (wraps `audioplayers`) plays a game's selection track. Volume fades in (~400ms) and out (~250ms) using async stepped `setVolume` calls; a generation counter cancels stale fades on rapid switching.
- Switching to a game with no `bgmPath` calls `stop()`, which fades out the previous track.
- `MissingPluginException` is caught and permanently disables the player (best-effort sound; never break the UI).

## Known quirks & gotchas
- **Native/plugin changes need a full restart**: `MissingPluginException` on `xyz.luan/audioplayers...` = stale session after adding audioplayers; the native plugin IS in `linux/flutter/generated_plugin_registrant.cc`. Fully stop and relaunch (do not hot-reload).
- **GStreamer + relative paths**: audioplayers on Linux builds a `file://` URI from the source path; relative paths fail with `gst-resource-error` ("Resource not found"). All loaded asset paths are therefore absolutized (`File(path).absolute.path`). Verify audio validity with `file <path>` before debugging the code.
- **Window hide/show** lives in `linux/runner/my_application.cc` using a custom `sigg_launcher/window` method channel (`FlMethodChannel`), registered after `fl_register_plugins`; the channel pointer is held in a file-scope `static` so it isn't garbage-collected.
- **Impeller disabled on purpose**: `my_application_activate` calls `fl_dart_project_set_enable_impeller(project, FALSE)` (Skia renderer — Impeller/Vulkan runs poorly on the Pi's V3D GPU). Impeller is enabled by default on Linux since Flutter 3.47; note the opt-out API may be removed in a future Flutter release.
- **evdev permissions**: `gamepads_linux` reads `/dev/input/event*`; an active GTK session normally gets ACL access via systemd-logind automatically. If no controller is detected, `sudo usermod -aG input $USER` + re-login (no extra system package needed).
- French quotes: prefer simple `"` in Dart strings (lints).
- Theme/seed is green but screens intentionally use neutral `kScreenBackground` via `scaffoldBackgroundColor`, not the theme color.
- Comments are welcome. Prefer concise "why" comments over restating what the code does; use them to explain non-obvious flows, race conditions, and platform quirks (e.g. audioplayers state machine, generation-token serialization in `bgm_player.dart`) so the codebase stays maintainable.

## Conventions
- State updates flow through ChangeNotifier singletons (`AppController`, `NavController`) + `ListenableBuilder`/`AnimatedBuilder`; `home.dart` also `setState`s from the `NavController` listener.
- Keep mouse and keyboard coexisting: taps still work as before; nav never steals mouse behavior.
- Mock/placeholder data lives next to the widgets that use it (`mock_*.dart`), while real file/folder loading lives in `services/`.