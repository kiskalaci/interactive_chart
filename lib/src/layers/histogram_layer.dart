import "dart:math" as math;

import "package:flutter/widgets.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/layer.dart";
import "package:interactive_chart/src/painting/buffered_layer.dart";
import "package:interactive_chart/src/painting/item_hit_region.dart";
import "package:interactive_chart/src/painting/shape_painters.dart";
import "package:interactive_chart/src/typedefs/value_range.dart";

/// A non-negative magnitude series (volume) drawn in its own bottom strip of
/// the viewport, scaled to its own visible max. Opts out of autoscale by
/// default (R-SCALE-9) — a volume histogram must not compress the price
/// scale). A true stacked sub-pane (R-LAYOUT-4) is out of scope for this POC;
/// this is a fixed-fraction overlay strip instead. The bars are painted in
/// one picture; [onTap] and [onHover] report the bar under the pointer
/// through one hit region over the layer. A bar of zero or less is not drawn.
/// Like `CandleLayer`, the bars are computed for a margin beyond the view, so
/// a pan within it moves the painted bars instead of painting them again.
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

    final interactive = onTap != null || onHover != null;

    return Stack(
      children: [
        Positioned.fill(
          child: BufferedLayer<_Bars>(
            ctx: ctx,
            // The bars are scaled to the visible maximum, so it is part of
            // the key: a pan that changes it recomputes them.
            cacheKey: (
              this,
              ctx.dataRevision,
              ctx.slotExtent,
              localMax,
              size.height,
            ),
            compute: (start, end) => _bars(
              ctx,
              data,
              start,
              end,
              barWidth: barWidth,
              stripHeight: stripHeight,
              localMax: localMax,
              bottom: size.height,
            ),
            paintersOf: (content) => [
              (
                key: null,
                painter: BarPainter(bars: content.rects, color: color),
              ),
            ],
            overlay: interactive
                ? (content, shift) => ItemHitRegion(
                    resolve: (p) => switch (topmostRectAt(
                      content.rects,
                      p.translate(-shift, 0),
                      barWidth,
                    )) {
                      final k? => content.indices[k],
                      null => null,
                    },
                    onTap: onTap,
                    onHover: onHover,
                  )
                : null,
          ),
        ),
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

  /// The bars of `[start, end)`, in viewport coordinates at the current
  /// scroll offset. A bar of zero or less, or not a number, is left out.
  _Bars _bars(
    InteractiveChartContext ctx,
    List<T> data,
    int start,
    int end, {
    required double barWidth,
    required double stripHeight,
    required double localMax,
    required double bottom,
  }) {
    final rects = <Rect>[];
    final indices = <int>[];
    for (var i = start; i < end && i < data.length; i++) {
      final v = valueOf(data[i]);
      if (v.isNaN || v.isInfinite || v <= 0) {
        continue;
      }
      final barHeight = stripHeight * (v / localMax);
      rects.add(
        Rect.fromLTWH(
          ctx.xOf(i) - barWidth / 2,
          bottom - barHeight,
          barWidth,
          barHeight,
        ),
      );
      indices.add(i);
    }
    return (rects: rects, indices: indices);
  }
}

/// A [HistogramLayer]'s computed content: the bars and their indices.
typedef _Bars = ({List<Rect> rects, List<int> indices});
