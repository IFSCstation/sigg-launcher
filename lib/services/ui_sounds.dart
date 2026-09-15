import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Plays the short UI "selection changed" tick (XMB-style), fired by
/// keyboard/gamepad navigation whenever the focused item moves.
///
/// Deliberately separate from [BgmPlayer]: it is a one-shot, non-looping
/// blip that should not fight the game's background music over volume or
/// release mode. It is best-effort — any plugin failure permanently disables
/// it so navigation never breaks on sound.
class UiSounds {
  UiSounds._();

  static final UiSounds instance = UiSounds._();

  AudioPlayer? _player;
  bool _unavailable = false;

  /// Silences the player (used by tests where no audio plugin exists). Mirrors
  /// the permanent latched state a first [MissingPluginException] triggers.
  @visibleForTesting
  void debugDisable() {
    _unavailable = true;
  }

  Future<void> selectionChanged() async {
    if (_unavailable) return;
    try {
      _player ??= AudioPlayer();
      await _player!.stop();
      await _player!.setReleaseMode(ReleaseMode.stop);
      await _player!.setVolume(0.75);
      await _player!.play(AssetSource('sfx/click.wav'));
    } on MissingPluginException {
      _unavailable = true;
    } catch (_) {
      // Best-effort: a transient decode/play error must never block nav.
    }
  }
}
