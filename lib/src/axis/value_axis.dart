import "package:flutter/widgets.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/ticks.dart";

enum ValueAxisPlacement { left, right }

/// R-AXIS-6/8/9. `null` at the call site means "no value axis" (R-API-3).
class ValueAxisConfig {
  const ValueAxisConfig({
    this.placement = ValueAxisPlacement.right,
    this.formatter,
    this.textStyle = const TextStyle(fontSize: 11, color: Color(0xFF757575)),
  });

  final ValueAxisPlacement placement;
  final String Function(double value)? formatter;
  final TextStyle textStyle;

  /// Formats [value]. Without a [formatter], [decimals] places are used
  /// (the axis passes enough to tell adjacent ticks apart).
  String format(double value, {int decimals = 2}) =>
      formatter?.call(value) ?? value.toStringAsFixed(decimals);
}

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
        final painter = TextPainter(
          text: TextSpan(text: text, style: config.textStyle),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: width);
        final dx = config.placement == ValueAxisPlacement.right
            ? 4.0
            : width - painter.width - 4.0;
        labels.add(
          Positioned(
            left: dx,
            top: y - painter.height / 2,
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
    final painter = TextPainter(
      text: TextSpan(
        text: config.format(v, decimals: decimals),
        style: config.textStyle,
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    if (painter.width > maxWidth) {
      maxWidth = painter.width;
    }
  }
  return maxWidth + 8;
}
