// Test plan sections 6 and 7: the time-axis tick hierarchy (TC-TIME-*) and
// interval inference / projected slots (TC-PROJ-*). See docs/poc_notes.md.
// TC-PROJ-06 (weekend skipping) and TC-PROJ-09 (monthly) are also covered in
// test/known_gaps_test.dart.
import "dart:math" as math;

import "package:flutter/gestures.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:interactive_chart/interactive_chart.dart";
import "package:interactive_chart/src/ticks.dart";

import "support/chart_harness.dart";

/// Daily bars with no gaps, from 2022-01-01.
DateTime _day(int i) => DateTime(2022).add(Duration(days: i));

List<DateTime> _days(int n) => [for (var i = 0; i < n; i++) _day(i)];

String _signature(List<TickMark> marks) =>
    marks.map((m) => "${m.index}:${m.weight}").join(",");

void main() {
  group("TC-TIME-01 timeWeight picks the coarsest boundary crossed", () {
    final cases = <(String, DateTime, DateTime, int)>[
      ("year", DateTime(2023, 12, 31, 23, 59, 59), DateTime(2024), 70),
      ("month", DateTime(2024, 1, 31), DateTime(2024, 2), 60),
      ("day", DateTime(2024, 3, 14, 23), DateTime(2024, 3, 15), 50),
      ("hour", DateTime(2024, 3, 15, 9, 59), DateTime(2024, 3, 15, 10), 30),
      (
        "minute",
        DateTime(2024, 3, 15, 10, 4, 59),
        DateTime(2024, 3, 15, 10, 5),
        20,
      ),
      (
        "second",
        DateTime(2024, 3, 15, 10, 5, 9),
        DateTime(2024, 3, 15, 10, 5, 10),
        10,
      ),
    ];
    for (final (name, a, b, weight) in cases) {
      test(name, () => expect(timeWeight(a, b), weight));
    }

    test("a year boundary beats the smaller boundaries it also crosses", () {
      // Dec 31 23:59 -> Jan 1 00:00 crosses year, month, day, hour, minute.
      expect(timeWeight(DateTime(2023, 12, 31, 23, 59), DateTime(2024)), 70);
    });

    test("the same month in a different year is still a year change", () {
      expect(timeWeight(DateTime(2023, 5, 10), DateTime(2024, 5, 10)), 70);
    });

    test("the same day-of-month in a different month is a month change", () {
      expect(timeWeight(DateTime(2024, 4, 10), DateTime(2024, 5, 10)), 60);
    });

    test("identical times have the lowest weight", () {
      final t = DateTime(2024, 5, 10, 8, 30, 15);
      expect(timeWeight(t, t), 10);
    });
  });

  group("TC-TIME-02 the first datum opens with maximum context", () {
    test("always weight 70, whatever its time", () {
      for (final first in [
        DateTime(2024, 6, 15, 13, 45, 30),
        DateTime(2024),
        DateTime(2024, 12, 31, 23, 59, 59),
      ]) {
        final times = [
          for (var i = 0; i < 50; i++) first.add(Duration(seconds: 10 * i)),
        ];
        final marks = buildTickMarks(
          times: times,
          realCount: 50,
          slotExtent: 8,
        );
        expect(marks.first.index, 0);
        expect(marks.first.weight, 70);
      }
    });

    test("a single datum yields a single mark", () {
      final marks = buildTickMarks(
        times: [DateTime(2024)],
        realCount: 1,
        slotExtent: 8,
      );
      expect(marks.length, 1);
      expect(marks.single.index, 0);
    });

    test("no data yields no marks", () {
      expect(
        buildTickMarks(times: const [], realCount: 0, slotExtent: 8),
        isEmpty,
      );
    });
  });

  group("TC-TIME-03 greedy selection", () {
    for (final extent in [1.0, 2.0, 5.0, 8.0, 20.0, 64.0]) {
      test("slot extent $extent", () {
        final times = _days(900);
        final marks = buildTickMarks(
          times: times,
          realCount: 900,
          slotExtent: extent,
        );
        final gap = (56 / extent).ceil().clamp(1, 1 << 30);
        final weights = [
          70,
          for (var i = 1; i < times.length; i++)
            timeWeight(times[i - 1], times[i]),
        ];

        // Ascending, unique indices.
        for (var i = 1; i < marks.length; i++) {
          expect(marks[i].index, greaterThan(marks[i - 1].index));
          // No two accepted marks closer than the minimum spacing.
          expect(
            marks[i].index - marks[i - 1].index,
            greaterThanOrEqualTo(gap),
          );
        }

        // Higher weights win: every rejected index has an accepted neighbour
        // within the gap that is at least as heavy.
        final accepted = {for (final m in marks) m.index};
        for (var i = 0; i < times.length; i += 1) {
          if (accepted.contains(i)) {
            continue;
          }
          final blocker = marks.any(
            (m) => (m.index - i).abs() < gap && m.weight >= weights[i],
          );
          expect(
            blocker,
            isTrue,
            reason: "index $i (weight ${weights[i]}) was dropped",
          );
        }
      });
    }

    test("the heaviest boundary in the data is always labelled", () {
      final times = _days(2000);
      for (final extent in [1.0, 3.0, 8.0, 30.0]) {
        final marks = buildTickMarks(
          times: times,
          realCount: 2000,
          slotExtent: extent,
        );
        expect(marks.map((m) => m.weight).reduce((a, b) => a > b ? a : b), 70);
      }
    });

    test("is deterministic", () {
      final times = _days(700);
      final a = buildTickMarks(times: times, realCount: 700, slotExtent: 3);
      final b = buildTickMarks(times: times, realCount: 700, slotExtent: 3);
      expect(_signature(a), _signature(b));
    });

    test(
      "equal weights: the earlier slot wins, so appending keeps the marks",
      () {
        // Marks on the existing data must not flip when more data is appended.
        final all = _days(1200);
        for (final extent in [2.0, 8.0]) {
          final before = buildTickMarks(
            times: all.sublist(0, 1000),
            realCount: 1000,
            slotExtent: extent,
          );
          final after = buildTickMarks(
            times: all,
            realCount: 1200,
            slotExtent: extent,
          );
          final gap = (56 / extent).ceil();
          final stable = before.where((m) => m.index < 1000 - gap).toList();
          final kept = after.where((m) => m.index < 1000 - gap).toList();
          expect(
            _signature(kept),
            _signature(stable),
            reason: "extent $extent",
          );
        }
      },
    );
  });

  group("TC-TIME-06 labels follow the weight, not the zoom", () {
    final t = DateTime(2024, 3, 5, 9, 7, 4);
    test("year", () => expect(defaultTimeLabel(t, 70), "2024"));
    test("month", () => expect(defaultTimeLabel(t, 60), "Mar"));
    test("day", () => expect(defaultTimeLabel(t, 50), "5"));
    test("hour", () => expect(defaultTimeLabel(t, 30), "09:07"));
    test("minute", () => expect(defaultTimeLabel(t, 20), "09:07"));
    test("sub-minute", () => expect(defaultTimeLabel(t, 10), "09:07:04"));

    test("all twelve month names", () {
      const names = [
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
      for (var m = 1; m <= 12; m++) {
        expect(defaultTimeLabel(DateTime(2024, m, 15), 60), names[m - 1]);
      }
    });

    test("midnight and noon pad correctly", () {
      expect(defaultTimeLabel(DateTime(2024, 1, 1, 0, 0, 0), 10), "00:00:00");
      expect(
        defaultTimeLabel(DateTime(2024, 1, 1, 23, 59, 59), 10),
        "23:59:59",
      );
    });
  });

  group("TC-TIME-07 calendar edge cases", () {
    test("month ends", () {
      expect(timeWeight(DateTime(2024, 1, 30), DateTime(2024, 1, 31)), 50);
      expect(timeWeight(DateTime(2024, 1, 31), DateTime(2024, 2, 1)), 60);
      expect(timeWeight(DateTime(2024, 4, 30), DateTime(2024, 5, 1)), 60);
    });

    test("year end", () {
      expect(timeWeight(DateTime(2024, 12, 30), DateTime(2024, 12, 31)), 50);
      expect(timeWeight(DateTime(2024, 12, 31), DateTime(2025)), 70);
    });

    test("leap day", () {
      expect(timeWeight(DateTime(2024, 2, 28), DateTime(2024, 2, 29)), 50);
      expect(timeWeight(DateTime(2024, 2, 29), DateTime(2024, 3, 1)), 60);
      // The same dates in a non-leap year skip straight to March.
      expect(timeWeight(DateTime(2023, 2, 28), DateTime(2023, 3, 1)), 60);
    });

    test("weights depend on calendar fields, not elapsed time (DST safe)", () {
      // Whatever the machine's zone, hours that change are weight 30 and
      // repeated wall-clock readings (a fall-back hour) are not boundaries.
      expect(
        timeWeight(DateTime(2024, 3, 10, 1, 59), DateTime(2024, 3, 10, 3)),
        30,
      );
      expect(
        timeWeight(DateTime(2024, 11, 3, 1, 30), DateTime(2024, 11, 3, 1, 30)),
        10,
      );
      // UTC has no DST at all; the midnight boundary is exact.
      expect(
        timeWeight(DateTime.utc(2024, 3, 9, 23, 59), DateTime.utc(2024, 3, 10)),
        50,
      );
    });

    test(
      "a full leap year of daily bars has no missing or duplicate boundary",
      () {
        final times = [
          for (var i = 0; i < 366; i++) DateTime(2024).add(Duration(days: i)),
        ];
        final weights = [
          70,
          for (var i = 1; i < times.length; i++)
            timeWeight(times[i - 1], times[i]),
        ];
        expect(weights.where((w) => w == 70).length, 1); // only the first bar
        expect(weights.where((w) => w == 60).length, 11); // Feb..Dec
        expect(weights.where((w) => w == 50).length, 366 - 12);
      },
    );

    test("the selected marks on a leap year are unique and ascending", () {
      final marks = buildTickMarks(
        times: [
          for (var i = 0; i < 366; i++) DateTime(2024).add(Duration(days: i)),
        ],
        realCount: 366,
        slotExtent: 4,
      );
      final indices = marks.map((m) => m.index).toList();
      expect(indices.toSet().length, indices.length);
      expect([...indices]..sort(), indices);
      expect(marks.map((m) => m.time).toSet().length, marks.length);
    });
  });

  group("widget behaviour", () {
    ChartHarness<int> chart({double slotExtent = 8}) => ChartHarness<int>(
      timeOf: _day,
      slotExtent: slotExtent,
      layers: () => [LineLayer<int>(valueOf: (i) => 10.0 + i % 5)],
    );

    testWidgets("TC-TIME-04 panning at a fixed zoom keeps the mark set", (
      tester,
    ) async {
      final h = chart();
      await tester.pumpWidget(h.app(intSeries(0, 1000)));
      await tester.pumpAndSettle();
      final before = _signature(h.ctx.timeTicks);
      expect(before, isNotEmpty);

      for (final dx in [-120.0, -333.0, 90.0, -700.0]) {
        await tester.drag(
          find.byType(InteractiveChart<int>),
          Offset(dx, 0),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        expect(
          _signature(h.ctx.timeTicks),
          before,
          reason: "after dragging $dx",
        );
      }
    });

    testWidgets(
      "TC-TIME-05 a sustained zoom changes the set only per bucket, never back",
      (tester) async {
        final h = chart();
        await tester.pumpWidget(h.app(intSeries(0, 1000)));
        await tester.pumpAndSettle();
        final at = tester.getCenter(find.byType(InteractiveChart<int>));
        final pointer = TestPointer(1, PointerDeviceKind.mouse)..hover(at);

        double bucket(double e) => (e.log2 * 6).round() / 6;
        final seen = <String>[];
        var previousBucket = bucket(h.ctx.slotExtent);
        var previousSignature = _signature(h.ctx.timeTicks);
        seen.add(previousSignature);

        for (var i = 0; i < 80; i++) {
          await tester.sendEventToBinding(pointer.scroll(const Offset(0, -12)));
          await tester.pump();
          final b = bucket(h.ctx.slotExtent);
          final sig = _signature(h.ctx.timeTicks);
          if (b == previousBucket) {
            expect(
              sig,
              previousSignature,
              reason: "set changed inside bucket $b (step $i)",
            );
          } else if (sig != previousSignature) {
            // No flicker: a set we already left is not revisited while zooming
            // in one direction. Adjacent buckets may give the same set (the
            // minimum index gap is a rounded-up integer), which is fine.
            expect(
              seen.contains(sig),
              isFalse,
              reason: "set returned at step $i",
            );
            seen.add(sig);
          }
          previousBucket = b;
          previousSignature = sig;
        }
        expect(seen.length, greaterThan(2));
      },
    );

    testWidgets(
      "TC-TIME-08 marks cover projected slots and survive overscroll",
      (tester) async {
        final h = chart();
        await tester.pumpWidget(h.app(intSeries(0, 1000)));
        await tester.pumpAndSettle();

        expect(h.ctx.timeTicks.any((m) => m.projected), isTrue);
        expect(h.ctx.timeTicks.any((m) => !m.projected), isTrue);
        final before = _signature(h.ctx.timeTicks);

        h.ctx.jumpTo(h.ctx.maxScrollOffset);
        await tester.pumpAndSettle();
        expect(_signature(h.ctx.timeTicks), before);
        // Fully in the void, the visible range still holds only real slots.
        expect(h.ctx.visibleEnd, lessThanOrEqualTo(1000));
      },
    );

    for (final extent in [1.0, 2.0, 4.0, 8.0, 16.0, 32.0, 64.0]) {
      testWidgets("TC-TIME-09 labels never overlap at slot extent $extent", (
        tester,
      ) async {
        final h = chart(slotExtent: extent);
        await tester.pumpWidget(h.app(intSeries(0, 1500)));
        await tester.pumpAndSettle();
        await tester.drag(
          find.byType(InteractiveChart<int>),
          const Offset(-400, 0),
        );
        await tester.pumpAndSettle();

        final axisLabels = find.descendant(
          of: find.byType(InteractiveChart<int>),
          matching: find.byWidgetPredicate(
            (w) => w is Text && !RegExp(r"^\d+\.\d\d$").hasMatch(w.data ?? ""),
          ),
        );
        final rects = [
          for (var i = 0; i < tester.widgetList(axisLabels).length; i++)
            tester.getRect(axisLabels.at(i)),
        ];
        for (var i = 0; i < rects.length; i++) {
          for (var j = i + 1; j < rects.length; j++) {
            expect(
              rects[i].overlaps(rects[j]),
              isFalse,
              reason: "labels $i and $j overlap at extent $extent",
            );
          }
        }
      });
    }
  });

  group("TC-PROJ interval inference", () {
    /// Weekday bars (Mon-Fri) from Monday 2024-01-01.
    List<DateTime> tradingDays(int n) {
      final out = <DateTime>[];
      var t = DateTime(2024);
      while (out.length < n) {
        if (t.weekday <= DateTime.friday) {
          out.add(t);
        }
        t = t.add(const Duration(days: 1));
      }
      return out;
    }

    test("TC-PROJ-01 daily trading data is a day, not the mean", () {
      expect(inferModalIntervalSeconds(tradingDays(60)), 86400);
    });

    test("TC-PROJ-02 minute data with missing bars", () {
      final times = <DateTime>[];
      for (var i = 0; i < 200; i++) {
        if (i % 17 == 5 || i % 31 == 0) {
          continue; // missing bars
        }
        times.add(DateTime(2024).add(Duration(minutes: i)));
      }
      expect(inferModalIntervalSeconds(times), 60);
    });

    for (final seconds in [10, 30]) {
      test("TC-PROJ-03 $seconds-second data", () {
        final times = [
          for (var i = 0; i < 100; i++)
            DateTime(2024).add(Duration(seconds: seconds * i)),
        ];
        expect(inferModalIntervalSeconds(times), seconds);
      });
    }

    test("TC-PROJ-04 fewer than two points falls back to a day", () {
      expect(inferModalIntervalSeconds(const []), 86400);
      expect(inferModalIntervalSeconds([DateTime(2024)]), 86400);
    });

    test("TC-PROJ-05 only the trailing sample is used", () {
      final times = <DateTime>[];
      var t = DateTime(2024);
      for (var i = 0; i < 150; i++) {
        times.add(t);
        t = t.add(const Duration(minutes: 1));
      }
      for (var i = 0; i < 101; i++) {
        times.add(t);
        t = t.add(const Duration(seconds: 30));
      }
      // 150 one-minute deltas precede 100 half-minute ones.
      expect(inferModalIntervalSeconds(times, sampleSize: 100), 30);
      expect(inferModalIntervalSeconds(times, sampleSize: 1000), 60);
    });

    test("ties resolve deterministically", () {
      final times = [
        DateTime(2024),
        DateTime(2024).add(const Duration(minutes: 1)),
        DateTime(2024).add(const Duration(minutes: 3)),
      ];
      final first = inferModalIntervalSeconds(times);
      expect(inferModalIntervalSeconds(times), first);
    });
  });

  group("TC-PROJ projection", () {
    test("TC-PROJ-06 daily data steps by a day and skips weekends", () {
      // Thursday 2024-01-04 and Friday 2024-01-05 are the last two bars.
      final real = [
        for (final d in [1, 2, 3, 4, 5]) DateTime(2024, 1, d),
      ];
      expect(projectTimes(real, 4), [
        DateTime(2024, 1, 8),
        DateTime(2024, 1, 9),
        DateTime(2024, 1, 10),
        DateTime(2024, 1, 11),
      ]);
    });

    test("TC-PROJ-06b weekend skipping can be turned off", () {
      final real = [
        for (final d in [1, 2, 3, 4, 5]) DateTime(2024, 1, d),
      ];
      expect(projectTimes(real, 2, skipWeekends: false), [
        DateTime(2024, 1, 6),
        DateTime(2024, 1, 7),
      ]);
    });

    test("TC-PROJ-07 intraday data steps by the interval across a weekend", () {
      final real = [
        for (var i = 0; i < 30; i++)
          DateTime(2024, 1, 5, 23, 40).add(Duration(minutes: i - 29)),
      ];
      // Last bar is Friday 23:40; the projection runs straight into Saturday.
      final projected = projectTimes(real, 25);
      expect(projected.first, DateTime(2024, 1, 5, 23, 41));
      expect(projected.last, DateTime(2024, 1, 6, 0, 5));
      for (var i = 1; i < projected.length; i++) {
        expect(
          projected[i].difference(projected[i - 1]),
          const Duration(minutes: 1),
        );
      }
    });

    test("sub-minute intervals project at their own cadence", () {
      final real = [
        for (var i = 0; i < 20; i++)
          DateTime(2024).add(Duration(seconds: 10 * i)),
      ];
      final projected = projectTimes(real, 3);
      expect(projected[0], real.last.add(const Duration(seconds: 10)));
      expect(projected[2], real.last.add(const Duration(seconds: 30)));
    });

    test("count of zero or less gives nothing", () {
      final real = [for (var i = 0; i < 5; i++) _day(i)];
      expect(projectTimes(real, 0), isEmpty);
      expect(projectTimes(real, -3), isEmpty);
    });

    test("TC-PROJ-08 empty data projects daily steps from now", () {
      final before = DateTime.now();
      final projected = projectTimes(const [], 3);
      final after = DateTime.now();
      expect(projected.length, 3);
      expect(projected[0].isAfter(before), isTrue);
      expect(
        projected[0].isBefore(after.add(const Duration(days: 1, seconds: 1))),
        isTrue,
      );
      for (var i = 1; i < 3; i++) {
        expect(
          projected[i].difference(projected[i - 1]),
          const Duration(days: 1),
        );
      }
    });

    test("projectTime returns the Nth slot", () {
      final real = [
        for (var i = 0; i < 10; i++) DateTime(2024).add(Duration(minutes: i)),
      ];
      expect(projectTime(real, 5), real.last.add(const Duration(minutes: 5)));
    });

    testWidgets(
      "TC-PROJ-10 appending a datum that matches the projection keeps the marks",
      (tester) async {
        final h = ChartHarness<int>(
          timeOf: minuteTime,
          layers: () => [LineLayer<int>(valueOf: (i) => 10.0 + i % 5)],
        );
        await tester.pumpWidget(h.app(intSeries(0, 1000)));
        await tester.pumpAndSettle();
        final before = List.of(h.ctx.timeTicks);
        // Bar 1000 is exactly the first projected slot.
        await tester.pumpWidget(h.app(intSeries(0, 1001)));
        await tester.pumpAndSettle();
        final after = h.ctx.timeTicks;

        // R-TIME-30: the mark set is identical (index, time, weight); only a
        // mark sitting on bar 1000 changes from projected to real.
        expect(_signature(after), _signature(before));
        for (var i = 0; i < after.length; i++) {
          expect(after[i].time, before[i].time);
        }
      },
    );
  });
}

extension on double {
  double get log2 => math.log(this) / math.ln2;
}
