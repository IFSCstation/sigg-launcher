import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

class PerfLogger {
  PerfLogger._();

  static bool get enabled => const bool.fromEnvironment('PERF_LOG');

  static final List<FrameTiming> _frames = <FrameTiming>[];

  static void start() {
    if (!enabled) return;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void _onTimings(List<FrameTiming> timings) {
    _frames.addAll(timings);
    if (_frames.length < 60) return;

    final build = <double>[];
    final raster = <double>[];
    final total = <double>[];
    var dropped = 0;
    for (final timing in _frames) {
      build.add(timing.buildDuration.inMicroseconds / 1000);
      raster.add(timing.rasterDuration.inMicroseconds / 1000);
      total.add(timing.totalSpan.inMicroseconds / 1000);
      if (timing.totalSpan.inMicroseconds > 16666) dropped++;
    }

    debugPrint(
      'PERF avg build=${_avg(build).toStringAsFixed(2)}ms '
      'raster=${_avg(raster).toStringAsFixed(2)}ms '
      'total=${_avg(total).toStringAsFixed(2)}ms '
      'p95 build=${_percentile(build, 0.95).toStringAsFixed(2)}ms '
      'raster=${_percentile(raster, 0.95).toStringAsFixed(2)}ms '
      'dropped=$dropped',
    );
    _frames.clear();
  }

  static double _avg(List<double> values) =>
      values.reduce((a, b) => a + b) / values.length;

  static double _percentile(List<double> values, double p) {
    final sorted = List<double>.of(values)..sort();
    final index = ((sorted.length * p).ceil() - 1).clamp(0, sorted.length - 1);
    return sorted[index];
  }
}