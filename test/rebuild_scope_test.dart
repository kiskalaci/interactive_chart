// Test plan section 15: TC-PERF-04 (R-PERF-4). Moving the crosshair must not
// rebuild or repaint the layers that do not draw it, while pans, zooms and
// data changes still rebuild everything. See docs/poc_notes.md.
import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart" hide testWidgets;
import "package:interactive_chart/interactive_chart.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/time_axis/time_ticks.dart";

import "support/chart_harness.dart";
import "support/variants.dart";

final _chartFinder = find.byType(InteractiveChart<int>);

/// Counts its builds, and the paints of a [CustomPaint] it builds.
class _CountingLayer extends ChartLayer<int> {
  _CountingLayer({this.highlight = false});

  final bool highlight;
  int builds = 0;
  int paints = 0;
  int? lastSeenHighlight;

  @override
  bool get dependsOnHighlight => highlight;

  @override
  Widget build(Size size, InteractiveChartContext ctx, List<int> data) {
    builds++;
    lastSeenHighlight = ctx.highlightedIndex;
    return CustomPaint(size: size, painter: _CountingPainter(this));
  }
}

class _CountingPainter extends CustomPainter {
  _CountingPainter(this.layer);

  final _CountingLayer layer;

  @override
  void paint(Canvas canvas, Size size) {
    layer.paints++;
    canvas.drawRect(Offset.zero & const Size(1, 1), Paint());
  }

  // Always "changed", so a rebuild always repaints: only skipping the
  // rebuild (and the repaint boundary) can keep the count still.
  @override
  bool shouldRepaint(_CountingPainter old) => true;
}

Future<ChartHarness<int>> _pump(
  WidgetTester tester,
  List<ChartLayer<int>> layers, {
  int count = 400,
}) async {
  final h = ChartHarness<int>(timeOf: minuteTime, layers: () => layers);
  await tester.pumpWidget(h.app(intSeries(0, count)));
  await tester.pumpAndSettle();
  return h;
}

Offset _slot(WidgetTester tester, ChartHarness<int> h, int i) =>
    tester.getTopLeft(_chartFinder) +
    Offset(h.ctx.xOf(i), h.ctx.viewportHeight / 2);

void main() {
  group("TC-PERF-04 crosshair moves rebuild only what draws it", () {
    testWidgets("hover leaves other layers unbuilt and unpainted", (
      tester,
    ) async {
      final plain = _CountingLayer();
      final h = await _pump(tester, [
        plain,
        LineLayer<int>(valueOf: (i) => 10.0 + i % 7),
        CrosshairLayer<int>(valueOf: (i) => 10.0 + i % 7, timeOf: minuteTime),
      ]);
      final builds = plain.builds;
      final paints = plain.paints;

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: _slot(tester, h, 5));
      await tester.pump();
      for (var i = 6; i < 20; i++) {
        await mouse.moveTo(_slot(tester, h, i));
        await tester.pump();
      }
      expect(h.controller.highlightedIndex, 19);
      expect(plain.builds, builds, reason: "rebuilt on a highlight change");
      expect(plain.paints, paints, reason: "repainted on a highlight change");

      await mouse.moveTo(
        tester.getBottomRight(_chartFinder) + const Offset(9, 9),
      );
      await tester.pump();
      expect(h.controller.highlightedIndex, isNull);
      expect(plain.builds, builds);
    });

    testWidgets("the crosshair still follows the pointer", (tester) async {
      const lineColor = Color(0xFF0A0B0C);
      final h = await _pump(tester, [
        CrosshairLayer<int>(
          valueOf: (i) => 10.0 + i % 7,
          timeOf: minuteTime,
          lineColor: lineColor,
        ),
      ]);
      final vertical = find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == lineColor,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: _slot(tester, h, 3));
      await tester.pump();
      for (final i in [3, 8, 12]) {
        await mouse.moveTo(_slot(tester, h, i));
        await tester.pump();
        final x =
            tester.getRect(vertical.first).left -
            tester.getTopLeft(_chartFinder).dx;
        expect(x, closeTo(h.ctx.xOf(i), 1e-6));
      }
    });

    testWidgets("a custom layer that depends on the highlight is rebuilt", (
      tester,
    ) async {
      final follower = _CountingLayer(highlight: true);
      final plain = _CountingLayer();
      final h = await _pump(tester, [plain, follower]);
      final plainBuilds = plain.builds;
      final followerBuilds = follower.builds;

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: _slot(tester, h, 4));
      await tester.pump();
      await mouse.moveTo(_slot(tester, h, 9));
      await tester.pump();

      expect(follower.lastSeenHighlight, 9);
      expect(follower.builds, greaterThan(followerBuilds));
      expect(plain.builds, plainBuilds);
    });

    testWidgets("a tap that places the crosshair rebuilds only it", (
      tester,
    ) async {
      final plain = _CountingLayer();
      final follower = _CountingLayer(highlight: true);
      final h = await _pump(tester, [plain, follower]);
      final builds = plain.builds;
      await tester.tapAt(_slot(tester, h, 7));
      await tester.pump(const Duration(milliseconds: 400));
      expect(h.controller.highlightedIndex, 7);
      expect(follower.lastSeenHighlight, 7);
      expect(plain.builds, builds);
    });

    testWidgets("highlight callbacks still fire on every move", (tester) async {
      final reported = <int?>[];
      final h = ChartHarness<int>(timeOf: minuteTime, layers: () => []);
      await tester.pumpWidget(
        MaterialApp(
          home: InteractiveChart<int>(
            data: intSeries(0, 200),
            timeOf: minuteTime,
            initialAnchor: ChartAnchor.left,
            controller: h.controller,
            onIndexHighlighted: reported.add,
            layers: [ContextProbe<int>((c) => h.ctx = c)],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: _slot(tester, h, 1));
      await tester.pump();
      await mouse.moveTo(_slot(tester, h, 2));
      await tester.pump();
      await mouse.moveTo(_slot(tester, h, 6));
      await tester.pump();
      expect(reported, containsAllInOrder(<int?>[2, 6]));
    });
  });

  group("view and data changes still rebuild every layer", () {
    testWidgets("a pan rebuilds and repaints", (tester) async {
      final plain = _CountingLayer();
      final h = await _pump(tester, [plain]);
      final builds = plain.builds;
      final paints = plain.paints;
      await tester.drag(_chartFinder, const Offset(-80, 0));
      await tester.pumpAndSettle();
      expect(h.ctx.scrollOffset, greaterThan(0));
      expect(plain.builds, greaterThan(builds));
      expect(plain.paints, greaterThan(paints));
    });

    testWidgets("a wheel zoom rebuilds", (tester) async {
      final plain = _CountingLayer();
      final h = await _pump(tester, [plain]);
      final builds = plain.builds;
      final before = h.ctx.slotExtent;
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(tester.getCenter(_chartFinder)),
      );
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
      await tester.pump();
      expect(h.ctx.slotExtent, greaterThan(before));
      expect(plain.builds, greaterThan(builds));
    });

    testWidgets("a value-axis zoom and autoscale toggle rebuild", (
      tester,
    ) async {
      final plain = _CountingLayer();
      final h = await _pump(tester, [plain]);
      var builds = plain.builds;
      h.ctx.zoomValueExtent(0.5, 100);
      await tester.pump();
      expect(plain.builds, greaterThan(builds));
      builds = plain.builds;
      h.controller.setAutoscale(true);
      await tester.pump();
      expect(plain.builds, greaterThan(builds));
    });

    testWidgets("new data rebuilds", (tester) async {
      final plain = _CountingLayer();
      final h = ChartHarness<int>(timeOf: minuteTime, layers: () => [plain]);
      await tester.pumpWidget(h.app(intSeries(0, 100)));
      await tester.pumpAndSettle();
      final builds = plain.builds;
      await tester.pumpWidget(h.app(intSeries(0, 101)));
      await tester.pump();
      expect(plain.builds, greaterThan(builds));
    });
  });

  group("context notifications", () {
    test("highlight changes notify highlightChanges, not viewChanges", () {
      final ctx = InteractiveChartContext()
        ..setSlotCount(100)
        ..setViewportSize(400, 200);
      var view = 0;
      var highlight = 0;
      var all = 0;
      ctx.viewChanges.addListener(() => view++);
      ctx.highlightChanges.addListener(() => highlight++);
      ctx
        ..addListener(() => all++)
        ..setHighlighted(3);
      expect((view, highlight, all), (0, 1, 1));
      ctx.setHighlighted(3); // unchanged: nothing
      expect((view, highlight, all), (0, 1, 1));

      ctx
        ..panBy(10)
        ..jumpTo(0)
        ..setSlotExtentAndScroll(10, 0)
        ..panValueByPixels(5)
        ..zoomValueExtent(0.5, 0.5)
        ..setAutoscale(true)
        ..announce();
      expect((view, highlight, all), (7, 1, 8));
      ctx.dispose();
    });
  });

  testWidgets(
    "a projected-slot hover with long data shows the projected time",
    (tester) async {
      // 3-minute bars, so the projection must infer the cadence from the
      // newest bars it is given.
      DateTime timeOf(int i) => fixtureStart.add(Duration(minutes: 3 * i));
      final h = ChartHarness<int>(
        timeOf: timeOf,
        anchor: ChartAnchor.right,
        valueAxis: null,
        timeAxis: null,
        layers: () => [LineLayer<int>(valueOf: (i) => i.toDouble())],
      );
      final data = intSeries(0, 50000);
      await tester.pumpWidget(h.app(data));
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(_chartFinder);
      final index = data.length + 3;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(
        location: origin + Offset(h.ctx.xOf(index), h.ctx.viewportHeight / 2),
      );
      await tester.pump();
      await mouse.moveTo(
        origin + Offset(h.ctx.xOf(index) + 1, h.ctx.viewportHeight / 2),
      );
      await tester.pump();
      expect(h.ctx.highlightedIndex, index);
      final all = [for (final d in data) timeOf(d)];
      expect(h.ctx.highlightedProjectedTime, projectTimes(all, 4).last);
      expect(h.ctx.highlightedProjectedTime, timeOf(index));
    },
  );
}
