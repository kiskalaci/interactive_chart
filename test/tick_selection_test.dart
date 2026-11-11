// buildTickMarks selects marks in near-linear time; it must pick exactly the
// marks the original pairwise greedy selection picked (R-TIME-7).
import "dart:math" as math;

import "package:flutter_test/flutter_test.dart";
import "package:interactive_chart/interactive_chart.dart";
import "package:interactive_chart/src/time_axis/time_ticks.dart";

/// The original selection: heaviest first (ties to the earlier slot), each
/// candidate checked against every accepted mark.
List<int> _reference(List<DateTime> times, double slotExtent) {
  final n = times.length;
  final weights = List<TickMarkWeight>.filled(n, TickMarkWeight.second);
  weights[0] = TickMarkWeight.year;
  for (var i = 1; i < n; i++) {
    weights[i] = timeWeight(times[i - 1], times[i]);
  }
  final gap = math.max(1, (56 / slotExtent).ceil());
  final order = List<int>.generate(n, (i) => i)
    ..sort((a, b) {
      final byWeight = weights[b].compareTo(weights[a]);
      return byWeight != 0 ? byWeight : a.compareTo(b);
    });
  final accepted = <int>[];
  for (final i in order) {
    if (accepted.every((a) => (a - i).abs() >= gap)) {
      accepted.add(i);
    }
  }
  return accepted..sort();
}

void main() {
  final random = math.Random(42);

  List<DateTime> series(int n, Duration step, {bool jitter = false}) {
    var t = DateTime(2023, 12, 28, 9, 30);
    return [
      for (var i = 0; i < n; i++)
        t = t.add(jitter ? step * (1 + random.nextInt(4)) : step),
    ];
  }

  for (final (name, times) in [
    ("1-minute", series(3000, const Duration(minutes: 1))),
    ("10-second", series(3000, const Duration(seconds: 10))),
    ("hourly", series(2000, const Duration(hours: 1))),
    ("daily", series(1500, const Duration(days: 1))),
    ("irregular", series(2500, const Duration(minutes: 7), jitter: true)),
    ("tiny", series(3, const Duration(minutes: 1))),
    ("single", series(1, const Duration(minutes: 1))),
  ]) {
    for (final slotExtent in [0.05, 0.4, 1.0, 3.0, 8.0, 21.0, 64.0]) {
      test("$name series at $slotExtent px per slot", () {
        final marks = buildTickMarks(
          times: times,
          realCount: times.length - 2,
          slotExtent: slotExtent,
        );
        expect([for (final m in marks) m.index], _reference(times, slotExtent));
        for (final m in marks) {
          expect(m.time, times[m.index]);
          expect(m.projected, m.index >= times.length - 2);
        }
      });
    }
  }

  test("a large series is selected quickly", () {
    final times = series(300000, const Duration(minutes: 1));
    final watch = Stopwatch()..start();
    final marks = buildTickMarks(
      times: times,
      realCount: times.length,
      slotExtent: 8,
    );
    watch.stop();
    expect(marks, isNotEmpty);
    // About 20 ms on a laptop; the pairwise version took about 10 s.
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
  });
}
