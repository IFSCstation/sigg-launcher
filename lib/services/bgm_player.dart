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
  int _fadeGeneration = 0;
  double _currentVolume = 1.0;

  /// Silences the player (used by tests where no audio plugin exists). This
  /// mirrors the permanent latched state that a first [MissingPluginException]
  /// triggers in production.
  @visibleForTesting
  void debugDisable() {
    _unavailable = true;
    _currentPath = null;
  }

  Future<void> play(String path) async {
    if (_unavailable) return;
    final file = File(path).absolute;
    if (!await file.exists()) return;
    if (_currentPath == file.path) return;

    _currentPath = file.path;
    await _fadeOutCurrent();

    try {
      _player ??= AudioPlayer();
      await _player!.stop();
      await _player!.setReleaseMode(ReleaseMode.loop);
      await _player!.setVolume(0.0);
      _currentVolume = 0.0;
      await _player!.play(DeviceFileSource(file.path));
      await _fadeTo(1.0, const Duration(milliseconds: 400));
    } on MissingPluginException {
      _unavailable = true;
    } catch (_) {
      _currentPath = null;
    }
  }

  Future<void> stop() async {
    _currentPath = null;
    await _fadeOutCurrent();
  }

  Future<void> _fadeOutCurrent() async {
    final player = _player;
    if (player == null || _player!.state != PlayerState.playing) return;
    await _fadeTo(0.0, const Duration(milliseconds: 250));
    try {
      await player.stop();
    } catch (_) {
      // Ignore: the player may already be released.
    }
  }

  Future<void> _fadeTo(double target, Duration duration) async {
    final player = _player;
    if (player == null) return;

    final generation = ++_fadeGeneration;
    final steps = (duration.inMilliseconds / 16).floor().clamp(1, 400);
    for (var i = 1; i <= steps; i++) {
      if (generation != _fadeGeneration) return;
      final value = _currentVolume + (target - _currentVolume) * (i / steps);
      try {
        await player.setVolume(value);
      } catch (_) {
        return;
      }
      _currentVolume = value;
      await Future<void>.delayed(const Duration(milliseconds: 12));
    }
    if (generation == _fadeGeneration) _currentVolume = target;
  }
}