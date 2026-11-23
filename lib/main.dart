import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'app_widget.dart';
import 'services/audio_log.dart';
import 'services/gamepad_nav.dart';
import 'services/perf_logger.dart';
import 'services/soloud_backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache
    ..maximumSize = 128
    // Generous enough for a full game library of decoded hero frames (each
    // ~2MB at display size) to survive a traversal without constant LRU
    // eviction, which churns MultiFrameImageStreamCompleter disposal.
    ..maximumSizeBytes = 64 * 1024 * 1024;
  _guardAgainstImageStreamAssertion();
  PerfLogger.start();
  registerSonyMappingOverrides();

  // Initialize the SoLoud audio engine before running the app. If audio
  // initialization fails (e.g. no audio sink available), the engine latches
  // off (_failed) and UI sound / BGM silently degrade — navigation and
  // playback are never blocked on audio. The original SoLoud.init() exception
  // is logged with its full stack trace by SoloudEngine.init().
  await SoloudEngine.instance.init();
  logAudioInfo('audio:startup',
      'SoloudEngine initialized=${SoloudEngine.instance.isInitialized}');

  await AppController.instance.loadUsers();
  runApp(AppWidget());
}

/// Swallows a benign Flutter framework assertion from animated images.
///
/// `MultiFrameImageStreamCompleter._handleAppFrame` assumes `_nextFrame` is
/// always set when it runs, but there is an upstream race: a frame callback
/// scheduled by `_decodeNextFrameAndSchedule` can fire after `_nextFrame` was
/// cleared by a concurrent decode / completer disposal (e.g. an `ImageCache`
/// eviction) while listeners still exist, violating
/// `assert(_nextFrame != null)`. It is non-fatal (the scheduler reports it and
/// moves on) and only ever trips in debug builds (asserts are compiled out in
/// release). We filter exactly this assertion; everything else is reported
/// normally. The app-side mitigation lives in the Library's debounced hero
/// preload + no-manual-eviction policy; this guard is belt-and-suspenders.
void _guardAgainstImageStreamAssertion() {
  if (!kDebugMode) return;
  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    final message = '${details.exception}';
    if (details.context == null &&
        message.contains("'_nextFrame != null': is not true")) {
      return;
    }
    if (defaultOnError != null) {
      defaultOnError(details);
    } else {
      FlutterError.presentError(details);
    }
  };
}
