import 'dart:async';
import 'dart:io';
import 'dart:ui' show FramePhase;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class FpsCounter extends StatefulWidget {
  const FpsCounter({super.key, required this.child});

  static bool get enabled =>
      const bool.fromEnvironment('FPS_OVERLAY') ||
      Platform.environment['SIGG_FPS_OVERLAY'] == '1';

  final Widget child;

  @override
  State<FpsCounter> createState() => _FpsCounterState();
}

class _FpsCounterState extends State<FpsCounter> {
  static const _window = Duration(seconds: 1);

  final List<FrameTiming> _frames = [];
  Timer? _timer;
  double _fps = 0;
  double _build = 0;
  double _raster = 0;
  double _rasterP95 = 0;
  int _dropped = 0;

  @override
  void initState() {
    super.initState();
    if (FpsCounter.enabled) {
      SchedulerBinding.instance.addTimingsCallback(_onTimings);
      _timer = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => _refresh(),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (FpsCounter.enabled) {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    }
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    _frames.addAll(timings);
  }

  void _refresh() {
    if (_frames.isEmpty) return;
    final now = _frames.last.timestampInMicroseconds(FramePhase.vsyncStart);
    final cutoff = now - _window.inMicroseconds;
    while (_frames.isNotEmpty &&
        _frames.first.timestampInMicroseconds(FramePhase.vsyncStart) < cutoff) {
      _frames.removeAt(0);
    }
    if (_frames.isEmpty) return;

    final builds = <double>[];
    final rasters = <double>[];
    var dropped = 0;
    for (final frame in _frames) {
      builds.add(frame.buildDuration.inMicroseconds / 1000);
      rasters.add(frame.rasterDuration.inMicroseconds / 1000);
      if (frame.totalSpan.inMicroseconds > 16666) dropped++;
    }
    final sorted = List<double>.of(rasters)..sort();
    final p95Index = ((sorted.length * 0.95).ceil() - 1).clamp(
      0,
      sorted.length - 1,
    );

    setState(() {
      _fps = _frames.length.toDouble();
      _build = builds.reduce((a, b) => a + b) / builds.length;
      _raster = rasters.reduce((a, b) => a + b) / rasters.length;
      _rasterP95 = sorted[p95Index];
      _dropped = dropped;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!FpsCounter.enabled) return widget.child;
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 8,
          right: 8,
          child: IgnorePointer(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'FPS ${_fps.round()}  '
                  'build ${_build.toStringAsFixed(1)}ms  '
                  'raster ${_raster.toStringAsFixed(1)}ms  '
                  'p95 ${_rasterP95.toStringAsFixed(1)}ms  '
                  'drop $_dropped',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
