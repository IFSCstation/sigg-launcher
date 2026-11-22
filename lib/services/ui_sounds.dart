import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sigg_launcher/services/audio_handle.dart';

/// Plays the short UI "selection changed" tick (XMB-style), fired by
/// keyboard/gamepad navigation whenever the focused item moves.
///
/// Deliberately separate from [BgmPlayer]: it is a one-shot, non-looping
/// blip that should not fight the game's background music over volume or
/// release mode. It is best-effort — plugin failures permanently disable it
/// so navigation never breaks on sound.
///
/// The tick uses a small round-robin pool of players that are created and
/// preloaded once. Creating and disposing a native pipeline per keypress was
/// the single most expensive audio operation in the app: each tick built a
/// GStreamer playbin/sink, extracted the asset, played it, and then ran a
/// blocking `ReleaseMediaSource()` on the platform thread. The pool pays that
/// cost once and reuses the pipelines, so auto-repeat (a tick every ~120 ms)
/// never touches player creation.
class UiSounds {
  UiSounds._();

  static final UiSounds instance = UiSounds._();

  static const int _poolSize = 3;
  static final AssetSource _tickSource = AssetSource('sfx/click.wav');

  AudioHandleFactory _factory = AudioplayersHandle.new;
  final List<AudioHandle> _pool = [];
  Future<void>? _poolReady;
  int _next = 0;

  bool _unavailable = false;
  bool _enabled = true;
  double _volume = 1.0;

  @visibleForTesting
  int debugPlayersCreated = 0;

  @visibleForTesting
  int debugPlayersDisposed = 0;

  bool get enabled => _enabled;

  double get volume => _volume;

  /// Silences the player (used by tests where no audio plugin exists). Mirrors
  /// the permanent latched state a first [MissingPluginException] triggers.
  @visibleForTesting
  void debugDisable() {
    _unavailable = true;
    unawaited(_disposePool());
  }

  @visibleForTesting
  void debugReset({AudioHandleFactory? factory}) {
    _factory = factory ?? AudioplayersHandle.new;
    _unavailable = false;
    _enabled = true;
    _volume = 1.0;
    _next = 0;
    debugPlayersCreated = 0;
    debugPlayersDisposed = 0;
    unawaited(_disposePool());
  }

  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) {
      unawaited(_disposePool());
    }
  }

  Future<void> setVolume(double volume) async {
    final next = volume.clamp(0.0, 1.0).toDouble();
    if (_volume == next) return;
    _volume = next;
    for (final player in List<AudioHandle>.of(_pool)) {
      try {
        await player.setVolume(next);
      } on MissingPluginException catch (error, stackTrace) {
        _unavailable = true;
        logAudioError('ui-volume', error, stackTrace);
        return;
      } catch (error, stackTrace) {
        logAudioError('ui-volume', error, stackTrace);
      }
    }
  }

  Future<void> selectionChanged() async {
    if (_unavailable || !_enabled) return;
    try {
      if (!await _ensurePool()) return;
      final player = _pool[_next % _pool.length];
      _next = (_next + 1) % _pool.length;
      await player.play(_tickSource);
    } on MissingPluginException catch (error, stackTrace) {
      _unavailable = true;
      logAudioError('ui-sound', error, stackTrace);
      await _disposePool();
    } catch (error, stackTrace) {
      logAudioError('ui-sound', error, stackTrace);
    }
  }

  Future<bool> _ensurePool() async {
    if (_unavailable) return false;
    final ready = _poolReady ??= _buildPool();
    try {
      await ready;
    } catch (error, stackTrace) {
      logAudioError('ui-pool', error, stackTrace);
      _poolReady = null;
      return false;
    }
    return !_unavailable && _pool.isNotEmpty;
  }

  Future<void> _buildPool() async {
    final created = <AudioHandle>[];
    try {
      for (var i = 0; i < _poolSize; i++) {
        final player = _factory();
        created.add(player);
        debugPlayersCreated++;
        try {
          // Release mode: after the blip ends the plugin releases the media
          // source, so the next `play()` re-prepares it instead of resuming a
          // pipeline stuck at EOS (the Linux stale-EOS failure mode).
          await player.setReleaseMode(ReleaseMode.release);
          await player.setVolume(_volume);
          await player.setSource(_tickSource);
        } on MissingPluginException {
          rethrow;
        } catch (error, stackTrace) {
          // Preload is best-effort; the player can still be played later.
          logAudioError('ui-preload', error, stackTrace);
        }
      }
      if (_unavailable) {
        await _disposeHandles(created);
        return;
      }
      _pool.addAll(created);
    } on MissingPluginException catch (error, stackTrace) {
      _unavailable = true;
      logAudioError('ui-preload', error, stackTrace);
      await _disposeHandles(created);
    }
  }

  Future<void> _disposePool() async {
    _poolReady = null;
    _next = 0;
    final handles = List<AudioHandle>.of(_pool);
    _pool.clear();
    await _disposeHandles(handles);
  }

  Future<void> _disposeHandles(List<AudioHandle> handles) async {
    for (final player in handles) {
      debugPlayersDisposed++;
      try {
        await player.dispose();
      } catch (error, stackTrace) {
        logAudioError('ui-dispose', error, stackTrace);
      }
    }
  }
}
