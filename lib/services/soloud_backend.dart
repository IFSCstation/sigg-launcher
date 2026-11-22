import 'package:flutter_soloud/flutter_soloud.dart';

import 'audio_log.dart';

/// Abstract interface over the SoLoud audio engine.
///
/// The app owns a single SoLoud engine instance for its entire lifetime.
/// This interface hides the `flutter_soloud` SDK types (`AudioSource`,
/// `SoundHandle`) behind opaque integer ids so the rest of the app — and its
/// tests — never depend on the plugin directly.
///
/// Source ids are returned by [loadFile]/[loadAsset] and identify a decoded
/// audio resource that can be played any number of times. Voice ids are
/// returned by [play] and identify a single playing instance of a source;
/// multiple voices can play the same source simultaneously (overlapping SFX).
abstract class SoloudBackend {
  /// Whether [init] has completed successfully.
  bool get isInitialized;

  /// Initialises the SoLoud engine once. Safe to call multiple times; only the
  /// first call initialises the native engine.
  Future<void> init({
    int sampleRate = 44100,
    int bufferSize = 2048,
    bool lowLatency = true,
  });

  /// Loads an audio file from [path] (absolute filesystem path) and returns an
  /// opaque source id. Used for BGM tracks and other on-disk audio.
  Future<int> loadFile(String path);

  /// Loads a bundled Flutter asset [key] and returns an opaque source id.
  /// Used for short UI sound effects.
  Future<int> loadAsset(String key);

  /// Plays [sourceId], returning an opaque voice id. When [looping] is true
  /// the source loops natively on the audio thread.
  int play(int sourceId, {bool looping = false, double volume = 1.0});

  /// Stops the voice [voiceId] immediately.
  void stop(int voiceId);

  /// Sets the volume of [voiceId] (0.0–1.0).
  void setVolume(int voiceId, double volume);

  /// Smoothly changes [voiceId]'s volume to [to] over [time] on the audio
  /// thread. Use this for fades instead of stepped Dart-side updates.
  void fadeVolume(int voiceId, double to, Duration time);

  /// Pauses or resumes [voiceId].
  void setPause(int voiceId, bool pause);

  /// Releases the native resources for [sourceId]. Safe to call after all
  /// voices using it have stopped.
  Future<void> disposeSource(int sourceId);

  /// Shuts down the engine and releases all native resources.
  void deinit();
}

/// Production [SoloudBackend] backed by `package:flutter_soloud`.
///
/// Initialisation failures (missing audio sink, etc.) are caught and surface
/// as a permanently disabled backend so the rest of the app keeps working.
class SoloudEngine implements SoloudBackend {
  SoloudEngine._();

  static final SoloudEngine instance = SoloudEngine._();

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
    if (_initialized || _failed) return;
    try {
      await SoLoud.instance.init(
        sampleRate: sampleRate,
        bufferSize: bufferSize,
        channels: Channels.stereo,
        lowLatency: lowLatency,
      );
      _initialized = true;
    } catch (error, stackTrace) {
      _failed = true;
      logAudioError('soloud-init', error, stackTrace);
    }
  }

  @override
  Future<int> loadFile(String path) async {
    if (!_initialized) throw StateError('SoloudEngine not initialized');
    final source = await SoLoud.instance.loadFile(path);
    return _registerSource(source);
  }

  @override
  Future<int> loadAsset(String key) async {
    if (!_initialized) throw StateError('SoloudEngine not initialized');
    final source = await SoLoud.instance.loadAsset(key);
    return _registerSource(source);
  }

  @override
  int play(int sourceId, {bool looping = false, double volume = 1.0}) {
    if (!_initialized) return -1;
    final source = _sources[sourceId];
    if (source == null) return -1;
    final handle = SoLoud.instance.play(
      source,
      looping: looping,
      volume: volume,
    );
    if (handle.isError) return -1;
    return _registerVoice(handle);
  }

  @override
  void stop(int voiceId) {
    if (!_initialized) return;
    final handle = _voices[voiceId];
    if (handle == null) return;
    SoLoud.instance.stop(handle);
    _voices.remove(voiceId);
  }

  @override
  void setVolume(int voiceId, double volume) {
    if (!_initialized) return;
    final handle = _voices[voiceId];
    if (handle == null) return;
    SoLoud.instance.setVolume(handle, volume);
  }

  @override
  void fadeVolume(int voiceId, double to, Duration time) {
    if (!_initialized) return;
    final handle = _voices[voiceId];
    if (handle == null) return;
    SoLoud.instance.fadeVolume(handle, to, time);
  }

  @override
  void setPause(int voiceId, bool pause) {
    if (!_initialized) return;
    final handle = _voices[voiceId];
    if (handle == null) return;
    SoLoud.instance.setPause(handle, pause);
  }

  @override
  Future<void> disposeSource(int sourceId) async {
    final source = _sources.remove(sourceId);
    if (source == null) return;
    await SoLoud.instance.disposeSource(source);
  }

  @override
  void deinit() {
    if (!_initialized) return;
    SoLoud.instance.deinit();
    _initialized = false;
    _sources.clear();
    _voices.clear();
  }

  /// Maps source id → AudioSource object (needed for play()).
  final Map<int, AudioSource> _sources = {};

  /// Maps voice id → SoundHandle (needed for stop/setVolume/fadeVolume).
  final Map<int, SoundHandle> _voices = {};

  int _nextSourceId = 0;
  int _nextVoiceId = 0;

  /// Registers a source and returns its opaque id.
  int _registerSource(AudioSource source) {
    final id = _nextSourceId++;
    _sources[id] = source;
    return id;
  }

  /// Registers a voice and returns its opaque id.
  int _registerVoice(SoundHandle handle) {
    final id = _nextVoiceId++;
    _voices[id] = handle;
    return id;
  }
}
