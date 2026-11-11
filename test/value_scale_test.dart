// Test plan section 3: value scale and autoscale (TC-SCALE-*).
// TC-SCALE-07 and TC-SCALE-11 live in test/known_gaps_test.dart.
// See docs/poc_notes.md.
import "dart:math" as math;

import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart" hide testWidgets;
import "package:interactive_chart/interactive_chart.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/value_axis/value_ticks.dart";

import "support/chart_harness.dart";
import "support/variants.dart";

/// Counts how often autoscale asks it for an extent.
class _CountingLayer extends ChartLayer<int> {
  int calls = 0;

  @override
  ValueRange? extentFor(List<int> data, int start, int end) {
    calls++;
    return (start * 1.0, (end - 1) * 1.0);
  }

  @override
  Widget build(Size size, InteractiveChartContext ctx, List<int> data) =>
      const SizedBox.shrink();
}

/// A chart with no axes (so no gutter changes the viewport after layout).
ChartHarness<int> _bare(List<ChartLayer<int>> Function() layers) =>
    ChartHarness<int>(
      timeOf: minuteTime,
      valueAxis: null,
      timeAxis: null,
      layers: layers,
    );

/// Extent the spec asks for: min/max of [values] plus 5 % padding each side.
(double, double) _padded(Iterable<double> values) {
  final lo = values.reduce(math.min);
  final hi = values.reduce(math.max);
  final pad = (hi - lo) * 0.05;
  return (lo - pad, hi + pad);
}

void main() {
  group("TC-SCALE-01 autoscale uses the visible range only", () {
    testWidgets("single layer, at the start and after panning", (tester) async {
      final values = [for (var i = 0; i < 500; i++) 100.0 + (i % 37) * 3 + i];
      final h = _bare(() => [LineLayer<int>(valueOf: (i) => values[i])]);
      await tester.pumpWidget(h.app(intSeries(0, 500)));
      await tester.pumpAndSettle();

      void check() {
        final (s, e) = h.controller.visibleRange;
        final (lo, hi) = _padded(values.sublist(s, e));
        expect(h.ctx.valueMin, closeTo(lo, 1e-9));
        expect(h.ctx.valueMax, closeTo(hi, 1e-9));
      }

      check();
      final before = h.ctx.valueMax;
      await tester.drag(
        find.byType(InteractiveChart<int>),
        const Offset(-1500, 0),
      );
      await tester.pumpAndSettle();
      check();
      expect(h.ctx.valueMax, isNot(before));
    });

    testWidgets("several layers combine into one extent", (tester) async {
      final h = _bare(
        () => [
          LineLayer<int>(valueOf: (i) => 100.0 + i % 10),
          LineLayer<int>(valueOf: (i) => 300.0 - i % 7),
          CandleLayer<int>(
            openOf: (i) => 150,
            highOf: (i) => 400,
            lowOf: (i) => 20,
            closeOf: (i) => 150,
          ),
        ],
      );
      await tester.pumpWidget(h.app(intSeries(0, 50)));
      await tester.pumpAndSettle();
      final (lo, hi) = _padded([20, 400]);
      expect(h.ctx.valueMin, closeTo(lo, 1e-9));
      expect(h.ctx.valueMax, closeTo(hi, 1e-9));
    });

    testWidgets("candle extent uses low and high, not open and close", (
      tester,
    ) async {
      final h = _bare(
        () => [
          CandleLayer<int>(
            openOf: (i) => 10,
            highOf: (i) => 30,
            lowOf: (i) => 5,
            closeOf: (i) => 12,
          ),
        ],
      );
      await tester.pumpWidget(h.app(intSeries(0, 20)));
      await tester.pumpAndSettle();
      final (lo, hi) = _padded([5, 30]);
      expect(h.ctx.valueMin, closeTo(lo, 1e-9));
      expect(h.ctx.valueMax, closeTo(hi, 1e-9));
    });
  });

  group("TC-SCALE-02 layers that opt out are excluded", () {
    final data = [1, 2, 3];

    test("GridLayer", () {
      expect(const GridLayer<int>().extentFor(data, 0, 3), isNull);
    });
    test("HistogramLayer by default", () {
      expect(
        HistogramLayer<int>(valueOf: (i) => 1e9).extentFor(data, 0, 3),
        isNull,
      );
    });
    test("LineLayer(contributesToExtent: false)", () {
      expect(
        LineLayer<int>(
          valueOf: (i) => 1e9,
          contributesToExtent: false,
        ).extentFor(data, 0, 3),
        isNull,
      );
    });
    test("CrosshairLayer", () {
      expect(const CrosshairLayer<int>().extentFor(data, 0, 3), isNull);
    });

    testWidgets("an opted-out layer does not move the extent", (tester) async {
      final h = _bare(
        () => [
          LineLayer<int>(valueOf: (i) => 10.0 + i % 5),
          LineLayer<int>(valueOf: (i) => 1e9, contributesToExtent: false),
          HistogramLayer<int>(valueOf: (i) => 1e9),
        ],
      );
      await tester.pumpWidget(h.app(intSeries(0, 50)));
      await tester.pumpAndSettle();
      expect(h.ctx.valueMax, lessThan(100));
    });
  });

  group("TC-SCALE-03 histogram can opt in", () {
    test("extent is (0, max) over the range", () {
      final layer = HistogramLayer<int>(
        valueOf: (i) => [4.0, 9.0, 2.0, 50.0][i],
        contributesToExtent: true,
      );
      expect(layer.extentFor([0, 1, 2, 3], 0, 3), (0, 9));
      expect(layer.extentFor([0, 1, 2, 3], 0, 4), (0, 50));
    });

    test("ignores NaN and infinity; all-gap range contributes nothing", () {
      final layer = HistogramLayer<int>(
        valueOf: (i) => [double.nan, double.infinity, 3.0][i],
        contributesToExtent: true,
      );
      expect(layer.extentFor([0, 1, 2], 0, 3), (0, 3));
      expect(layer.extentFor([0, 1, 2], 0, 2), isNull);
    });
  });

  group("TC-SCALE-04 degenerate extents", () {
    testWidgets("all visible values equal", (tester) async {
      final h = _bare(() => [LineLayer<int>(valueOf: (i) => 100)]);
      await tester.pumpWidget(h.app(intSeries(0, 40)));
      await tester.pumpAndSettle();
      // 100 +/- 0.5, then 5 % padding of that 1.0 span.
      expect(h.ctx.valueMin, closeTo(99.45, 1e-9));
      expect(h.ctx.valueMax, closeTo(100.55, 1e-9));
    });

    testWidgets("a single datum", (tester) async {
      final h = _bare(() => [LineLayer<int>(valueOf: (i) => -3)]);
      await tester.pumpWidget(h.app([0]));
      await tester.pumpAndSettle();
      expect(h.ctx.valueMin, closeTo(-3.55, 1e-9));
      expect(h.ctx.valueMax, closeTo(-2.45, 1e-9));
    });

    testWidgets("yOf stays finite for a flat series", (tester) async {
      final h = _bare(() => [LineLayer<int>(valueOf: (i) => 7)]);
      await tester.pumpWidget(h.app(intSeries(0, 10)));
      await tester.pumpAndSettle();
      expect(h.ctx.yOf(7).isFinite, isTrue);
      expect(h.ctx.yOf(7), closeTo(h.ctx.viewportHeight / 2, 1));
    });

    test("a zero-span context does not divide by zero", () {
      final ctx = InteractiveChartContext()
        ..setViewportSize(800, 400)
        ..setValueExtent(5, 5);
      expect(ctx.yOf(5), 200);
      expect(ctx.valueOfViewportY(100).isFinite, isTrue);
    });
  });

  group("TC-SCALE-05 nothing to scale", () {
    testWidgets("no contributing layer falls back to 0..1 plus padding", (
      tester,
    ) async {
      final h = _bare(() => [const GridLayer<int>()]);
      await tester.pumpWidget(h.app(intSeries(0, 20)));
      await tester.pumpAndSettle();
      expect(h.ctx.valueMin, closeTo(-0.05, 1e-9));
      expect(h.ctx.valueMax, closeTo(1.05, 1e-9));
    });

    testWidgets("contributing layer whose visible values are all gaps", (
      tester,
    ) async {
      final h = _bare(() => [LineLayer<int>(valueOf: (i) => double.nan)]);
      await tester.pumpWidget(h.app(intSeries(0, 20)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(h.ctx.valueMin, closeTo(-0.05, 1e-9));
      expect(h.ctx.valueMax, closeTo(1.05, 1e-9));
    });

    testWidgets("empty data", (tester) async {
      final h = _bare(() => [LineLayer<int>(valueOf: (i) => i.toDouble())]);
      await tester.pumpWidget(h.app(const []));
      await tester.pumpAndSettle();
      expect(h.ctx.valueMax.isFinite, isTrue);
      expect(h.ctx.valueMax, greaterThan(h.ctx.valueMin));
    });
  });

  testWidgets("TC-SCALE-06 panning within the same range does not recompute", (
    tester,
  ) async {
    final counting = _CountingLayer();
    final h = _bare(() => [counting]);
    await tester.pumpWidget(h.app(intSeries(0, 500)));
    await tester.pumpAndSettle();

    // Offsets 4 and 6 px both show slots [0, 101) at 8 px per slot.
    h.ctx.jumpTo(4);
    await tester.pumpAndSettle();
    final range = h.controller.visibleRange;
    final calls = counting.calls;

    h.ctx.jumpTo(6);
    await tester.pumpAndSettle();
    expect(h.controller.visibleRange, range);
    expect(counting.calls, calls);

    // Crossing into a new range does recompute.
    h.ctx.jumpTo(30);
    await tester.pumpAndSettle();
    expect(h.controller.visibleRange, isNot(range));
    expect(counting.calls, greaterThan(calls));
  });

  group("manual extent", () {
    testWidgets(
      "TC-SCALE-08 autoscale off keeps the extent when data changes",
      (tester) async {
        var values = [for (var i = 0; i < 100; i++) 10.0 + i % 7];
        final h = _bare(() => [LineLayer<int>(valueOf: (i) => values[i])]);
        await tester.pumpWidget(h.app(intSeries(0, 100)));
        await tester.pumpAndSettle();

        h.controller.setAutoscale(false);
        await tester.pumpAndSettle();
        final (lo, hi) = (h.ctx.valueMin, h.ctx.valueMax);

        values = [...values]..[3] = 9999;
        await tester.pumpWidget(h.app(intSeries(0, 100)));
        await tester.pumpAndSettle();
        expect((h.ctx.valueMin, h.ctx.valueMax), (lo, hi));

        // Also when the range changes.
        await tester.drag(
          find.byType(InteractiveChart<int>),
          const Offset(-300, 0),
        );
        await tester.pumpAndSettle();
        expect((h.ctx.valueMin, h.ctx.valueMax), (lo, hi));
      },
    );

    testWidgets("TC-SCALE-09 re-enabling autoscale recomputes immediately", (
      tester,
    ) async {
      final h = _bare(() => [LineLayer<int>(valueOf: (i) => 10.0 + i % 7)]);
      await tester.pumpWidget(h.app(intSeries(0, 100)));
      await tester.pumpAndSettle();
      final (autoLo, autoHi) = (h.ctx.valueMin, h.ctx.valueMax);

      // Manual value zoom switches autoscale off.
      h.ctx.zoomValueExtent(3, h.ctx.valueOfViewportY(200));
      await tester.pumpAndSettle();
      expect(h.controller.autoscale, isFalse);
      expect(
        h.ctx.valueMax - h.ctx.valueMin,
        greaterThan((autoHi - autoLo) * 2),
      );

      h.controller.setAutoscale(true);
      await tester.pumpAndSettle();
      expect(h.ctx.valueMin, closeTo(autoLo, 1e-9));
      expect(h.ctx.valueMax, closeTo(autoHi, 1e-9));
    });

    testWidgets("TC-SCALE-09b value-axis double-tap restores the auto extent", (
      tester,
    ) async {
      final h = ChartHarness<int>(
        timeOf: minuteTime,
        layers: () => [LineLayer<int>(valueOf: (i) => 10.0 + i % 7)],
      );
      await tester.pumpWidget(h.app(intSeries(0, 100)));
      await tester.pumpAndSettle();
      final (autoLo, autoHi) = (h.ctx.valueMin, h.ctx.valueMax);

      h.ctx.zoomValueExtent(3, h.ctx.valueOfViewportY(200));
      await tester.pumpAndSettle();

      // The value axis gutter is at the right edge of the chart.
      final chart = tester.getRect(find.byType(InteractiveChart<int>));
      final gutter = Offset(chart.right - 10, chart.center.dy);
      await tester.tapAt(gutter);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(gutter);
      await tester.pumpAndSettle();

      expect(h.controller.autoscale, isTrue);
      expect(h.ctx.valueMin, closeTo(autoLo, 1e-9));
      expect(h.ctx.valueMax, closeTo(autoHi, 1e-9));
    });
  });

  group("TC-SCALE-10 yOf and valueOfViewportY are inverses", () {
    for (final (min, max) in [
      (0.0, 1.0),
      (-50.0, 50.0),
      (1e-6, 3e-6),
      (1e9, 1e9 + 500),
      (-1e6, -999000.0),
    ]) {
      test("extent $min..$max", () {
        final ctx = InteractiveChartContext()
          ..setViewportSize(800, 377)
          ..setValueExtent(min, max);
        for (var i = 0; i <= 20; i++) {
          final v = min + (max - min) * i / 20;
          expect(
            ctx.valueOfViewportY(ctx.yOf(v)),
            closeTo(v, (max - min) * 1e-9),
          );
        }
        for (final y in [0.0, 1.0, 188.5, 376.0, 377.0]) {
          expect(ctx.yOf(ctx.valueOfViewportY(y)), closeTo(y, 1e-6));
        }
      });
    }

    test("the extent ends map to the viewport edges", () {
      final ctx = InteractiveChartContext()
        ..setViewportSize(800, 400)
        ..setValueExtent(10, 20);
      expect(ctx.yOf(20), 0);
      expect(ctx.yOf(10), 400);
      expect(ctx.yOf(15), 200);
      expect(ctx.valueOfViewportY(0), 20);
      expect(ctx.valueOfViewportY(400), 10);
    });

    test("higher values have smaller y", () {
      final ctx = InteractiveChartContext()
        ..setViewportSize(800, 400)
        ..setValueExtent(0, 100);
      expect(ctx.yOf(80), lessThan(ctx.yOf(20)));
    });
  });

  group("TC-SCALE-12 value ticks across magnitudes", () {
    const ladder = [1.0, 2.0, 2.5, 5.0, 10.0];
    final ranges = <(double, double)>[
      (0, 1),
      (0, 0.0003),
      (0.0001, 0.0009),
      (-1, 1),
      (-250, 40),
      (-7.3, -1.1),
      (99.5, 100.5),
      (0, 12.5),
      (1234, 98765),
      (-1e9, 1e9),
      (5e8, 5.4e8),
      (1e-9, 2e-9),
    ];

    for (final (min, max) in ranges) {
      test("range $min..$max", () {
        final ticks = niceValueTicks(min, max);
        final range = max - min;

        expect(ticks, isNotEmpty);
        expect(ticks.length, inInclusiveRange(3, 9));

        // Ascending, evenly stepped.
        final step = ticks[1] - ticks[0];
        expect(step, greaterThan(0));
        for (var i = 1; i < ticks.length; i++) {
          expect(
            ticks[i] - ticks[i - 1],
            closeTo(step, step * 1e-6),
            reason: "uneven step at $i",
          );
        }

        // Inside the extent (within rounding).
        expect(ticks.first, greaterThanOrEqualTo(min - range * 1e-6));
        expect(ticks.last, lessThanOrEqualTo(max + range * 1e-6));

        // Step is 1, 2, 2.5, 5 or 10 times a power of ten.
        final mantissa =
            step / math.pow(10, (math.log(step) / math.ln10).floor());
        expect(
          ladder.any((m) => (m - mantissa).abs() < 1e-6),
          isTrue,
          reason: "step $step has mantissa $mantissa",
        );
      });
    }

    test("a range that crosses zero includes zero", () {
      for (final (min, max) in [(-250.0, 40.0), (-1.0, 1.0), (-0.003, 0.009)]) {
        expect(
          niceValueTicks(min, max).any((t) => t.abs() < (max - min) * 1e-9),
          isTrue,
          reason: "$min..$max",
        );
      }
    });

    test("min == max still produces ticks", () {
      final ticks = niceValueTicks(42, 42);
      expect(ticks, isNotEmpty);
      expect(ticks.first, lessThanOrEqualTo(43));
      expect(ticks.last, greaterThanOrEqualTo(41));
    });

    test("target count changes the density", () {
      final few = niceValueTicks(0, 100, targetCount: 3);
      final many = niceValueTicks(0, 100, targetCount: 10);
      expect(many.length, greaterThan(few.length));
    });
  });
}
