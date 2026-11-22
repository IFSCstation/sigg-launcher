import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:sigg_launcher/services/audio_handle.dart';

/// Deterministic [AudioHandle] for the queue/pool tests. It records every
/// platform-level call the services make and can hold `play()` pending so
/// overlapping requests can be interleaved on purpose.
class FakeAudioHandle implements AudioHandle {
  FakeAudioHandle({this.label = ''});

  final String label;
  final StreamController<void> _complete = StreamController<void>.broadcast();

  final List<Source> played = [];
  final List<Source> sources = [];
  final List<double> volumes = [];
  final List<ReleaseMode> releaseModes = [];
  final List<Duration> seeks = [];

  int playCount = 0;
  int pauseCount = 0;
  int resumeCount = 0;
  int stopCount = 0;
  int disposeCount = 0;

  bool disposed = false;

  /// When set, `play()` blocks after recording the call until completed.
  Completer<void>? playGate;

  /// When set, `play()` throws instead of succeeding.
  Object? playError;

  @override
  Stream<void> get onPlayerComplete => _complete.stream;

  @override
  Future<void> setReleaseMode(ReleaseMode mode) async {
    releaseModes.add(mode);
  }

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
  }

  @override
  Future<void> setSource(Source source) async {
    sources.add(source);
  }

  @override
  Future<void> play(Source source) async {
    playCount++;
    played.add(source);
    final gate = playGate;
    if (gate != null) await gate.future;
    final error = playError;
    if (error != null) throw error;
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
  }

  @override
  Future<void> pause() async {
    pauseCount++;
  }

  @override
  Future<void> resume() async {
    resumeCount++;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
    disposed = true;
    await _complete.close();
  }

  /// Simulates the native end-of-stream event.
  void complete() {
    if (!_complete.isClosed) _complete.add(null);
  }

  double get lastVolume => volumes.isEmpty ? double.nan : volumes.last;

  String get lastPlayedPath {
    if (played.isEmpty) return '';
    final source = played.last;
    return source is DeviceFileSource ? source.path : source.toString();
  }
}

class FakeAudioHandleFactory {
  final List<FakeAudioHandle> created = [];

  FakeAudioHandle call() {
    final handle = FakeAudioHandle(label: 'player-${created.length}');
    created.add(handle);
    return handle;
  }

  FakeAudioHandle get last => created.last;
}

String deviceFileName(Source source) =>
    source is DeviceFileSource ? source.path : source.toString();
