// Test plan section 1: data model and data updates (TC-DATA-*).
// See docs/poc_notes.md.
import "dart:math" as math;

import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart" hide testWidgets;
import "package:interactive_chart/interactive_chart.dart";

import "support/chart_harness.dart";
import "support/painted.dart";
import "support/variants.dart";

class _Bar {
  const _Bar(this.time, this.price);
  final DateTime time;
  final double price;
}

void main() {
  group("TC-DATA-01 generic datum types", () {
    testWidgets("record", (tester) async {
      final h = ChartHarness<({DateTime t, double v})>(
        timeOf: (d) => d.t,
        layers: () => [LineLayer(valueOf: (d) => d.v)],
      );
      await tester.pumpWidget(
        h.app([for (var i = 0; i < 30; i++) (t: minuteTime(i), v: i * 1.0)]),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(h.ctx.slotCount, 30);
    });

    testWidgets("plain class", (tester) async {
      final h = ChartHarness<_Bar>(
        timeOf: (d) => d.time,
        layers: () => [LineLayer(valueOf: (d) => d.price)],
      );
      await tester.pumpWidget(
        h.app([for (var i = 0; i < 30; i++) _Bar(minuteTime(i), i * 1.0)]),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(h.ctx.slotCount, 30);
    });

    testWidgets("int", (tester) async {
      final h = ChartHarness<int>(
        timeOf: minuteTime,
        layers: () => [LineLayer(valueOf: (d) => d.toDouble())],
      );
      await tester.pumpWidget(h.app(intSeries(0, 30)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(h.ctx.slotCount, 30);
    });
  });

  group("TC-DATA-02 empty data", () {
    testWidgets("every layer, both axes, no exception", (tester) async {
      final h = ChartHarness<_Bar>(
        timeOf: (d) => d.time,
        layers: () => [
          const GridLayer(),
          HistogramLayer(valueOf: (d) => d.price),
          CandleLayer(
            openOf: (d) => d.price,
            highOf: (d) => d.price,
            lowOf: (d) => d.price,
            closeOf: (d) => d.price,
          ),
          LineLayer(
            valueOf: (d) => d.price,
            latestPointBuilder: (_, _, _) =>
                const SizedBox.square(dimension: 4),
          ),
          CrosshairLayer(valueOf: (d) => d.price, timeOf: (d) => d.time),
        ],
      );
      await tester.pumpWidget(h.app(const []));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(h.controller.visibleRange, (0, 0));
    });

    testWidgets("hover and wheel on an empty chart do nothing", (tester) async {
      final h = ChartHarness<int>(timeOf: minuteTime);
      await tester.pumpWidget(h.app(const []));
      await tester.pumpAndSettle();
      final center = tester.getCenter(find.byType(InteractiveChart<int>));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: center);
      await mouse.moveTo(center + const Offset(10, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(h.controller.visibleRange, (0, 0));
    });

    testWidgets("empty -> populated -> empty", (tester) async {
      final h = ChartHarness<int>(
        timeOf: minuteTime,
        layers: () => [LineLayer(valueOf: (d) => d.toDouble())],
      );
      await tester.pumpWidget(h.app(const []));
      await tester.pumpWidget(h.app(intSeries(0, 50)));
      await tester.pumpAndSettle();
      expect(h.ctx.slotCount, 50);
      await tester.pumpWidget(h.app(const []));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(h.controller.visibleRange, (0, 0));
    });
  });

  testWidgets("TC-DATA-03 single datum renders with a non-degenerate extent", (
    tester,
  ) async {
    final h = ChartHarness<int>(
      timeOf: minuteTime,
      layers: () => [LineLayer(valueOf: (d) => 100)],
    );
    await tester.pumpWidget(h.app([0]));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(h.controller.visibleRange, (0, 1));
    expect(h.ctx.valueMax, greaterThan(h.ctx.valueMin));
    expect(h.ctx.valueMin, lessThan(100));
    expect(h.ctx.valueMax, greaterThan(100));
  });

  group("appending", () {
    testWidgets("TC-DATA-04 mid-history: pan and zoom are untouched", (
      tester,
    ) async {
      final h = ChartHarness<int>(
        timeOf: minuteTime,
        layers: () => [LineLayer(valueOf: (d) => d.toDouble())],
      );
      await tester.pumpWidget(h.app(intSeries(0, 500)));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(InteractiveChart<int>),
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();

      final range = h.controller.visibleRange;
      final offset = h.ctx.scrollOffset;
      final extent = h.ctx.slotExtent;
      expect(offset, greaterThan(0));

      await tester.pumpWidget(h.app(intSeries(0, 501)));
      await tester.pumpAndSettle();

      expect(h.controller.visibleRange, range);
      expect(h.ctx.scrollOffset, offset);
      expect(h.ctx.slotExtent, extent);
    });

    testWidgets("TC-DATA-05 at the right edge: no follow mode (pinned)", (
      tester,
    ) async {
      final h = ChartHarness<int>(
        timeOf: minuteTime,
        anchor: ChartAnchor.right,
        layers: () => [LineLayer(valueOf: (d) => d.toDouble())],
      );
      await tester.pumpWidget(h.app(intSeries(0, 500)));
      await tester.pumpAndSettle();
      final offset = h.ctx.scrollOffset;

      await tester.pumpWidget(h.app(intSeries(0, 503)));
      await tester.pumpAndSettle();

      // The chart does not follow new data (R-SCROLL-5 is not implemented):
      // the offset stays put and the new bars arrive to the right. If follow
      // mode is added, this test should change deliberately.
      expect(h.ctx.scrollOffset, offset);
    });
  });

  group("prepending", () {
    testWidgets("TC-DATA-06 at the left edge", (tester) async {
      final h = ChartHarness<int>(
        timeOf: minuteTime,
        layers: () => [LineLayer(valueOf: (d) => d.toDouble())],
      );
      await tester.pumpWidget(h.app(intSeries(1000, 1200)));
      await tester.pumpAndSettle();
      expect(h.controller.visibleRange.$1, 0);

      await tester.pumpWidget(h.app(intSeries(880, 1200)));
      await tester.pumpAndSettle();
      expect(h.controller.visibleRange.$1, 120);
    });

    testWidgets(
      "TC-DATA-07 mid-history, zoomed in: datum stays under its pixel",
      (tester) async {
        final h = ChartHarness<int>(
          timeOf: minuteTime,
          slotExtent: 24,
          layers: () => [LineLayer(valueOf: (d) => d.toDouble())],
        );
        await tester.pumpWidget(h.app(intSeries(1000, 1500)));
        await tester.pumpAndSettle();
        await tester.drag(
          find.byType(InteractiveChart<int>),
          const Offset(-500, 0),
        );
        await tester.pumpAndSettle();

        final tracked = h.controller.visibleRange.$1 + 5;
        final xBefore = h.ctx.xOf(tracked);

        await tester.pumpWidget(h.app(intSeries(880, 1500)));
        await tester.pumpAndSettle();

        expect(h.ctx.xOf(tracked + 120), closeTo(xBefore, 0.5));
      },
    );

    testWidgets(
      "TC-DATA-08 prepend and append together shift by prepended only",
      (tester) async {
        final h = ChartHarness<int>(
          timeOf: minuteTime,
          layers: () => [LineLayer(valueOf: (d) => d.toDouble())],
        );
        await tester.pumpWidget(h.app(intSeries(1000, 1500)));
        await tester.pumpAndSettle();
        await tester.drag(
          find.byType(InteractiveChart<int>),
          const Offset(-300, 0),
        );
        await tester.pumpAndSettle();
        final offset = h.ctx.scrollOffset;

        // 50 older bars in front, 7 newer bars at the back.
        await tester.pumpWidget(h.app(intSeries(950, 1507)));
        await tester.pumpAndSettle();

        expect(h.ctx.scrollOffset, closeTo(offset + 50 * 8, 0.001));
      },
    );

    testWidgets("TC-DATA-09 unrelated replacement: no shift, no exception", (
      tester,
    ) async {
      final h = ChartHarness<int>(
        timeOf: minuteTime,
        layers: () => [LineLayer(valueOf: (d) => d.toDouble())],
      );
      await tester.pumpWidget(h.app(intSeries(1000, 1200)));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(InteractiveChart<int>),
        const Offset(-100, 0),
      );
      await tester.pumpAndSettle();
      final offset = h.ctx.scrollOffset;

      // Entirely later times, longer list: old first timestamp not present.
      await tester.pumpWidget(h.app(intSeries(5000, 5300)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(h.ctx.scrollOffset, offset);

      // Entirely earlier times, longer list.
      await tester.pumpWidget(h.app(intSeries(0, 400)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(h.ctx.scrollOffset, offset);
    });

    testWidgets("TC-DATA-11 duplicate timestamps at the old first datum", (
      tester,
    ) async {
      final h = ChartHarness<_Bar>(
        timeOf: (d) => d.time,
        layers: () => [LineLayer(valueOf: (d) => d.price)],
      );
      // Two bars share the first timestamp (minute 100).
      final old = [
        _Bar(minuteTime(100), 1),
        _Bar(minuteTime(100), 2),
        for (var i = 101; i < 400; i++) _Bar(minuteTime(i), i * 1.0),
      ];
      final older = [
        for (var i = 90; i < 100; i++) _Bar(minuteTime(i), i * 1.0),
      ];

      await tester.pumpWidget(h.app(old));
      await tester.pumpAndSettle();
      expect(h.controller.visibleRange.$1, 0);

      await tester.pumpWidget(h.app([...older, ...old]));
      await tester.pumpAndSettle();

      // The binary search lands on the first of the duplicates, so the shift
      // is exactly the 10 prepended bars.
      expect(h.controller.visibleRange.$1, 10);
    });
  });

  testWidgets("TC-DATA-10 shrinking data re-clamps scroll and range", (
    tester,
  ) async {
    final h = ChartHarness<int>(
      timeOf: minuteTime,
      anchor: ChartAnchor.right,
      layers: () => [
        LineLayer(valueOf: (d) => d.toDouble()),
        CandleLayer(
          openOf: (d) => d.toDouble(),
          highOf: (d) => d + 1.0,
          lowOf: (d) => d - 1.0,
          closeOf: (d) => d.toDouble(),
        ),
        HistogramLayer(valueOf: (d) => d.toDouble()),
      ],
    );
    await tester.pumpWidget(h.app(intSeries(0, 500)));
    await tester.pumpAndSettle();
    expect(h.ctx.scrollOffset, greaterThan(1000));

    await tester.pumpWidget(h.app(intSeries(0, 50)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(h.ctx.scrollOffset, lessThanOrEqualTo(h.ctx.maxScrollOffset));
    final (start, end) = h.controller.visibleRange;
    expect(start, inInclusiveRange(0, 50));
    expect(end, inInclusiveRange(start, 50));
  });

  group("TC-DATA-12 unsorted data", () {
    // Undefined behaviour, but it must not crash. The data must be sorted
    // oldest to newest (documented on InteractiveChart.data).
    testWidgets("renders and survives updates without throwing", (
      tester,
    ) async {
      final shuffled = intSeries(0, 200)..shuffle(math.Random(1));
      final h = ChartHarness<int>(
        timeOf: minuteTime,
        layers: () => [LineLayer(valueOf: (d) => d.toDouble())],
      );
      await tester.pumpWidget(h.app(shuffled));
      await tester.pumpAndSettle();
      await tester.pumpWidget(h.app([...intSeries(300, 330), ...shuffled]));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group("in-place updates", () {
    testWidgets("TC-DATA-13 last datum changes, same length", (tester) async {
      final seen = <double>[];
      var values = [for (var i = 0; i < 100; i++) 10.0 + i];
      final h = ChartHarness<int>(
        timeOf: minuteTime,
        layers: () => [
          LineLayer<int>(
            valueOf: (i) => values[i],
            latestPointBuilder: (_, _, i) {
              seen.add(values[i]);
              return const SizedBox.square(dimension: 4);
            },
          ),
        ],
      );
      await tester.pumpWidget(h.app(intSeries(0, 100)));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(InteractiveChart<int>),
        const Offset(200, 0),
      );
      await tester.pumpAndSettle();
      final offset = h.ctx.scrollOffset;
      final extent = h.ctx.slotExtent;
      final range = h.controller.visibleRange;

      // The caller mutates the series and hands the chart a fresh list.
      values = [...values]..[99] = 555;
      await tester.pumpWidget(h.app(intSeries(0, 100)));
      await tester.pumpAndSettle();

      expect(h.ctx.scrollOffset, offset);
      expect(h.ctx.slotExtent, extent);
      expect(h.controller.visibleRange, range);

      // Scroll back to the newest bar: it must show the new value.
      h.controller.jumpToLatest();
      await tester.pumpAndSettle();
      expect(seen.last, 555);
      expect(h.ctx.valueMax, greaterThanOrEqualTo(555));
    });
  });

  group("TC-DATA-14 NaN and infinity are gaps", () {
    for (final bad in [double.nan, double.infinity, double.negativeInfinity]) {
      testWidgets("line breaks at $bad and extent ignores it", (tester) async {
        List<double> values({double? at4}) => [
          for (var i = 0; i < 10; i++)
            if (i == 4 && at4 != null) at4 else 50.0 + i,
        ];
        Future<(int, ChartHarness<int>)> pump(List<double> v) async {
          final h = ChartHarness<int>(
            timeOf: minuteTime,
            layers: () => [LineLayer<int>(valueOf: (i) => v[i])],
          );
          await tester.pumpWidget(h.app(intSeries(0, 10)));
          await tester.pumpAndSettle();
          return (paintedLineSegments(tester), h);
        }

        final (clean, _) = await pump(values());
        final (gapped, h) = await pump(values(at4: bad));
        expect(tester.takeException(), isNull);
        // Removing one interior point removes the two segments touching it.
        expect(clean - gapped, 2);
        expect(h.ctx.valueMin.isFinite, isTrue);
        expect(h.ctx.valueMax.isFinite, isTrue);
      });
    }

    for (final field in ["open", "high", "low", "close"]) {
      testWidgets("candle with NaN $field is skipped", (tester) async {
        final data = [
          for (var i = 0; i < 20; i++)
            (o: 10.0 + i, h: 12.0 + i, l: 9.0 + i, c: 11.0 + i),
        ];
        final bad = data[7];
        data[7] = (
          o: field == "open" ? double.nan : bad.o,
          h: field == "high" ? double.nan : bad.h,
          l: field == "low" ? double.nan : bad.l,
          c: field == "close" ? double.nan : bad.c,
        );
        final h = ChartHarness<int>(
          timeOf: minuteTime,
          layers: () => [
            CandleLayer<int>(
              openOf: (i) => data[i].o,
              highOf: (i) => data[i].h,
              lowOf: (i) => data[i].l,
              closeOf: (i) => data[i].c,
            ),
          ],
        );
        await tester.pumpWidget(h.app(intSeries(0, 20)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(h.ctx.valueMin.isFinite, isTrue);
        expect(h.ctx.valueMax.isFinite, isTrue);
      });
    }

    testWidgets("histogram with a NaN bar still draws the others", (
      tester,
    ) async {
      final h = ChartHarness<int>(
        timeOf: minuteTime,
        layers: () => [
          HistogramLayer<int>(valueOf: (i) => i == 3 ? double.nan : 5.0 + i),
        ],
      );
      await tester.pumpWidget(h.app(intSeries(0, 10)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group("TC-DATA-15 prepend before the initial anchor is applied", () {
    for (final anchor in ChartAnchor.values) {
      testWidgets("anchor ${anchor.name} wins, no double shift", (
        tester,
      ) async {
        final h = ChartHarness<int>(
          timeOf: minuteTime,
          anchor: anchor,
          layers: () => [LineLayer(valueOf: (d) => d.toDouble())],
        );
        // Zero-sized viewport: the initial anchor cannot be applied yet.
        await tester.pumpWidget(
          h.app(intSeries(1000, 1200), width: 0, height: 0),
        );
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          h.app(intSeries(880, 1200), width: 0, height: 0),
        );
        await tester.pumpAndSettle();

        // Now give it a real size.
        await tester.pumpWidget(h.app(intSeries(880, 1200)));
        await tester.pumpAndSettle();

        final (start, end) = h.controller.visibleRange;
        if (anchor == ChartAnchor.left) {
          expect(start, 0);
        } else {
          expect(end, 320); // whole series visible from the right edge
          // The anchor is applied before the value-axis gutter finishes
          // growing, so the offset can sit up to a gutter-growth short of
          // the final maximum; the newest bar must still be in view.
          expect(h.ctx.scrollOffset, greaterThan(h.ctx.maxScrollOffset - 50));
        }
      });
    }
  });
}
