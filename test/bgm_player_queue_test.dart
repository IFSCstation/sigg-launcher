import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigg_launcher/services/bgm_player.dart';

import 'fake_soloud_backend.dart';

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
    final engine = FakeSoloudBackend();
    BgmPlayer.instance.debugReset(engine: engine);

    await Future.wait([
      BgmPlayer.instance.play(trackA),
      BgmPlayer.instance.play(trackB),
      BgmPlayer.instance.play(trackC),
    ]);

    // Only one source should be loaded (for trackC; A and B were superseded).
    expect(engine.loadCalls, hasLength(1));
    expect(engine.lastPlayedSource, trackC);
    expect(BgmPlayer.instance.debugCurrentPath, trackC);
    expect(BgmPlayer.instance.debugTrackActive, isTrue);
  });

  test('a stale request cannot stop or replace the newer track', () async {
    final engine = FakeSoloudBackend();
    final gate = Completer<void>();
    engine.playGate = gate;
    BgmPlayer.instance.debugReset(engine: engine);

    final first = BgmPlayer.instance.play(trackA);
    await waitFor(() => engine.playCalls.isNotEmpty, reason: 'A never started');

    final second = BgmPlayer.instance.play(trackB);
    gate.complete();
    engine.playGate = null;
    await Future.wait([first, second]);

    // B's play replaced A's; A's stale command must not stop B's voice.
    expect(engine.stopCalls, isEmpty, reason: 'stale A must not stop B');
    expect(BgmPlayer.instance.debugCurrentPath, trackB);
    expect(BgmPlayer.instance.debugTrackActive, isTrue);
  });

  test('stop cancels a queued play before it reaches the player', () async {
    final engine = FakeSoloudBackend();
    BgmPlayer.instance.debugReset(engine: engine);

    final first = BgmPlayer.instance.play(trackA);
    final stopped = BgmPlayer.instance.stop();
    await Future.wait([first, stopped]);

    expect(engine.loadCalls, isEmpty);
    expect(BgmPlayer.instance.debugCurrentPath, isNull);
    expect(BgmPlayer.instance.debugTrackActive, isFalse);
  });

  test('stop during an in-flight play leaves no active track', () async {
    final engine = FakeSoloudBackend();
    final gate = Completer<void>();
    engine.playGate = gate;
    BgmPlayer.instance.debugReset(engine: engine);

    final playing = BgmPlayer.instance.play(trackA);
    await waitFor(() => engine.playCalls.isNotEmpty, reason: 'play never started');

    final stopping = BgmPlayer.instance.stop();
    gate.complete();
    engine.playGate = null;
    await Future.wait([playing, stopping]);

    expect(BgmPlayer.instance.debugCurrentPath, isNull);
    expect(BgmPlayer.instance.debugTrackActive, isFalse);
    expect(engine.stopCalls, hasLength(1));
  });

  test('disabling releases the pipeline and enabling replays the selection', () async {
    final engine = FakeSoloudBackend();
    BgmPlayer.instance.debugReset(engine: engine);

    await BgmPlayer.instance.play(trackA);
    expect(engine.loadCalls, hasLength(1));
    expect(BgmPlayer.instance.debugTrackActive, isTrue);

    await BgmPlayer.instance.setEnabled(false);
    expect(engine.stopCalls, hasLength(1));
    expect(engine.disposedSourceIds, hasLength(1));
    expect(BgmPlayer.instance.debugCurrentPath, isNull);
    expect(BgmPlayer.instance.debugTrackActive, isFalse);

    // A selection change while music is off is remembered, not played.
    await BgmPlayer.instance.play(trackB);
    expect(engine.loadCalls, hasLength(1), reason: 'disabled play must not load');
    expect(engine.playCalls, hasLength(1)); // only trackA was played

    await BgmPlayer.instance.setEnabled(true);
    expect(engine.loadCalls, hasLength(2));
    expect(engine.playCalls, hasLength(2)); // trackA and trackB played
    expect(engine.lastPlayedSource, trackB);
  });

  test('plugin failures latch audio off instead of escaping', () async {
    final engine = FakeSoloudBackend()
      ..loadError = MissingPluginException('no plugin');
    BgmPlayer.instance.debugReset(engine: engine);

    await BgmPlayer.instance.play(trackA);
    expect(BgmPlayer.instance.debugTrackActive, isFalse);

    await BgmPlayer.instance.play(trackB);
    expect(engine.playCalls, isEmpty, reason: 'the second request must be ignored');
  });

  test('native fade calls fadeVolume once per fade, no stepped updates', () async {
    final engine = FakeSoloudBackend();
    BgmPlayer.instance.debugReset(engine: engine);
    BgmPlayer.instance.debugSetFadeDurations(
      fadeIn: const Duration(milliseconds: 120),
      fadeOut: Duration.zero,
    );

    await BgmPlayer.instance.play(trackA);

    // One fadeVolume call for the fade-in (0 -> target volume).
    expect(engine.fadeCalls, hasLength(1));
    expect(engine.fadeCalls.first.to, 1.0);
  });

  test('track switching disposes the previous source', () async {
    final engine = FakeSoloudBackend();
    BgmPlayer.instance.debugReset(engine: engine);

    await BgmPlayer.instance.play(trackA);
    expect(engine.loadCalls, hasLength(1));
    expect(
      engine.loadCalls.where((c) => c.kind == 'file').length,
      1,
    );

    await BgmPlayer.instance.play(trackB);
    expect(engine.loadCalls, hasLength(2));
    expect(engine.disposedSourceIds, contains(0)); // source 0 (trackA) disposed
    expect(BgmPlayer.instance.debugCurrentPath, trackB);
  });
}
