// Test plan section 8: layers (TC-LAYER-*, TC-GRID-*, TC-CANDLE-*, TC-HIST-*,
// TC-LINE-*). See docs/poc_notes.md. TC-LINE-05 is in
// test/latest_point_test.dart.
import "dart:math" as math;

import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart" hide testWidgets;
import "package:interactive_chart/interactive_chart.dart";
import "package:interactive_chart/src/chart_context.dart";

import "support/chart_harness.dart";
import "support/variants.dart";

const _up = Color(0xFF00AA00);
const _down = Color(0xFFAA0000);
const _gridColor = Color(0xFF123456);
const _histColor = Color(0xFF654321);
const _lineColor = Color(0xFF0000EE);

final _chartFinder = find.byType(InteractiveChart<int>);

Finder _boxes(Color color) => find.byWidgetPredicate(
  (w) => w is ColoredBox && w.color == color,
  description: "ColoredBox $color",
);

/// No axes, so the viewport equals the widget and layer coordinates equal
/// global coordinates minus the widget's top-left corner.
ChartHarness<int> _bare(
  List<ChartLayer<int>> Function() layers, {
  double slotExtent = 8,
  ChartAnchor anchor = ChartAnchor.left,
}) => ChartHarness<int>(
  timeOf: minuteTime,
  slotExtent: slotExtent,
  anchor: anchor,
  valueAxis: null,
  timeAxis: null,
  layers: layers,
);

Future<ChartHarness<int>> _pump(
  WidgetTester tester,
  List<ChartLayer<int>> Function() layers, {
  int count = 30,
  double slotExtent = 8,
  ChartAnchor anchor = ChartAnchor.left,
}) async {
  final h = _bare(layers, slotExtent: slotExtent, anchor: anchor);
  await tester.pumpWidget(h.app(intSeries(0, count)));
  await tester.pumpAndSettle();
  return h;
}

/// Global centre of slot [i] horizontally, middle of the viewport vertically.
Offset _slotPoint(WidgetTester tester, ChartHarness<int> h, int i) {
  final origin = tester.getTopLeft(_chartFinder);
  return origin + Offset(h.ctx.xOf(i), h.ctx.viewportHeight / 2);
}

/// A layer whose children are one full-size tappable box, to test z-order.
class _TapLayer extends ChartLayer<int> {
  _TapLayer(this.name, this.log);
  final String name;
  final List<String> log;

  @override
  Widget build(Size size, InteractiveChartContext ctx, List<int> data) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => log.add(name),
        child: const SizedBox.expand(),
      );
}

class _CustomLayer extends ChartLayer<int> {
  _CustomLayer(this.onBuild, {this.extent});
  final void Function(Size, InteractiveChartContext, List<int>) onBuild;
  final ValueRange? extent;

  @override
  ValueRange? extentFor(List<int> data, int start, int end) => extent;

  @override
  Widget build(Size size, InteractiveChartContext ctx, List<int> data) {
    onBuild(size, ctx, data);
    return const SizedBox.shrink();
  }
}

void main() {
  group("TC-LAYER generic layer behaviour", () {
    testWidgets("TC-LAYER-01 later layers draw on top of earlier ones", (
      tester,
    ) async {
      final log = <String>[];
      await _pump(
        tester,
        () => [_TapLayer("bottom", log), _TapLayer("top", log)],
      );
      await tester.tapAt(tester.getCenter(_chartFinder));
      await tester.pump(const Duration(milliseconds: 400));
      expect(log, ["top"]);
    });

    testWidgets("TC-LAYER-01b swapping the order swaps who is on top", (
      tester,
    ) async {
      final log = <String>[];
      await _pump(
        tester,
        () => [_TapLayer("top", log), _TapLayer("bottom", log)],
      );
      await tester.tapAt(tester.getCenter(_chartFinder));
      await tester.pump(const Duration(milliseconds: 400));
      expect(log, ["bottom"]);
    });

    testWidgetsOnce(
      "TC-LAYER-02 child count follows the visible slots, not the data",
      (tester) async {
        Future<int> boxCount(int n) async {
          await tester.pumpWidget(const SizedBox());
          await _pump(
            tester,
            () => [
              CandleLayer<int>(
                openOf: (i) => 10,
                highOf: (i) => 12,
                lowOf: (i) => 8,
                closeOf: (i) => 11,
                upColor: _up,
                downColor: _down,
              ),
              HistogramLayer<int>(valueOf: (i) => 5, color: _histColor),
              LineLayer<int>(valueOf: (i) => 10, color: _lineColor),
            ],
            count: n,
          );
          return _boxes(_up).evaluate().length +
              _boxes(_histColor).evaluate().length +
              _boxes(_lineColor).evaluate().length;
        }

        final small = await boxCount(1000);
        final large = await boxCount(50000);
        expect(small, greaterThan(50));
        // Equal up to the slots that straddle the viewport edges.
        expect((large - small).abs(), lessThanOrEqualTo(6));
      },
    );

    testWidgets("TC-LAYER-03 custom layers get size, context and data", (
      tester,
    ) async {
      Size? seenSize;
      InteractiveChartContext? seenCtx;
      List<int>? seenData;
      final h = await _pump(
        tester,
        () => [
          _CustomLayer((s, c, d) {
            seenSize = s;
            seenCtx = c;
            seenData = d;
          }, extent: (500, 900)),
        ],
      );
      expect(seenSize, Size(h.ctx.viewportWidth, h.ctx.viewportHeight));
      expect(seenCtx, same(h.ctx));
      expect(seenData, intSeries(0, 30));
      // Its extent feeds autoscale: 500..900 plus 5 % padding.
      expect(h.ctx.valueMin, closeTo(480, 1e-9));
      expect(h.ctx.valueMax, closeTo(920, 1e-9));
    });
  });

  group("TC-GRID-01 grid lines", () {
    testWidgets("one horizontal line per value tick at yOf(tick)", (
      tester,
    ) async {
      final h = await _pump(
        tester,
        () => [
          const GridLayer<int>(color: _gridColor),
          LineLayer<int>(valueOf: (i) => 10.0 + i),
        ],
      );
      final lines = tester
          .widgetList<Positioned>(
            find.descendant(
              of: _chartFinder,
              matching: find.byWidgetPredicate(
                (w) => w is Positioned && w.height == 1 && w.left == 0,
              ),
            ),
          )
          .toList();
      final ys = lines.map((p) => p.top!).toList()..sort();
      final expected = [for (final v in h.ctx.valueTicks) h.ctx.yOf(v)]..sort();
      expect(ys.length, expected.length);
      for (var i = 0; i < ys.length; i++) {
        expect(ys[i], closeTo(expected[i], 1e-9));
      }
      expect(_boxes(_gridColor), findsWidgets);
    });

    testWidgets("vertical lines sit on the visible time marks", (tester) async {
      final h = await _pump(
        tester,
        () => [const GridLayer<int>(color: _gridColor)],
        count: 400,
      );
      final verticals = tester
          .widgetList<Positioned>(
            find.descendant(
              of: _chartFinder,
              matching: find.byWidgetPredicate(
                (w) => w is Positioned && w.width == 1 && w.top == 0,
              ),
            ),
          )
          .map((p) => p.left!)
          .toList();
      final expected = [
        for (final m in h.ctx.timeTicks)
          if (h.ctx.xOf(m.index) >= -1 &&
              h.ctx.xOf(m.index) <= h.ctx.viewportWidth + 1)
            h.ctx.xOf(m.index),
      ];
      expect(verticals, expected);
      expect(verticals, isNotEmpty);
    });

    testWidgets("the configured colour is used and the grid ignores pointers", (
      tester,
    ) async {
      final h = await _pump(
        tester,
        () => [
          const GridLayer<int>(color: _gridColor),
          LineLayer<int>(valueOf: (i) => 10.0 + i),
        ],
        count: 400,
      );
      expect(_boxes(_gridColor), findsWidgets);
      // Panning through the grid still works. (A drag that starts on a
      // hittable element loses one touch slop, about 20 px, to the tap and
      // long-press recognisers, hence the tolerance.)
      await tester.drag(_chartFinder, const Offset(-120, 0));
      await tester.pumpAndSettle();
      expect(h.ctx.scrollOffset, closeTo(120, 25));
    });
  });

  group("candles", () {
    CandleLayer<int> candles({
      required double Function(int) open,
      required double Function(int) close,
      double Function(int)? high,
      double Function(int)? low,
      double bodyWidthRatio = 0.7,
      double minBodyWidth = 1,
      void Function(int)? onTap,
      void Function(int?)? onHover,
    }) => CandleLayer<int>(
      openOf: open,
      closeOf: close,
      highOf: high ?? (i) => math.max(open(i), close(i)) + 2,
      lowOf: low ?? (i) => math.min(open(i), close(i)) - 2,
      upColor: _up,
      downColor: _down,
      bodyWidthRatio: bodyWidthRatio,
      minBodyWidth: minBodyWidth,
      onTap: onTap,
      onHover: onHover,
    );

    testWidgets("TC-CANDLE-01 close >= open is up, otherwise down", (
      tester,
    ) async {
      // 0: up, 1: down, 2: doji (close == open) which counts as up.
      const opens = [10.0, 14.0, 12.0];
      const closes = [13.0, 11.0, 12.0];
      await _pump(
        tester,
        () => [candles(open: (i) => opens[i], close: (i) => closes[i])],
        count: 3,
      );
      // Each candle is a wick plus a body, both in the candle's colour.
      expect(_boxes(_up).evaluate().length, 4);
      expect(_boxes(_down).evaluate().length, 2);
    });

    testWidgets("TC-CANDLE-02 body width and minimum body height", (
      tester,
    ) async {
      final h = await _pump(
        tester,
        () => [candles(open: (i) => 10, close: (i) => 10)], // flat candles
        count: 5,
        slotExtent: 20,
      );
      final bodies = [
        for (var i = 0; i < _boxes(_up).evaluate().length; i++)
          tester.getRect(_boxes(_up).at(i)),
      ].where((r) => r.width > 1).toList();
      expect(bodies.length, 5);
      for (final r in bodies) {
        expect(r.width, closeTo(14, 1e-6)); // 20 * 0.7
        expect(r.height, closeTo(1, 1e-6)); // flat: at least 1 px
      }
      expect(h.ctx.slotExtent, 20);
    });

    testWidgets("TC-CANDLE-02b minBodyWidth wins over a thin ratio", (
      tester,
    ) async {
      await _pump(
        tester,
        () => [
          candles(
            open: (i) => 10,
            close: (i) => 14,
            bodyWidthRatio: 0.2,
            minBodyWidth: 6,
          ),
        ],
        count: 4,
        slotExtent: 12,
      );
      final bodies = [
        for (var i = 0; i < _boxes(_up).evaluate().length; i++)
          tester.getRect(_boxes(_up).at(i)),
      ].where((r) => r.width > 1).toList();
      expect(bodies, isNotEmpty);
      for (final r in bodies) {
        expect(r.width, closeTo(6, 1e-6));
      }
    });

    testWidgets("TC-CANDLE-03 below 2 px per slot the body is a 1 px line", (
      tester,
    ) async {
      await _pump(
        tester,
        () => [candles(open: (i) => 10, close: (i) => 14)],
        count: 20,
        slotExtent: 1.5,
      );
      final rects = [
        for (var i = 0; i < _boxes(_up).evaluate().length; i++)
          tester.getRect(_boxes(_up).at(i)),
      ];
      expect(rects, isNotEmpty);
      for (final r in rects) {
        expect(r.width, closeTo(1, 1e-6));
      }
    });

    testWidgets("TC-CANDLE-04 the wick runs from high to low", (tester) async {
      final h = await _pump(
        tester,
        () => [
          candles(
            open: (i) => 10,
            close: (i) => 12,
            high: (i) => 20,
            low: (i) => 4,
          ),
        ],
        count: 3,
        slotExtent: 20,
      );
      final origin = tester.getTopLeft(_chartFinder);
      final wicks = [
        for (var i = 0; i < _boxes(_up).evaluate().length; i++)
          tester.getRect(_boxes(_up).at(i)),
      ].where((r) => r.width == 1);
      expect(wicks.length, 3);
      for (final w in wicks) {
        expect(w.top - origin.dy, closeTo(h.ctx.yOf(20), 1e-6));
        expect(w.bottom - origin.dy, closeTo(h.ctx.yOf(4), 1e-6));
      }
    });

    testWidgets("TC-CANDLE-05 a candle with any NaN field is skipped", (
      tester,
    ) async {
      await _pump(
        tester,
        () => [
          candles(
            open: (i) => i == 2 ? double.nan : 10,
            close: (i) => i == 3 ? double.infinity : 12,
            high: (i) => i == 4 ? double.nan : 15,
            low: (i) => i == 5 ? double.negativeInfinity : 8,
          ),
        ],
        count: 10,
      );
      expect(tester.takeException(), isNull);
      expect(_boxes(_up).evaluate().length, 2 * 6); // 10 - 4 skipped
    });

    testWidgets("TC-CANDLE-06 tap reports the index; hover enter and exit", (
      tester,
    ) async {
      final taps = <int>[];
      final hovers = <int?>[];
      final h = await _pump(
        tester,
        () => [
          candles(
            open: (i) => 10,
            close: (i) => 12,
            onTap: taps.add,
            onHover: hovers.add,
          ),
        ],
        count: 20,
        slotExtent: 20,
      );

      await tester.tapAt(_slotPoint(tester, h, 4));
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, [4]);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: _slotPoint(tester, h, 2));
      await tester.pump();
      expect(hovers, [2]);
      await mouse.moveTo(_slotPoint(tester, h, 3));
      await tester.pump();
      expect(hovers, [2, null, 3]);
      await mouse.moveTo(
        tester.getBottomRight(_chartFinder) + const Offset(20, 20),
      );
      await tester.pump();
      expect(hovers.last, isNull);
    });

    testWidgets("candles without callbacks do not swallow gestures", (
      tester,
    ) async {
      final h = await _pump(
        tester,
        () => [candles(open: (i) => 10, close: (i) => 12)],
        count: 400,
      );
      await tester.drag(_chartFinder, const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(h.ctx.scrollOffset, closeTo(200, 25)); // see the note on slop
    });
  });

  group("histogram", () {
    HistogramLayer<int> hist(
      double Function(int) value, {
      double fraction = 0.25,
      void Function(int)? onTap,
      void Function(int?)? onHover,
    }) => HistogramLayer<int>(
      valueOf: value,
      color: _histColor,
      heightFraction: fraction,
      onTap: onTap,
      onHover: onHover,
    );

    testWidgets("TC-HIST-01 the tallest visible bar fills the strip", (
      tester,
    ) async {
      final h = await _pump(
        tester,
        () => [
          hist((i) => [2.0, 8.0, 4.0, 1.0][i % 4]),
        ],
        count: 40,
      );
      final strip = h.ctx.viewportHeight * 0.25;
      final heights = [
        for (var i = 0; i < _boxes(_histColor).evaluate().length; i++)
          tester.getRect(_boxes(_histColor).at(i)).height,
      ].where((v) => v > 1.5).toList()..sort();
      expect(heights.last, closeTo(strip, 1e-6));
      // 8 : 4 : 2 : 1 are in proportion.
      expect(heights.toSet().length, 4);
      expect(heights.last / heights.first, closeTo(8, 0.01));
    });

    testWidgets("TC-HIST-01b the scale follows what is visible", (
      tester,
    ) async {
      // A huge bar far to the right must not shrink the bars on screen.
      final h = await _pump(
        tester,
        () => [hist((i) => i == 500 ? 1e6 : 10.0)],
        count: 600,
      );
      final strip = h.ctx.viewportHeight * 0.25;
      final top = [
        for (var i = 0; i < _boxes(_histColor).evaluate().length; i++)
          tester.getRect(_boxes(_histColor).at(i)).height,
      ].where((v) => v > 1.5).reduce(math.max);
      expect(top, closeTo(strip, 1e-6));
    });

    testWidgets("TC-HIST-02 nothing is drawn when no bar is positive", (
      tester,
    ) async {
      await _pump(tester, () => [hist((i) => i.isEven ? double.nan : 0)]);
      expect(_boxes(_histColor), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, () => [hist((i) => -5)]);
      expect(tester.takeException(), isNull);
      expect(_boxes(_histColor), findsNothing);
    });

    testWidgets("TC-HIST-02b a negative bar among positive ones is ignored", (
      tester,
    ) async {
      await _pump(tester, () => [hist((i) => i == 3 ? -5 : 10)], count: 10);
      expect(tester.takeException(), isNull);
      // 9 positive bars plus the baseline.
      final tall = [
        for (var i = 0; i < _boxes(_histColor).evaluate().length; i++)
          tester.getRect(_boxes(_histColor).at(i)).height,
      ].where((v) => v > 1.5);
      expect(tall.length, 9);
    });

    testWidgets("TC-HIST-03 tap reports the index; hover enter and exit", (
      tester,
    ) async {
      final taps = <int>[];
      final hovers = <int?>[];
      final h = await _pump(
        tester,
        () => [
          hist((i) => 10, fraction: 0.5, onTap: taps.add, onHover: hovers.add),
        ],
        count: 20,
        slotExtent: 20,
      );
      // Bars sit at the bottom of the viewport.
      final origin = tester.getTopLeft(_chartFinder);
      Offset bar(int i) =>
          origin + Offset(h.ctx.xOf(i), h.ctx.viewportHeight - 10);

      await tester.tapAt(bar(5));
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, [5]);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: bar(1));
      await tester.pump();
      await mouse.moveTo(bar(2));
      await tester.pump();
      expect(hovers, [1, null, 2]);
    });
  });

  group("lines", () {
    testWidgets(
      "TC-LINE-01 one segment per consecutive pair, correctly angled",
      (tester) async {
        final h = await _pump(
          tester,
          () => [
            LineLayer<int>(valueOf: (i) => 10.0 + i * 2, color: _lineColor),
          ],
          count: 10,
          slotExtent: 30,
        );
        final segments = find.descendant(
          of: find.byWidgetPredicate((w) => w is Positioned && w.height == 1.5),
          matching: find.byType(Transform),
        );
        expect(segments, findsNWidgets(9));

        // Every segment has the same slope: dy between neighbours / one slot.
        final dy = h.ctx.yOf(12) - h.ctx.yOf(10);
        final expectedAngle = math.atan2(dy, 30);
        for (var i = 0; i < 9; i++) {
          final m = tester.widget<Transform>(segments.at(i)).transform.storage;
          expect(math.atan2(m[1], m[0]), closeTo(expectedAngle, 1e-9));
        }
        // And each one is as long as the distance between its two points.
        final lengths = tester
            .widgetList<Positioned>(
              find.byWidgetPredicate((w) => w is Positioned && w.height == 1.5),
            )
            .map((p) => p.width!)
            .toList();
        for (final length in lengths) {
          expect(length, closeTo(math.sqrt(30 * 30 + dy * dy), 1e-9));
        }
      },
    );

    testWidgets("TC-LINE-03 fill draws one 15% strip per visible point", (
      tester,
    ) async {
      final h = await _pump(
        tester,
        () => [
          LineLayer<int>(
            valueOf: (i) => 10.0 + i,
            color: _lineColor,
            fill: true,
          ),
        ],
        count: 12,
        slotExtent: 20,
      );
      final fillColor = _lineColor.withValues(alpha: 0.15);
      final strips = _boxes(fillColor);
      expect(strips, findsNWidgets(12));
      // Each strip runs from the line down to the bottom of the viewport.
      final origin = tester.getTopLeft(_chartFinder);
      for (var i = 0; i < 12; i++) {
        final r = tester.getRect(strips.at(i));
        expect(r.top - origin.dy, closeTo(h.ctx.yOf(10.0 + i), 1e-6));
        expect(r.bottom - origin.dy, closeTo(h.ctx.viewportHeight, 1e-6));
      }
    });

    testWidgets("no fill strips by default", (tester) async {
      await _pump(
        tester,
        () => [LineLayer<int>(valueOf: (i) => 10.0 + i, color: _lineColor)],
        count: 12,
      );
      expect(_boxes(_lineColor.withValues(alpha: 0.15)), findsNothing);
    });

    group("TC-LINE-04 point hit targets", () {
      Finder targets() => find.byWidgetPredicate(
        (w) => w is MouseRegion,
        description: "MouseRegion",
      );

      int hitTargets(WidgetTester tester) => [
        for (var i = 0; i < tester.widgetList(targets()).length; i++)
          tester.getSize(targets().at(i)),
      ].where((s) => s == const Size(12, 12)).length;

      testWidgets("none without callbacks", (tester) async {
        await _pump(
          tester,
          () => [LineLayer<int>(valueOf: (i) => 10.0 + i)],
          count: 15,
          slotExtent: 20,
        );
        expect(hitTargets(tester), 0);
      });

      testWidgets(
        "12 px targets with a callback, tap and hover report the index",
        (tester) async {
          final taps = <int>[];
          final hovers = <int?>[];
          final h = await _pump(
            tester,
            () => [
              LineLayer<int>(
                valueOf: (i) => 10.0 + i,
                onPointTap: taps.add,
                onPointHover: hovers.add,
              ),
            ],
            count: 15,
            slotExtent: 20,
          );
          expect(hitTargets(tester), 15);

          final origin = tester.getTopLeft(_chartFinder);
          Offset point(int i) =>
              origin + Offset(h.ctx.xOf(i), h.ctx.yOf(10.0 + i));
          await tester.tapAt(point(7));
          await tester.pump(const Duration(milliseconds: 400));
          expect(taps, [7]);

          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: point(3));
          await tester.pump();
          await mouse.moveTo(point(4));
          await tester.pump();
          expect(hovers, [3, null, 4]);
        },
      );
    });
  });

  group("latest-point marker", () {
    LineLayer<int> withMarker(
      Widget Function(BuildContext, int, int) builder, {
      double Function(int)? value,
    }) => LineLayer<int>(
      valueOf: value ?? (i) => 10.0 + i % 7,
      latestPointBuilder: (context, datum, index) =>
          builder(context, datum, index),
    );

    testWidgets("TC-LINE-06 not built while the last datum is off screen", (
      tester,
    ) async {
      var built = 0;
      final h = await _pump(
        tester,
        () => [
          withMarker((c, d, i) {
            built++;
            return const SizedBox.square(key: Key("m"), dimension: 6);
          }),
        ],
        count: 1000,
      );
      expect(built, 0);
      expect(find.byKey(const Key("m")), findsNothing);

      h.controller.jumpToLatest();
      await tester.pumpAndSettle();
      expect(built, greaterThan(0));
      expect(find.byKey(const Key("m")), findsOneWidget);

      // And away again.
      h.ctx.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key("m")), findsNothing);
    });

    testWidgets("TC-LINE-07 no marker when the last value is NaN or infinite", (
      tester,
    ) async {
      for (final bad in [double.nan, double.infinity]) {
        await tester.pumpWidget(const SizedBox());
        await _pump(
          tester,
          () => [
            withMarker(
              (c, d, i) => const SizedBox.square(key: Key("m"), dimension: 6),
              value: (i) => i == 9 ? bad : 10.0 + i,
            ),
          ],
          count: 10,
        );
        expect(find.byKey(const Key("m")), findsNothing, reason: "$bad");
      }
    });

    for (final size in [5.0, 6.0, 17.0]) {
      testWidgets("TC-LINE-08 centred on the point for a $size px marker", (
        tester,
      ) async {
        final h = await _pump(
          tester,
          () => [
            withMarker(
              (c, d, i) =>
                  SizedBox.square(key: const Key("m"), dimension: size),
              value: (i) => 10.0 + i,
            ),
          ],
          count: 20,
          anchor: ChartAnchor.right,
        );
        final centre = tester.getCenter(find.byKey(const Key("m")));
        final origin = tester.getTopLeft(_chartFinder);
        expect(centre.dx - origin.dx, closeTo(h.ctx.xOf(19), 0.01));
        expect(centre.dy - origin.dy, closeTo(h.ctx.yOf(29), 0.01));
      });
    }

    testWidgets("TC-LINE-09 the marker does not take pointer events", (
      tester,
    ) async {
      var markerTapped = false;
      final h = await _pump(
        tester,
        () => [
          withMarker(
            (c, d, i) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => markerTapped = true,
              onPanUpdate: (_) => markerTapped = true,
              child: const SizedBox.square(key: Key("m"), dimension: 40),
            ),
            value: (i) => 10.0 + i,
          ),
        ],
        count: 400,
        anchor: ChartAnchor.right,
      );
      final at = tester.getCenter(find.byKey(const Key("m")));

      // Hover shows the crosshair at the last slot.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: at);
      await mouse.moveTo(at + const Offset(1, 0));
      await tester.pump();
      expect(h.controller.highlightedIndex, 399);

      // A drag that starts on the marker pans the chart.
      final before = h.ctx.scrollOffset;
      await tester.dragFrom(at, const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(h.ctx.scrollOffset, isNot(before));
      expect(markerTapped, isFalse);
    });

    testWidgets("TC-LINE-10 a live tick moves the marker and keeps its state", (
      tester,
    ) async {
      var inits = 0;
      var values = [for (var i = 0; i < 20; i++) 10.0 + i];
      final h = _bare(
        () => [
          LineLayer<int>(
            valueOf: (i) => values[i],
            latestPointBuilder: (_, _, _) => _CountingMarker(() => inits++),
          ),
        ],
        anchor: ChartAnchor.right,
      );
      await tester.pumpWidget(h.app(intSeries(0, 20)));
      await tester.pumpAndSettle();
      expect(inits, 1);
      final y0 = tester.getCenter(find.byKey(const Key("counting"))).dy;

      // The last bar's value changes (same length).
      values = [...values]..[19] = 15;
      await tester.pumpWidget(h.app(intSeries(0, 20)));
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.byKey(const Key("counting"))).dy, isNot(y0));
      expect(inits, 1, reason: "state lost on a same-length tick");

      // A new bar arrives: one more segment before the marker in the stack.
      values = [...values, 16];
      await tester.pumpWidget(h.app(intSeries(0, 21)));
      await tester.pumpAndSettle();
      h.controller.jumpToLatest();
      await tester.pumpAndSettle();
      expect(inits, 1, reason: "state lost when a bar was appended");

      // Panning changes how many segments are visible.
      await tester.drag(
        find.byType(InteractiveChart<int>),
        const Offset(30, 0),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(InteractiveChart<int>),
        const Offset(-30, 0),
      );
      await tester.pumpAndSettle();
      expect(inits, 1, reason: "state lost while panning");
    });
  });
}

class _CountingMarker extends StatefulWidget {
  const _CountingMarker(this.onInit) : super(key: const Key("counting"));
  final VoidCallback onInit;

  @override
  State<_CountingMarker> createState() => _CountingMarkerState();
}

class _CountingMarkerState extends State<_CountingMarker> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.square(dimension: 8);
}
