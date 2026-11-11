// Zoomed out past a pixel per slot (minSlotExtent < 1), painted layers draw
// one item per pixel column, and wide ranges use cached block extents.
import "dart:math" as math;

import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart" hide testWidgets;
import "package:interactive_chart/interactive_chart.dart";
import "package:interactive_chart/src/chart_context.dart";

import "support/chart_harness.dart";
import "support/painted.dart";
import "support/variants.dart";

final _chartFinder = find.byType(InteractiveChart<int>);

/// A deterministic, jumpy series.
double _wave(int i) => 100 + ((i * 7919) % 1000) / 10 + (i % 37);

/// The column (content pixel) slot [i] falls in.
int _column(int i, double slotExtent) => (i * slotExtent).floor();

ChartHarness<int> _harness(
  List<ChartLayer<int>> Function() layers, {
  double slotExtent = 0.25,
}) => ChartHarness<int>(
  timeOf: minuteTime,
  slotExtent: slotExtent,
  minSlotExtent: 0.02,
  valueAxis: null,
  timeAxis: null,
  layers: layers,
);

Future<ChartHarness<int>> _pump(
  WidgetTester tester,
  List<ChartLayer<int>> Function() layers, {
  int count = 20000,
  double slotExtent = 0.25,
}) async {
  final h = _harness(layers, slotExtent: slotExtent);
  await tester.pumpWidget(h.app(intSeries(0, count)));
  await tester.pumpAndSettle();
  return h;
}

CandleLayer<int> _candles({void Function(int)? onTap}) => CandleLayer<int>(
  openOf: _wave,
  closeOf: (i) => _wave(i + 1),
  highOf: (i) => math.max(_wave(i), _wave(i + 1)) + (i % 5),
  lowOf: (i) => math.min(_wave(i), _wave(i + 1)) - (i % 3),
  onTap: onTap,
);

/// Counts how many data its extent queries read.
class _ScanCounter extends ChartLayer<int> {
  int scanned = 0;

  @override
  ValueRange? extentFor(List<int> data, int start, int end) {
    double? lo, hi;
    for (var i = start; i < end; i++) {
      scanned++;
      final v = _wave(data[i]);
      lo = lo == null ? v : math.min(lo, v);
      hi = hi == null ? v : math.max(hi, v);
    }
    return lo == null || hi == null ? null : (lo, hi);
  }

  @override
  Widget build(Size size, InteractiveChartContext ctx, List<int> data) =>
      const SizedBox.shrink();
}

void main() {
  group("candles", () {
    testWidgets("one per pixel column, merging its candles", (tester) async {
      final h = await _pump(tester, () => [_candles()]);
      const e = 0.25;
      final candles = paintedCandles(tester);
      // About one per pixel of the view and its painted margin.
      expect(candles.length, lessThan(h.ctx.viewportWidth * 1.6 + 4));
      expect(candles.length, greaterThan(h.ctx.viewportWidth * 0.9));

      for (final c in candles.take(40)) {
        final col = _column(c.index, e);
        expect(_column(c.lastIndex, e), col);
        expect(c.lastIndex - c.index, 3); // four slots per pixel
        final slots = [for (var i = c.index; i <= c.lastIndex; i++) i];
        final high = slots.map(_candles().highOf).reduce(math.max);
        final low = slots.map(_candles().lowOf).reduce(math.min);
        final open = _wave(c.index);
        final close = _wave(c.lastIndex + 1);
        expect(c.wick.width, 1);
        expect(c.wick.left, closeTo(col - h.ctx.scrollOffset, 1e-9));
        expect(c.wick.top, closeTo(h.ctx.yOf(high), 1e-9));
        expect(c.wick.bottom, closeTo(h.ctx.yOf(low), 1e-9));
        expect(c.up, close >= open);
        expect(
          c.body.top,
          closeTo(math.min(h.ctx.yOf(open), h.ctx.yOf(close)), 1e-9),
        );
      }
    });

    testWidgets("a tap reports the slot under the finger", (tester) async {
      final taps = <int>[];
      final h = await _pump(tester, () => [_candles(onTap: taps.add)]);
      final origin = tester.getTopLeft(_chartFinder);
      // Inside the candle of slots 400..403 (pixel 100), at its third slot.
      final x = 402 * 0.25 + 0.1 - h.ctx.scrollOffset;
      final c = paintedCandles(tester).firstWhere((c) => c.index == 400);
      await tester.tapAt(origin + Offset(x, c.wick.center.dy));
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, [402]);
    });

    testWidgets("gaps are skipped and a column of gaps draws nothing", (
      tester,
    ) async {
      await _pump(
        tester,
        () => [
          CandleLayer<int>(
            // Slots 40..47 (pixels 10 and 11) are gaps, and slot 49.
            openOf: (i) => (i >= 40 && i < 48) || i == 49 ? double.nan : 10,
            closeOf: (i) => 12,
            highOf: (i) => 13,
            lowOf: (i) => 9,
          ),
        ],
        count: 400,
      );
      final candles = paintedCandles(tester);
      expect(candles.any((c) => c.index >= 40 && c.index < 48), isFalse);
      final at12 = candles.firstWhere((c) => c.index == 48);
      expect(at12.lastIndex, 51); // 49 is skipped inside the column
    });

    testWidgets("at 1 px per slot and above, nothing is merged", (
      tester,
    ) async {
      await _pump(tester, () => [_candles()], slotExtent: 1);
      for (final c in paintedCandles(tester)) {
        expect(c.lastIndex, c.index);
      }
    });
  });

  group("histogram", () {
    testWidgets("one bar per pixel column, as tall as its tallest", (
      tester,
    ) async {
      final taps = <int>[];
      final h = await _pump(
        tester,
        () => [HistogramLayer<int>(valueOf: _wave, onTap: taps.add)],
      );
      final bars = paintedBars(tester);
      final strip = h.ctx.viewportHeight * 0.22;
      final visibleMax = [
        for (var i = h.ctx.visibleStart; i < h.ctx.visibleEnd; i++) _wave(i),
      ].reduce(math.max);
      for (final r in bars.take(40)) {
        final col = (r.left + h.ctx.scrollOffset).round();
        expect(r.width, 1);
        final tallest = [
          for (var i = col * 4; i < col * 4 + 4; i++) _wave(i),
        ].reduce(math.max);
        expect(r.height, closeTo(strip * tallest / visibleMax, 1e-9));
      }
      final origin = tester.getTopLeft(_chartFinder);
      final x = 41 * 0.25 + 0.1 - h.ctx.scrollOffset;
      await tester.tapAt(origin + Offset(x, h.ctx.viewportHeight - 1));
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, [41]);
    });
  });

  group("line", () {
    testWidgets("per column only its first, lowest, highest and last point", (
      tester,
    ) async {
      final h = await _pump(
        tester,
        () => [LineLayer<int>(valueOf: _wave, onPointTap: (_) {})],
        slotExtent: 0.1,
      );
      final run = paintedLineRuns(tester).single;
      // At most four points per pixel column.
      expect(
        run.length,
        lessThanOrEqualTo(4 * (h.ctx.viewportWidth * 1.6 + 4)),
      );
      final byColumn = <int, List<Offset>>{};
      for (final o in run) {
        final i = ((o.dx + h.ctx.scrollOffset) / 0.1).floor();
        expect(o.dy, closeTo(h.ctx.yOf(_wave(i)), 1e-9));
        (byColumn[_column(i, 0.1)] ??= []).add(o);
      }
      // Every column keeps its extremes, so the stroke spans them.
      for (final MapEntry(key: col, value: points) in byColumn.entries.take(
        50,
      )) {
        final values = [
          for (var i = col * 10; i < col * 10 + 10; i++) _wave(i),
        ];
        final ys = points.map((o) => o.dy);
        expect(
          ys.reduce(math.min),
          closeTo(h.ctx.yOf(values.reduce(math.max)), 1e-9),
        );
        expect(
          ys.reduce(math.max),
          closeTo(h.ctx.yOf(values.reduce(math.min)), 1e-9),
        );
        expect(points.length, lessThanOrEqualTo(4));
      }
    });

    testWidgets("a column of gaps breaks the line, a gap inside one does not", (
      tester,
    ) async {
      await _pump(
        tester,
        () => [
          LineLayer<int>(
            // Pixel 10 (slots 40..43) is all gaps; slot 50 is a lone gap.
            valueOf: (i) => (i >= 40 && i < 44) || i == 50 ? double.nan : 10,
          ),
        ],
        count: 400,
      );
      expect(paintedLineRuns(tester).length, 2);
    });
  });

  group("zooming out", () {
    testWidgets("the wheel zooms below a pixel per slot, down to the minimum", (
      tester,
    ) async {
      final h = await _pump(tester, () => [_candles()], slotExtent: 2);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(tester.getCenter(_chartFinder)),
      );
      for (var k = 0; k < 30; k++) {
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 200)));
        await tester.pump();
      }
      expect(h.ctx.slotExtent, closeTo(0.02, 1e-9));
      expect(paintedCandles(tester).length, lessThan(h.ctx.viewportWidth * 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets("the crosshair and projected slots still work", (tester) async {
      final h = await _pump(tester, () => [..._candlesAnd()], count: 3000);
      // Scrolled as far right as it goes: the newest bar mid-view, projected
      // slots to its right.
      h.ctx.jumpTo(h.ctx.maxScrollOffset);
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(_chartFinder);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      final i = h.ctx.visibleEnd - 10;
      expect(h.ctx.xOf(3040), lessThan(h.ctx.viewportWidth));
      await mouse.addPointer(location: origin + Offset(h.ctx.xOf(i), 50));
      await mouse.moveTo(origin + Offset(h.ctx.xOf(i) + 0.01, 50));
      await tester.pump();
      expect(h.controller.highlightedIndex, i);
      // Past the newest bar.
      await mouse.moveTo(origin + Offset(h.ctx.xOf(3000 + 40), 50));
      await tester.pump();
      expect(h.ctx.highlightedIndex, 3040);
      expect(h.ctx.highlightedProjectedTime, minuteTime(3040));
    });
  });

  group("block extents for very wide views", () {
    testWidgets("autoscale over 20k+ visible slots matches a direct scan", (
      tester,
    ) async {
      final counter = _ScanCounter();
      // Far wider than any test screen, so there is room to pan.
      final h = await _pump(
        tester,
        () => [counter],
        count: 200000,
        slotExtent: 0.03,
      );
      h.ctx.jumpTo(3000);
      await tester.pump();
      final visible = h.ctx.visibleEnd - h.ctx.visibleStart;
      expect(visible, greaterThan(4096));
      final values = [
        for (var i = h.ctx.visibleStart; i < h.ctx.visibleEnd; i++) _wave(i),
      ];
      final lo = values.reduce(math.min);
      final hi = values.reduce(math.max);
      final pad = (hi - lo) * 0.05;
      expect(h.ctx.valueMin, closeTo(lo - pad, 1e-9));
      expect(h.ctx.valueMax, closeTo(hi + pad, 1e-9));

      // A pan reads the blocks it brings into view for the first time and the
      // partial blocks at the edges, not every visible slot.
      counter.scanned = 0;
      h.ctx.panBy(37);
      await tester.pump();
      final newSlots = (37 / 0.03).ceil();
      expect(counter.scanned, greaterThan(0));
      expect(counter.scanned, lessThan(newSlots + 3 * 256));
      expect(counter.scanned, lessThan(visible ~/ 4));
      // Panning back over cached blocks reads only the partial ones.
      counter.scanned = 0;
      h.ctx.panBy(-37);
      await tester.pump();
      expect(counter.scanned, greaterThan(0));
      expect(counter.scanned, lessThanOrEqualTo(2 * 256));
    });

    testWidgets("an edit in place reaches the cached blocks", (tester) async {
      final values = [for (var i = 0; i < 60000; i++) 10.0];
      final h = _harness(
        () => [LineLayer<int>(valueOf: (i) => values[i])],
        slotExtent: 0.03,
      );
      final data = intSeries(0, 60000);
      await tester.pumpWidget(h.app(data));
      await tester.pumpAndSettle();
      expect(h.ctx.valueMax, lessThan(20));
      values[h.ctx.visibleStart + 1000] = 500;
      await tester.pumpWidget(h.app(data));
      await tester.pump();
      expect(h.ctx.valueMax, greaterThan(500));
    });
  });
}

List<ChartLayer<int>> _candlesAnd() => [
  _candles(),
  const HistogramLayer<int>(valueOf: _wave),
  const LineLayer<int>(valueOf: _wave, fill: true),
  const CrosshairLayer<int>(valueOf: _wave, timeOf: minuteTime),
];
