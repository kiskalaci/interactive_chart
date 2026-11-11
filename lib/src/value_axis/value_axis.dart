import "package:flutter/widgets.dart";
import "package:interactive_chart/src/value_axis/value_axis_config.dart";
import "package:interactive_chart/src/value_axis/value_axis_placement.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/painting/label_sizes.dart";
import "package:interactive_chart/src/value_axis/value_ticks.dart";

/// Renders tick labels for the value axis gutter as positioned [Text]
/// widgets. Self-sizing (measuring the widest label) is done by
/// [measureValueAxisWidth], used by the widget that owns this view per
/// R-AXIS-3 — this widget only lays out at a given width.
class ValueAxisView extends StatelessWidget {
  const ValueAxisView({required this.ctx, required this.config, super.key});

  final InteractiveChartContext ctx;
  final ValueAxisConfig config;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;
      final labels = <Widget>[];
      final decimals = valueDecimals(ctx.valueTicks);
      for (final v in ctx.valueTicks) {
        final y = ctx.yOf(v);
        if (y < -8 || y > height + 8) {
          continue;
        }
        final text = config.format(v, decimals: decimals);
        final label = _labelSize(
          text,
          config.textStyle,
          MediaQuery.textScalerOf(context),
          width,
        );
        final dx = config.placement == ValueAxisPlacement.right
            ? 4.0
            : width - label.width - 4.0;
        labels.add(
          Positioned(
            left: dx,
            top: y - label.height / 2,
            child: Text(text, style: config.textStyle),
          ),
        );
      }
      return Stack(children: labels);
    },
  );
}

/// Measures the widest currently-visible tick label, used by the widget to
/// keep the gutter width sticky (R-AXIS-5: grow-only within a session).
double measureValueAxisWidth(
  InteractiveChartContext ctx,
  ValueAxisConfig config, {
  TextScaler textScaler = TextScaler.noScaling,
}) {
  var maxWidth = 0.0;
  final decimals = valueDecimals(ctx.valueTicks);
  for (final v in ctx.valueTicks) {
    final width = LabelSizes.instance
        .of(config.format(v, decimals: decimals), config.textStyle, textScaler)
        .width;
    if (width > maxWidth) {
      maxWidth = width;
    }
  }
  return maxWidth + 8;
}

/// The size of a label laid out at most [maxWidth] wide: the cached one-line
/// size when it fits, as it does once the gutter has grown to its labels.
Size _labelSize(
  String text,
  TextStyle style,
  TextScaler textScaler,
  double maxWidth,
) {
  final size = LabelSizes.instance.of(text, style, textScaler);
  if (size.width <= maxWidth) {
    return size;
  }
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout(maxWidth: maxWidth);
  final constrained = painter.size;
  painter.dispose();
  return constrained;
}
