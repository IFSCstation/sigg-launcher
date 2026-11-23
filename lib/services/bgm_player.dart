import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sigg_launcher/services/audio_log.dart';
import 'package:sigg_launcher/services/soloud_backend.dart';

/// Owns the single background-music pipeline.
///
/// One SoLoud [AudioSource] is loaded per track and played with native
/// looping (`looping: true`), so the audio thread restarts the track on
/// completion — no Dart-side re-entrant `Play()` path, which on Linux with
/// `audioplayers` could throw inside a GStreamer bus callback and abort the
/// process.
///
/// All mutations run through one serialized command chain: a command only
/// starts after the previous one finished, so a stale request can never issue
/// native calls that touch a newer track. The generation counter aborts
/// superseded commands before they touch native state.
///
/// Fades use SoLoud's native `fadeVolume()` on the audio thread instead of
/// stepped Dart-side `setVolume` calls, so the UI isolate never blocks on
/// per-step platform round-trips.
class BgmPlayer {
  BgmPlayer._();

  static final BgmPlayer instance = BgmPlayer._();

  /// The SoLoud engine. Inject a fake in tests via [debugReset].
  SoloudBackend _engine = SoloudEngine.instance;

  int? _sourceId;        // loaded AudioSource for the current track
  int? _voiceId;         // currently playing voice (or null if stopped)
  String? _currentPath;  // path of the loaded/source track
  String? _desiredPath;  // path the user last requested

  bool _unavailable = false;
  bool _enabled = true;

  bool _reportedInitFailure = false;

  int _requestGeneration = 0;
  bool _trackActive = false;
  double _targetVolume = 1.0;

  Duration _fadeInDuration = const Duration(milliseconds: 400);
  Duration _fadeOutDuration = const Duration(milliseconds: 250);

  /// Serializes every native call made against the engine.
  Future<void> _commands = Future<void>.value();

  @visibleForTesting
  String? debugLastRequested;

  @visibleForTesting
  int debugSourcesLoaded = 0;

  @visibleForTesting
  int debugSourcesDisposed = 0;

  @visibleForTesting
  String? get debugCurrentPath => _currentPath;

  @visibleForTesting
  bool get debugTrackActive => _trackActive;

  /// Silences the player (used by tests where no audio plugin exists). Mirrors
  /// the permanent latched state that a first engine failure triggers in
  /// production.
  @visibleForTesting
  void debugDisable() {
    _unavailable = true;
    _currentPath = null;
    _desiredPath = null;
    _trackActive = false;
    _requestGeneration++;
  }

  /// Restores the player to a pristine state and optionally injects a test
  /// backend. Commands already queued by a previous test are aborted by the
  /// generation bump.
  @visibleForTesting
  void debugReset({SoloudBackend? engine}) {
    _engine = engine ?? SoloudEngine.instance;
    _unavailable = false;
    _enabled = true;
    _currentPath = null;
    _desiredPath = null;
    _trackActive = false;
    _targetVolume = 1.0;
    _fadeInDuration = const Duration(milliseconds: 400);
    _fadeOutDuration = const Duration(milliseconds: 250);
    _requestGeneration++;
    debugLastRequested = null;
    debugSourcesLoaded = 0;
    debugSourcesDisposed = 0;

    // Release any playing voice and loaded source under the old backend.
    final voiceId = _voiceId;
    final sourceId = _sourceId;
    _voiceId = null;
    _sourceId = null;
    if (voiceId != null) {
      unawaited(_engineStopVoice(voiceId));
    }
    if (sourceId != null) {
      unawaited(_engineDisposeSource(sourceId));
    }
  }

  @visibleForTesting
  void debugSetFadeDurations({
    Duration fadeIn = const Duration(milliseconds: 400),
    Duration fadeOut = const Duration(milliseconds: 250),
  }) {
    _fadeInDuration = fadeIn;
    _fadeOutDuration = fadeOut;
  }

  /// Plays [path] as the selected game's track. Re-selecting the track that is
  /// already playing is a no-op. While music is disabled the path is only
  /// remembered so [setEnabled] can resume it later.
  Future<void> play(String path) {
    debugLastRequested = path;
    if (_unavailable) return Future<void>.value();
    // If the engine failed to initialize, report it once and stop here.
    if (_engine.initError != null) {
      if (!_reportedInitFailure) {
        logAudioError(
          'bgm-init',
          'SoloudEngine failed to initialize: ${_engine.initError}; '
          'background music is unavailable',
        );
        _reportedInitFailure = true;
      }
      _unavailable = true;
      return Future<void>.value();
    }
    final file = File(path).absolute;
    _desiredPath = file.path;
    if (!_enabled) return Future<void>.value();
    return _enqueuePlay(file.path);
  }

  /// Stops the current track. [fade] is false for call sites that must not
  /// wait for the fade (e.g. right before launching a game).
  Future<void> stop({bool fade = true}) {
    _desiredPath = null;
    final generation = ++_requestGeneration;
    return _enqueue(() => _stopCommand(generation, fade: fade));
  }

  /// Sets the preferred music volume (0..1). It also controls an already
  /// playing track; the preference is applied to the next [play] as well.
  Future<void> setVolume(double volume) async {
    _targetVolume = volume.clamp(0.0, 1.0).toDouble();
    if (_unavailable || !_trackActive || _voiceId == null) return;
    // Slider drags and held-key repeats can issue updates faster than a short
    // fade can finish. Cancel any in-flight fade and apply the current target
    // directly so the audible level follows the control without lagging behind.
    _engine.setVolume(_voiceId!, _targetVolume);
  }

  /// Enables or disables background music.
  ///
  /// Disabling stops and releases the native pipeline instead of leaving a
  /// muted pipeline decoding into the sink. Enabling replays the remembered
  /// selection.
  Future<void> setEnabled(bool enabled) {
    if (_enabled == enabled) return Future<void>.value();
    _enabled = enabled;
    if (!enabled) {
      final generation = ++_requestGeneration;
      return _enqueue(() => _disableCommand(generation));
    }
    final path = _desiredPath;
    if (_unavailable || path == null) return Future<void>.value();
    return _enqueuePlay(path);
  }

  Future<void> _enqueuePlay(String path) {
    final generation = ++_requestGeneration;
    return _enqueue(() => _playCommand(path, generation));
  }

  /// Every queued command is isolated: an exception is logged here and never
  /// leaks into the caller (most call sites intentionally do not await).
  Future<void> _enqueue(Future<void> Function() command) {
    final result = _commands.then((_) async {
      try {
        await command();
      } catch (error, stackTrace) {
        logAudioError('bgm-command', error, stackTrace);
      }
    });
    _commands = result;
    return result;
  }

  Future<void> _playCommand(String path, int generation) async {
    if (_unavailable || !_enabled) return;
    if (generation != _requestGeneration) return;
    if (_currentPath == path && _trackActive) return;

    // If the engine failed to initialize, report the original failure once
    // and permanently disable BGM instead of repeatedly throwing
    // "SoloudEngine not initialized" on every play request.
    if (_engine.initError != null) {
      if (!_reportedInitFailure) {
        logAudioError(
          'bgm-init',
          'SoloudEngine failed to initialize: ${_engine.initError}; '
          'background music is unavailable',
        );
        _reportedInitFailure = true;
      }
      _unavailable = true;
      return;
    }

    final file = File(path);
    if (!await file.exists()) return;
    if (generation != _requestGeneration) return;

    // Load the source if this is a new track, or reuse the existing one.
    if (_sourceId == null || _currentPath != path) {
      // Dispose the previous source if we're switching tracks.
      if (_sourceId != null) {
        await _engine.disposeSource(_sourceId!);
        debugSourcesDisposed++;
        _sourceId = null;
        _voiceId = null;
      }
      final sourceId = await _engine.loadFile(path);
      if (generation != _requestGeneration) {
        // Stale: dispose the source we just loaded.
        await _engine.disposeSource(sourceId);
        debugSourcesDisposed++;
        return;
      }
      _sourceId = sourceId;
      _currentPath = path;
      debugSourcesLoaded++;
    }

    // If a voice is still playing (e.g. crossfade), stop it first.
    if (_voiceId != null) {
      _engine.stop(_voiceId!);
      _voiceId = null;
      _trackActive = false;
      if (generation != _requestGeneration) return;
    }

    try {
      // Start the voice at 0 volume, then fade in to the target level on the
      // audio thread. No stepped Dart-side volume updates needed.
      final voiceId = _engine.play(_sourceId!, looping: true, volume: 0.0);
      if (generation != _requestGeneration) {
        // Stale: stop the voice we just started.
        _engine.stop(voiceId);
        return;
      }
      _voiceId = voiceId;
      _trackActive = true;

      // Fade in to the target volume.
      _engine.fadeVolume(voiceId, _targetVolume, _fadeInDuration);
    } catch (error, stackTrace) {
      logAudioError('bgm-play', error, stackTrace);
      if (generation == _requestGeneration) {
        _currentPath = null;
        _trackActive = false;
        _voiceId = null;
      }
    }
  }

  Future<void> _stopCommand(int generation, {required bool fade}) async {
    if (generation != _requestGeneration) return;
    _desiredPath = null;
    _trackActive = false;

    if (fade && _voiceId != null) {
      // Fade out on the audio thread, then stop after the fade duration.
      _engine.fadeVolume(_voiceId!, 0.0, _fadeOutDuration);
      await Future<void>.delayed(_fadeOutDuration);
      if (generation != _requestGeneration) return;
    }

    if (_voiceId != null) {
      _engine.stop(_voiceId!);
      _voiceId = null;
    }
    _currentPath = null;
  }

  Future<void> _disableCommand(int generation) async {
    if (generation != _requestGeneration) return;
    if (_trackActive && _voiceId != null) {
      _engine.fadeVolume(_voiceId!, 0.0, _fadeOutDuration);
      await Future<void>.delayed(_fadeOutDuration);
      if (generation != _requestGeneration) return;
    }
    _trackActive = false;
    _currentPath = null;

    if (_voiceId != null) {
      _engine.stop(_voiceId!);
      _voiceId = null;
    }
    if (_sourceId != null) {
      await _engine.disposeSource(_sourceId!);
      debugSourcesDisposed++;
      _sourceId = null;
    }
  }

  Future<void> _engineStopVoice(int voiceId) async {
    try {
      _engine.stop(voiceId);
    } catch (error, stackTrace) {
      logAudioError('bgm-stop-voice', error, stackTrace);
    }
  }

  Future<void> _engineDisposeSource(int sourceId) async {
    try {
      await _engine.disposeSource(sourceId);
    } catch (error, stackTrace) {
      logAudioError('bgm-dispose-source', error, stackTrace);
    }
  }
}
