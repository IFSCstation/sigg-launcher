import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigg_launcher/services/ui_sounds.dart';

import 'fake_audio_handle.dart';

Future<void> waitFor(bool Function() condition, {String? reason}) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail(reason ?? 'condition was not met in time');
}

void main() {
  setUp(() {
    UiSounds.instance.debugReset();
  });

  tearDown(() {
    UiSounds.instance.debugReset();
  });

  test('pool is preloaded once and reused round-robin', () async {
    final factory = FakeAudioHandleFactory();
    UiSounds.instance.debugReset(factory: factory.call);

    for (var i = 0; i < 6; i++) {
      await UiSounds.instance.selectionChanged();
    }

    expect(factory.created, hasLength(3));
    expect(factory.created.map((handle) => handle.playCount), [2, 2, 2]);
    for (final handle in factory.created) {
      expect(handle.disposeCount, 0, reason: 'ticks must not dispose players');
      expect(handle.sources, hasLength(1), reason: 'source is preloaded once');
      expect(handle.releaseModes, [ReleaseMode.release]);
      expect(handle.lastVolume, 1.0);
    }
  });

  test('volume is applied to every pooled player', () async {
    final factory = FakeAudioHandleFactory();
    UiSounds.instance.debugReset(factory: factory.call);

    await UiSounds.instance.selectionChanged();
    await UiSounds.instance.setVolume(0.4);
    expect(factory.created.map((handle) => handle.lastVolume), [0.4, 0.4, 0.4]);

    final calls = factory.created.fold<int>(
      0,
      (sum, handle) => sum + handle.volumes.length,
    );
    await UiSounds.instance.setVolume(0.4);
    expect(
      factory.created.fold<int>(0, (sum, h) => sum + h.volumes.length),
      calls,
      reason: 'unchanged volume must not hit the platform',
    );
  });

  test(
    'disabling disposes the pool and re-enabling rebuilds it lazily',
    () async {
      final factory = FakeAudioHandleFactory();
      UiSounds.instance.debugReset(factory: factory.call);

      await UiSounds.instance.selectionChanged();
      final firstPool = List.of(factory.created);
      expect(firstPool, hasLength(3));

      UiSounds.instance.setEnabled(false);
      await waitFor(
        () => firstPool.every((handle) => handle.disposeCount == 1),
        reason: 'pool was not disposed',
      );

      await UiSounds.instance.selectionChanged();
      expect(
        factory.created,
        hasLength(3),
        reason: 'disabled pool must be idle',
      );

      UiSounds.instance.setEnabled(true);
      await UiSounds.instance.selectionChanged();
      expect(factory.created, hasLength(6));
      expect(factory.created[3].playCount, 1);
    },
  );

  test('overlapping ticks use distinct pooled players', () async {
    final factory = FakeAudioHandleFactory();
    UiSounds.instance.debugReset(factory: factory.call);

    await Future.wait([
      UiSounds.instance.selectionChanged(),
      UiSounds.instance.selectionChanged(),
      UiSounds.instance.selectionChanged(),
    ]);

    expect(factory.created, hasLength(3));
    expect(factory.created.map((handle) => handle.playCount), [
      1,
      1,
      1,
    ], reason: 'a tick must never reuse the player another tick is using');
  });

  test('plugin failure latches the effect off and disposes the pool', () async {
    final factory = FakeAudioHandleFactory();
    UiSounds.instance.debugReset(
      factory: () {
        final handle = factory();
        handle.playError = MissingPluginException('no plugin');
        return handle;
      },
    );

    await UiSounds.instance.selectionChanged();
    expect(factory.created, hasLength(3));
    expect(factory.created.first.playCount, 1);
    await waitFor(
      () => factory.created.every((handle) => handle.disposeCount == 1),
      reason: 'latched player pool was not disposed',
    );

    await UiSounds.instance.selectionChanged();
    expect(factory.created, hasLength(3));
  });
}
