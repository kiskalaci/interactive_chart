import "package:flutter/widgets.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/layer.dart";
import "package:interactive_chart/src/value_axis/value_ticks.dart";

/// Follows the highlighted slot and projects labelled badges onto the
/// viewport edges (R-INT-1/2). `ctx.highlightedIndex` is the raw index —
/// real or projected. Over a projected slot ([InteractiveChartContext.highlightedProjectedTime]
/// set) it shows the time badge only, no value readout (R-TIME-29).
class CrosshairLayer<T> extends ChartLayer<T> {
  const CrosshairLayer({
    this.valueOf,
    this.timeOf,
    this.timeFormatter,
    this.lineColor = const Color(0x80000000),
    this.labelStyle = const TextStyle(fontSize: 11, color: Color(0xFFFFFFFF)),
    this.labelBackground = const Color(0xFF111111),
  });

  final double Function(T datum)? valueOf;
  final DateTime Function(T datum)? timeOf;

  /// Formats the time badge. Null uses the default.
  final String Function(DateTime time)? timeFormatter;
  final Color lineColor;
  final TextStyle labelStyle;
  final Color labelBackground;

  @override
  bool get dependsOnHighlight => true;

  @override
  Widget build(Size size, InteractiveChartContext ctx, List<T> data) {
    final index = ctx.highlightedIndex;
    if (index == null) {
      return const SizedBox.shrink();
    }

    final x = ctx.xOf(index);
    final projectedTime = ctx.highlightedProjectedTime;
    final isRealDatum =
        projectedTime == null && index >= 0 && index < data.length;

    final children = <Widget>[
      Positioned(
        left: x,
        top: 0,
        width: 1,
        height: size.height,
        child: ColoredBox(color: lineColor),
      ),
    ];

    if (isRealDatum && valueOf != null) {
      final v = valueOf!(data[index]);
      final y = ctx.yOf(v);
      children
        ..add(
          Positioned(
            left: 0,
            top: y,
            width: size.width,
            height: 1,
            child: ColoredBox(color: lineColor),
          ),
        )
        // Right-aligned to the viewport edge, centred on the line.
        ..add(
          _badge(
            anchor: Offset(size.width, y),
            translation: const Offset(-1, -0.5),
            text: v.toStringAsFixed(valueDecimals(ctx.valueTicks)),
          ),
        );
    }

    final format = timeFormatter ?? defaultTimeBadge;
    final timeLabel = projectedTime != null
        ? format(projectedTime)
        : (isRealDatum && timeOf != null ? format(timeOf!(data[index])) : null);
    if (timeLabel != null) {
      // Centred on the line, resting on the bottom edge.
      children.add(
        _badge(
          anchor: Offset(x, size.height),
          translation: const Offset(-0.5, -1),
          text: timeLabel,
        ),
      );
    }

    return IgnorePointer(child: Stack(children: children));
  }

  /// A badge whose box sits at [anchor] shifted by [translation] times its
  /// own size, then pulled back inside the viewport so it is never clipped
  /// at an edge.
  Widget _badge({
    required Offset anchor,
    required Offset translation,
    required String text,
  }) => Positioned.fill(
    child: CustomSingleChildLayout(
      delegate: _BadgeLayoutDelegate(anchor: anchor, translation: translation),
      child: Container(
        padding: const EdgeInsets.all(4),
        color: labelBackground,
        child: Text(text, style: labelStyle),
      ),
    ),
  );

  /// The default time badge (R-TIME-16: full precision of the datum). Daily
  /// or coarser bars, which sit on midnight, show the date; anything with a
  /// time of day also shows it, with seconds only when they are non-zero.
  static String defaultTimeBadge(DateTime t) {
    String two(int n) => n.toString().padLeft(2, "0");
    final date = "${t.year}-${two(t.month)}-${two(t.day)}";
    if (t.hour == 0 && t.minute == 0 && t.second == 0 && t.millisecond == 0) {
      return date;
    }
    final time = "${two(t.hour)}:${two(t.minute)}";
    return t.second == 0 ? "$date $time" : "$date $time:${two(t.second)}";
  }
}

class _BadgeLayoutDelegate extends SingleChildLayoutDelegate {
  const _BadgeLayoutDelegate({required this.anchor, required this.translation});

  final Offset anchor;
  final Offset translation;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final dx = anchor.dx + translation.dx * childSize.width;
    final dy = anchor.dy + translation.dy * childSize.height;
    return Offset(
      dx.clamp(0.0, (size.width - childSize.width).clamp(0.0, double.infinity)),
      dy.clamp(
        0.0,
        (size.height - childSize.height).clamp(0.0, double.infinity),
      ),
    );
  }

  @override
  bool shouldRelayout(_BadgeLayoutDelegate old) =>
      old.anchor != anchor || old.translation != translation;
}
