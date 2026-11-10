import "dart:math" as math;

import "package:flutter/widgets.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/layer.dart";

/// R-LAYER-5 (subset): solid stroke, optional fill, gap handling per
/// R-DATA-8 — a NaN breaks the line rather than being interpolated across.
///
/// The stroke is built from rotated 1px-tall [ColoredBox] segments (one real
/// widget per gap-free pair of consecutive points) rather than a single
/// canvas [Path], and each vertex gets a small invisible hit target so
/// [onPointTap]/[onPointHover] can report which datum is under the pointer.
/// `fill` is approximated as one vertical strip per visible index rather
/// than a true area path — a deliberate trade-off of the widget-based
/// approach, acceptable since it's off by default.
class LineLayer<T> extends ChartLayer<T> {
  const LineLayer({
    required this.valueOf,
    this.color = const Color(0xFF3B82F6),
    this.strokeWidth = 1.5,
    this.fill = false,
    this.contributesToExtent = true,
    this.onPointTap,
    this.onPointHover,
    this.latestPointBuilder,
  });

  final double Function(T datum) valueOf;
  final Color color;
  final double strokeWidth;
  final bool fill;
  final bool contributesToExtent;

  /// Fires when the point at [index] is tapped.
  final void Function(int index)? onPointTap;

  /// Fires with the hovered point's index on enter, and `null` on exit.
  final void Function(int? index)? onPointHover;

  /// Optional marker for the series' latest point (the last datum), centred
  /// on it — e.g. a pulsing "live" dot. Only built while that point is
  /// within the visible range and has a finite value. The marker ignores
  /// pointer events.
  final Widget Function(BuildContext context, T datum, int index)?
  latestPointBuilder;

  @override
  ValueRange? extentFor(List<T> data, int start, int end) {
    if (!contributesToExtent) {
      return null;
    }
    double? lo, hi;
    for (var i = start; i < end; i++) {
      final v = valueOf(data[i]);
      if (v.isNaN || v.isInfinite) {
        continue;
      }
      lo = lo == null ? v : math.min(lo, v);
      hi = hi == null ? v : math.max(hi, v);
    }
    if (lo == null || hi == null) {
      return null;
    }
    return (lo, hi);
  }

  @override
  Widget build(Size size, InteractiveChartContext ctx, List<T> data) {
    final fills = <Widget>[];
    final segments = <Widget>[];
    final points = <Widget>[];
    Offset? prev;

    for (var i = ctx.visibleStart; i < ctx.visibleEnd && i < data.length; i++) {
      final v = valueOf(data[i]);
      if (v.isNaN || v.isInfinite) {
        prev = null;
        continue;
      }
      final x = ctx.xOf(i);
      final y = ctx.yOf(v);
      final point = Offset(x, y);

      if (fill) {
        fills.add(
          Positioned(
            left: x - ctx.slotExtent / 2,
            top: y,
            width: ctx.slotExtent,
            height: math.max(0, size.height - y),
            child: ColoredBox(color: color.withValues(alpha: 0.15)),
          ),
        );
      }

      if (prev != null) {
        segments.add(_segment(prev, point));
      }
      prev = point;

      if (onPointTap != null || onPointHover != null) {
        final index = i;
        const hitSize = 12.0;
        points.add(
          Positioned(
            left: x - hitSize / 2,
            top: y - hitSize / 2,
            width: hitSize,
            height: hitSize,
            child: MouseRegion(
              onEnter: onPointHover == null
                  ? null
                  : (_) => onPointHover!(index),
              onExit: onPointHover == null ? null : (_) => onPointHover!(null),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: onPointTap == null ? null : () => onPointTap!(index),
              ),
            ),
          ),
        );
      }
    }

    final marker = _latestPointMarker(ctx, data);

    return Stack(children: [...fills, ...segments, ...points, ?marker]);
  }

  Widget? _latestPointMarker(InteractiveChartContext ctx, List<T> data) {
    final builder = latestPointBuilder;
    final last = data.length - 1;
    if (builder == null || last < ctx.visibleStart || last >= ctx.visibleEnd) {
      return null;
    }
    final v = valueOf(data[last]);
    if (v.isNaN || v.isInfinite) {
      return null;
    }
    return Positioned(
      // Keyed so the marker keeps its element (and any State, such as a
      // running animation) when the number of segments before it in the
      // stack changes on a pan, zoom or appended bar.
      key: const ValueKey("interactive_chart.latestPointMarker"),
      left: ctx.xOf(last),
      top: ctx.yOf(v),
      child: IgnorePointer(
        child: FractionalTranslation(
          translation: const Offset(-0.5, -0.5),
          child: Builder(
            builder: (context) => builder(context, data[last], last),
          ),
        ),
      ),
    );
  }

  Widget _segment(Offset a, Offset b) {
    final delta = b - a;
    final length = delta.distance;
    final angle = math.atan2(delta.dy, delta.dx);
    return Positioned(
      left: a.dx,
      top: a.dy - strokeWidth / 2,
      width: length,
      height: strokeWidth,
      child: Transform.rotate(
        alignment: Alignment.centerLeft,
        angle: angle,
        child: ColoredBox(color: color),
      ),
    );
  }
}
