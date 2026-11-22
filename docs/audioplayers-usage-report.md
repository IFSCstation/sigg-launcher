# Report — `audioplayers` usage in `sigg_launcher`

Date: 2026-11-22
Scope: every audio call site in `lib/`, plus the Linux implementation shipped with the
pinned dependency.

Versions inspected:

| Package | Version |
| --- | --- |
| `audioplayers` | 6.8.1 (`pubspec.yaml:11`) |
| `audioplayers_linux` | 4.3.0 |
| `audioplayers_platform_interface` | 7.2.0 |

There are only two consumers:

* `lib/services/bgm_player.dart` — looping background music for the selected game.
* `lib/services/ui_sounds.dart` — the one-shot XMB "tick" played on every focus move.
* `lib/services/audio_preferences.dart` — a thin volume/enable facade over both.

`audioplayers` is a *media player* abstraction: one `AudioPlayer` instance == one native
pipeline, built for playing a track, not for mixing short sound effects or for sample-accurate
gain automation. Both call sites use it as if it were a game-audio mixer, which is the root
cause of most findings below.

---

## 1. Severity summary

| # | Finding | Severity | Where |
| --- | --- | --- | --- |
| 1 | A new native audio pipeline is created **and destroyed on every menu tick** | High | `ui_sounds.dart:63-99` |
| 2 | Fades are implemented as 20–35 awaited platform-channel calls in Dart, with wrong timing math | High | `bgm_player.dart:121-149` |
| 3 | Native `stop()`/`dispose()` are **blocking** GStreamer calls invoked on the UI platform thread | High | `bgm_player.dart:58,115`; `ui_sounds.dart:94` |
| 4 | `play()`/`stop()` are not serialized: a stale request can stop the **newer** track | High | `bgm_player.dart:36-75` |
| 5 | Game launch is delayed by `await BgmPlayer.instance.stop()` (fade + blocking stop) | Medium | `game_launcher.dart:23`; `store_page.dart:435` |
| 6 | Position updater left at the per-frame default → `getCurrentPosition` platform call **every frame**, forever | Medium | `bgm_player.dart:50` (never set) |
| 7 | "Music off" is implemented as volume 0: muted pipeline keeps decoding and holding the sink | Medium | `audio_preferences.dart:28-33` |
| 8 | Errors are swallowed (or permanently latch the player off) with no logging/diagnostics | Medium | `bgm_player.dart:70-74,100-104`; `ui_sounds.dart:79-83` |
| 9 | Redundant per-play setup: double `stop()`, `setReleaseMode` and `setVolume(0)` on every track change | Low | `bgm_player.dart:51-58` |
| 10 | Fades are linear in amplitude, not perceptual | Low | `bgm_player.dart:133` |
| 11 | Asset SFX relies on `AudioCache` temp-file extraction; no preloading/warm-up | Low | `ui_sounds.dart:78` |
| 12 | No test seam for audio: every test calls `debugDisable()`, so none of this is exercised | Low | `test/*` |

---

## 2. Findings in detail

### 2.1 A native pipeline per UI tick (`ui_sounds.dart`)

```dart
final player = AudioPlayer();                    // :70
player.onPlayerComplete.listen((_) { ... _disposeSafely(player); });  // :72-75
await player.setReleaseMode(ReleaseMode.stop);   // :76
await player.setVolume(_volume);                 // :77
await player.play(AssetSource('sfx/click.wav')); // :78
```

The doc comment states this is deliberate, to work around a Linux stale-EOS bug. It does avoid
that bug, but at a cost the abstraction is not designed for. On Linux, `AudioPlayer()` immediately
runs `_create()` → the plugin constructor (`audio_player.cc:6-55`), which for **every tick**:

1. calls `gst_init`,
2. builds a `playbin` + `audiopanorama` + `autoaudiosink` bin and links the pads,
3. attaches a `GstBus` watch.

Then `play()` does `setSourceAsset` → `AudioCache.loadPath` (a bundle-cache lookup plus an
`existsSync` on the extracted temp file, `audio_cache.dart:143-158`) → `setSourceUrl` → a full
`GST_STATE_NULL → READY → PAUSED` transition, waits for the async `prepared` event, then
`resume`; on completion the `onPlayerComplete` handler calls `dispose()`, which runs
`ReleaseMediaSource()` and tears the whole bin down again (`audio_player.cc:446-479`).

Per tick that is ≈ 7 method-channel calls plus a full pipeline build/teardown. The tick fires on
**every** focus move, and gamepad auto-repeat drives it at ~8 Hz (`gamepad_nav.dart`, 350 ms then
120 ms), i.e. up to ~56 platform calls/s and 8 pipeline lifecycles/s while a direction is held.
Rapid moves also overlap: each tick disposes the previous player fire-and-forget, so several native
pipelines and sinks can be alive at once.

This is exactly the workload a "one player per sound" API is worst at. `PlayerMode.lowLatency` is
not an escape hatch on Linux — the plugin's `setPlayerMode` is an empty stub (`audioplayers_linux_plugin.cc`,
`"setPlayerMode"` branch, marked TODO).

### 2.2 Fades in Dart, with drifting timing (`bgm_player.dart`)

```dart
final steps = (duration.inMilliseconds / 16).floor().clamp(1, 400); // :127
...
await player.setVolume(value);                                      // :135
await Future<void>.delayed(const Duration(milliseconds: 12));       // :144
```

* The step count assumes a **16 ms** frame, but the loop sleeps **12 ms**, so even with zero
  channel latency the fade is 25 % shorter than requested: 400 ms → 25 steps × 12 ms = 300 ms;
  250 ms → 15 steps × 12 ms = 180 ms. With ~1–3 ms per channel round-trip on the Pi it lands at
  roughly 330 ms / 200 ms — audible as a slightly abrupt fade-in.
* Each `setVolume` awaits a platform round-trip, so the duration is neither wall-clock based nor
  monotonic; under load (game launching, hero image decoding) the fade stretches instead of
  staying at 400 ms.
* A single track switch costs ~45 platform calls: 15 fade-out `setVolume` + `stop`, a second
  `stop`, `setReleaseMode`, `setVolume(0)`, `setSourceUrl`/`resume`, then 25 fade-in `setVolume`
  (`bgm_player.dart:46-69,107-119`). None of this belongs in the UI isolate.
* `_fadeTo` interpolates the raw channel value linearly (`:133`). Amplitude-linear fades sound
  abrupt at the low end; perceptual curves (`pow(v, 2)`/dB) are the norm. Same issue in
  `UiSounds.setVolume`.

### 2.3 Blocking native calls on the platform thread

`audioplayers_linux` performs playback control on the Flutter platform thread (the GTK main loop):

* `Stop()` when `ReleaseMode.loop` (the mode `BgmPlayer` sets) does `SetPosition(0)` then
  `gst_element_get_state(playbin, NULL, NULL, GST_CLOCK_TIME_NONE)` — an **unbounded** wait
  (`audio_player.cc:410-428`).
* `ReleaseMediaSource()` does the same unbounded wait (`:81-92`).
* `dispose()` calls `ReleaseMediaSource()` (`:446`).

So every `BgmPlayer.stop()` and every `UiSounds` tick's `dispose()` can stall the thread that also
pumps GTK events. Typically this is a few milliseconds of jank; if the sink is suspended or the
element never reaches the requested state, it is a UI freeze with no timeout. A 12 KB click should
never be able to do that.

### 2.4 Unsynchronized `play()`/`stop()` on the shared BGM player

`BgmPlayer.play()` performs several awaits against the **same** `AudioPlayer` and only checks the
generation counter between awaits (`:43-63`). Interleaving example:

1. `play(A)` starts, sets `_currentPath = A`, and is awaiting `_player.play(...)`.
2. The user moves to B. `play(B)` bumps the generation, runs its own `stop`/`setSource` sequence
   on the same player.
3. A's `await` finally returns, sees `generation != _requestGeneration`, and executes
   `_trackActive = false; await _player!.stop();` (`:59-63`).

That `stop()` acts on the shared player and can silence **B**, which was already started. Result:
`_trackActive == true`, volume fading in, and no audio. The same hazard exists between
`stop()`'s `_fadeOutCurrent` and a concurrent `play()`. Generation counters guard the *state
writes* but not the *native side effects*; the operations need to be serialized (single-flight
queue / mutex) rather than merely tagged.

### 2.5 Launch latency

`GameLauncher.launch` awaits the fade-out before `Process.start`
(`game_launcher.dart:23`), so every game start is delayed by ~180–250 ms of fade plus the
blocking native `stop()`. The window is about to be hidden anyway; the fade is not seen. Same in
the store uninstall path (`store_page.dart:435`) where it delays the delete.

### 2.6 Per-frame position polling

The default `positionUpdater` is `FramePositionUpdater` (`audioplayer.dart:171-173`), started by
`_resume()` (`:272-279`). While BGM plays it calls `getCurrentPosition()` — a platform channel call
into `gst_element_query_position` — **once per Flutter frame**, forever, although nothing in this
app subscribes to `onPositionChanged`. On a Pi 4 rendering 720p with Skia, that is continuous main
thread work for a value nobody reads. A `TimerPositionUpdater` (e.g. 500 ms) or leaving the
position stream unused/disabled would remove it entirely.

### 2.7 "Music disabled" keeps playing

`AudioPreferences.setMusicEnabled(false)` calls `BgmPlayer.setVolume(0)`
(`audio_preferences.dart:31`), and `play()` then fades in to `_targetVolume == 0`
(`bgm_player.dart:65-68`). The pipeline stays in `PLAYING`, decoding full tracks into a muted sink
and holding the audio device. On a fanless Pi 4 that is pointless CPU/thermal load; `pause()` would
preserve the position with no decode.

### 2.8 Error handling

`catch (_)` swallows everything in both services (`bgm_player.dart:72-74`, `bgm_player.dart:102-104`,
`ui_sounds.dart:81-83`); a `MissingPluginException` permanently latches `_unavailable`. There is no
`debugPrint`, no `onLog`/`onPlayerComplete` observation in BGM, and no way to distinguish "user
disabled audio" from "GStreamer failed to open the sink" or "file is corrupt". Combined with 2.4,
a silent failure looks identical to a race. The best-effort policy is right, but the diagnostics
are missing.

Two smaller defects in the same area:

* `UiSounds.selectionChanged` sets `_active = player` before `play()`; if `play` throws, the catch
  leaves `_active` pointing at a created-but-never-disposed native player (until the next tick).
* `MissingPluginException` is caught, but the broad `catch` around the same block means a real
  `PlatformException` from GStreamer is also silenced forever if it happens first.

### 2.9 Redundant per-play work

`_fadeOutCurrent` already calls `player.stop()` (`:115`), and `play()` calls `stop()` again (`:51`),
which on Linux with loop mode is a second blocking seek. `setReleaseMode(loop)` (`:53`) is fixed for
the lifetime of the player and need not be set per track, and `setVolume(0)` (`:55`) could be part of
the initial player setup. `ReleaseMode.stop` in `UiSounds` (`:76`) is also redundant because the
player is disposed right after completion.

### 2.10 Asset handling

`AssetSource('sfx/click.wav')` is extracted by `AudioCache` into
`<tmp>/<uuid>/sfx/click.wav` on first use (`audio_cache.dart:117-131`). It is cached per process, so
the disk write happens once, but the temp-dir existence check runs on every tick and there is no
warm-up/preload at startup. `BgmPlayer.play()` also awaits `File(path).exists()` (`:40`) on every
selection change; the loader already validated the path.

### 2.11 No test coverage of the audio layer

Every widget/nav test calls `BgmPlayer.instance.debugDisable()` and
`UiSounds.instance.debugDisable()` in `setUp` (8 test files), so the entire audioplayers code path
is dead code in CI. There is no seam to assert "one create per app lifetime", "no dispose per tick",
or "a rapid A→B→A switch ends on A". This is why 2.4 can regress unnoticed.

---

## 3. Why this happens

`audioplayers` deliberately maps one Dart object to one native pipeline and exposes only
`setVolume`, `seek`, `stop`; it has no mixing engine, no fades, no polyphony, no preloading API for
SFX, and on Linux no low-latency mode. The project therefore reimplements fades and a one-shot SFX
pool on top of it — both by brute force (stepped channel calls, throwaway pipelines). Every
symptom above is a consequence of that mismatch.

---

## 4. Recommendations

### Short term (stay on `audioplayers`, low risk)

1. **SFX: preload a small pool instead of building a pipeline per tick.**
   Create 2–4 `AudioPlayer`s once, `setVolume`/`setSource(AssetSource(...))` each once, then on a
   tick use the next one with `seek(Duration.zero)` + `resume()` (or `stop()` + `resume()`), and let
   it wrap on `onPlayerComplete`. This removes the per-tick `create`/`dispose` and most of the
   blocking `ReleaseMediaSource`. If the Linux EOS path still misbehaves with a pool, dispose and
   rebuild only *one* pool member per tick, not a fresh pipeline per tick.
2. **Serialize `BgmPlayer`.** Hold a `Future<void> _chain = Future.value();` and run every
   `play`/`stop`/`setVolume` through `_chain = _chain.then((_) => _play(...))`, or use a
   `Completer`-based mutex. Keep the generation counter, but stop issuing native calls from stale
   requests (drop the `_player.stop()` in the stale-cleanup branch at `:59-63`).
3. **Fix the fade clock.** Drive the fade from elapsed wall time (`Stopwatch`), not step count ×
   12 ms, and coalesce to ~16 ms steps. Better: don't fade in Dart at all if a 6.8+ API allows gain
   ramps (it does not) — consider `flutter_soloud` (see below).
4. **Don't block launch/uninstall:** replace `await BgmPlayer.stop()` with a fire-and-forget
   `stop()` (or add `stopNow()` with no fade) before `Process.start` / folder delete.
5. **Kill per-frame polling:** `player.positionUpdater = TimerPositionUpdater(getPosition: player.getCurrentPosition, interval: const Duration(milliseconds: 500));`
   or leave it unstarted when no one listens.
6. **Pause when music is disabled**, don't just mute (`pause()`/`resume()` on the current track).
7. **Log once:** replace empty `catch` bodies with a single `debugPrint`/`PerfLogger` line including
   the exception, and keep the permanent-disable latch only for `MissingPluginException`.
8. **Drop redundant calls:** `setReleaseMode` once at creation, single `stop()`, and set the initial
   volume before the first `play()`.
9. **Perceptual gain:** map 0..1 UI volume through a curve (`v*v` or dB) before `setVolume`.

### Long term

Replace `audioplayers` with an engine built for this workload:

* **`flutter_soloud`** (or `just_audio` + a small mixer is *not* enough): one native audio engine,
  polyphonic playback of preloaded sounds, sub-frame latency, built-in volume ramps for fades, no
  GStreamer pipeline per blip, and no per-frame position polling. The UI tick becomes
  `engine.play(clickHandle)` with a gain envelope; BGM fades become
  `engine.fadeVolume(handle, target, 400ms)` on the audio thread.
* Or a small native **GStreamer service** in `linux/runner`: one persistent `playbin` for music
  (`GstStreamVolume` + `GstController` interpolation for fades) and a pre-rolled SFX bin/sink shared
  by all blips, with a Dart method channel. More work, but keeps the dependency tree small and
  avoids the per-tick cost entirely.
* Either way, expose an `AudioBackend` interface so tests can assert call sequences without
  `debugDisable()`.

---

## 5. How to verify (measure, don't guess)

1. **Count platform calls.** Temporarily wrap `AudioPlayer` in a counting proxy or
   `GST_DEBUG=3` to see pipeline create/destroy per tick. Target: 0 player `create`/`dispose` per
   tick, one `create` for BGM for the whole session.
2. **Frame time.** Run `./sigg_launcher --fps-overlay` (or `PERF_LOG`) with a gamepad holding
   Right on the home row and in the store. Record p95 raster and dropped frames before/after; the
   tick should not move them.
3. **Fade duration.** Add a test hook around `_fadeTo` and assert wall-clock 400 ms ± 30 ms.
4. **Race regression.** Add an injectable backend fake; fire `play(A)`, `play(B)`, `play(A)` with
   controlled delays and assert the final desired source is A and `_trackActive == true`.
5. **Pi 4 budget.** Measure idle CPU with BGM playing and with "music off"; the disabled case should
   drop to near-idle.
6. **Launch latency.** Time `GameLauncher.launch` from key press to process start; it should be
   < 50 ms once the stop is not awaited.

---

## Appendix — evidence map

| Evidence | File |
| --- | --- |
| Per-tick player creation/disposal | `lib/services/ui_sounds.dart:63-99` |
| Fade step math and 12 ms sleep | `lib/services/bgm_player.dart:121-149` |
| Double stop, per-play release mode | `lib/services/bgm_player.dart:49-69` |
| Stale-request `stop()` race | `lib/services/bgm_player.dart:58-63` |
| Launch awaits stop | `lib/services/game_launcher.dart:23` |
| Music-off = volume 0 | `lib/services/audio_preferences.dart:28-41` |
| Linux blocking `Stop`/`ReleaseMediaSource` | `~/.pub-cache/.../audioplayers_linux-4.3.0/linux/audio_player.cc:81-92,410-428` |
| Pipeline construction per player | `.../audio_player.cc:6-55` |
| No low-latency mode on Linux | `.../audioplayers_linux_plugin.cc` (`setPlayerMode` TODO) |
| Per-frame position updater | `~/.pub-cache/.../audioplayers-6.8.1/lib/src/position_updater.dart:63-91` and `audioplayer.dart:171-173,272-279` |
| Asset extraction to temp dir | `.../audioplayers-6.8.1/lib/src/audio_cache.dart:117-158` |

---

## 6. Follow-up — native EOS investigation (implementation notes)

The short-term fixes above were implemented in `bgm_player.dart`, `ui_sounds.dart`,
`audio_preferences.dart`, `game_launcher.dart`, `store_page.dart` and the new
`audio_handle.dart`. One requirement was to inspect `AudioPlayer::AboutToFinish()` because a
GDB backtrace named it. Findings:

* **`AboutToFinish` does not exist** in `audioplayers_linux` 4.3.0 (the pinned version), nor
  in the upstream `main` branch, nor anywhere in the audioplayers git history (GitHub commit
  search returns zero hits). `AboutToFinish` is a **GStreamer `playbin` signal**, not a method
  of this plugin. A backtrace naming it therefore came from a patched/foreign native build,
  not from the source tree this app compiles.
* The nearest real code path is `AudioPlayer::OnPlaybackEnded()` (`audio_player.cc:245`,
  called from the bus watch). With `ReleaseMode.loop` it calls `Play()` →
  `SetPosition()`/`Resume()` **directly inside a GStreamer C callback with no try/catch**.
  Those methods throw C++ `const char*` on state failures; unwinding that through GStreamer's
  C frames is undefined behaviour and can terminate the process. The plugin's method-channel
  handler has a try/catch, but the bus callback does not.
* `Stop()`/`ReleaseMediaSource()` also call
  `gst_element_get_state(..., GST_CLOCK_TIME_NONE)`, an unbounded wait on the Flutter Linux
  platform thread (the GTK main loop), so a stuck sink can freeze the UI.

Because the native file is out of scope (pinned dependency), the Dart layer now avoids the
unsafe paths instead of patching them:

1. BGM uses `ReleaseMode.release` and restarts the track from Dart on `onPlayerComplete`,
   so the native `loop` → `Play()` re-entry is never used.
2. Track transitions no longer call the native `stop()`; a new `play()` replaces the source and
   `pause() + seek(0)` (non-blocking state changes) handles explicit stops.
3. The SFX pool keeps only three long-lived players and replays them, so per-tick native
   create/dispose (and the blocking `ReleaseMediaSource()` on every click) is gone.
4. `dispose()` is only called when music is disabled, and it is not awaited by the UI.

**Remaining native risks that cannot be fixed from Dart:** the unbounded `get_state` waits in
`Stop()`/`ReleaseMediaSource()`/`Dispose()` still exist, and an exception thrown by `Pause()`/
`Resume()` inside the bus watch can still escape uncaught. Eliminating those requires a patched
plugin (guard the bus callback, use finite timeouts, and only release after reaching PAUSED) or
a different audio engine.
