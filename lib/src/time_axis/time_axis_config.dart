import "package:equatable/equatable.dart";
import "package:flutter/widgets.dart";
import "package:interactive_chart/src/ticks.dart";
import "package:interactive_chart/src/time_axis/time_axis_placement.dart";

/// R-AXIS-7/R-TIME-13. `null` at the call site means "no time axis".
class TimeAxisConfig extends Equatable {
  const TimeAxisConfig({
    this.placement = TimeAxisPlacement.bottom,
    this.formatter,
    this.textStyle = const TextStyle(fontSize: 11, color: Color(0xFF757575)),
    this.emphasizedTextStyle = const TextStyle(
      fontSize: 11,
      color: Color(0xFF757575),
      fontWeight: FontWeight.w600,
    ),
  });

  /// Which edge of the chart the time axis sits on.
  final TimeAxisPlacement placement;

  /// Builds the label text for a mark at [DateTime] `time` with the given
  /// `weight` (the coarsest boundary it crosses: 70 year, 60 month, 50 day,
  /// 30 hour, 20 minute, otherwise 10). When null, a default label for that
  /// weight is used.
  final String Function(DateTime time, int weight)? formatter;

  /// Style for ordinary marks, those with a weight below 60.
  final TextStyle textStyle;

  /// Style for marks with a weight of 60 or more (month and year boundaries).
  /// The heaviest weight on screen is additionally set in bold.
  final TextStyle emphasizedTextStyle;

  /// A copy with the given fields replaced. A null argument keeps the current
  /// value, so [formatter] cannot be reset to the default through this.
  TimeAxisConfig copyWith({
    TimeAxisPlacement? placement,
    String Function(DateTime time, int weight)? formatter,
    TextStyle? textStyle,
    TextStyle? emphasizedTextStyle,
  }) => TimeAxisConfig(
    placement: placement ?? this.placement,
    formatter: formatter ?? this.formatter,
    textStyle: textStyle ?? this.textStyle,
    emphasizedTextStyle: emphasizedTextStyle ?? this.emphasizedTextStyle,
  );

  String format(DateTime t, int weight) =>
      formatter?.call(t, weight) ?? defaultTimeLabel(t, weight);

  @override
  List<Object?> get props => [
    placement,
    formatter,
    textStyle,
    emphasizedTextStyle,
  ];
}
