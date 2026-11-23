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

  @override
  Future<void> dispose() async {
    await events.close();
    await super.dispose();
  }
}

FakeGamepadsPlatform installFakeGamepads({List<String> names = const []}) {
  final fake = FakeGamepadsPlatform(names);
  GamepadsPlatformInterface.instance = fake;
  return fake;
}

/// SDL3 `SDL_GamepadButton` index for the buttons the launcher handles, as
/// documented by ivi-homescreen's `gamepads_linux` v2.0.
const sdl3ButtonIndices = <GamepadButton, int>{
  GamepadButton.a: 0,
  GamepadButton.b: 1,
  GamepadButton.start: 6,
  GamepadButton.dpadUp: 11,
  GamepadButton.dpadDown: 12,
  GamepadButton.dpadLeft: 13,
  GamepadButton.dpadRight: 14,
};

/// SDL3 `SDL_GamepadAxis` index for the axes the launcher handles.
const sdl3AxisIndices = <GamepadAxis, int>{
  GamepadAxis.leftStickX: 0,
  GamepadAxis.leftStickY: 1,
  GamepadAxis.rightStickX: 2,
  GamepadAxis.rightStickY: 3,
  GamepadAxis.leftTrigger: 4,
  GamepadAxis.rightTrigger: 5,
};

/// Raw event exactly as the ivi-homescreen plugin writes it: the key is the
/// SDL3 index as a decimal string and buttons report 1.0/0.0.
GamepadEvent rawSdl3Button(int index, double value) {
  return GamepadEvent(
    gamepadId: '0',
    timestamp: 0,
    type: KeyType.button,
    key: '$index',
    value: value,
  );
}

/// Raw SDL3 analog event. [value] is the SDL-contract value: Sint16, bipolar
/// for sticks (-32767..32767, negative = up) and 0..32767 for triggers.
GamepadEvent rawSdl3Axis(int index, double value) {
  return GamepadEvent(
    gamepadId: '0',
    timestamp: 0,
    type: KeyType.analog,
    key: '$index',
    value: value,
  );
}

/// Raw event in the GTK plugin's evdev numbering (key = `/dev/input/js*`
/// index, values handed across unchecked).
GamepadEvent rawEvdevEvent(
  int jsIndex,
  KeyType type,
  double value, {
  int? vendorId,
  int? productId,
}) {
  return GamepadEvent(
    gamepadId: '0',
    timestamp: 0,
    type: type,
    key: '$jsIndex',
    value: value,
    vendorId: vendorId,
    productId: productId,
  );
}

/// Semantic helper: a raw SDL3 button event.
GamepadEvent buttonEvent(GamepadButton button, double value) {
  return rawSdl3Button(sdl3ButtonIndices[button]!, value);
}

/// Semantic helper: a raw SDL3 axis event from a normalized value (the shape
/// the bridge consumes), converted back to the wire's Sint16 range.
GamepadEvent axisEvent(GamepadAxis axis, double value) {
  final index = sdl3AxisIndices[axis]!;
  switch (axis) {
    case GamepadAxis.leftTrigger:
    case GamepadAxis.rightTrigger:
      return rawSdl3Axis(index, value * 32767);
    case GamepadAxis.leftStickY:
    case GamepadAxis.rightStickY:
      return rawSdl3Axis(index, -value * 32767);
    default:
      return rawSdl3Axis(index, value * 32767);
  }
}
