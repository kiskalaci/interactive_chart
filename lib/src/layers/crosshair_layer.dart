import "package:flutter/widgets.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/layer.dart";

/// Follows the highlighted slot and projects labelled badges onto the
/// viewport edges (R-INT-1/2). `ctx.highlightedIndex` is the raw index —
/// real or projected. Over a projected slot ([InteractiveChartContext.highlightedProjectedTime]
/// set) it shows the time badge only, no value readout (R-TIME-29).
class CrosshairLayer<T> extends ChartLayer<T> {
  const CrosshairLayer({
    this.valueOf,
    this.timeOf,
    this.lineColor = const Color(0x80000000),
    this.labelStyle = const TextStyle(fontSize: 11, color: Color(0xFFFFFFFF)),
    this.labelBackground = const Color(0xFF111111),
  });

  final double Function(T datum)? valueOf;
  final DateTime Function(T datum)? timeOf;
  final Color lineColor;
  final TextStyle labelStyle;
  final Color labelBackground;

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
        ..add(
          _badge(
            right: 0,
            top: y,
            text: v.toStringAsFixed(2),
            translation: const Offset(0, -0.5),
          ),
        );
    }

    final timeLabel = projectedTime != null
        ? _formatDate(projectedTime)
        : (isRealDatum && timeOf != null
              ? _formatDate(timeOf!(data[index]))
              : null);
    if (timeLabel != null) {
      children.add(
        _badge(
          left: x,
          top: size.height,
          text: timeLabel,
          translation: const Offset(-0.5, -1),
        ),
      );
    }

    return IgnorePointer(child: Stack(children: children));
  }

  Widget _badge({
    required double top,
    required String text,
    required Offset translation,
    double? left,
    double? right,
  }) => Positioned(
    left: left,
    right: right,
    top: top,
    child: FractionalTranslation(
      translation: translation,
      child: Container(
        padding: const EdgeInsets.all(4),
        color: labelBackground,
        child: Text(text, style: labelStyle),
      ),
    ),
  );

  String _formatDate(DateTime t) =>
      "${t.year}-${t.month.toString().padLeft(2, "0")}-${t.day.toString().padLeft(2, "0")}";
}
