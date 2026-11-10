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
  "Jan", "Feb", "Mar", "Apr", "May", "Jun",
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
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
  final order = List<int>.generate(n, (i) => i)
    ..sort((a, b) => weights[b].compareTo(weights[a]));

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
      TickMark(index: i, time: times[i], weight: weights[i], projected: i >= realCount),
  ];
}

/// Modal-delta interval inference (R-TIME-20) over the trailing [sampleSize]
/// deltas between real timestamps.
int inferModalIntervalMinutes(List<DateTime> real, {int sampleSize = 100}) {
  if (real.length < 2) {
    return 24 * 60;
  }
  final n = math.min(sampleSize, real.length - 1);
  final counts = <int, int>{};
  for (var i = real.length - n; i < real.length; i++) {
    final minutes = real[i].difference(real[i - 1]).inMinutes;
    counts[minutes] = (counts[minutes] ?? 0) + 1;
  }
  return (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
}

/// Projects [count] time points past the end of [real], stepped
/// calendar-day-aware with weekend skipping for day-or-coarser series
/// (R-TIME-21/22, simplified: exact for minute/hour/day cadences, not
/// calendar-month arithmetic). Computes the modal interval once, so this is
/// O(sampleSize + count) rather than O(count * sampleSize).
List<DateTime> projectTimes(List<DateTime> real, int count, {int sampleSize = 100, bool skipWeekends = true}) {
  if (count <= 0) {
    return const [];
  }
  if (real.isEmpty) {
    final now = DateTime.now();
    return [for (var i = 0; i < count; i++) now.add(Duration(days: i + 1))];
  }

  final modalMinutes = inferModalIntervalMinutes(real, sampleSize: sampleSize);
  final isDailyPlus = modalMinutes >= 24 * 60;

  var t = real.last;
  final result = <DateTime>[];
  for (var i = 0; i < count; i++) {
    t = t.add(Duration(minutes: modalMinutes));
    if (isDailyPlus && skipWeekends) {
      while (t.weekday == DateTime.saturday || t.weekday == DateTime.sunday) {
        t = t.add(const Duration(days: 1));
      }
    }
    result.add(t);
  }
  return result;
}

/// Single-slot convenience matching the `DateTime Function(int)` projector
/// shape from R-TIME-19's public API sketch.
DateTime projectTime(List<DateTime> real, int slotsAfterLast, {int sampleSize = 100, bool skipWeekends = true}) =>
    projectTimes(real, slotsAfterLast, sampleSize: sampleSize, skipWeekends: skipWeekends).last;

/// "Nice" step value-axis ticks (R-AXIS-8: 1/2/2.5/5/10 progression).
List<double> niceValueTicks(double min, double max, {int targetCount = 5}) {
  final lo = min == max ? min - 1 : min;
  final hi = min == max ? max + 1 : max;
  final range = hi - lo;
  final rawStep = range / targetCount;
  final magnitude = math.pow(10, (math.log(rawStep) / math.ln10).floor()).toDouble();
  final residual = rawStep / magnitude;
  double niceResidual;
  if (residual > 5) {
    niceResidual = 10;
  } else if (residual > 2) {
    niceResidual = 5;
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
