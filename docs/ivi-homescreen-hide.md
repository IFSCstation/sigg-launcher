# Hiding the launcher under ivi-homescreen

Status: **research / design draft**. Nothing in the build, the CI workflow, the
Dart code, or the ivi-homescreen source was changed for this document. It
records what the embedder actually provides (verified against source), what is
missing, the revised design, and the patch sketch.

Claims are marked **[VERIFIED]** (checked against ivi-homescreen source at the
given file:line) or **[UNVERIFIED]** (not checked against source; treat as a
hypothesis to confirm on the target).

## Requirement (unchanged)

Single-window app, running under labwc with the xdg shell. Dart must be able to
hide the window programmatically, keep running in the background while a
launched subprocess runs, and show the window again when it exits. While hidden,
the app must not render a single frame.

## What was removed from the earlier plan

- **Null-buffer unmap (`wl_surface_attach(NULL)` + commit) removed.**
  For an `xdg_toplevel` this is wrong: unmapping discards toplevel state
  (title, app_id, fullscreen, maximized, ...) and returns the surface to the
  state right after `get_toplevel`. Re-mapping requires a buffer-less commit,
  waiting for a configure, and acking it *before* attaching a buffer; attaching
  earlier is a protocol error and compositors such as wlroots/labwc disconnect
  the client ("xdg_surface has never been configured"). Since `wl_egl_window`
  attaches inside `eglSwapBuffers()`, the `show` path would likely crash the
  app. **[UNVERIFIED for labwc specifically; the protocol constraint is from
  xdg-shell.]**

- **"Race with the raster thread" options removed.** They existed only to
  support the null-commit unmap. With the unmap gone, they are moot.

- **"Unmapping is needed for fullscreen direct scan-out under labwc" removed.**
  Treated as unverified. Occluded surfaces are often culled by the compositor
  anyway; whether labwc requires an unmapped launcher surface for direct
  scan-out is not established. **[UNVERIFIED]**

## What is kept from the earlier plan

- `sigg_launcher/window` method channel with `hide` / `show`, registered in
  `SetUpCommonEngineState()`. **[VERIFIED approach — see patch.]**
- `FlutterView::Suspend()` / `Resume()` and vsync parking as the mechanism that
  stops frames. **[VERIFIED]** — `shell/view/flutter_view.h:289,296`,
  `shell/view/flutter_view.cc:470-503`,
  `shell/backend/wayland_egl/wayland_egl.h:206-209`,
  `shell/vsync/ivsync_provider.cc:313-322`.
- The `wp_presentation` / `IVI_WL_VSYNC` precondition and verification of it.
  **[VERIFIED code path]** — parking only forwards when `vsync_ != nullptr`
  (`shell/backend/wayland_egl/wayland_egl.h:206-209`), and the engine uses the
  provider only when `GetVsyncCallback()` is non-null (requires `wp_presentation`
  with `CLOCK_MONOTONIC` and `IVI_WL_VSYNC != 0`). **[UNVERIFIED]**: labwc
  actually advertises `wp_presentation` on the target.
- Two-reasons-to-suspend (app-hidden vs output-disconnected), replacing the
  single `m_suspended` bool. **[VERIFIED need]** — `App::ApplyOnDisconnect()`
  calls `view->Suspend()` (`shell/app.cc:549`) and `view->Resume()`
  (`shell/app.cc:589,596`); a single bool makes the two causes
  indistinguishable.

## The embedder primitive (verified)

`FlutterView::Suspend()` / `Resume()` → `Backend::SetVsyncParked(true/false)`
→ `IVsyncProvider::SetParked()`. While parked:

- `DeliverBaton()`, `DrainParkedBaton()` and `DeliverDiscard()` all early-return
  (`shell/vsync/ivsync_provider.cc:324-333`), so no `FlutterEngineOnVsync` is
  posted.
- Flutter never receives a vsync callback, so the UI thread, rasterizer, GPU
  and scanout stay idle — zero frames.
- Reversible; keeps the engine warm.

`SetSuspended()` is safe to call from the platform thread and is idempotent
(`shell/view/flutter_view.cc:470-473`). `IVsyncProvider::IsParked()` is
thread-safe (`shell/vsync/ivsync_provider.h:135`).

The only current caller is `App::ApplyOnDisconnect()` (output unplugged,
`shell/app.cc:538-550`). There is no Dart-facing path to it.

**Precondition:** `WaylandEglBackend::SetVsyncParked()` only forwards to the
provider when `vsync_ != nullptr` (`shell/backend/wayland_egl/wayland_egl.h:206-
209`). The provider exists only when the compositor advertises `wp_presentation`
with `CLOCK_MONOTONIC` and `IVI_WL_VSYNC != 0`. If unavailable, Flutter falls
back to its wall-clock scheduler and parking is a no-op. Verify the
`[WaylandVsync]` / `wp_presentation` log line on the target.

## Visual hiding: minimize via foreign-toplevel (replacement for null-commit)

`Suspend()` stops frame production but leaves the last buffer attached to the
`wl_surface`, so the launcher remains in the compositor scene. For visual
hiding under labwc, the replacement is **minimize via
wlr-foreign-toplevel-management**:

- **Hide:** park vsync (`Suspend()`), then `set_minimized` on our own
  foreign-toplevel handle.
- **Show:** `unset_minimized` + `activate` on the handle, then `Resume()`.

labwc implements `zwlr_foreign_toplevel_manager_v1`. Its toplevel handle has
`set_minimized`, `unset_minimized` and `activate`. Minimized state is owned by
the compositor, so there is no role teardown, no reconfigure handshake, and a
late frame commit cannot re-map the surface. **[UNVERIFIED]** — not checked
against labwc source; confirmed only as the user's stated requirement.

Implementation notes:

- Bind `zwlr_foreign_toplevel_manager_v1` in the xdg shell client
  (`shell/wayland/shell/xdg_shell.cc`). Add the protocol XML to the scanner
  inputs (`shell/wayland/protocols/` + `cmake/wayland_cxx.cmake`).
- Collect handles from `toplevel` events; identify our own toplevel by a unique
  `app_id` (set via the app_id config, already passed to `xdg_toplevel.set_app_id`
  at `shell/wayland/shell/xdg_shell.cc:96`). The compositor reports ALL
  toplevels, so filter strictly by app_id.
- Post all Wayland requests onto the Wayland reactor thread (Display already
  owns `asio::io_context* ioc_` and uses `asio::post(*ioc_, ...)` internally at
  `shell/wayland/display.cc:821,842,853`); never issue them from the raster or
  platform thread.
- Confirm in compositor-reported state events (`configure` states array,
  handled at `shell/wayland/shell/xdg_shell.cc:80-115`) that the window actually
  became minimized/unminimized; do not assume the request succeeded.
- Handle the case where the foreign-toplevel global is absent (other
  compositors): report that hide is unsupported rather than pretending it
  worked. **[UNVERIFIED]** — no foreign-toplevel code exists in ivi-homescreen
  today.

**`xdg_toplevel.set_minimized` is NOT sufficient:** xdg-shell's
`set_minimized` has no matching `unset_minimized` — "There is no way to know if
the surface is currently minimized, nor is there any way to unset minimization
on this surface" (`/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml:
1131-1138`). Only foreign-toplevel provides both directions.

## State machine

```
Visible -> Hiding -> Hidden -> Showing -> Visible
```

`hide` must only reply once no frame is in flight (drain outstanding batons /
track last present). `show` transitions Hidden → Showing → Visible. This
prevents a frame that started before `hide` from committing after the surface
is minimized (which would violate "not a single frame while hidden").

**Currently unverified:** ivi-homescreen has no exposed "frame in flight"
counter at the `FlutterView` level. `IVsyncProvider` tracks `source_pending_`
internally (`shell/vsync/ivsync_provider.h`) but it is not exposed through
`Backend` or `FlutterView`. The patch may need to add one, or treat `hide` as
"parking requested" and rely on the minimize + parked vsync to prevent visible
frames even if one was already in flight.

## No silent failure

If the vsync provider does not exist (`wp_presentation` missing or
`IVI_WL_VSYNC=0`), parking is a no-op — frames are still produced. `hide` must
return an error (or a `parked: false` flag), not `Success`, so Dart knows.

**Verification approach:** after `SetSuspended(true)`, check
`IsParked()` on the provider. If false, return an error from the `hide` method.
Requires exposing `IsParked()` through `Backend` → `FlutterView`
(see patch sketch).

## Watchdog

`BUILD_WATCHDOG=ON` makes a parked render thread stop checking in and abort the
process after `timeout_ms` (default 5000ms) — `abort()` on timeout,
`shell/watchdog/README.md:53`. The render thread is petted at
`shell/engine.cc:1496`; the main thread at `shell/app.cc:673,764,810`.

While hidden, pause/stop the render source and restart it on `show`. Where the
render thread is the one being watched, `hide` should either pet it on a
reduced cadence or temporarily deregister it; `show` re-registers. **[UNVERIFIED]**
— exact mechanism depends on whether the render thread continues running while
parked (it does: parking only withholds the vsync baton, the thread itself is
alive).

## Lifecycle

The embedder does **not** handle `flutter/lifecycle` messages — no handler is
registered for that channel (`shell/platform/homescreen/platform_handler.cc`
handles only `flutter/platform` clipboard; `shell/view/flutter_view.cc` and
`shell/app.cc` have no `flutter/lifecycle` handling). Confirmed by grep of
`shell/`.

Send `AppLifecycleState.hidden` on `hide` and `AppLifecycleState.resumed` on
`show` so the Flutter framework stops scheduling frames and tickers pause.
Note: `scheduleForcedFrame` ignores lifecycle state — grep the app and plugins
for it before relying on lifecycle alone. **[UNVERIFIED]** — exact message
format (JSON vs plain string) and channel handling on the Flutter side need
confirmation against the Flutter engine version in use.

## Other drawers / platform views

List built-in plugins and platform views that could commit buffers while hidden,
and make sure `set_suspended` notification stops them:

- `shell/platform/homescreen/text_input_plugin.cc` — text input, no buffer
  commits.
- `shell/platform/homescreen/mouse_cursor_handler.cc` — cursor, no buffer
  commits.
- `shell/platform/homescreen/watchdog_plugin.cc` — watchdog, no buffer commits.
- `shell/platform/homescreen/platform_views/` — platform views (video, camera,
  any `wl_subsurface`) can commit buffers. `NotifySuspended()` at
  `shell/view/flutter_view.cc:470` notifies platform views via
  `PlatformViewRegistry::SetSuspended(id, off)`. **[UNVERIFIED]** — confirm
  all built-in platform views honor `set_suspended`.

## Suspend reasons (replacing single bool)

Replace `FlutterView::m_suspended` (single bool,
`shell/view/flutter_view.h:488`) with two flags (app-hidden and
output-suspended), or a counter, so `show` cannot resume a view whose output is
gone. Park while either reason is set.

**Verified existing usage:** `App::ApplyOnDisconnect()` calls `view->Suspend()`
(`shell/app.cc:549`) on output loss, and `view->Resume()` on `kMoved` /
`kAppeared` (`shell/app.cc:589,596`). These must be migrated to the
reason-based API.

## Build/CI

- Pin the clone to a specific commit SHA on the upstream v3.0 branch, not the
  `v3.0.0` tag unless confirmed. Current v3.0 HEAD:
  `9c6dac86df39961851c1d188c554afe7f6617754` (2026-11-25). **[VERIFIED]** via
  `git log` on the local clone. `v3.0.0` tag exists and contains
  `Suspend()/Resume()` — confirmed via `git show v3.0.0:shell/view/flutter_view.h`.
  Prefer a commit SHA on v3.0 because recent upstream fixes land on that branch.
- Keep the `apply --check` / `apply` flow in the workflow:
  ```sh
  git -C "$B/ivi-homescreen" apply --check \
    "$GITHUB_WORKSPACE/tool/ivi-homescreen/0001-sigg-window-channel.patch"
  git -C "$B/ivi-homescreen" apply \
    "$GITHUB_WORKSPACE/tool/ivi-homescreen/0001-sigg-window-channel.patch"
  ```
- Mention (do not do) the option of upstreaming the channel to
  toyota-connected/ivi-homescreen so the patch need not be carried.

## Dart side

- `WindowService` should catch `PlatformException` as well as
  `MissingPluginException` and log it. **[UNVERIFIED]** — current exception
  handling in `lib/services/window_service.dart` needs review.
- The subprocess flow must always restore: `show` goes in a `finally` block so
  a failed launch or crashing child never leaves the user with no visible window.
- `hide` should be awaited before `Process.start`.

## Patch scope

`tool/ivi-homescreen/0001-sigg-window-channel.patch` against pinned commit
`9c6dac86df39961851c1d188c554afe7f6617754` (v3.0 branch HEAD). The patch
covers:

1. `shell/platform/homescreen/flutter_desktop.cc` — register a
   `sigg_launcher/window` method channel in `SetUpCommonEngineState()` mapping
   `hide`→`SetSuspended(kAppHidden, true)` / `show`→`SetSuspended(kAppHidden,
   false)` + `ScheduleFrame`.
2. `shell/view/flutter_view.h/.cc` — two-reason suspend flags, state machine,
   `IsParked()` query, lifecycle message sending, watchdog pause/resume.
3. `shell/backend/backend.h` + `wayland_egl` — `IsVsyncParked()` to detect
   whether parking actually took effect.
4. `shell/app.cc` — migrate `ApplyOnDisconnect()` to reason-based suspend.

Not in this patch (future work): foreign-toplevel minimize/unset_minimized for
visual hiding; protocol XML for `zwlr_foreign_toplevel_manager_v1`.

## Verification plan

1. `WAYLAND_DEBUG=client`: after `hide` completes there must be no attach+commit
   with a buffer until `show`. Pings, configure and ack should still appear.
2. Counter or log in the present path: assert zero presents between
   hide-complete and show-start.
3. Test hide during an active animation (in-flight-frame case) and during video
   playback.
4. Confirm focus returns to the launcher after the child exits, and that
   restored geometry/fullscreen state is unchanged.
5. Confirm the GTK build's `WindowService` path still works with the shared
   channel name.
6. Verify `wp_presentation` is usable on the target (`[WaylandVsync]` log line);
   if not, `hide` returns an error and Dart must fall back to lifecycle-only
   throttling.

## What could not be verified

- labwc implements `zwlr_foreign_toplevel-management` with `set_minimized` /
  `unset_minimized` / `activate` (user-stated; not checked against labwc source).
- `wp_presentation` advertisement on the labwc target.
- Exact `flutter/lifecycle` message format expected by the Flutter engine
  version vendored by ivi-homescreen.
- Whether the render thread continues to be petted while parked (watchdog
  interaction).
- That all built-in platform views honor `set_suspended`.
- Whether a frame already in flight at `hide` time can commit after minimize.
