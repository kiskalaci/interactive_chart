import "dart:math" as math;

import "package:flutter/widgets.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/layer.dart";
import "package:interactive_chart/src/typedefs/value_range.dart";

/// R-LAYER-4: body from open/close, wick from low/high, up/down colours,
/// configurable body-to-slot width ratio and minimum body width, and
/// degrades to a 1px line when `slotExtent < 2`.
///
/// Each candle is a real widget (a slot-wide [Positioned] column containing
/// wick + body), so it can carry its own [onTap]/[onHover] — a canvas paint
/// call has no way to know which pixels belong to which datum after the
/// fact.
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
    final bodyWidth = math.max(minBodyWidth, ctx.slotExtent * bodyWidthRatio);
    final halfSlot = ctx.slotExtent / 2;
    final children = <Widget>[];

    for (var i = ctx.visibleStart; i < ctx.visibleEnd && i < data.length; i++) {
      final datum = data[i];
      final o = openOf(datum);
      final h = highOf(datum);
      final l = lowOf(datum);
      final c = closeOf(datum);
      if (_isGap(o) || _isGap(h) || _isGap(l) || _isGap(c)) {
        continue;
      }

      final up = c >= o;
      final color = up ? upColor : downColor;
      final x = ctx.xOf(i);
      final yHigh = ctx.yOf(h);
      final yLow = ctx.yOf(l);
      final yOpen = ctx.yOf(o);
      final yClose = ctx.yOf(c);
      final top = math.min(yOpen, yClose);
      final bottom = math.max(math.max(yOpen, yClose), top + 1);

      final body = <Widget>[
        Positioned(
          left: halfSlot - 0.5,
          top: yHigh,
          width: 1,
          height: math.max(0, yLow - yHigh),
          child: ColoredBox(color: color),
        ),
        if (ctx.slotExtent < 2)
          Positioned(
            left: halfSlot - 0.5,
            top: math.min(yOpen, yClose),
            width: 1,
            height: math.max(1, (yOpen - yClose).abs()),
            child: ColoredBox(color: color),
          )
        else
          Positioned(
            left: halfSlot - bodyWidth / 2,
            top: top,
            width: bodyWidth,
            height: bottom - top,
            child: ColoredBox(color: color),
          ),
      ];

      final index = i;
      children.add(
        Positioned(
          left: x - halfSlot,
          top: 0,
          width: ctx.slotExtent,
          height: size.height,
          child: MouseRegion(
            onEnter: onHover == null ? null : (_) => onHover!(index),
            onExit: onHover == null ? null : (_) => onHover!(null),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: onTap == null ? null : () => onTap!(index),
              child: Stack(clipBehavior: Clip.none, children: body),
            ),
          ),
        ),
      );
    }

    return Stack(children: children);
  }
}
