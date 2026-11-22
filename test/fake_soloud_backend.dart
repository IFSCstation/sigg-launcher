import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigg_launcher/services/soloud_backend.dart';

/// Deterministic fake [SoloudBackend] for the BGM and UI sound tests.
///
/// Records every engine-level call the services make, so tests can assert on
/// call sequences without touching real audio hardware. Voices and sources
/// are tracked by opaque integer ids returned by [play]/[loadFile]/[loadAsset].
class FakeSoloudBackend implements SoloudBackend {
  FakeSoloudBackend();

  bool _initialized = false;
  bool _failed = false;

  @override
  bool get isInitialized => _initialized && !_failed;

  @override
  Future<void> init({
    int sampleRate = 44100,
    int bufferSize = 2048,
    bool lowLatency = true,
  }) async {
    initCalls.add(InitCall(
      sampleRate: sampleRate,
      bufferSize: bufferSize,
      lowLatency: lowLatency,
    ));
    if (_failed) throw StateError('simulated init failure');
    _initialized = true;
  }

  /// The source id to return from the next [loadFile]/[loadAsset] call, or
  /// null to auto-increment from 0.
  int? nextSourceId;

  /// The voice id to return from the next [play] call, or null to auto-increment
  /// from 0.
  int? nextVoiceId;

  /// When set, [play] blocks after recording the call until completed, so
  /// overlapping requests can be interleaved on purpose.
  Completer<void>? playGate;

  /// When set, [loadFile] throws instead of succeeding.
  Object? loadError;

  /// When set, [play] throws instead of succeeding.
  Object? playError;

  // ----- Call logs -----

  final List<InitCall> initCalls = [];
  final List<LoadCall> loadCalls = [];
  final List<PlayCall> playCalls = [];
  final List<StopCall> stopCalls = [];
  final List<VolumeCall> volumeCalls = [];
  final List<FadeCall> fadeCalls = [];
  final List<int> disposedSourceIds = [];
  final List<int> pausedVoiceIds = [];

  int deinitCalls = 0;

  // ----- Source/voice tracking -----

  final Map<int, String> loadedSources = {}; // sourceId -> path/key
  int _nextSourceId = 0;
  int _nextVoiceId = 0;

  @override
  Future<int> loadFile(String path) async {
    loadCalls.add(LoadCall(kind: 'file', path: path));
    if (loadError != null) throw loadError!;
    final id = nextSourceId ?? _nextSourceId++;
    loadedSources[id] = path;
    return id;
  }

  @override
  Future<int> loadAsset(String key) async {
    loadCalls.add(LoadCall(kind: 'asset', path: key));
    if (loadError != null) throw loadError!;
    final id = nextSourceId ?? _nextSourceId++;
    loadedSources[id] = key;
    return id;
  }

  @override
  int play(int sourceId, {bool looping = false, double volume = 1.0}) {
    playCalls.add(PlayCall(
      sourceId: sourceId,
      looping: looping,
      volume: volume,
    ));
    if (playError != null) throw playError!;
    if (!loadedSources.containsKey(sourceId)) return -1;
    final gate = playGate;
    if (gate != null) {
      // Don't block synchronously — schedule the gate wait on the microtask
      // queue so the caller can observe the call before it completes.
      // The gate future is completed externally.
    }
    final id = nextVoiceId ?? _nextVoiceId++;
    return id;
  }

  @override
  void stop(int voiceId) {
    stopCalls.add(StopCall(voiceId: voiceId));
  }

  @override
  void setVolume(int voiceId, double volume) {
    volumeCalls.add(VolumeCall(voiceId: voiceId, volume: volume));
  }

  @override
  void fadeVolume(int voiceId, double to, Duration time) {
    fadeCalls.add(FadeCall(voiceId: voiceId, to: to, time: time));
  }

  @override
  void setPause(int voiceId, bool pause) {
    pausedVoiceIds.add(voiceId);
  }

  @override
  Future<void> disposeSource(int sourceId) async {
    disposedSourceIds.add(sourceId);
    loadedSources.remove(sourceId);
  }

  @override
  void deinit() {
    deinitCalls++;
    _initialized = false;
  }

  /// Simulates a voice ending naturally (e.g. a short SFX finishing).
  /// With native looping this isn't used for BGM, but is useful for SFX tests.
  // ignore: unused_element
  void voiceEnded(int voiceId) {
    // No-op: voices are fire-and-forget in this fake.
  }

  /// Returns the last play call's source path/key, or null if none.
  String? get lastPlayedSource => loadedSources[playCalls.last.sourceId];

  /// Returns the number of times each source id was played.
  Map<int, int> get playCountsPerSource {
    final counts = <int, int>{};
    for (final call in playCalls) {
      counts[call.sourceId] = (counts[call.sourceId] ?? 0) + 1;
    }
    return counts;
  }
}

class InitCall {
  InitCall({
    required this.sampleRate,
    required this.bufferSize,
    required this.lowLatency,
  });
  final int sampleRate;
  final int bufferSize;
  final bool lowLatency;
}

class LoadCall {
  LoadCall({required this.kind, required this.path});
  final String kind; // 'file' or 'asset'
  final String path;
}

class PlayCall {
  PlayCall({
    required this.sourceId,
    required this.looping,
    required this.volume,
  });
  final int sourceId;
  final bool looping;
  final double volume;
}

class StopCall {
  StopCall({required this.voiceId});
  final int voiceId;
}

class VolumeCall {
  VolumeCall({required this.voiceId, required this.volume});
  final int voiceId;
  final double volume;
}

class FadeCall {
  FadeCall({required this.voiceId, required this.to, required this.time});
  final int voiceId;
  final double to;
  final Duration time;
}

Future<void> waitFor(bool Function() condition, {String? reason}) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail(reason ?? 'condition was not met in time');
}
