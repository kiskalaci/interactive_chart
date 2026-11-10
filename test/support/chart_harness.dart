import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:interactive_chart/interactive_chart.dart";
import "package:interactive_chart/src/chart_context.dart";

/// Fixed start for every fixture so tests never depend on the wall clock.
final DateTime fixtureStart = DateTime(2024);

/// Time of the `i`-th one-minute bar.
DateTime minuteTime(int i) => fixtureStart.add(Duration(minutes: i));

/// Ascending integer series `[from, to)`; the value doubles as the minute
/// offset, so prepending is just a lower `from`.
List<int> intSeries(int from, int to) => [for (var i = from; i < to; i++) i];

/// A layer that draws nothing and hands the chart's internal context to the
/// test, so assertions can read scroll offset, extents and pixel positions.
class ContextProbe<T> extends ChartLayer<T> {
  ContextProbe(this._onContext);

  final void Function(InteractiveChartContext ctx) _onContext;

  @override
  Widget build(Size size, InteractiveChartContext ctx, List<T> data) {
    _onContext(ctx);
    return const SizedBox.shrink();
  }
}

/// Builds an [InteractiveChart] inside a fixed-size box, with a
/// [ContextProbe] appended to [layers]. Re-pump with new `data` to simulate
/// a parent update; the harness keeps the controller and context stable.
class ChartHarness<T> {
  ChartHarness({
    required this.timeOf,
    this.layers,
    this.anchor = ChartAnchor.left,
    this.slotExtent = 8,
    this.minSlotExtent = 1,
    this.maxSlotExtent = 64,
    this.textScale = 1,
    this.panEnabled = true,
    this.zoomEnabled = true,
    this.crosshairEnabled = true,
    this.valueAxis = const ValueAxisConfig(),
    this.timeAxis = const TimeAxisConfig(),
  });

  final DateTime Function(T datum) timeOf;
  final List<ChartLayer<T>> Function()? layers;
  final ChartAnchor anchor;
  final double slotExtent;
  final double minSlotExtent;
  final double textScale;
  final bool panEnabled;
  final bool zoomEnabled;
  final bool crosshairEnabled;
  final double maxSlotExtent;
  final ValueAxisConfig? valueAxis;
  final TimeAxisConfig? timeAxis;

  final controller = InteractiveChartController();
  late InteractiveChartContext ctx;

  /// The chart. By default it fills the whole screen, so tests run at
  /// whatever size the active variant (see variants.dart) gives them; pass a
  /// [width] and/or [height] to pin an exact size instead.
  Widget app(List<T> data, {double? width, double? height}) {
    final chart = InteractiveChart<T>(
      controller: controller,
      data: data,
      timeOf: timeOf,
      initialAnchor: anchor,
      initialSlotExtent: slotExtent,
      minSlotExtent: minSlotExtent,
      maxSlotExtent: maxSlotExtent,
      panEnabled: panEnabled,
      zoomEnabled: zoomEnabled,
      crosshairEnabled: crosshairEnabled,
      valueAxis: valueAxis,
      timeAxis: timeAxis,
      layers: [...?layers?.call(), ContextProbe<T>((c) => ctx = c)],
    );
    return MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      // Same tree shape either way, so changing the size keeps the chart's
      // State. An infinite size fills whatever the screen allows.
      home: Center(
        child: SizedBox(
          width: width ?? double.infinity,
          height: height ?? double.infinity,
          child: chart,
        ),
      ),
    );
  }
}

/// Makes the test screen large enough for charts wider than the default
/// 800 px; without it a wider `SizedBox` is silently clamped to the screen.
void useLargeSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(2000, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
