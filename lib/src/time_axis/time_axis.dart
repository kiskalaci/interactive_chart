import "dart:math" as math;

import "package:flutter/widgets.dart";
import "package:interactive_chart/src/time_axis/tick_mark_weight.dart";
import "package:interactive_chart/src/time_axis/time_axis_config.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/painting/label_sizes.dart";
import "package:interactive_chart/src/time_axis/time_ticks.dart";

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
      final textScaler = MediaQuery.textScalerOf(context);
      final marks = ctx.timeTicks;
      final visible =
          <({TickMark mark, String text, TextStyle style, double left})>[];
      // A label is centred on its mark and dropped unless it fits entirely,
      // so a mark outside the axis can never show. Marks are in slot order:
      // start at the first one inside and stop past the right edge, instead
      // of formatting and measuring every mark of the series on each frame.
      for (var k = _firstMarkAtOrAfter(marks, 0); k < marks.length; k++) {
        final mark = marks[k];
        final x = ctx.xOf(mark.index);
        if (x > width) {
          break;
        }
        final style = mark.weight >= TickMarkWeight.month
            ? config.emphasizedTextStyle
            : config.textStyle;
        final text = config.format(mark.time, mark.weight);
        final labelWidth = LabelSizes.instance
            .of(text, style, textScaler)
            .width;

        final left = x - labelWidth / 2;
        if (left < 0 || left + labelWidth > width) {
          continue; // R-TIME-15: drop rather than clip/overlap.
        }
        visible.add((mark: mark, text: text, style: style, left: left));
      }

      // The coarsest tier currently on screen is set in bold, so the reader
      // can tell which boundary (year, month, day, ...) the labels anchor to.
      TickMarkWeight? maxWeight;
      for (final v in visible) {
        if (maxWeight == null || v.mark.weight > maxWeight) {
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
        final boldWidth = LabelSizes.instance
            .of(v.text, style, textScaler)
            .width;
        labels.add(
          Positioned(
            left: (ctx.xOf(v.mark.index) - boldWidth / 2).clamp(
              0,
              math.max(0, width - boldWidth),
            ),
            top: 4,
            child: Text(v.text, style: style),
          ),
        );
      }
      return Stack(children: labels);
    },
  );

  /// The index of the first of [marks] (in slot order) at or right of
  /// viewport x [x], or `marks.length` if none is.
  int _firstMarkAtOrAfter(List<TickMark> marks, double x) {
    var lo = 0;
    var hi = marks.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (ctx.xOf(marks[mid].index) < x) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}
