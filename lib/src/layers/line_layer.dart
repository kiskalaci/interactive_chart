import "dart:math" as math;
import "dart:ui" as ui;

import "package:flutter/widgets.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/layer.dart";
import "package:interactive_chart/src/painting/buffered_layer.dart";
import "package:interactive_chart/src/painting/item_hit_region.dart";
import "package:interactive_chart/src/painting/shape_painters.dart";
import "package:interactive_chart/src/typedefs/value_range.dart";
import "package:interactive_chart/src/value_axis/block_extents.dart";

/// R-LAYER-5 (subset): solid stroke, optional fill, gap handling per
/// R-DATA-8 — a NaN breaks the line rather than being interpolated across.
///
/// The stroke is one canvas path ([LinePainter]) through every gap-free run
/// of points, with round joins, so its cost does not depend on a widget per
/// segment and sharp turns have no notches. A point with no finite neighbour
/// on either side draws nothing. With [onPointTap] or [onPointHover], one hit
/// region over the
/// layer reports the point under the pointer: each point answers to a
/// [pointHitSize] square around it. Like `CandleLayer`, the line is computed
/// for a margin beyond the view, so a pan within it moves the painted line
/// instead of painting it again. Zoomed out past a pixel per slot, each pixel
/// column keeps only its first, lowest, highest and last point.
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
  ValueRange? extentFor(List<T> data, int start, int end) =>
      contributesToExtent ? _rangeOf(data, start, end) : null;

  /// The lowest and highest finite value in `[start, end)`.
  ValueRange? _rangeOf(List<T> data, int start, int end) {
    double? lo, hi;
    for (var i = start; i < end; i++) {
      final v = valueOf(data[i]);
      if (v.isNaN || v.isInfinite) {
        continue;
      }
      lo = lo == null ? v : math.min(lo, v);
      hi = hi == null ? v : math.max(hi, v);
    }
    return lo == null || hi == null ? null : (lo, hi);
  }

  @override
  Widget build(Size size, InteractiveChartContext ctx, List<T> data) {
    final interactive = onPointTap != null || onPointHover != null;
    // The fill's gradient starts at the highest point in view, so a pan
    // that moves it repaints the fill.
    final fillTop = fill ? _highestVisibleY(size, ctx, data) : null;
    final marker = _latestPointMarker(ctx, data);

    final line = BufferedLayer<_Line>(
      ctx: ctx,
      cacheKey: (
        this,
        ctx.dataRevision,
        ctx.slotExtent,
        ctx.valueMin,
        ctx.valueMax,
        size.height,
        fillTop,
      ),
      compute: (start, end) => ctx.slotExtent < 1
          ? _columnLine(ctx, data, start, end, withTargets: interactive)
          : _line(ctx, data, start, end, withTargets: interactive),
      paintersOf: (content) => [
        if (fillTop != null && content.runs.isNotEmpty)
          (
            key: fillKey,
            painter: _AreaFillPainter(
              runs: content.runs,
              top: fillTop,
              color: color,
              topOpacity: fillTopOpacity,
              bottomOpacity: fillBottomOpacity,
            ),
          ),
        if (content.runs.isNotEmpty)
          (
            key: strokeKey,
            painter: LinePainter(
              runs: content.runs,
              color: color,
              strokeWidth: strokeWidth,
            ),
          ),
      ],
      overlay: interactive
          ? (content, shift) => ItemHitRegion(
              resolve: (p) => switch (topmostRectAt(
                content.targets,
                p.translate(-shift, 0),
                pointHitSize,
              )) {
                final k? => content.targetIndices[k],
                null => null,
              },
              onTap: onPointTap,
              onHover: onPointHover,
            )
          : null,
    );

    return Stack(
      children: [
        Positioned.fill(child: line),
        ?marker,
      ],
    );
  }

  /// The y of the highest finite point in view, or the bottom of the
  /// viewport if there is none. Cached per block, so a wide zoomed-out view
  /// does not rescan every point on each frame.
  double _highestVisibleY(
    Size size,
    InteractiveChartContext ctx,
    List<T> data,
  ) {
    final visible = ctx
        .cached((
          this,
          #lineRange,
        ), () => BlockExtents((a, b) => _rangeOf(data, a, b)))
        .over(ctx.visibleStart, math.min(ctx.visibleEnd, data.length));
    return visible == null
        ? size.height
        : math.min(size.height, ctx.yOf(visible.$2));
  }

  /// The gap-free runs of points in `[start, end)`, in viewport coordinates at
  /// the current scroll offset, and with [withTargets] each point's hit
  /// square and index.
  _Line _line(
    InteractiveChartContext ctx,
    List<T> data,
    int start,
    int end, {
    required bool withTargets,
  }) {
    final targets = <Rect>[];
    final targetIndices = <int>[];
    final runs = <List<Offset>>[];
    var inRun = false;
    for (var i = start; i < end && i < data.length; i++) {
      final v = valueOf(data[i]);
      if (v.isNaN || v.isInfinite) {
        inRun = false;
        continue;
      }
      final point = Offset(ctx.xOf(i), ctx.yOf(v));
      if (inRun) {
        runs.last.add(point);
      } else {
        runs.add([point]);
        inRun = true;
      }
      if (withTargets) {
        targets.add(
          Rect.fromCenter(
            center: point,
            width: pointHitSize,
            height: pointHitSize,
          ),
        );
        targetIndices.add(i);
      }
    }
    return (runs: runs, targets: targets, targetIndices: targetIndices);
  }

  /// Below a pixel per slot (level of detail): per pixel column of content,
  /// only the first, lowest, highest and last point, in index order. The
  /// stroke through them covers the same pixels as one through every point,
  /// at a few points per pixel however far out the view is zoomed. A column
  /// with no finite value breaks the line; a gap inside a column does not.
  _Line _columnLine(
    InteractiveChartContext ctx,
    List<T> data,
    int start,
    int end, {
    required bool withTargets,
  }) {
    final targets = <Rect>[];
    final targetIndices = <int>[];
    final runs = <List<Offset>>[];
    var inRun = false;

    int? column;
    var any = false;
    var first = 0, last = 0, low = 0, high = 0;
    var lowV = 0.0, highV = 0.0;

    void flush() {
      if (column == null) {
        return;
      }
      if (!any) {
        inRun = false;
        return;
      }
      final picked = {first, low, high, last}.toList()..sort();
      for (final i in picked) {
        final point = Offset(ctx.xOf(i), ctx.yOf(valueOf(data[i])));
        if (inRun) {
          runs.last.add(point);
        } else {
          runs.add([point]);
          inRun = true;
        }
        if (withTargets) {
          targets.add(
            Rect.fromCenter(
              center: point,
              width: pointHitSize,
              height: pointHitSize,
            ),
          );
          targetIndices.add(i);
        }
      }
    }

    for (var i = start; i < end && i < data.length; i++) {
      final col = (i * ctx.slotExtent).floor();
      if (col != column) {
        flush();
        column = col;
        any = false;
      }
      final v = valueOf(data[i]);
      if (v.isNaN || v.isInfinite) {
        continue;
      }
      if (!any) {
        any = true;
        first = low = high = i;
        lowV = highV = v;
      } else {
        if (v < lowV) {
          low = i;
          lowV = v;
        }
        if (v > highV) {
          high = i;
          highV = v;
        }
      }
      last = i;
    }
    flush();
    return (runs: runs, targets: targets, targetIndices: targetIndices);
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
/// [top] down to the bottom of the canvas.
class _AreaFillPainter extends CustomPainter {
  const _AreaFillPainter({
    required this.runs,
    required this.top,
    required this.color,
    required this.topOpacity,
    required this.bottomOpacity,
  });

  final List<List<Offset>> runs;

  /// Where the gradient starts: the highest point of the line in view.
  final double top;
  final Color color;
  final double topOpacity;
  final double bottomOpacity;

  @override
  void paint(Canvas canvas, Size size) {
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

  /// Painting only: a layer's taps and hovers go through its hit region.
  @override
  bool hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_AreaFillPainter old) =>
      old.runs != runs ||
      old.top != top ||
      old.color != color ||
      old.topOpacity != topOpacity ||
      old.bottomOpacity != bottomOpacity;
}

/// A [LineLayer]'s computed content: its runs of points, and the points' hit
/// squares and indices when the layer has callbacks.
typedef _Line = ({
  List<List<Offset>> runs,
  List<Rect> targets,
  List<int> targetIndices,
});
