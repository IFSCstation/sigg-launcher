# Performance Plan: Flutter on Raspberry Pi 4

Status: phases 0-5 implemented; pending on-Pi measurement (rerun the PERF macro
on a release build and compare against the pre-change baseline). Escape hatch if
targets are missed: migrate to Qt Quick/QML (documented below).

Target hardware: Pi 4 4GB, Wayland (labwc), ARM64, V3D GPU (no Impeller —
Skia/GLES only). Real content is animated `gif`/`webp` at full res
(hero ~1900×620, cover 600×900) loaded from `~/games`.

## Hotspots (identified in code)

- `lib/screens/home/widgets/hero_banner.dart`
  - `Image.file` with no `cacheWidth`/`cacheHeight` → each animation frame is
    decoded + uploaded at source resolution (~2x waste on hero).
  - Four full-bleed gradient `DecoratedBox` scrims (lines 47-108) stacked over
    the art → every animated frame blits art + 4 gradient overlays across the
    whole 1280px hero.
- `lib/screens/home/home.dart`
  - `AnimatedSwitcher` (lines 207-221) crossfades the full hero; old + new hero
    both animate/live during the 300ms transition.
  - `_onNavChanged` (lines 112-122) `setState`s the whole `Scaffold` per keypress,
    rebuilding every cover in the row on every nav move.
- `lib/screens/home/widgets/games_row.dart`
  - `Image.file` covers decode/uploaded at 600×900 while displayed ~180×270
    (~8x waste per cover, times all visible covers + scrolling).
  - No `RepaintBoundary` anywhere; nothing isolates repaints.
- `lib/main.dart` — default image cache is ~100MB/1000 entries, way over budget
  for a 4GB Pi running a game alongside the launcher.

## Phase 0 — Measurement harness (gate every change) — DONE

1. `lib/services/perf_logger.dart`, active only with
   `--dart-define=PERF_LOG=true`:
   `SchedulerBinding.instance.addTimingsCallback` → log rolling avg/p95
   `build`, `raster`, total frame time, and dropped-frame count every 60 frames.

## Phase 1 — Image pipeline — DONE

- Decode at display size: `cacheWidth`/`cacheHeight` on `Image.file` for hero
  (`hero_banner.dart`) and covers (`games_row.dart`), sized from the render
  target (~1280×520 hero, ~180×270 cover). Applies per animation frame.
  Hero frame cost ~2x cheaper, covers ~3-6x.
- Image cache capped in `main.dart` (~128 entries / 32MB); previous hero
  evicted after its crossfade (`home.dart`).

## Phase 2 — Hero rendering structure — DONE

- `RepaintBoundary` around hero art (`hero_banner.dart`), each `GameCover`
  (`games_row.dart`), and header content (`header.dart`).
- The four full-bleed gradient scrims merged into one `_HeroScrimPainter`
  composited overlay (`hero_banner.dart`).

## Phase 3 — Rebuild scoping — DONE

- `home.dart` no longer `setState`s the whole Scaffold per nav change. Hero,
  header, and games row rebuild through `ListenableBuilder` on scoped
  `ValueNotifier`s (`_selected`, `_gamesActive`/`_gamesIndex`,
  `_headerActive`/`_headerIndex`); the layout skeleton stays constant.

## Phase 4 — Adjacent image preload — DONE

- `lib/services/image_cache.dart`: `ImagePreloader` precaches heroes (home,
  on selection) and covers (row, on focus change) in `index±2` using the same
  `ResizeImage` keys as the widgets, so pre-decodes hit the normal cache.
- Hero eviction in `home.dart` now skips neighbors (jump distance > 2 only).

## Phase 5 — Shader warm-up — DONE (lightweight)

- `_FadeIn` (home.dart) fades the loaded Library content in over 450ms, priming
  Skia gradient/box-shadow/clip shaders once at startup.

## FPS/raster overlay (dev tool)

- `lib/services/fps_counter.dart`, active only with
  `--dart-define=FPS_OVERLAY=true`: on-screen box (top-right) with live FPS,
  avg build/raster ms, p95 raster and dropped frames over the last second.
  Wired in `app_widget.dart` around the `MaterialApp`. Independent of the
  `PERF_LOG` console harness; use it to eyeball smoothness during nav macros
  on the Pi. Since the env check is `Platform.environment`, it is also
  enabled at runtime by `SIGG_FPS_OVERLAY=1` or `./sigg_launcher
  --fps-overlay` (no rebuild needed). `build-pi.sh --fps-overlay` adds the
  define for Pi builds.

## Phase 6 — Display path: fullscreen + direct scan-out (SPIKE)

Status: native hook in place; pending on-Pi measurement.

Reasoning: the GTK/FEL/flutter-pi/Flutter-compositor comparison concluded the
only per-frame win from flutter-pi is **no compositing pass** (same engine,
same Skia, same V3D). flutters on labwc keep that pass because wlroots
composites every client surface — unless **direct scan-out** engages, which it
does when a surface exactly matches the output geometry and nothing overlays
it. The launcher never hits that today (1280×720 window + CSD header on an
1080p output).

Change:
- `linux/runner/my_application.cc` reads the `--fullscreen` exec flag (or the
  `SIGG_FULLSCREEN` env var); when set, the GTK window starts fullscreen (CSD
  header auto-hides, so the Flutter view gets the full panel height).
- On the Pi, pair it with a 720p KMS mode (`config.txt`: `hdmi_group=2`,
  `hdmi_mode=4`) so the fullscreen surface matches the output 1:1 and wlroots
  direct-scans it. 1080p fullscreen would also scan out but makes the engine
  raster 2.25x the pixels, which is worse for the frame budget.

Verify on Pi:
1. `labwc -d` (log to file) shows `Direct scan-out enabled` (wlr_scene).
   Toggle `WLR_SCENE_DISABLE_DIRECT_SCANOUT=1` to see the difference.
2. Cursor: wlroots uses a KMS cursor plane on Pi, so it shouldn't block
   scan-out; if it does, hide it or set `WLR_NO_HARDWARE_CURSORS`.
3. PERF macro (release, `PERF_LOG=true`) before/after: framerate can stay
   equal or rise; raster p95 is engine-side, so it should be unchanged.
4. Re-show after game exit must still be fullscreen
   (`gtk_window_present` + saved fullscreen state) — the one behavior risk.

Rejected embedding alternatives (same reason each time: no raster gain +
broken "launch arbitrary windowed games" requirement):
- flutter-pi (ardera): DRM master only, no Wayland/X11 → can't coexist with a
  compositor, and games are Wayland clients.
- flutter-embedded-linux / sony: locked to Flutter ≤3.29 (project is
  3.47/Dart 3.13), no window hide/show, plugin ABI rework.
- Flutter-as-Wayland-compositor (Denial/Zenith): alpha, and compositing every
  client through Flutter destroys direct scan-out for fullscreen games —
  strictly worse than labwc.

## Verification — pending on Pi

- Re-run macro: target raster p95 < 16ms and vsync-capped average during rapid
  nav. Then `flutter analyze` clean and `flutter test` green (gamepad/nav and
  sony ds4 mapping tests must stay green). No behavior regressions: hero swap,
  BGM fades, window hide/show, launch gating.
- If raster stays hot after all phases: start the Qt Quick/QML rewrite, using
  the same harness as the acceptance gate.

## House rules

- Comments are welcome (see AGENTS.md): explain "why", not "what" — race conditions, platform quirks, and non-obvious perf trade-offs stay maintainable.
- After Dart changes: `flutter analyze` and `flutter build linux --debug`.
- Build `--release` and measure on the Pi itself (x86 numbers don't transfer).