import 'dart:async';

import 'package:gamepads/gamepads.dart';
import 'package:gamepads_platform_interface/gamepads_platform_interface.dart';

class FakeGamepadsPlatform extends GamepadsPlatformInterface {
  FakeGamepadsPlatform([this._names = const []]);

  final List<String> _names;

  final StreamController<GamepadEvent> events =
      StreamController<GamepadEvent>.broadcast();

  late final List<GamepadController> gamepads = [
    for (var i = 0; i < _names.length; i++)
      GamepadController(id: '$i', name: _names[i], plugin: this),
  ];

  @override
  Future<List<GamepadController>> listGamepads() async => gamepads;

  @override
  Stream<GamepadEvent> get gamepadEventsStream => events.stream;

  void dispose() {
    events.close();
  }
}

FakeGamepadsPlatform installFakeGamepads({List<String> names = const []}) {
  final fake = FakeGamepadsPlatform(names);
  GamepadsPlatformInterface.instance = fake;
  return fake;
}

GamepadEvent rawEvent(GamepadButton button, double value) {
  return GamepadEvent(
    gamepadId: '0',
    timestamp: 0,
    type: KeyType.button,
    key: button.name,
    value: value,
  );
}

GamepadEvent rawAxisEvent(GamepadAxis axis, double value) {
  return GamepadEvent(
    gamepadId: '0',
    timestamp: 0,
    type: KeyType.analog,
    key: axis.name,
    value: value,
  );
}

NormalizedGamepadEvent buttonEvent(GamepadButton button, double value) {
  return NormalizedGamepadEvent(
    gamepadId: '0',
    timestamp: 0,
    value: value,
    button: button,
    rawEvent: rawEvent(button, value),
  );
}

NormalizedGamepadEvent axisEvent(GamepadAxis axis, double value) {
  return NormalizedGamepadEvent(
    gamepadId: '0',
    timestamp: 0,
    value: value,
    axis: axis,
    rawEvent: rawAxisEvent(axis, value),
  );
}
