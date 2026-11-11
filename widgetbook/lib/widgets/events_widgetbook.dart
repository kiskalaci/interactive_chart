import "package:flutter/material.dart";
import "package:interactive_chart/candle.dart";
import "package:interactive_chart/interactive_chart.dart";
import "package:interactive_chart_widgetbook/color_palette.dart";
import "package:interactive_chart_widgetbook/time_mark_label.dart";
import "package:widgetbook/widgetbook.dart";
import "package:widgetbook_annotation/widgetbook_annotation.dart" as widgetbook;

/// Financial events marked on a daily chart.
///
/// Dividends, earnings and revenue releases appear as small icons just above
/// the volume histogram, on the day they happened. Tap one to open a details
/// card in the middle of the chart; close it with its button (or by tapping
/// outside it, which a knob can switch off). Events that share a day stack,
/// and icons that would overlap are hidden until the chart is zoomed in.
@widgetbook.UseCase(name: "Events", type: InteractiveChart)
Widget chartEventsUseCase(BuildContext context) => _ChartEventsDemo(
  showDividends: context.knobs.boolean(
    label: "Show dividends",
    initialValue: true,
  ),
  showEarnings: context.knobs.boolean(
    label: "Show earnings",
    initialValue: true,
  ),
  showRevenue: context.knobs.boolean(label: "Show revenue", initialValue: true),
  dismissOnBarrierTap: context.knobs.boolean(
    label: "Dismiss on outside tap",
    initialValue: true,
  ),
  initialSlotExtent: context.knobs.double.slider(
    label: "Initial slot extent",
    initialValue: 12,
    min: 2,
    max: 64,
  ),
);

class _ChartEventsDemo extends StatelessWidget {
  const _ChartEventsDemo({
    required this.showDividends,
    required this.showEarnings,
    required this.showRevenue,
    required this.dismissOnBarrierTap,
    required this.initialSlotExtent,
  });

  final bool showDividends;
  final bool showEarnings;
  final bool showRevenue;
  final bool dismissOnBarrierTap;
  final double initialSlotExtent;

  static const _histogramFraction = 0.12;

  /// A quarterly event `shiftDays` after the first candle of every quarter.
  static List<ChartEvent> _quarterly(
    List<Candle> candles, {
    required int shiftDays,
    required IconData icon,
    required Color color,
    required String Function(DateTime date, int quarter) title,
    required String Function(DateTime date, int quarter) description,
  }) {
    final events = <ChartEvent>[];
    var lastQuarter = -1;
    for (final candle in candles) {
      final quarter = candle.time.year * 4 + (candle.time.month - 1) ~/ 3;
      if (quarter == lastQuarter) {
        continue;
      }
      lastQuarter = quarter;
      final date = candle.time.add(Duration(days: shiftDays));
      events.add(
        ChartEvent(
          time: date,
          title: title(date, quarter % 4 + 1),
          description: description(date, quarter % 4 + 1),
          icon: icon,
          color: color,
        ),
      );
    }
    return events;
  }

  static String _date(DateTime d) =>
      "${d.year}-${d.month.toString().padLeft(2, "0")}-"
      "${d.day.toString().padLeft(2, "0")}";

  @override
  Widget build(BuildContext context) {
    final colors = ColorPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final candles = generateDemoCandles();
    final events = [
      if (showDividends)
        ..._quarterly(
          candles,
          shiftDays: 7,
          icon: Icons.payments,
          color: colors.green,
          title: (date, q) => "Dividend",
          description: (date, q) =>
              "Q$q cash dividend of 0.${20 + q * 5} per share, paid on "
              "${_date(date)} to holders of record the day before.",
        ),
      if (showEarnings)
        ..._quarterly(
          candles,
          shiftDays: 14,
          icon: Icons.bar_chart,
          color: colors.blue,
          title: (date, q) => "Q$q earnings",
          description: (date, q) =>
              "Reported on ${_date(date)}: EPS of 1.${10 + q * 3} against an "
              "estimate of 1.${8 + q * 3}, ahead of expectations.",
        ),
      if (showRevenue)
        ..._quarterly(
          candles,
          // Lands on the same day as the earnings events, to show stacking.
          shiftDays: 14,
          icon: Icons.attach_money,
          color: colors.purple,
          title: (date, q) => "Q$q revenue",
          description: (date, q) =>
              "Revenue of ${(4 + q * 0.3).toStringAsFixed(1)}bn on "
              "${_date(date)}, up ${3 + q}% year on year.",
        ),
    ];

    return Padding(
      padding: const EdgeInsets.all(8),
      child: InteractiveChart<Candle>(
        data: candles,
        timeOf: (c) => c.time,
        initialAnchor: ChartAnchor.right,
        initialSlotExtent: initialSlotExtent,
        valueAxis: const ValueAxisConfig(),
        timeAxis: const TimeAxisConfig(formatter: formatTimeMark),
        layers: [
          const GridLayer<Candle>(),
          HistogramLayer<Candle>(
            heightFraction: _histogramFraction,
            valueOf: (c) => c.volume,
            color: colors.blue.withValues(alpha: 0.4),
          ),
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
          // Last, so the icons and the card are drawn above everything else.
          EventLayer<Candle>(
            events: events,
            timeOf: (c) => c.time,
            bottomInsetFraction: _histogramFraction,
            overlay: EventOverlayConfig(
              dismissOnBarrierTap: dismissOnBarrierTap,
              backgroundColor: scheme.surface,
              titleStyle: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
                decoration: TextDecoration.none,
              ),
              descriptionStyle: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
