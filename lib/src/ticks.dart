import "dart:math" as math;

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
  final int weight;
  final bool projected;
}

/// Simplified tick-weight ladder (R-TIME-1). The full spec has 13 tiers
/// (down to sub-second and 5/30-minute/3/6/12-hour boundaries); this POC
/// keeps the six tiers needed to demonstrate the "coarsest boundary wins"
/// behaviour without the extra granularity.
int timeWeight(DateTime previous, DateTime current) {
  if (current.year != previous.year) {
    return 70;
  }
  if (current.month != previous.month) {
    return 60;
  }
  if (current.day != previous.day) {
    return 50;
  }
  if (current.hour != previous.hour) {
    return 30;
  }
  if (current.minute != previous.minute) {
    return 20;
  }
  return 10;
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
String defaultTimeLabel(DateTime t, int weight) {
  if (weight >= 70) {
    return "${t.year}";
  }
  if (weight >= 60) {
    return _monthNames[t.month - 1];
  }
  if (weight >= 50) {
    return "${t.day}";
  }
  final hh = t.hour.toString().padLeft(2, "0");
  final mm = t.minute.toString().padLeft(2, "0");
  if (weight >= 20) {
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
  final weights = List<int>.filled(n, 0);
  weights[0] = 70; // R-TIME-2: first datum opens with maximum context.
  for (var i = 1; i < n; i++) {
    weights[i] = timeWeight(times[i - 1], times[i]);
  }

  final minIndexGap = math.max(1, (minLabelSpacingPx / slotExtent).ceil());
  // Heaviest first; equal weights go to the earlier slot. `List.sort` is not
  // stable, so without this tie-break which of two equal-weight neighbours
  // gets the label would be arbitrary, and could flip when data is appended
  // or the zoom changes. It also lets the first datum (R-TIME-2) win a tie.
  final order = List<int>.generate(n, (i) => i)
    ..sort((a, b) {
      final byWeight = weights[b].compareTo(weights[a]);
      return byWeight != 0 ? byWeight : a.compareTo(b);
    });

  final accepted = <int>[];
  for (final i in order) {
    var ok = true;
    for (final a in accepted) {
      if ((a - i).abs() < minIndexGap) {
        ok = false;
        break;
      }
    }
    if (ok) {
      accepted.add(i);
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

/// How many decimals value labels need so adjacent ticks read differently:
/// enough to show the tick step exactly, and never fewer than two. Tiny
/// ranges (1e-8) would otherwise all print as `0.00`.
int valueDecimals(List<double> ticks) {
  if (ticks.length < 2) {
    return 2;
  }
  final step = (ticks[1] - ticks[0]).abs();
  if (!step.isFinite || step == 0) {
    return 2;
  }
  // The smallest number of decimals at which the step is a whole number of
  // units in the last place (within rounding error). Relative, so a tiny step
  // is not mistaken for zero.
  bool whole(double scaled) {
    final nearest = scaled.round();
    return nearest != 0 && (scaled - nearest).abs() <= 1e-6 * nearest;
  }

  var decimals = 0;
  var scaled = step;
  while (decimals < 12 && !whole(scaled)) {
    decimals++;
    scaled *= 10;
  }
  return math.max(2, decimals);
}

/// "Nice" step value-axis ticks (R-AXIS-8: 1/2/2.5/5/10 progression).
List<double> niceValueTicks(double min, double max, {int targetCount = 5}) {
  final lo = min == max ? min - 1 : min;
  final hi = min == max ? max + 1 : max;
  final range = hi - lo;
  final rawStep = range / targetCount;
  final magnitude = math
      .pow(10, (math.log(rawStep) / math.ln10).floor())
      .toDouble();
  final residual = rawStep / magnitude;
  // 1/2/2.5/5/10 progression (R-AXIS-8): round the raw step up to the next.
  double niceResidual;
  if (residual > 5) {
    niceResidual = 10;
  } else if (residual > 2.5) {
    niceResidual = 5;
  } else if (residual > 2) {
    niceResidual = 2.5;
  } else if (residual > 1) {
    niceResidual = 2;
  } else {
    niceResidual = 1;
  }
  final step = niceResidual * magnitude;
  final start = (lo / step).ceil() * step;

  final ticks = <double>[];
  for (var v = start; v <= hi + step * 1e-6; v += step) {
    ticks.add(v);
  }
  return ticks;
}
