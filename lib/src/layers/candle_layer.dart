import "dart:math" as math;

import "package:flutter/widgets.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/layer.dart";
import "package:interactive_chart/src/painting/buffered_layer.dart";
import "package:interactive_chart/src/painting/item_hit_region.dart";
import "package:interactive_chart/src/painting/shape_painters.dart";
import "package:interactive_chart/src/typedefs/value_range.dart";

/// R-LAYER-4: body from open/close, wick from low/high, up/down colours,
/// configurable body-to-slot width ratio and minimum body width, and
/// degrades to a 1px line when `slotExtent < 2`.
///
/// All candles are painted in one picture ([CandlePainter]), so the cost of a
/// frame does not depend on a widget per candle. [onTap] and [onHover] still
/// report the candle under the pointer: one hit region over the layer looks
/// it up in the painted geometry, each candle answering for its whole slot
/// column. Without either callback the layer takes no pointer events.
///
/// The candles are computed for a margin of slots beyond each edge of the
/// view and painted once; a pan that stays within that margin moves the
/// painted picture instead of painting it again (see [BufferedLayer]).
class CandleLayer<T> extends ChartLayer<T> {
  const CandleLayer({
    required this.openOf,
    required this.highOf,
    required this.lowOf,
    required this.closeOf,
    this.upColor = const Color(0xFF22C55E),
    this.downColor = const Color(0xFFEF4444),
    this.bodyWidthRatio = 0.7,
    this.minBodyWidth = 1,
    this.onTap,
    this.onHover,
  });

  final double Function(T datum) openOf;
  final double Function(T datum) highOf;
  final double Function(T datum) lowOf;
  final double Function(T datum) closeOf;
  final Color upColor;
  final Color downColor;
  final double bodyWidthRatio;
  final double minBodyWidth;

  /// Fires when the candle at `index` is tapped.
  final void Function(int index)? onTap;

  /// Fires with the hovered candle's index on enter, and `null` on exit.
  final void Function(int? index)? onHover;

  bool _isGap(double v) => v.isNaN || v.isInfinite;

  @override
  ValueRange? extentFor(List<T> data, int start, int end) {
    double? lo, hi;
    for (var i = start; i < end; i++) {
      final l = lowOf(data[i]);
      final h = highOf(data[i]);
      if (_isGap(l) || _isGap(h)) {
        continue;
      }
      lo = lo == null ? l : math.min(lo, l);
      hi = hi == null ? h : math.max(hi, h);
    }
    if (lo == null || hi == null) {
      return null;
    }
    return (lo, hi);
  }

  @override
  Widget build(Size size, InteractiveChartContext ctx, List<T> data) {
    final interactive = onTap != null || onHover != null;
    final slotExtent = ctx.slotExtent;
    return BufferedLayer<_Candles>(
      ctx: ctx,
      cacheKey: (
        this,
        ctx.dataRevision,
        slotExtent,
        ctx.valueMin,
        ctx.valueMax,
        size.height,
      ),
      compute: (start, end) {
        final shapes = _shapes(ctx, data, start, end);
        return (
          shapes: shapes,
          // Each candle answers for its whole slot column, top to bottom.
          columns: interactive
              ? [
                  for (final c in shapes)
                    Rect.fromLTWH(
                      c.wick.center.dx - slotExtent / 2,
                      0,
                      slotExtent,
                      size.height,
                    ),
                ]
              : const <Rect>[],
        );
      },
      paintersOf: (content) => [
        (
          key: null,
          painter: CandlePainter(
            candles: content.shapes,
            upColor: upColor,
            downColor: downColor,
          ),
        ),
      ],
      overlay: interactive
          ? (content, shift) => ItemHitRegion(
              resolve: (p) => switch (topmostRectAt(
                content.columns,
                p.translate(-shift, 0),
                slotExtent,
              )) {
                final k? => content.shapes[k].index,
                null => null,
              },
              onTap: onTap,
              onHover: onHover,
            )
          : null,
    );
  }

  /// The geometry of the candles in `[start, end)`, in viewport coordinates
  /// at the current scroll offset. A candle with any non-finite field is left
  /// out.
  List<CandleShape> _shapes(
    InteractiveChartContext ctx,
    List<T> data,
    int start,
    int end,
  ) {
    final bodyWidth = math.max(minBodyWidth, ctx.slotExtent * bodyWidthRatio);
    final thin = ctx.slotExtent < 2;
    final candles = <CandleShape>[];

    for (var i = start; i < end && i < data.length; i++) {
      final datum = data[i];
      final o = openOf(datum);
      final h = highOf(datum);
      final l = lowOf(datum);
      final c = closeOf(datum);
      if (_isGap(o) || _isGap(h) || _isGap(l) || _isGap(c)) {
        continue;
      }

      final x = ctx.xOf(i);
      final yHigh = ctx.yOf(h);
      final yLow = ctx.yOf(l);
      final yOpen = ctx.yOf(o);
      final yClose = ctx.yOf(c);
      final top = math.min(yOpen, yClose);
      final bottom = math.max(math.max(yOpen, yClose), top + 1);

      candles.add(
        CandleShape(
          index: i,
          up: c >= o,
          wick: Rect.fromLTWH(x - 0.5, yHigh, 1, math.max(0, yLow - yHigh)),
          body: thin
              ? Rect.fromLTWH(
                  x - 0.5,
                  top,
                  1,
                  math.max(1, (yOpen - yClose).abs()),
                )
              : Rect.fromLTWH(x - bodyWidth / 2, top, bodyWidth, bottom - top),
        ),
      );
    }
    return candles;
  }
}

/// A [CandleLayer]'s computed content: the candles, and their hit columns
/// when the layer has callbacks.
typedef _Candles = ({List<CandleShape> shapes, List<Rect> columns});
