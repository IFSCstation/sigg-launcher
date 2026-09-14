import 'package:flutter/material.dart';
import 'package:sigg_launcher/app_controller.dart';
import 'package:sigg_launcher/screens/home/home.dart';
import 'package:sigg_launcher/services/fps_counter.dart';
import 'package:sigg_launcher/services/gamepad_nav.dart';

const Color kScreenBackground = Color(0xFF0E1116);

ThemeData theme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.green,
    brightness: Brightness.dark,
  ),
  scaffoldBackgroundColor: kScreenBackground,
  focusColor: Colors.transparent,
);

class AppWidget extends StatefulWidget {
  const AppWidget({super.key});

  @override
  State<AppWidget> createState() => _AppWidgetState();
}

class _AppWidgetState extends State<AppWidget> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppController.instance,
      builder: (context, child) {
        return FpsCounter(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            initialRoute: '/',
            navigatorObservers: [LauncherRouteObserver.instance],
            routes: {
              // POS Screens
              '/': (context) => Library(),
            },
          ),
        );
      },
    );
  }
}
