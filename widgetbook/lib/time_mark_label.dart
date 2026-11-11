import "package:interactive_chart/interactive_chart.dart";
import "package:intl/intl.dart";

final _year = DateFormat.y();
final _month = DateFormat.MMM();
final _day = DateFormat.d();
final _hourMinute = DateFormat.Hm();

/// Locale-aware time-axis label for a mark of the given [weight]: the year,
/// the month name, the day of the month, or `HH:mm`. `HH:mm` is the smallest
/// label, so seconds are never shown. Shared by the use cases so they format
/// the axis the same way.
String formatTimeMark(DateTime t, TickMarkWeight weight) {
  if (weight >= TickMarkWeight.year) {
    return _year.format(t);
  }
  if (weight >= TickMarkWeight.month) {
    return _month.format(t);
  }
  if (weight >= TickMarkWeight.day) {
    return _day.format(t);
  }
  return _hourMinute.format(t);
}
