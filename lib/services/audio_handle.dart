import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Logs a best-effort audio failure. Audio must never break navigation or
/// playback of the UI, but silently swallowing the exception makes real
/// platform problems (missing GStreamer sink, broken file, disposed player)
/// indistinguishable from "the user turned sound off".
void logAudioError(String scope, Object error, [StackTrace? stackTrace]) {
  debugPrint('[audio:$scope] $error');
  if (stackTrace != null) {
    debugPrint('$stackTrace');
  }
}

/// Narrow seam over `audioplayers`' [AudioPlayer].
///
/// The app only needs start/stop/pause/volume operations; hiding the rest
/// behind this interface keeps the queue/pool logic testable without the
/// native plugin and documents exactly which platform calls we allow.
abstract class AudioHandle {
  Stream<void> get onPlayerComplete;

  Future<void> setReleaseMode(ReleaseMode mode);

  Future<void> setVolume(double volume);

  /// Loads [source] without starting playback (pool warm-up).
  Future<void> setSource(Source source);

  /// Loads [source] and starts playback from its beginning.
  Future<void> play(Source source);

  Future<void> seek(Duration position);

  Future<void> pause();

  Future<void> resume();

  Future<void> stop();

  Future<void> dispose();
}

typedef AudioHandleFactory = AudioHandle Function();

/// Production [AudioHandle] backed by one native `audioplayers` pipeline.
class AudioplayersHandle implements AudioHandle {
  AudioplayersHandle({AudioPlayer? player})
    : _player = player ?? AudioPlayer() {
    // The app never consumes position/duration streams. `audioplayers`
    // installs a FramePositionUpdater by default, which turns into a
    // getCurrentPosition method-channel call on *every Flutter frame* while
    // playing (and a gst_element_query_position on the platform thread).
    // No consumer -> no polling.
    _player.positionUpdater = null;
  }

  final AudioPlayer _player;

  @override
  Stream<void> get onPlayerComplete => _player.onPlayerComplete;

  @override
  Future<void> setReleaseMode(ReleaseMode mode) => _player.setReleaseMode(mode);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setSource(Source source) => _player.setSource(source);

  @override
  Future<void> play(Source source) => _player.play(source);

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
