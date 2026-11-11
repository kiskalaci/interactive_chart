import "dart:math" as math;
import "dart:ui" as ui;

import "package:flutter/widgets.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/layer.dart";
import "package:interactive_chart/src/painting/item_hit_region.dart";
import "package:interactive_chart/src/painting/shape_painters.dart";
import "package:interactive_chart/src/typedefs/value_range.dart";

/// R-LAYER-5 (subset): solid stroke, optional fill, gap handling per
/// R-DATA-8 — a NaN breaks the line rather than being interpolated across.
///
/// The stroke is one canvas path ([LinePainter]) through every gap-free run
/// of points, with round joins, so its cost does not depend on a widget per
/// segment and sharp turns have no notches. A point with no finite neighbour
/// on either side draws nothing. With [onPointTap] or [onPointHover], one hit
/// region over the
/// layer reports the point under the pointer: each point answers to a
/// [pointHitSize] square around it.
///
/// With [fill], the area under the line is shaded with a vertical gradient:
/// strongest ([fillTopOpacity]) at the highest point of the line in view,
/// fading to [fillBottomOpacity] (transparent by default) at the bottom of
/// the viewport. It is a single canvas path per gap-free run of points, so a
/// gap in the data leaves a gap in the shading too.
class LineLayer<T> extends ChartLayer<T> {
  const LineLayer({
    required this.valueOf,
    this.color = const Color(0xFF3B82F6),
    this.strokeWidth = 1.5,
    this.fill = false,
    this.fillTopOpacity = 0.4,
    this.fillBottomOpacity = 0,
    this.contributesToExtent = true,
    this.onPointTap,
    this.onPointHover,
    this.latestPointBuilder,
  });

  /// Key of the gradient fill while [fill] is on and there is something to
  /// shade.
  static const fillKey = ValueKey("interactive_chart.lineFill");

  /// Key of the stroke while there is a point to draw.
  static const strokeKey = ValueKey("interactive_chart.lineStroke");

  /// Side of the square around each point that [onPointTap] and
  /// [onPointHover] answer to. Where neighbouring squares overlap, the later
  /// point wins.
  static const pointHitSize = 12.0;

  final double Function(T datum) valueOf;
  final Color color;
  final double strokeWidth;
  final bool fill;

  /// Opacity of the fill at the highest point of the line in view, 0 to 1.
  /// Only used when [fill] is true.
  final double fillTopOpacity;

  /// Opacity of the fill at the bottom of the viewport, 0 to 1. Transparent
  /// by default. Only used when [fill] is true.
  final double fillBottomOpacity;
  final bool contributesToExtent;

  /// Fires when the point at `index` is tapped.
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
    // Hit targets of the points, and their indices.
    final targets = <Rect>[];
    final targetIndices = <int>[];
    // Gap-free runs of points, for the stroke and the fill.
    final runs = <List<Offset>>[];
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

      if (prev == null) {
        runs.add([point]);
      } else {
        runs.last.add(point);
      }
      prev = point;

      if (onPointTap != null || onPointHover != null) {
        targets.add(
          Rect.fromLTWH(
            x - pointHitSize / 2,
            y - pointHitSize / 2,
            pointHitSize,
            pointHitSize,
          ),
        );
        targetIndices.add(i);
      }
    }

    final marker = _latestPointMarker(ctx, data);

    return Stack(
      children: [
        if (fill && runs.isNotEmpty)
          Positioned.fill(
            key: fillKey,
            child: IgnorePointer(
              child: CustomPaint(
                painter: _AreaFillPainter(
                  runs: runs,
                  color: color,
                  topOpacity: fillTopOpacity,
                  bottomOpacity: fillBottomOpacity,
                ),
              ),
            ),
          ),
        if (runs.isNotEmpty)
          Positioned.fill(
            key: strokeKey,
            child: CustomPaint(
              painter: LinePainter(
                runs: runs,
                color: color,
                strokeWidth: strokeWidth,
              ),
            ),
          ),
        if (targets.isNotEmpty)
          Positioned.fill(
            // Keyed so it keeps its hover state when the fill or the stroke
            // before it comes or goes.
            key: const ValueKey("interactive_chart.linePointTargets"),
            child: ItemHitRegion(
              resolve: (p) => switch (topmostRectAt(targets, p, pointHitSize)) {
                final k? => targetIndices[k],
                null => null,
              },
              onTap: onPointTap,
              onHover: onPointHover,
            ),
          ),
        ?marker,
      ],
    );
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
      // running animation) when the layers before it in the stack come or
      // go on a pan, zoom or appended bar.
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
}

/// Shades the area under each run of points with a vertical gradient from
/// the highest point of any run down to the bottom of the canvas.
class _AreaFillPainter extends CustomPainter {
  const _AreaFillPainter({
    required this.runs,
    required this.color,
    required this.topOpacity,
    required this.bottomOpacity,
  });

  final List<List<Offset>> runs;
  final Color color;
  final double topOpacity;
  final double bottomOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    var top = size.height;
    for (final run in runs) {
      for (final point in run) {
        top = math.min(top, point.dy);
      }
    }
    // Keeps the gradient well defined when the line sits on the bottom edge.
    final bottom = math.max(size.height, top + 1);
    final paint = Paint()
      ..shader = ui.Gradient.linear(Offset(0, top), Offset(0, bottom), [
        color.withValues(alpha: topOpacity),
        color.withValues(alpha: bottomOpacity),
      ]);
    for (final run in runs) {
      if (run.length < 2) {
        continue;
      }
      final path = Path()..moveTo(run.first.dx, bottom);
      for (final point in run) {
        path.lineTo(point.dx, point.dy);
      }
      path
        ..lineTo(run.last.dx, bottom)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_AreaFillPainter old) =>
      old.runs != runs ||
      old.color != color ||
      old.topOpacity != topOpacity ||
      old.bottomOpacity != bottomOpacity;
}
