import 'package:flutter/foundation.dart';

class GameRunState extends ChangeNotifier {
  GameRunState._();

  static final GameRunState instance = GameRunState._();

  bool _running = false;
  bool get running => _running;

  void setRunning(bool value) {
    if (value == _running) return;
    _running = value;
    notifyListeners();
  }

  @visibleForTesting
  void debugReset() {
    _running = false;
  }
}