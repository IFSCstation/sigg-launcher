import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sigg_launcher/services/bgm_player.dart';
import 'package:sigg_launcher/services/ui_sounds.dart';

/// Runtime audio controls shared by settings and the actual audio players.
/// Preferences currently live for this app session; the UI can be persisted
/// once the launcher adds a general settings store.
class AudioPreferences extends ChangeNotifier {
  AudioPreferences._();

  static final AudioPreferences instance = AudioPreferences._();

  bool _musicEnabled = true;
  double _musicVolume = 1.0;
  bool _uiSoundsEnabled = true;
  double _uiSoundsVolume = 1.0;

  bool get musicEnabled => _musicEnabled;

  double get musicVolume => _musicVolume;

  bool get uiSoundsEnabled => _uiSoundsEnabled;

  double get uiSoundsVolume => _uiSoundsVolume;

  void setMusicEnabled(bool enabled) {
    if (_musicEnabled == enabled) return;
    _musicEnabled = enabled;
    unawaited(BgmPlayer.instance.setVolume(_musicEnabled ? _musicVolume : 0.0));
    notifyListeners();
  }

  void setMusicVolume(double volume) {
    final next = _clamp(volume);
    if (_musicVolume == next) return;
    _musicVolume = next;
    if (_musicEnabled) unawaited(BgmPlayer.instance.setVolume(_musicVolume));
    notifyListeners();
  }

  void setUiSoundsEnabled(bool enabled) {
    if (_uiSoundsEnabled == enabled) return;
    _uiSoundsEnabled = enabled;
    UiSounds.instance.setEnabled(enabled);
    notifyListeners();
  }

  void setUiSoundsVolume(double volume) {
    final next = _clamp(volume);
    if (_uiSoundsVolume == next) return;
    _uiSoundsVolume = next;
    unawaited(UiSounds.instance.setVolume(_uiSoundsVolume));
    notifyListeners();
  }

  static double _clamp(double value) => value.clamp(0.0, 1.0).toDouble();

  @visibleForTesting
  void debugReset() {
    _musicEnabled = true;
    _musicVolume = 1.0;
    _uiSoundsEnabled = true;
    _uiSoundsVolume = 1.0;
    unawaited(BgmPlayer.instance.setVolume(_musicVolume));
    UiSounds.instance.setEnabled(true);
    unawaited(UiSounds.instance.setVolume(_uiSoundsVolume));
    notifyListeners();
  }
}
