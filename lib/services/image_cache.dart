import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:sigg_launcher/screens/home/widgets/mock_games.dart';

class ImagePreloader {
  ImagePreloader._();

  static void preloadHeroes(
    BuildContext context,
    List<GameEntry> games,
    int focusIndex,
    Size size, {
    int range = 2,
  }) {
    _preload(
      context,
      games.map((game) => game.heroPath).toList(),
      focusIndex,
      size,
      range,
    );
  }

  static void preloadCovers(
    BuildContext context,
    List<GameEntry> games,
    int focusIndex,
    Size size, {
    int range = 2,
  }) {
    _preload(
      context,
      games.map((game) => game.coverPath).toList(),
      focusIndex,
      size,
      range,
    );
  }

  static void _preload(
    BuildContext context,
    List<String?> paths,
    int focusIndex,
    Size size,
    int range,
  ) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final width = math.max(1, (size.width * dpr).round());
    final height = math.max(1, (size.height * dpr).round());
    for (var i = focusIndex - range; i <= focusIndex + range; i++) {
      if (i < 0 || i >= paths.length) continue;
      final path = paths[i];
      if (path == null) continue;
      precacheImage(
        ResizeImage(FileImage(File(path)), width: width, height: height),
        context,
      );
    }
  }
}
