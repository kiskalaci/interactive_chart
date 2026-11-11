import "package:flutter/widgets.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/layer.dart";
import "package:interactive_chart/src/value_axis/value_ticks.dart";

/// Marks the latest price: a horizontal line across the whole chart at the
/// value of the newest datum, and a tag on the value axis showing that value.
///
/// The "latest" datum is the last one in the dataset, not the last one in
/// view, so the tag keeps showing the current price while the user pans back
/// in time. When that level is scrolled out of the vertical range, the tag
/// sticks to the top or bottom edge of the axis and the line is not drawn.
/// If the newest value is not a number, the newest one that is, is used.
///
/// The tag is only drawn when the chart has a value axis, because that is
/// where it sits; the axis grows to fit it. The value is never rounded:
/// digits past [precision] are cropped (see [truncateToDecimals]).
///
/// Purely decorative, so it never intercepts gestures. It does not
/// contribute to autoscale.
class PriceTagLayer<T> extends ChartLayer<T> {
  const PriceTagLayer({
    required this.valueOf,
    this.precision = 2,
    this.lineColor = const Color(0xFF111111),
    this.tagColor = const Color(0xFF111111),
    this.textStyle = const TextStyle(fontSize: 11, color: Color(0xFFFFFFFF)),
  }) : assert(precision >= 0, "precision must not be negative");

  /// The value of a datum that the tag follows, e.g. a candle's close.
  final double Function(T datum) valueOf;

  /// How many digits to show after the decimal separator. Extra digits are
  /// cropped, never rounded, and missing ones are padded with zeros.
  final int precision;

  /// Colour of the horizontal line.
  final Color lineColor;

  /// Background of the tag.
  final Color tagColor;

  /// Style of the tag text.
  final TextStyle textStyle;

  static const _tagPadding = EdgeInsets.symmetric(horizontal: 4, vertical: 3);

  double? _latestValue(List<T> data) {
    for (var i = data.length - 1; i >= 0; i--) {
      final v = valueOf(data[i]);
      if (v.isFinite) {
        return v;
      }
    }
    return null;
  }

  @override
  Widget build(Size size, InteractiveChartContext ctx, List<T> data) {
    final value = _latestValue(data);
    if (value == null) {
      return const SizedBox.shrink();
    }
    final y = ctx.yOf(value);
    if (y < 0 || y > size.height) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: y,
            width: size.width,
            height: 1,
            child: ColoredBox(color: lineColor),
          ),
        ],
      ),
    );
  }

  @override
  Widget? buildValueAxisOverlay(
    Size size,
    InteractiveChartContext ctx,
    List<T> data,
  ) {
    final value = _latestValue(data);
    if (value == null) {
      return null;
    }
    return IgnorePointer(
      child: CustomSingleChildLayout(
        delegate: _TagLayoutDelegate(centerY: ctx.yOf(value)),
        child: Container(
          padding: _tagPadding,
          color: tagColor,
          alignment: Alignment.center,
          child: Text(
            truncateToDecimals(value, precision),
            style: textStyle,
            maxLines: 1,
          ),
        ),
      ),
    );
  }

  @override
  double measureValueAxisOverlayWidth(
    InteractiveChartContext ctx,
    List<T> data,
    TextScaler textScaler,
  ) {
    final value = _latestValue(data);
    if (value == null) {
      return 0;
    }
    final painter = TextPainter(
      text: TextSpan(
        text: truncateToDecimals(value, precision),
        style: textStyle,
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    return painter.width + _tagPadding.horizontal;
  }
}

/// Stretches the tag across the gutter and centres it on [centerY], pulled
/// back inside the gutter so it is never clipped at the top or bottom.
class _TagLayoutDelegate extends SingleChildLayoutDelegate {
  const _TagLayoutDelegate({required this.centerY});

  final double centerY;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        minWidth: constraints.maxWidth,
        maxWidth: constraints.maxWidth,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxTop = (size.height - childSize.height).clamp(0.0, double.infinity);
    return Offset(0, (centerY - childSize.height / 2).clamp(0.0, maxTop));
  }

  @override
  bool shouldRelayout(_TagLayoutDelegate old) => old.centerY != centerY;
}
