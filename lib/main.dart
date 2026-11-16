import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'app_controller.dart';
import 'app_widget.dart';
import 'services/gamepad_nav.dart';
import 'services/perf_logger.dart';

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
