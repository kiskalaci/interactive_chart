import "package:flutter/widgets.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/layer.dart";

/// Horizontal lines at the value ticks, vertical lines at the time ticks —
/// including projected ones, so the grid does not stop dead at the last bar
/// (R-TIME-26). Purely decorative, so it never intercepts gestures meant for
/// the layers above it.
class GridLayer<T> extends ChartLayer<T> {
  const GridLayer({this.color = const Color(0x1F000000)});

  final Color color;

  @override
  Widget build(Size size, InteractiveChartContext ctx, List<T> data) {
    final lines = <Widget>[
      for (final v in ctx.valueTicks)
        Positioned(
          left: 0,
          top: ctx.yOf(v),
          width: size.width,
          height: 1,
          child: ColoredBox(color: color),
        ),
      for (final mark in ctx.timeTicks)
        if (ctx.xOf(mark.index) >= -1 && ctx.xOf(mark.index) <= size.width + 1)
          Positioned(
            left: ctx.xOf(mark.index),
            top: 0,
            width: 1,
            height: size.height,
            child: ColoredBox(color: color),
          ),
    ];
    return IgnorePointer(child: Stack(children: lines));
  }
}
