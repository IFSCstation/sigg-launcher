import 'package:flutter_test/flutter_test.dart';
import 'package:gamepads/gamepads.dart';
import 'package:sigg_launcher/services/gamepad_nav.dart';

void main() {
  test('DualShock 4 override maps Cross to a and Circle to b', () {
    registerSonyMappingOverrides();
    final mapping = ControllerDatabase.lookup(
      vendorId: 0x054c,
      productId: 0x09cc,
      platform: GamepadPlatform.linux,
    );
    expect(mapping, isNotNull);
    expect(mapping!.buttons['0'], GamepadButton.a);
    expect(mapping.buttons['1'], GamepadButton.b);
    expect(mapping.buttons['3'], GamepadButton.x);
    expect(mapping.buttons['2'], GamepadButton.y);
  });

  test('normalizer resolves DS4 raw js events through the override', () {
    registerSonyMappingOverrides();
    final normalizer = GamepadNormalizer.forPlatform(GamepadPlatform.linux);
    normalizer.setDeviceInfo('gp1', vendorId: 0x054c, productId: 0x09cc);

    GamepadButton normalize(String key) {
      final results = normalizer.normalize(
        GamepadEvent(
          gamepadId: 'gp1',
          timestamp: 0,
          type: KeyType.button,
          key: key,
          value: 1.0,
          vendorId: 0x054c,
          productId: 0x09cc,
        ),
      );
      return results.single.button!;
    }

    expect(normalize('0'), GamepadButton.a);
    expect(normalize('1'), GamepadButton.b);
    expect(normalize('2'), GamepadButton.y);
    expect(normalize('3'), GamepadButton.x);
  });
}
