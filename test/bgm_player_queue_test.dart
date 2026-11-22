import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigg_launcher/services/bgm_player.dart';

import 'fake_audio_handle.dart';

Future<void> waitFor(bool Function() condition, {String? reason}) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail(reason ?? 'condition was not met in time');
}

void main() {
  late Directory tempDir;
  late String trackA;
  late String trackB;
  late String trackC;

  String writeTrack(String name) {
    final file = File('${tempDir.path}/$name.mp3')
      ..writeAsStringSync('not really audio');
    return file.path;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sigg_bgm_queue');
    trackA = writeTrack('a');
    trackB = writeTrack('b');
    trackC = writeTrack('c');
    BgmPlayer.instance.debugReset();
    BgmPlayer.instance.debugSetFadeDurations(
      fadeIn: Duration.zero,
      fadeOut: Duration.zero,
    );
  });

  tearDown(() async {
    BgmPlayer.instance.debugReset();
    await tempDir.delete(recursive: true);
  });

  test('rapid switches only play the last requested track', () async {
    final factory = FakeAudioHandleFactory();
    BgmPlayer.instance.debugReset(factory: factory.call);
    BgmPlayer.instance.debugSetFadeDurations(
      fadeIn: Duration.zero,
      fadeOut: Duration.zero,
    );

    await Future.wait([
      BgmPlayer.instance.play(trackA),
      BgmPlayer.instance.play(trackB),
      BgmPlayer.instance.play(trackC),
    ]);

    expect(factory.created, hasLength(1));
    expect(
      factory.last.played,
      hasLength(1),
      reason: 'superseded requests must not touch the shared player',
    );
    expect(deviceFileName(factory.last.played.single), trackC);
    expect(BgmPlayer.instance.debugCurrentPath, trackC);
    expect(BgmPlayer.instance.debugTrackActive, isTrue);
  });

  test('a stale request cannot stop or replace the newer track', () async {
    final handle = FakeAudioHandle();
    final gate = Completer<void>();
    handle.playGate = gate;
    BgmPlayer.instance.debugReset(factory: () => handle);
    BgmPlayer.instance.debugSetFadeDurations(
      fadeIn: Duration.zero,
      fadeOut: Duration.zero,
    );

    final first = BgmPlayer.instance.play(trackA);
    await waitFor(() => handle.playCount == 1, reason: 'A never started');

    final second = BgmPlayer.instance.play(trackB);
    gate.complete();
    handle.playGate = null;
    await Future.wait([first, second]);

    expect(handle.played.map(deviceFileName), [trackA, trackB]);
    expect(handle.pauseCount, 0, reason: 'stale A must not pause B');
    expect(handle.stopCount, 0, reason: 'stale A must not stop B');
    expect(handle.disposeCount, 0);
    expect(BgmPlayer.instance.debugCurrentPath, trackB);
    expect(BgmPlayer.instance.debugTrackActive, isTrue);
  });

  test('stop cancels a queued play before it reaches the player', () async {
    final factory = FakeAudioHandleFactory();
    BgmPlayer.instance.debugReset(factory: factory.call);

    final first = BgmPlayer.instance.play(trackA);
    final stopped = BgmPlayer.instance.stop();
    await Future.wait([first, stopped]);

    expect(factory.created, isEmpty);
    expect(BgmPlayer.instance.debugCurrentPath, isNull);
    expect(BgmPlayer.instance.debugTrackActive, isFalse);
  });

  test('stop during an in-flight play leaves no active track', () async {
    final handle = FakeAudioHandle();
    final gate = Completer<void>();
    handle.playGate = gate;
    BgmPlayer.instance.debugReset(factory: () => handle);
    BgmPlayer.instance.debugSetFadeDurations(
      fadeIn: Duration.zero,
      fadeOut: Duration.zero,
    );

    final playing = BgmPlayer.instance.play(trackA);
    await waitFor(() => handle.playCount == 1, reason: 'play never started');

    final stopping = BgmPlayer.instance.stop();
    gate.complete();
    handle.playGate = null;
    await Future.wait([playing, stopping]);

    expect(BgmPlayer.instance.debugCurrentPath, isNull);
    expect(BgmPlayer.instance.debugTrackActive, isFalse);
    expect(handle.pauseCount, 1);
  });

  test('track completion restarts the current track from Dart', () async {
    final factory = FakeAudioHandleFactory();
    BgmPlayer.instance.debugReset(factory: factory.call);
    BgmPlayer.instance.debugSetFadeDurations(
      fadeIn: Duration.zero,
      fadeOut: Duration.zero,
    );

    await BgmPlayer.instance.play(trackA);
    expect(factory.last.playCount, 1);

    factory.last.complete();
    await waitFor(
      () => factory.last.playCount == 2,
      reason: 'completion did not restart the loop',
    );

    expect(deviceFileName(factory.last.played.last), trackA);
    expect(BgmPlayer.instance.debugTrackActive, isTrue);
    expect(factory.last.disposeCount, 0);
  });

  test('completion after stop does not restart playback', () async {
    final factory = FakeAudioHandleFactory();
    BgmPlayer.instance.debugReset(factory: factory.call);
    BgmPlayer.instance.debugSetFadeDurations(
      fadeIn: Duration.zero,
      fadeOut: Duration.zero,
    );

    await BgmPlayer.instance.play(trackA);
    await BgmPlayer.instance.stop();
    final playsAfterStop = factory.last.playCount;

    factory.last.complete();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(factory.last.playCount, playsAfterStop);
    expect(BgmPlayer.instance.debugTrackActive, isFalse);
  });

  test(
    'disabling releases the pipeline and enabling replays the selection',
    () async {
      final factory = FakeAudioHandleFactory();
      BgmPlayer.instance.debugReset(factory: factory.call);
      BgmPlayer.instance.debugSetFadeDurations(
        fadeIn: Duration.zero,
        fadeOut: Duration.zero,
      );

      await BgmPlayer.instance.play(trackA);
      expect(factory.created, hasLength(1));

      await BgmPlayer.instance.setEnabled(false);
      expect(factory.last.disposeCount, 1);
      expect(BgmPlayer.instance.debugCurrentPath, isNull);
      expect(BgmPlayer.instance.debugTrackActive, isFalse);

      // A selection change while music is off is remembered, not played.
      await BgmPlayer.instance.play(trackB);
      expect(factory.created, hasLength(1));
      expect(factory.last.playCount, 1);

      await BgmPlayer.instance.setEnabled(true);
      expect(factory.created, hasLength(2));
      expect(deviceFileName(factory.last.played.single), trackB);
    },
  );

  test('plugin failures latch audio off instead of escaping', () async {
    final handle = FakeAudioHandle()
      ..playError = MissingPluginException('no plugin');
    BgmPlayer.instance.debugReset(factory: () => handle);
    BgmPlayer.instance.debugSetFadeDurations(
      fadeIn: Duration.zero,
      fadeOut: Duration.zero,
    );

    await BgmPlayer.instance.play(trackA);
    expect(BgmPlayer.instance.debugTrackActive, isFalse);

    await BgmPlayer.instance.play(trackB);
    expect(handle.playCount, 1, reason: 'the second request must be ignored');
  });

  test('fade is wall-clock based and bounded in channel calls', () async {
    final factory = FakeAudioHandleFactory();
    BgmPlayer.instance.debugReset(factory: factory.call);
    BgmPlayer.instance.debugSetFadeDurations(
      fadeIn: const Duration(milliseconds: 120),
      fadeOut: Duration.zero,
    );

    final clock = Stopwatch()..start();
    await BgmPlayer.instance.play(trackA);
    clock.stop();

    expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(80));
    expect(factory.last.lastVolume, 1.0);
    expect(
      factory.last.volumes.length,
      lessThan(15),
      reason: 'a 120 ms fade must not issue one call per frame',
    );
  });
}
