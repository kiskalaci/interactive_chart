import "package:equatable/equatable.dart";
import "package:flutter/widgets.dart";
import "package:interactive_chart/src/value_axis/value_axis_placement.dart";

/// R-AXIS-6/8/9. `null` at the call site means "no value axis" (R-API-3).
class ValueAxisConfig extends Equatable {
  const ValueAxisConfig({
    this.placement = ValueAxisPlacement.right,
    this.formatter,
    this.textStyle = const TextStyle(fontSize: 11, color: Color(0xFF757575)),
  });

  /// Which side of the chart the value axis sits on.
  final ValueAxisPlacement placement;

  /// Builds the label text for a tick at the given value. When null, values
  /// are printed with as many decimals as it takes to tell adjacent ticks
  /// apart.
  final String Function(double value)? formatter;

  /// Style for the tick labels.
  final TextStyle textStyle;

  /// A copy with the given fields replaced. A null argument keeps the current
  /// value, so [formatter] cannot be reset to the default through this.
  ValueAxisConfig copyWith({
    ValueAxisPlacement? placement,
    String Function(double value)? formatter,
    TextStyle? textStyle,
  }) => ValueAxisConfig(
    placement: placement ?? this.placement,
    formatter: formatter ?? this.formatter,
    textStyle: textStyle ?? this.textStyle,
  );

  /// Formats [value]. Without a [formatter], [decimals] places are used
  /// (the axis passes enough to tell adjacent ticks apart).
  String format(double value, {int decimals = 2}) =>
      formatter?.call(value) ?? value.toStringAsFixed(decimals);

  @override
  List<Object?> get props => [placement, formatter, textStyle];
}
