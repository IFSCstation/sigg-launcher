import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sigg_launcher/services/audio_handle.dart';

/// Owns the single background-music pipeline.
///
/// All mutations of the shared [AudioHandle] run through one serialized
/// command chain: a command only starts after the previous one finished, so a
/// stale request can never issue native calls that touch a newer track. The
/// generation counter is only used to *abort* a command that has been
/// superseded; it never authorizes cleanup of the shared player.
///
/// Looping is driven from Dart (`onPlayerComplete` -> replay) instead of the
/// plugin's `ReleaseMode.loop`. On Linux the native loop path re-enters
/// `Play()` from a GStreamer bus callback with no exception handling, so a
/// single state failure aborts the process; letting the media finish and
/// issuing a fresh `play()` avoids that path entirely.
class BgmPlayer {
  BgmPlayer._();

  static final BgmPlayer instance = BgmPlayer._();

  static const Duration _fadeTick = Duration(milliseconds: 25);

  AudioHandleFactory _factory = AudioplayersHandle.new;
  AudioHandle? _player;
  StreamSubscription<void>? _completeSubscription;

  bool _unavailable = false;
  bool _enabled = true;

  String? _currentPath;
  String? _desiredPath;
  int _requestGeneration = 0;
  int _fadeGeneration = 0;
  bool _trackActive = false;
  double _currentVolume = 1.0;
  double _targetVolume = 1.0;

  Duration _fadeInDuration = const Duration(milliseconds: 400);
  Duration _fadeOutDuration = const Duration(milliseconds: 250);

  /// Serializes every native call made against [_player].
  Future<void> _commands = Future<void>.value();

  @visibleForTesting
  String? debugLastRequested;

  @visibleForTesting
  int debugPlayersCreated = 0;

  @visibleForTesting
  int debugPlayersDisposed = 0;

  @visibleForTesting
  String? get debugCurrentPath => _currentPath;

  @visibleForTesting
  bool get debugTrackActive => _trackActive;

  /// Silences the player (used by tests where no audio plugin exists). This
  /// mirrors the permanent latched state that a first [MissingPluginException]
  /// triggers in production.
  @visibleForTesting
  void debugDisable() {
    _unavailable = true;
    _currentPath = null;
    _desiredPath = null;
    _trackActive = false;
    _requestGeneration++;
    _fadeGeneration++;
  }

  /// Restores the player to a pristine state and optionally injects a test
  /// backend. Commands already queued by a previous test are aborted by the
  /// generation bump.
  @visibleForTesting
  void debugReset({AudioHandleFactory? factory}) {
    _factory = factory ?? AudioplayersHandle.new;
    _unavailable = false;
    _enabled = true;
    _currentPath = null;
    _desiredPath = null;
    _trackActive = false;
    _currentVolume = 1.0;
    _targetVolume = 1.0;
    _fadeInDuration = const Duration(milliseconds: 400);
    _fadeOutDuration = const Duration(milliseconds: 250);
    _requestGeneration++;
    _fadeGeneration++;
    debugLastRequested = null;
    debugPlayersCreated = 0;
    debugPlayersDisposed = 0;

    final player = _player;
    _player = null;
    unawaited(_completeSubscription?.cancel());
    _completeSubscription = null;
    if (player != null) {
      debugPlayersDisposed++;
      unawaited(_disposeQuietly(player));
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
    final file = File(path).absolute;
    _desiredPath = file.path;
    if (!_enabled) return Future<void>.value();
    return _enqueuePlay(file.path);
  }

  /// Stops the current track. [fade] is false for call sites that must not
  /// wait for the 250 ms fade (e.g. right before launching a game).
  Future<void> stop({bool fade = true}) {
    _desiredPath = null;
    final generation = ++_requestGeneration;
    return _enqueue(() => _stopCommand(generation, fade: fade));
  }

  /// Sets the preferred music volume (0..1). It also controls an already
  /// playing track; the preference is applied to the next [play] as well.
  Future<void> setVolume(double volume) async {
    _targetVolume = volume.clamp(0.0, 1.0).toDouble();
    final player = _player;
    if (_unavailable || player == null || !_trackActive) return;
    // Slider drags and held-key repeats can issue updates faster than a short
    // fade can finish. Cancel any in-flight fade and apply the current target
    // directly so the audible level follows the control without lagging behind.
    _fadeGeneration++;
    await _applyVolume(player, _targetVolume);
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

    final file = File(path);
    if (!await file.exists()) return;
    if (generation != _requestGeneration) return;

    final player = await _ensurePlayer();
    if (player == null) return;

    if (_trackActive) {
      await _fadeTo(0.0, _fadeOutDuration, generation);
      // A newer command is already queued behind this one and owns the
      // player now. Return without stopping, fading or otherwise touching it.
      if (generation != _requestGeneration) return;
      _trackActive = false;
    }

    _currentPath = path;
    try {
      await player.setVolume(0.0);
      if (generation != _requestGeneration) return;
      _currentVolume = 0.0;

      await player.play(DeviceFileSource(path));
      if (generation != _requestGeneration) {
        // Same contract as above: the queued command will replace this source
        // and fade in. Never stop the shared pipeline from a stale command.
        return;
      }

      _trackActive = true;
      await _fadeTo(_targetVolume, _fadeInDuration, generation);
    } on MissingPluginException catch (error, stackTrace) {
      _unavailable = true;
      logAudioError('bgm-play', error, stackTrace);
    } catch (error, stackTrace) {
      logAudioError('bgm-play', error, stackTrace);
      if (generation == _requestGeneration) {
        _currentPath = null;
        _trackActive = false;
      }
    }
  }

  Future<void> _stopCommand(int generation, {required bool fade}) async {
    if (generation != _requestGeneration) return;
    if (fade && _trackActive) {
      await _fadeTo(0.0, _fadeOutDuration, generation);
      if (generation != _requestGeneration) return;
    } else {
      // A no-fade stop still needs to cancel a fade that is in flight.
      _fadeGeneration++;
    }
    _trackActive = false;
    _currentPath = null;

    final player = _player;
    if (player == null) return;
    try {
      // `AudioPlayer.stop()` blocks the platform thread on Linux (it waits on
      // a GStreamer state change with GST_CLOCK_TIME_NONE). Pause + seek keeps
      // the same "restart from the beginning next time" semantics without
      // that unbounded wait.
      await player.pause();
      await player.seek(Duration.zero);
    } catch (error, stackTrace) {
      logAudioError('bgm-stop', error, stackTrace);
    }
  }

  Future<void> _disableCommand(int generation) async {
    if (generation != _requestGeneration) return;
    await _fadeTo(0.0, _fadeOutDuration, generation);
    if (generation != _requestGeneration) return;
    _trackActive = false;
    _currentPath = null;
    _fadeGeneration++;
    await _releasePlayer();
  }

  Future<AudioHandle?> _ensurePlayer() async {
    final existing = _player;
    if (existing != null) return existing;
    AudioHandle? created;
    try {
      final player = _factory();
      created = player;
      debugPlayersCreated++;
      _completeSubscription = player.onPlayerComplete.listen(
        (_) => _onPlayerComplete(player),
        onError: (Object error, StackTrace stackTrace) =>
            logAudioError('bgm-events', error, stackTrace),
      );
      // Release mode (not loop): on Linux the native loop handler re-enters
      // Play() from the bus watch without exception handling. Dart restarts
      // the track on completion instead.
      await player.setReleaseMode(ReleaseMode.release);
      await player.setVolume(_currentVolume);
      _player = player;
      return player;
    } on MissingPluginException catch (error, stackTrace) {
      _unavailable = true;
      logAudioError('bgm-create', error, stackTrace);
      await _abandonPlayer(created);
      return null;
    } catch (error, stackTrace) {
      logAudioError('bgm-create', error, stackTrace);
      await _abandonPlayer(created);
      return null;
    }
  }

  /// Releases a player whose construction failed before it became [_player].
  Future<void> _abandonPlayer(AudioHandle? player) async {
    if (player == null) return;
    final subscription = _completeSubscription;
    _completeSubscription = null;
    await subscription?.cancel();
    await _disposeQuietly(player);
  }

  void _onPlayerComplete(AudioHandle player) {
    if (_unavailable || !_enabled) return;
    if (!identical(player, _player)) return;
    // A stray completion from a source that has already been replaced, or a
    // stop that has been requested but not executed yet. [_desiredPath] is
    // updated synchronously at request time, so it is the authoritative
    // "should anything be playing" signal here.
    if (!_trackActive || _currentPath == null) return;
    if (_desiredPath != _currentPath) return;

    _trackActive = false;
    unawaited(_enqueuePlay(_currentPath!));
  }

  Future<void> _releasePlayer() async {
    final player = _player;
    _player = null;
    final subscription = _completeSubscription;
    _completeSubscription = null;
    await subscription?.cancel();
    if (player == null) return;
    debugPlayersDisposed++;
    try {
      await player.setReleaseMode(ReleaseMode.release);
    } catch (error, stackTrace) {
      logAudioError('bgm-release', error, stackTrace);
    }
    try {
      await player.pause();
    } catch (error, stackTrace) {
      logAudioError('bgm-release', error, stackTrace);
    }
    await _disposeQuietly(player);
  }

  Future<void> _disposeQuietly(AudioHandle player) async {
    try {
      await player.dispose();
    } catch (error, stackTrace) {
      logAudioError('bgm-dispose', error, stackTrace);
    }
  }

  Future<void> _applyVolume(AudioHandle player, double value) async {
    try {
      await player.setVolume(value);
      _currentVolume = value;
    } on MissingPluginException catch (error, stackTrace) {
      _unavailable = true;
      logAudioError('bgm-volume', error, stackTrace);
    } catch (error, stackTrace) {
      logAudioError('bgm-volume', error, stackTrace);
    }
  }

  /// Wall-clock fade. Unlike a fixed step count, this always lands on
  /// [target] after roughly [duration] even when platform calls are slow, and
  /// issues at most one `setVolume` per [_fadeTick].
  Future<void> _fadeTo(double target, Duration duration, int generation) async {
    final player = _player;
    if (player == null) {
      _currentVolume = target;
      return;
    }

    final fadeId = ++_fadeGeneration;
    if (duration <= Duration.zero) {
      await _applyVolume(player, target);
      return;
    }

    final start = _currentVolume;
    if ((target - start).abs() < 0.001) {
      _currentVolume = target;
      return;
    }

    final clock = Stopwatch()..start();
    final totalMicros = duration.inMicroseconds;
    while (true) {
      if (generation != _requestGeneration || fadeId != _fadeGeneration) return;
      final progress = (clock.elapsedMicroseconds / totalMicros).clamp(
        0.0,
        1.0,
      );
      final value = start + (target - start) * progress;
      if ((value - _currentVolume).abs() >= 0.001) {
        await _applyVolume(player, value);
      }
      if (progress >= 1.0) break;
      if (generation != _requestGeneration || fadeId != _fadeGeneration) return;
      await Future<void>.delayed(_fadeTick);
    }
    _currentVolume = target;
  }
}
