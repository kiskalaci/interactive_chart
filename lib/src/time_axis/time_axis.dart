import "dart:math" as math;

import "package:flutter/widgets.dart";
import "package:interactive_chart/src/time_axis/time_axis_config.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/ticks.dart";

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
      final visible =
          <({TickMark mark, String text, TextStyle style, double left})>[];
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
        visible.add((mark: mark, text: text, style: style, left: left));
      }

      // The coarsest tier currently on screen is set in bold, so the reader
      // can tell which boundary (year, month, day, ...) the labels anchor to.
      var maxWeight = 0;
      for (final v in visible) {
        if (v.mark.weight > maxWeight) {
          maxWeight = v.mark.weight;
        }
      }
      final labels = <Widget>[];
      for (final v in visible) {
        if (v.mark.weight != maxWeight) {
          labels.add(
            Positioned(
              left: v.left,
              top: 4,
              child: Text(v.text, style: v.style),
            ),
          );
          continue;
        }
        // Bold is wider than what the survivors were measured with, so
        // re-centre it on its slot rather than letting it lean right.
        final style = v.style.copyWith(fontWeight: FontWeight.bold);
        final painter = TextPainter(
          text: TextSpan(text: v.text, style: style),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        labels.add(
          Positioned(
            left: (ctx.xOf(v.mark.index) - painter.width / 2).clamp(
              0,
              math.max(0, width - painter.width),
            ),
            top: 4,
            child: Text(v.text, style: style),
          ),
        );
      }
      return Stack(children: labels);
    },
  );
}
