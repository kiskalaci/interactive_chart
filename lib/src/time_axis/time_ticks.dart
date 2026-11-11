import "dart:math" as math;
import "dart:typed_data";

import "package:interactive_chart/src/time_axis/tick_mark_weight.dart";

/// One candidate/selected label position on the time axis (§7.3).
class TickMark {
  const TickMark({
    required this.index,
    required this.time,
    required this.weight,
    required this.projected,
  });

  final int index;
  final DateTime time;
  final TickMarkWeight weight;
  final bool projected;
}

/// Tick-weight ladder (R-TIME-1), following TradingView's tiers: the weight
/// is the coarsest boundary crossed between [previous] and [current]. Intraday
/// tiers (1/5/30 minutes, 1/3/6/12 hours) are read from the wall-clock fields,
/// so they are unaffected by DST. Sub-second tiers are not modelled.
TickMarkWeight timeWeight(DateTime previous, DateTime current) {
  if (current.year != previous.year) {
    return TickMarkWeight.year;
  }
  if (current.month != previous.month) {
    return TickMarkWeight.month;
  }
  if (current.day != previous.day) {
    return TickMarkWeight.day;
  }
  if (current.hour != previous.hour) {
    if (current.hour ~/ 12 != previous.hour ~/ 12) {
      return TickMarkWeight.hour12;
    }
    if (current.hour ~/ 6 != previous.hour ~/ 6) {
      return TickMarkWeight.hour6;
    }
    if (current.hour ~/ 3 != previous.hour ~/ 3) {
      return TickMarkWeight.hour3;
    }
    return TickMarkWeight.hour1;
  }
  if (current.minute != previous.minute) {
    if (current.minute ~/ 30 != previous.minute ~/ 30) {
      return TickMarkWeight.minute30;
    }
    if (current.minute ~/ 5 != previous.minute ~/ 5) {
      return TickMarkWeight.minute5;
    }
    return TickMarkWeight.minute1;
  }
  return TickMarkWeight.second;
}

const _monthNames = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];

/// Weight -> label (R-TIME-12/13): format is chosen by the mark's weight,
/// not by zoom level.
String defaultTimeLabel(DateTime t, TickMarkWeight weight) {
  if (weight >= TickMarkWeight.year) {
    return "${t.year}";
  }
  if (weight >= TickMarkWeight.month) {
    return _monthNames[t.month - 1];
  }
  if (weight >= TickMarkWeight.day) {
    return "${t.day}";
  }
  final hh = t.hour.toString().padLeft(2, "0");
  final mm = t.minute.toString().padLeft(2, "0");
  if (weight >= TickMarkWeight.minute1) {
    return "$hh:$mm";
  }
  final ss = t.second.toString().padLeft(2, "0");
  return "$hh:$mm:$ss";
}

/// Greedy descending-weight tick selection (R-TIME-7). Runs over the whole
/// supplied [times] (real + projected, R-TIME-9/24) so panning at fixed zoom
/// never changes which marks exist.
///
/// POC simplification of R-TIME-8: `minLabelSpacingPx` is a configured
/// constant here rather than measured against the surviving levels' actual
/// label widths.
List<TickMark> buildTickMarks({
  required List<DateTime> times,
  required int realCount,
  required double slotExtent,
  double minLabelSpacingPx = 56,
}) {
  final n = times.length;
  if (n == 0) {
    return const [];
  }
  final weights = List<TickMarkWeight>.filled(n, TickMarkWeight.second);
  weights[0] =
      TickMarkWeight.year; // R-TIME-2: first datum opens with maximum context.
  for (var i = 1; i < n; i++) {
    weights[i] = timeWeight(times[i - 1], times[i]);
  }

  final minIndexGap = math.max(1, (minLabelSpacingPx / slotExtent).ceil());

  // Candidates go heaviest first, and equal weights in index order, so the
  // earlier slot wins a tie. That keeps which of two equal-weight neighbours
  // gets the label from flipping when data is appended or the zoom changes,
  // and lets the first datum (R-TIME-2) win a tie. Grouping by weight gives
  // that order in one pass, with no sort.
  final byWeight = <TickMarkWeight, List<int>>{};
  for (var i = 0; i < n; i++) {
    (byWeight[weights[i]] ??= []).add(i);
  }
  final tiers = byWeight.keys.toList()..sort((a, b) => b.compareTo(a));

  // A candidate is accepted unless an accepted mark is closer than
  // minIndexGap. Accepted marks are at least that far apart, so each bucket
  // of minIndexGap slots holds at most one, and any mark too close to slot i
  // is in i's bucket or a neighbouring one.
  final bucketCount = (n - 1) ~/ minIndexGap + 1;
  final buckets = Int32List(bucketCount)..fillRange(0, bucketCount, -1);
  bool clear(int i) {
    final b = i ~/ minIndexGap;
    for (var k = math.max(0, b - 1); k <= b + 1 && k < buckets.length; k++) {
      final a = buckets[k];
      if (a >= 0 && (a - i).abs() < minIndexGap) {
        return false;
      }
    }
    return true;
  }

  final accepted = <int>[];
  for (final tier in tiers) {
    for (final i in byWeight[tier]!) {
      if (clear(i)) {
        accepted.add(i);
        buckets[i ~/ minIndexGap] = i;
      }
    }
  }
  accepted.sort();

  return [
    for (final i in accepted)
      TickMark(
        index: i,
        time: times[i],
        weight: weights[i],
        projected: i >= realCount,
      ),
  ];
}

/// Modal-delta interval inference (R-TIME-20) over the trailing [sampleSize]
/// deltas between real timestamps, in seconds so sub-minute bars work.
int inferModalIntervalSeconds(List<DateTime> real, {int sampleSize = 100}) {
  if (real.length < 2) {
    return 24 * 60 * 60;
  }
  final n = math.min(sampleSize, real.length - 1);
  final counts = <int, int>{};
  for (var i = real.length - n; i < real.length; i++) {
    final minutes = real[i].difference(real[i - 1]).inSeconds;
    counts[minutes] = (counts[minutes] ?? 0) + 1;
  }
  return (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
      .first
      .key;
}

/// Projects [count] time points past the end of [real], stepped
/// calendar-day-aware with weekend skipping for day-or-coarser series
/// (R-TIME-21/22, simplified: exact for minute/hour/day cadences, not
/// calendar-month arithmetic). Computes the modal interval once, so this is
/// O(sampleSize + count) rather than O(count * sampleSize).
List<DateTime> projectTimes(
  List<DateTime> real,
  int count, {
  int sampleSize = 100,
  bool skipWeekends = true,
}) {
  if (count <= 0) {
    return const [];
  }
  if (real.isEmpty) {
    final now = DateTime.now();
    return [for (var i = 0; i < count; i++) now.add(Duration(days: i + 1))];
  }

  final modalSeconds = inferModalIntervalSeconds(real, sampleSize: sampleSize);
  final isDailyPlus = modalSeconds >= 24 * 60 * 60;

  // Monthly or coarser cadences (R-TIME-21): step by calendar months from the
  // last real datum, so Jan 31 -> Feb 28/29 -> Mar 31 rather than drifting
  // by a fixed number of days. A 28-day cadence is indistinguishable from
  // monthly here and is treated as monthly.
  const day = 24 * 60 * 60;
  if (modalSeconds >= 28 * day) {
    final months = math.max(1, (modalSeconds / (30.4375 * day)).round());
    return [for (var i = 1; i <= count; i++) _addMonths(real.last, months * i)];
  }

  var t = real.last;
  final result = <DateTime>[];
  for (var i = 0; i < count; i++) {
    t = t.add(Duration(seconds: modalSeconds));
    if (isDailyPlus && skipWeekends) {
      while (t.weekday == DateTime.saturday || t.weekday == DateTime.sunday) {
        t = t.add(const Duration(days: 1));
      }
    }
    result.add(t);
  }
  return result;
}

/// [t] moved forward by [months] calendar months, keeping the time of day
/// and clamping the day to the target month's length (Jan 31 + 1 month is
/// Feb 28, or Feb 29 in a leap year).
DateTime _addMonths(DateTime t, int months) {
  final monthIndex = t.month - 1 + months;
  final year = t.year + monthIndex ~/ 12;
  final month = monthIndex % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  final day = math.min(t.day, lastDay);
  return t.isUtc
      ? DateTime.utc(
          year,
          month,
          day,
          t.hour,
          t.minute,
          t.second,
          t.millisecond,
        )
      : DateTime(year, month, day, t.hour, t.minute, t.second, t.millisecond);
}

/// Single-slot convenience matching the `DateTime Function(int)` projector
/// shape from R-TIME-19's public API sketch.
DateTime projectTime(
  List<DateTime> real,
  int slotsAfterLast, {
  int sampleSize = 100,
  bool skipWeekends = true,
}) => projectTimes(
  real,
  slotsAfterLast,
  sampleSize: sampleSize,
  skipWeekends: skipWeekends,
).last;
