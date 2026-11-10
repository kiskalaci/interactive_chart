import "package:flutter/widgets.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/ticks.dart";

enum TimeAxisPlacement { top, bottom }

/// R-AXIS-7/R-TIME-13. `null` at the call site means "no time axis".
class TimeAxisConfig {
  const TimeAxisConfig({
    this.placement = TimeAxisPlacement.bottom,
    this.formatter,
    this.textStyle = const TextStyle(fontSize: 11, color: Color(0xFF757575)),
    this.emphasizedTextStyle = const TextStyle(
      fontSize: 11,
      color: Color(0xFF757575),
      fontWeight: FontWeight.w600,
    ),
  });

  final TimeAxisPlacement placement;
  final String Function(DateTime time, int weight)? formatter;
  final TextStyle textStyle;
  final TextStyle emphasizedTextStyle;

  String format(DateTime t, int weight) =>
      formatter?.call(t, weight) ?? defaultTimeLabel(t, weight);
}

/// Renders tick labels as positioned [Text] widgets rather than painting
/// them to a canvas, one per surviving mark.
class TimeAxisView extends StatelessWidget {
  const TimeAxisView({required this.ctx, required this.config, super.key});

  final InteractiveChartContext ctx;
  final TimeAxisConfig config;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final labels = <Widget>[];
      for (final mark in ctx.timeTicks) {
        final x = ctx.xOf(mark.index);
        final style = mark.weight >= 60
            ? config.emphasizedTextStyle
            : config.textStyle;
        final text = config.format(mark.time, mark.weight);
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();

        final left = x - painter.width / 2;
        if (left < 0 || left + painter.width > width) {
          continue; // R-TIME-15: drop rather than clip/overlap.
        }
        labels.add(
          Positioned(
            left: left,
            top: 4,
            child: Text(text, style: style),
          ),
        );
      }
      return Stack(children: labels);
    },
  );
}
