import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BgmPlayer {
  BgmPlayer._();

  static final BgmPlayer instance = BgmPlayer._();

  AudioPlayer? _player;
  bool _unavailable = false;

  String? _currentPath;
  int _requestGeneration = 0;
  bool _trackActive = false;
  double _currentVolume = 1.0;

  @visibleForTesting
  String? debugLastRequested;

  /// Silences the player (used by tests where no audio plugin exists). This
  /// mirrors the permanent latched state that a first [MissingPluginException]
  /// triggers in production.
  @visibleForTesting
  void debugDisable() {
    _unavailable = true;
    _currentPath = null;
    _trackActive = false;
  }

  Future<void> play(String path) async {
    debugLastRequested = path;
    if (_unavailable) return;
    final file = File(path).absolute;
    if (!await file.exists()) return;
    if (_currentPath == file.path) return;

    final generation = ++_requestGeneration;
    _currentPath = file.path;

    await _fadeOutCurrent(generation);
    if (generation != _requestGeneration || _unavailable) return;

    try {
      _player ??= AudioPlayer();
      await _player!.stop();
      if (generation != _requestGeneration) return;
      await _player!.setReleaseMode(ReleaseMode.loop);
      if (generation != _requestGeneration) return;
      await _player!.setVolume(0.0);
      if (generation != _requestGeneration) return;
      _currentVolume = 0.0;
      await _player!.play(DeviceFileSource(file.path));
      if (generation != _requestGeneration) {
        _trackActive = false;
        await _player!.stop();
        return;
      }
      _trackActive = true;
      await _fadeTo(1.0, const Duration(milliseconds: 400), generation);
    } on MissingPluginException {
      _unavailable = true;
    } catch (_) {
      if (generation == _requestGeneration) _currentPath = null;
    }
  }

  Future<void> stop() async {
    _currentPath = null;
    final generation = ++_requestGeneration;
    await _fadeOutCurrent(generation);
  }

  Future<void> _fadeOutCurrent(int generation) async {
    final player = _player;
    if (player == null || !_trackActive) return;
    if (generation != _requestGeneration) return;
    await _fadeTo(0.0, const Duration(milliseconds: 250), generation);
    if (generation != _requestGeneration) return;
    _trackActive = false;
    try {
      await player.stop();
    } catch (_) {
      // Ignore: the player may already be released.
    }
  }

  Future<void> _fadeTo(double target, Duration duration, int generation) async {
    final player = _player;
    if (player == null) return;

    final steps = (duration.inMilliseconds / 16).floor().clamp(1, 400);
    for (var i = 1; i <= steps; i++) {
      if (generation != _requestGeneration) return;
      final value = _currentVolume + (target - _currentVolume) * (i / steps);
      try {
        await player.setVolume(value);
      } catch (_) {
        return;
      }
      if (generation != _requestGeneration) return;
      _currentVolume = value;
      await Future<void>.delayed(const Duration(milliseconds: 12));
    }
    if (generation == _requestGeneration) _currentVolume = target;
  }
}
