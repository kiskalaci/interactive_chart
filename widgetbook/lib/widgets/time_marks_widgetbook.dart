import "dart:math" as math;

import "package:flutter/material.dart";
import "package:interactive_chart/candle.dart";
import "package:interactive_chart/interactive_chart.dart";
import "package:interactive_chart_widgetbook/color_palette.dart";
import "package:intl/intl.dart";
import "package:widgetbook/widgetbook.dart";
import "package:widgetbook_annotation/widgetbook_annotation.dart" as widgetbook;

/// Time axis marks of different weights.
///
/// A mark's weight is set by the coarsest boundary it crosses relative to the
/// previous datum: year (70), month (60), day (50), hour (30), minute (20),
/// otherwise 10. The series spans several years, so zooming in and out shows
/// every tier. Heavier marks win when labels compete for space, and marks of
/// weight 60 and above use the emphasized text style.
@widgetbook.UseCase(name: "Time mark weights", type: InteractiveChart)
Widget timeMarkWeightsUseCase(BuildContext context) {
  final step = context.knobs.object.dropdown(
    label: "Candle interval",
    options: _Step.values,
    labelBuilder: (v) => v.label,
    initialOption: _Step.hour,
  );
  return _TimeMarksDemo(
    step: step,
    initialSlotExtent: context.knobs.double.slider(
      label: "Initial slot extent",
      initialValue: 6,
      min: 1,
      max: 64,
    ),
    showWeights: context.knobs.boolean(
      label: "Show weight in label",
      initialValue: false,
    ),
    timeAxisPlacement: context.knobs.object.dropdown(
      label: "Time axis placement",
      options: TimeAxisPlacement.values,
      labelBuilder: (v) => v.name,
      initialOption: TimeAxisPlacement.bottom,
    ),
  );
}

enum _Step {
  minute("1 minute", Duration(minutes: 1)),
  hour("1 hour", Duration(hours: 1)),
  day("1 day", Duration(days: 1)),
  week("1 week", Duration(days: 7));

  const _Step(this.label, this.duration);

  final String label;
  final Duration duration;
}

final _year = DateFormat.y();
final _month = DateFormat.MMM();
final _day = DateFormat.d();
final _hourMinute = DateFormat.Hm();
final _hourMinuteSecond = DateFormat.Hms();

String _label(DateTime t, int weight) {
  if (weight >= 70) {
    return _year.format(t);
  }
  if (weight >= 60) {
    return _month.format(t);
  }
  if (weight >= 50) {
    return _day.format(t);
  }
  return (weight >= 20 ? _hourMinute : _hourMinuteSecond).format(t);
}

class _TimeMarksDemo extends StatelessWidget {
  const _TimeMarksDemo({
    required this.step,
    required this.initialSlotExtent,
    required this.showWeights,
    required this.timeAxisPlacement,
  });

  final _Step step;
  final double initialSlotExtent;
  final bool showWeights;
  final TimeAxisPlacement timeAxisPlacement;

  static const _count = 3000;

  List<Candle> _generate() {
    final random = math.Random(11);
    // Starts shortly before a year boundary so the first marks cover every
    // tier quickly.
    final start = DateTime(2023, 12, 31, 22);
    var price = 100.0;
    return [
      for (var i = 0; i < _count; i++)
        () {
          final open = price;
          final close = math.max(1.0, open + (random.nextDouble() - 0.5) * 1.5);
          price = close;
          return Candle(
            time: start.add(step.duration * i),
            open: open,
            high: math.max(open, close) + random.nextDouble() * 0.5,
            low: math.max(
              0.5,
              math.min(open, close) - random.nextDouble() * 0.5,
            ),
            close: close,
            volume: 100 + random.nextDouble() * 500,
          );
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = ColorPalette.of(context);
    final candles = _generate();
    return Padding(
      padding: const EdgeInsets.all(8),
      child: InteractiveChart<Candle>(
        // Rebuild the chart (and its viewport) when the interval changes.
        key: ValueKey(step),
        data: candles,
        timeOf: (c) => c.time,
        initialAnchor: ChartAnchor.left,
        initialSlotExtent: initialSlotExtent,
        timeAxis: TimeAxisConfig(
          placement: timeAxisPlacement,
          formatter: showWeights
              ? (t, weight) => "${_label(t, weight)} w$weight"
              : _label,
        ),
        layers: [
          const GridLayer<Candle>(),
          CandleLayer<Candle>(
            openOf: (c) => c.open,
            highOf: (c) => c.high,
            lowOf: (c) => c.low,
            closeOf: (c) => c.close,
            upColor: colors.green,
            downColor: colors.red,
          ),
          CrosshairLayer<Candle>(
            valueOf: (c) => c.close,
            timeOf: (c) => c.time,
          ),
        ],
      ),
    );
  }
}
