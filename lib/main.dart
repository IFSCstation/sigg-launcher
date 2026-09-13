import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'app_widget.dart';
import 'services/gamepad_nav.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerSonyMappingOverrides();
  await AppController.instance.loadUsers();
  runApp(AppWidget());
}