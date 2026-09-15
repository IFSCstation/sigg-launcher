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
///
/// A single reused [AudioPlayer] can't keep up with rapid moves (gamepad
/// auto-repeat fires every ~120ms) and re-playing a pipeline that already hit
/// EOS goes silently silent on the Linux plugin (native Stop() re-seeks it
/// and the pulse sink never resyncs). So every tick gets a brand-new player
/// that plays the source once and disposes itself on completion — fresh
/// pipelines never hit the stale-EOS path, and a `dispose` of a mid-play
/// player is a cheap, non-blocking teardown.
class UiSounds {
  UiSounds._();

  static final UiSounds instance = UiSounds._();

  static const double _volume = 1.0;

  AudioPlayer? _active;
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
      // Retire a still-playing blip (usually already gone) before starting a
      // fresh one so a rapid repeat never overlaps itself.
      _disposeSafely(_active);
      _active = null;
      final player = AudioPlayer();
      _active = player;
      player.onPlayerComplete.listen((_) {
        if (identical(_active, player)) _active = null;
        _disposeSafely(player);
      });
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(_volume);
      await player.play(AssetSource('sfx/click.wav'));
    } on MissingPluginException {
      _unavailable = true;
    } catch (_) {
      // Best-effort: a transient decode/play error must never block nav.
    }
  }

  /// Discards a finished/overshadowed blip's pipeline. Fire-and-forget and
  /// exception-proof: [AudioPlayer.dispose] is not idempotent (a disposed
  /// pipeline re-disposes on the native side), and raced EOS teardown must
  /// never surface an unhandled async error.
  void _disposeSafely(AudioPlayer? player) {
    if (player == null) return;
    unawaited(() async {
      try {
        await player.dispose();
      } catch (_) {
        // Best-effort: never break navigation over sound teardown.
      }
    }());
  }
}