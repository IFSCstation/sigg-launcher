# Performance Plan: Flutter on Raspberry Pi 4

Status: planned. Scope: keep Flutter and reduce per-frame GPU/CPU work so rapid
D-pad nav + hero crossfades hold ~60fps on the Pi 4 4GB **release** build.
Escape hatch if targets are missed: rewrite UI in Qt Quick/QML (C++ backend is
acceptable). The acceptance gate below applies to either path.

Target hardware: Pi 4 4GB, Wayland (labwc), ARM64, V3D GPU (no Impeller —
Skia/GLES only). Real content is animated `gif`/`webp` at full res
(hero ~1900×620, cover 600×900) loaded from `games/`.

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

## Phase 0 — Measurement harness (gate every change)

1. Add `lib/services/perf_logger.dart`, active only with
   `--dart-define=PERF_LOG=true`:
   `SchedulerBinding.instance.addTimingsCallback` → log rolling avg/p95
   `build`, `raster`, total frame time, and dropped-frame count every 60 frames.
2. Script a repeatable macro on the Pi: rapid Right-arrow presses ~30s
   (hero crossfade + row scroll), then idle. Record baseline: raster p95, avg
   fps, RSS (`/proc/self/status`).
3. Re-run the same macro after each phase; only claim gains backed by the
   harness.

## Phase 1 — Image pipeline (highest ROI)

- Decode at display size: `cacheWidth`/`cacheHeight` on `Image.file` for hero
  (`hero_banner.dart`) and covers (`games_row.dart`), sized from the render
  target (~1280×520 hero, ~180×270 cover). Applies per animation frame.
  Hero frame cost ~2x cheaper, covers ~3-6x. Add
  `filterQuality: FilterQuality.medium` to cheapen the downscale.
- Cap the image cache in `main.dart`:
  `PaintingBinding.instance.imageCache` → `maximumSize` ~128,
  `maximumSizeBytes` ~32MB; evict the previous hero after its crossfade.
- Asset-side (recommended, optional content task — beats all code paths):
  regenerate heroes as animated webp ≤ 1280×520 and covers low-fps or static
  ≤ 360×540.

## Phase 2 — Hero rendering structure

- `RepaintBoundary` around hero art, each `GameCover`, and the `Header`, so the
  animated hero only repaints its own surface and the row scroll never
  re-rasterizes static covers.
- Merge the four full-bleed gradient scrims into one composite layer
  (single `ShaderMask` or pre-composed gradient).
- Cheapen the crossfade: 300→~220ms and avoid two simultaneously-live hero
  textures (keep outgoing hero as a frozen cached layer, fade in the new one
  on top).

## Phase 3 — Rebuild scoping

- Split `Library` build (`home.dart`) so only pieces driven by `NavController`
  rebuild: hero, header, games row as `ListenableBuilder(animation:
  NavController.instance)` subtrees; scope `_selectGame` to the hero only.
  Static backdrop/skeleton stays put. Kills the O(all covers) rebuild per
  keypress during scroll/crossfade.

## Phase 4 — Shader warm-up (only if first-nav jank persists)

- Skia JIT-compiles shaders on first use. If the macro shows jank on first
  moves, drive the existing loading spinner through a hidden opacity/scale
  animation at startup to prime the shader cache.

## Phase 5 — Verify & fallback

- Re-run macro: target raster p95 < 16ms and vsync-capped average during rapid
  nav. Then `flutter analyze` clean and `flutter test` green (gamepad/nav and
  sony ds4 mapping tests must stay green). No behavior regressions: hero swap,
  BGM fades, window hide/show, launch gating.
- If raster stays hot after Phases 1-3: start the Qt Quick/QML rewrite, using
  the same harness as the acceptance gate.

## House rules

- No code comments (repo rule).
- After Dart changes: `flutter analyze` and `flutter build linux --debug`.
- Build `--release` and measure on the Pi itself (x86 numbers don't transfer).