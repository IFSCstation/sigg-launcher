import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'app_widget.dart';
import 'services/gamepad_nav.dart';
import 'services/perf_logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache
    ..maximumSize = 128
    ..maximumSizeBytes = 32 * 1024 * 1024;
  PerfLogger.start();
  registerSonyMappingOverrides();
  await AppController.instance.loadUsers();
  runApp(AppWidget());
}