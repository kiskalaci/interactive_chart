// Painted layers are computed for a margin beyond the view and moved, not
// recomputed or repainted, while a pan stays within it (BufferedLayer).
import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart" hide testWidgets;
import "package:interactive_chart/interactive_chart.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/painting/buffered_layer.dart";
import "package:interactive_chart/src/painting/shape_painters.dart";

import "support/chart_harness.dart";
import "support/painted.dart";
import "support/variants.dart";

const _up = Color(0xFF00AA00);
const _lineColor = Color(0xFF0000EE);

final _chartFinder = find.byType(InteractiveChart<int>);

/// A buffered layer that counts how often it computes and paints, and keeps
/// the slot range it last computed.
class _Probe extends ChartLayer<int> {
  int computes = 0;
  int paints = 0;
  (int, int) range = (0, 0);

  @override
  Widget build(Size size, InteractiveChartContext ctx, List<int> data) =>
      BufferedLayer<(int, int)>(
        ctx: ctx,
        cacheKey: (this, ctx.dataRevision, ctx.slotExtent, size.height),
        compute: (start, end) {
          computes++;
          return range = (start, end);
        },
        paintersOf: (_) => [(key: null, painter: _CountingPainter(this))],
      );
}

class _CountingPainter extends CustomPainter {
  _CountingPainter(this.probe);
  final _Probe probe;

  @override
  void paint(Canvas canvas, Size size) {
    probe.paints++;
    canvas.drawRect(const Rect.fromLTWH(0, 0, 1, 1), Paint());
  }

  @override
  bool shouldRepaint(_CountingPainter old) => true;
}

/// How far right the probe's picture is shifted.
double _shift(WidgetTester tester) => tester
    .widget<Transform>(
      find.descendant(
        of: find.byType(BufferedLayer<(int, int)>),
        matching: find.byType(Transform),
      ),
    )
    .transform
    .getTranslation()
    .x;

Future<ChartHarness<int>> _pump(
  WidgetTester tester,
  List<ChartLayer<int>> layers, {
  int count = 2000,
  double slotExtent = 8,
}) async {
  final h = ChartHarness<int>(
    timeOf: minuteTime,
    slotExtent: slotExtent,
    valueAxis: null,
    timeAxis: null,
    layers: () => layers,
  );
  await tester.pumpWidget(h.app(intSeries(0, count)));
  await tester.pumpAndSettle();
  return h;
}

CustomPainter _painterOf<P extends CustomPainter>(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<P>()
    .single;

void main() {
  group("BufferedLayer", () {
    testWidgets("covers the view plus a margin on each side", (tester) async {
      final probe = _Probe();
      final h = await _pump(tester, [probe]);
      h.ctx.jumpTo(4000);
      await tester.pump();
      final (start, end) = probe.range;
      final visible = h.ctx.visibleEnd - h.ctx.visibleStart;
      final pad = (visible * BufferedLayer.bufferFraction).ceil() + 1;
      expect(start, h.ctx.visibleStart - pad);
      expect(end, h.ctx.visibleEnd + pad);
    });

    testWidgets("the margin is clamped to the data", (tester) async {
      final probe = _Probe();
      final h = await _pump(tester, [probe], count: 30);
      expect(probe.range, (0, 30));
      expect(h.ctx.visibleStart, 0);
    });

    testWidgets("a pan within the margin moves the picture only", (
      tester,
    ) async {
      final probe = _Probe();
      final h = await _pump(tester, [probe]);
      h.ctx.jumpTo(4000);
      await tester.pump();
      final computes = probe.computes;
      final paints = probe.paints;

      for (final dx in [3.0, 17.5, -40.0, 24.0]) {
        h.ctx.panBy(dx);
        await tester.pump();
      }
      expect(probe.computes, computes);
      expect(probe.paints, paints);
      expect(_shift(tester), closeTo(-(3 + 17.5 - 40 + 24), 1e-9));

      // A real drag too.
      await tester.drag(_chartFinder, const Offset(-30, 0));
      await tester.pumpAndSettle();
      expect(probe.computes, computes);
      expect(probe.paints, paints);
      expect(_shift(tester), closeTo(4000 - h.ctx.scrollOffset, 1e-9));
    });

    testWidgets("a pan past the margin recomputes at the new position", (
      tester,
    ) async {
      final probe = _Probe();
      final h = await _pump(tester, [probe]);
      final computes = probe.computes;
      h.ctx.panBy(h.ctx.viewportWidth);
      await tester.pump();
      expect(probe.computes, computes + 1);
      expect(_shift(tester), 0);
      final (start, end) = probe.range;
      expect(start, lessThanOrEqualTo(h.ctx.visibleStart));
      expect(end, greaterThanOrEqualTo(h.ctx.visibleEnd));
    });

    testWidgets("zoom, data and viewport height changes recompute", (
      tester,
    ) async {
      final probe = _Probe();
      final h = await _pump(tester, [probe]);

      var computes = probe.computes;
      h.ctx.setSlotExtentAndScroll(10, h.ctx.scrollOffset);
      await tester.pump();
      expect(probe.computes, computes + 1, reason: "zoom");

      // The parent rebuilds with the same data: it may have been edited in
      // place, so cached geometry is dropped.
      computes = probe.computes;
      await tester.pumpWidget(h.app(intSeries(0, 2000)));
      await tester.pump();
      expect(probe.computes, computes + 1, reason: "parent rebuild");

      computes = probe.computes;
      await tester.pumpWidget(h.app(intSeries(0, 2000), height: 300));
      await tester.pump();
      expect(probe.computes, greaterThan(computes), reason: "height");
    });

    testWidgets("a highlight change does not touch it", (tester) async {
      final probe = _Probe();
      final h = await _pump(tester, [probe]);
      final computes = probe.computes;
      final paints = probe.paints;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(_chartFinder));
      await mouse.moveTo(tester.getCenter(_chartFinder) + const Offset(30, 0));
      await tester.pump();
      expect(h.controller.highlightedIndex, isNotNull);
      expect((probe.computes, probe.paints), (computes, paints));
    });
  });

  group("candles", () {
    CandleLayer<int> flat({void Function(int)? onTap}) => CandleLayer<int>(
      openOf: (i) => 10,
      highOf: (i) => 14,
      lowOf: (i) => 6,
      closeOf: (i) => 12,
      upColor: _up,
      downColor: const Color(0xFFAA0000),
      onTap: onTap,
    );

    testWidgets("a pan keeps the painter, and the candles stay on their "
        "slots", (tester) async {
      final h = await _pump(tester, [flat()], slotExtent: 20);
      final painter = _painterOf<CandlePainter>(tester);
      final firstOffScreen = h.ctx.visibleEnd;

      h.ctx.panBy(20 * 4.0 + 7);
      await tester.pump();
      expect(_painterOf<CandlePainter>(tester), same(painter));
      for (final c in paintedCandles(tester)) {
        expect(c.body.center.dx, closeTo(h.ctx.xOf(c.index), 1e-9));
      }

      // The candle that was just past the right edge was painted ahead of
      // time, and is drawn now that it has scrolled in.
      expect(h.ctx.visibleEnd, greaterThan(firstOffScreen));
      final origin = tester.getTopLeft(_chartFinder);
      final at = origin + Offset(h.ctx.xOf(firstOffScreen), h.ctx.yOf(11));
      expect(h.ctx.xOf(firstOffScreen), lessThan(h.ctx.viewportWidth));
      expect(await colorAt(tester, at), _up);
    });

    testWidgets("taps after a pan report the candle under the finger", (
      tester,
    ) async {
      final taps = <int>[];
      final h = await _pump(tester, [flat(onTap: taps.add)], slotExtent: 20);
      final painter = _painterOf<CandlePainter>(tester);
      h.ctx.panBy(20 * 3.0 + 5);
      await tester.pump();
      expect(_painterOf<CandlePainter>(tester), same(painter));
      final origin = tester.getTopLeft(_chartFinder);
      final i = h.ctx.visibleStart + 4;
      await tester.tapAt(origin + Offset(h.ctx.xOf(i), h.ctx.yOf(11)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, [i]);
    });

    testWidgets("an edit in place shows after the parent rebuilds", (
      tester,
    ) async {
      final closes = List<double>.filled(50, 12);
      final h = ChartHarness<int>(
        timeOf: minuteTime,
        slotExtent: 20,
        valueAxis: null,
        timeAxis: null,
        layers: () => [
          CandleLayer<int>(
            openOf: (i) => 10,
            highOf: (i) => 14,
            lowOf: (i) => 6,
            closeOf: (i) => closes[i],
          ),
        ],
      );
      final data = intSeries(0, 50);
      await tester.pumpWidget(h.app(data));
      await tester.pumpAndSettle();
      closes[3] = 8; // now a down candle
      await tester.pumpWidget(h.app(data));
      await tester.pump();
      expect(paintedCandles(tester).firstWhere((c) => c.index == 3).up, false);
    });

    testWidgets("an autoscale change after a pan recomputes", (tester) async {
      // Rising candles: panning changes the visible extent.
      final h = await _pump(tester, [
        CandleLayer<int>(
          openOf: (i) => i.toDouble(),
          highOf: (i) => i + 2.0,
          lowOf: (i) => i - 2.0,
          closeOf: (i) => i + 1.0,
        ),
      ]);
      final painter = _painterOf<CandlePainter>(tester);
      final extent = (h.ctx.valueMin, h.ctx.valueMax);
      h.ctx.panBy(16);
      await tester.pump();
      expect((h.ctx.valueMin, h.ctx.valueMax), isNot(extent));
      expect(_painterOf<CandlePainter>(tester), isNot(same(painter)));
      for (final c in paintedCandles(tester)) {
        expect(c.wick.top, closeTo(h.ctx.yOf(c.index + 2.0), 1e-9));
      }
    });
  });

  group("histogram", () {
    testWidgets("a pan keeps the painter while the tallest bar stays", (
      tester,
    ) async {
      final taps = <int>[];
      final h = await _pump(tester, [
        HistogramLayer<int>(valueOf: (i) => 10, onTap: taps.add),
      ], slotExtent: 20);
      final painter = _painterOf<BarPainter>(tester);
      h.ctx.panBy(20 * 3.0 + 2);
      await tester.pump();
      expect(_painterOf<BarPainter>(tester), same(painter));
      for (final (k, r) in paintedBars(tester).indexed) {
        expect(r.center.dx, closeTo(h.ctx.xOf(k), 1e-9));
      }
      final origin = tester.getTopLeft(_chartFinder);
      final i = h.ctx.visibleStart + 2;
      await tester.tapAt(
        origin + Offset(h.ctx.xOf(i), h.ctx.viewportHeight - 4),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, [i]);
    });

    testWidgets("a new tallest bar in view recomputes", (tester) async {
      // Bar 400 is twice as tall as the rest, and far outside the first
      // view and its margin.
      final h = await _pump(tester, [
        HistogramLayer<int>(valueOf: (i) => i == 400 ? 20 : 10),
      ], count: 1000);
      final strip = h.ctx.viewportHeight * 0.22;
      expect(paintedBars(tester).length, lessThan(400));
      expect(paintedBars(tester).first.height, closeTo(strip, 1e-9));

      h.ctx.jumpTo(400 * 8.0 - 100);
      await tester.pump();
      expect(h.ctx.visibleStart, lessThanOrEqualTo(400));
      expect(h.ctx.visibleEnd, greaterThan(400));
      final bars = paintedBars(tester);
      final tall = bars.where((r) => (r.center.dx - h.ctx.xOf(400)).abs() < 1);
      expect(tall.single.height, closeTo(strip, 1e-9));
      expect(bars.first.height, closeTo(strip / 2, 1e-9));
    });
  });

  group("line", () {
    testWidgets("a pan keeps the painters; points and hit squares follow", (
      tester,
    ) async {
      final hovers = <int?>[];
      final h = await _pump(tester, [
        LineLayer<int>(
          valueOf: (i) => 10.0 + i % 3,
          color: _lineColor,
          onPointHover: hovers.add,
        ),
      ], slotExtent: 20);
      h.controller.setAutoscale(false);
      await tester.pump();
      final painter = _painterOf<LinePainter>(tester);
      h.ctx.panBy(20 * 2.0 + 3);
      await tester.pump();
      expect(_painterOf<LinePainter>(tester), same(painter));
      for (final o in paintedLineRuns(tester).single) {
        final i = ((o.dx + h.ctx.scrollOffset) / 20).floor();
        expect(o, Offset(h.ctx.xOf(i), h.ctx.yOf(10.0 + i % 3)));
      }
      final origin = tester.getTopLeft(_chartFinder);
      final i = h.ctx.visibleStart + 3;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(
        location: origin + Offset(h.ctx.xOf(i), h.ctx.yOf(10.0 + i % 3)),
      );
      await tester.pump();
      expect(hovers, [i]);
    });

    testWidgets("the fill follows the highest point in view", (tester) async {
      // Flat, with one spike at slot 2.
      final h = await _pump(tester, [
        LineLayer<int>(
          valueOf: (i) => i == 2 ? 20 : 10,
          color: _lineColor,
          fill: true,
        ),
      ]);
      h.controller.setAutoscale(false);
      await tester.pump();
      CustomPainter? fillPainter() =>
          (tester.widget<Positioned>(find.byKey(LineLayer.fillKey)).child
                  as CustomPaint)
              .painter;
      final withSpike = fillPainter();
      // Slot 2 scrolls out of view: the gradient's top moves.
      h.ctx.panBy(8 * 5.0);
      await tester.pump();
      final withoutSpike = fillPainter();
      expect(withoutSpike, isNot(same(withSpike)));
      // Flat from here on: the highest point stays where it is.
      h.ctx.panBy(8 * 2.0);
      await tester.pump();
      expect(fillPainter(), same(withoutSpike));
    });
  });
}
