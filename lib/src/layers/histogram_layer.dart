import "dart:math" as math;

import "package:flutter/widgets.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/layer.dart";

/// A non-negative magnitude series (volume) drawn in its own bottom strip of
/// the viewport, scaled to its own visible max. Opts out of autoscale by
/// default (R-SCALE-9) — a volume histogram must not compress the price
/// scale). A true stacked sub-pane (R-LAYOUT-4) is out of scope for this POC;
/// this is a fixed-fraction overlay strip instead. Each bar is a real widget
/// so it can carry its own [onTap]/[onHover].
class HistogramLayer<T> extends ChartLayer<T> {
  const HistogramLayer({
    required this.valueOf,
    this.color = const Color(0x803B82F6),
    this.heightFraction = 0.22,
    this.contributesToExtent = false,
    this.onTap,
    this.onHover,
  });

  final double Function(T datum) valueOf;
  final Color color;
  final double heightFraction;
  final bool contributesToExtent;
  final void Function(int index)? onTap;
  final void Function(int? index)? onHover;

  @override
  ValueRange? extentFor(List<T> data, int start, int end) {
    if (!contributesToExtent) {
      return null;
    }
    double? hi;
    for (var i = start; i < end; i++) {
      final v = valueOf(data[i]);
      if (v.isNaN || v.isInfinite) {
        continue;
      }
      hi = hi == null ? v : math.max(hi, v);
    }
    if (hi == null) {
      return null;
    }
    return (0, hi);
  }

  @override
  Widget build(Size size, InteractiveChartContext ctx, List<T> data) {
    double localMax = 0;
    for (var i = ctx.visibleStart; i < ctx.visibleEnd && i < data.length; i++) {
      final v = valueOf(data[i]);
      if (v.isNaN || v.isInfinite) {
        continue;
      }
      localMax = math.max(localMax, v);
    }
    if (localMax <= 0) {
      return const SizedBox.shrink();
    }

    final stripHeight = size.height * heightFraction;
    final stripTop = size.height - stripHeight;
    final barWidth = math.max(1, ctx.slotExtent * 0.7).toDouble();

    final bars = <Widget>[];
    for (var i = ctx.visibleStart; i < ctx.visibleEnd && i < data.length; i++) {
      final v = valueOf(data[i]);
      if (v.isNaN || v.isInfinite) {
        continue;
      }
      final x = ctx.xOf(i);
      final barHeight = stripHeight * (v / localMax);
      final index = i;

      bars.add(
        Positioned(
          left: x - barWidth / 2,
          top: size.height - barHeight,
          width: barWidth,
          height: barHeight,
          child: MouseRegion(
            onEnter: onHover == null ? null : (_) => onHover!(index),
            onExit: onHover == null ? null : (_) => onHover!(null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap == null ? null : () => onTap!(index),
              child: ColoredBox(color: color),
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        ...bars,
        // Baseline so the strip reads as its own region.
        Positioned(
          left: 0,
          top: stripTop,
          width: size.width,
          height: 1,
          child: ColoredBox(color: color.withValues(alpha: 0.3)),
        ),
      ],
    );
  }
}
