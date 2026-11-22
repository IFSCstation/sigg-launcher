import 'package:flutter/foundation.dart';

/// Logs a best-effort audio failure. Audio must never break navigation or
/// playback of the UI, but silently swallowing the exception makes real
/// platform problems (missing audio sink, broken file, disposed source)
/// indistinguishable from "the user turned sound off".
void logAudioError(String scope, Object error, [StackTrace? stackTrace]) {
  debugPrint('[audio:$scope] $error');
  if (stackTrace != null) {
    debugPrint('$stackTrace');
  }
}
