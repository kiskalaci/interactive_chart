// Test plan section 4: pan and zoom gestures (TC-GEST-*).
// TC-GEST-02 (horizontal drag keeps autoscale on) is in test/prepend_test.dart.
// See docs/poc_notes.md.
import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart" hide testWidgets;
import "package:interactive_chart/interactive_chart.dart";

import "support/chart_harness.dart";
import "support/variants.dart";

/// No axes, so the viewport is the whole widget and global x minus the
/// widget's left edge is the viewport-local x.
ChartHarness<int> _chart({
  ChartAnchor anchor = ChartAnchor.left,
  bool panEnabled = true,
  bool zoomEnabled = true,
  bool crosshairEnabled = true,
  double verticalPanThreshold = 16,
  double slotExtent = 8,
  double minSlotExtent = 1,
  double maxSlotExtent = 64,
}) => ChartHarness<int>(
  timeOf: minuteTime,
  anchor: anchor,
  panEnabled: panEnabled,
  zoomEnabled: zoomEnabled,
  crosshairEnabled: crosshairEnabled,
  verticalPanThreshold: verticalPanThreshold,
  slotExtent: slotExtent,
  minSlotExtent: minSlotExtent,
  maxSlotExtent: maxSlotExtent,
  valueAxis: null,
  timeAxis: null,
  layers: () => [LineLayer<int>(valueOf: (i) => 100.0 + i % 11)],
);

final _chartFinder = find.byType(InteractiveChart<int>);

Future<ChartHarness<int>> _pump(
  WidgetTester tester, {
  int count = 1000,
  ChartAnchor anchor = ChartAnchor.left,
  bool panEnabled = true,
  bool zoomEnabled = true,
  bool crosshairEnabled = true,
  double verticalPanThreshold = 16,
  double slotExtent = 8,
  double minSlotExtent = 1,
  double maxSlotExtent = 64,
}) async {
  final h = _chart(
    anchor: anchor,
    panEnabled: panEnabled,
    zoomEnabled: zoomEnabled,
    crosshairEnabled: crosshairEnabled,
    verticalPanThreshold: verticalPanThreshold,
    slotExtent: slotExtent,
    minSlotExtent: minSlotExtent,
    maxSlotExtent: maxSlotExtent,
  );
  await tester.pumpWidget(h.app(intSeries(0, count)));
  await tester.pumpAndSettle();
  return h;
}

/// Viewport-local x of a global x.
double _localX(WidgetTester tester, double globalX) =>
    globalX - tester.getRect(_chartFinder).left;

/// A mouse-wheel scroll of [delta] with the pointer at [at].
Future<void> _wheel(WidgetTester tester, Offset at, Offset delta) async {
  final pointer = TestPointer(1, PointerDeviceKind.mouse)..hover(at);
  await tester.sendEventToBinding(pointer.scroll(delta));
  await tester.pump();
}

/// Two-finger pinch about [center]. The span goes from [startSpan] to
/// [endSpan] in [steps] equal steps while the midpoint travels by [pan].
Future<void> _pinch(
  WidgetTester tester, {
  required Offset center,
  required double startSpan,
  required double endSpan,
  int? steps,
  Offset pan = Offset.zero,
  bool release = true,
}) async {
  // Fingers are dispatched one after the other, so the midpoint is briefly
  // off-centre by half a step. Keep steps small (about 2 px of span) so that
  // artefact stays well under a pixel.
  final count =
      steps ?? ((endSpan - startSpan).abs() / 2).ceil().clamp(10, 600);
  Offset left(double span, Offset mid) => mid - Offset(span / 2, 0);
  Offset right(double span, Offset mid) => mid + Offset(span / 2, 0);

  final a = await tester.startGesture(left(startSpan, center), pointer: 1);
  final b = await tester.startGesture(right(startSpan, center), pointer: 2);
  for (var i = 1; i <= count; i++) {
    final t = i / count;
    final span = startSpan + (endSpan - startSpan) * t;
    final mid = center + pan * t;
    await a.moveTo(left(span, mid));
    await b.moveTo(right(span, mid));
    await tester.pump();
  }
  if (release) {
    await a.up();
    await b.up();
    await tester.pump();
  }
}

void main() {
  group("TC-GEST-01 horizontal drag pans x", () {
    testWidgets("by the drag distance", (tester) async {
      final h = await _pump(tester);
      await tester.drag(_chartFinder, const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(h.ctx.scrollOffset, closeTo(300, 1));
      expect(h.ctx.slotExtent, 8);
    });

    testWidgets("dragging right moves back toward the start", (tester) async {
      final h = await _pump(tester, anchor: ChartAnchor.right);
      final before = h.ctx.scrollOffset;
      await tester.drag(_chartFinder, const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(h.ctx.scrollOffset, closeTo(before - 200, 1));
    });

    testWidgets("clamped at both ends", (tester) async {
      final h = await _pump(tester, count: 200);
      await tester.drag(
        _chartFinder,
        const Offset(5000, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(h.ctx.scrollOffset, 0);

      await tester.drag(
        _chartFinder,
        const Offset(-5000, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(h.ctx.scrollOffset, h.ctx.maxScrollOffset);
    });

    testWidgets("successive drags accumulate", (tester) async {
      final h = await _pump(tester);
      await tester.drag(_chartFinder, const Offset(-100, 0));
      await tester.pumpAndSettle();
      await tester.drag(_chartFinder, const Offset(-150, 0));
      await tester.pumpAndSettle();
      expect(h.ctx.scrollOffset, closeTo(250, 2));
    });
  });

  group("pan and pinch work on empty space, with or without the crosshair", () {
    for (final crosshair in [true, false]) {
      testWidgets("crosshair enabled: $crosshair", (tester) async {
        // A flat, low line: the point where the finger lands is empty.
        final h = ChartHarness<int>(
          timeOf: minuteTime,
          crosshairEnabled: crosshair,
          valueAxis: null,
          timeAxis: null,
          layers: () => [LineLayer<int>(valueOf: (i) => i < 0 ? 0 : 5)],
        );
        await tester.pumpWidget(h.app(intSeries(0, 400)));
        await tester.pumpAndSettle();
        final origin = tester.getTopLeft(_chartFinder);
        final w = tester.getSize(_chartFinder).width;
        final empty = origin + Offset(w * 0.7, 40); // far from the line

        final finger = await tester.startGesture(empty);
        for (var i = 1; i <= 10; i++) {
          await finger.moveTo(empty + Offset(-10.0 * i, 0));
          await tester.pump();
        }
        await finger.up();
        await tester.pumpAndSettle();
        expect(h.ctx.scrollOffset, closeTo(100, 0.5));

        final before = h.ctx.slotExtent;
        await _pinch(
          tester,
          center: origin + Offset(w * 0.5, 40),
          startSpan: w * 0.3,
          endSpan: w * 0.6,
        );
        expect(h.ctx.slotExtent, greaterThan(before * 1.5));
      });
    }
  });

  testWidgets("TC-GEST-03 vertical movement pans the value extent", (
    tester,
  ) async {
    final h = await _pump(tester);
    final probe = (h.ctx.valueMin + h.ctx.valueMax) / 2;
    final yBefore = h.ctx.yOf(probe);
    final span = h.ctx.valueMax - h.ctx.valueMin;
    expect(h.controller.autoscale, isTrue);

    await tester.drag(_chartFinder, const Offset(-60, 80));
    await tester.pumpAndSettle();

    expect(h.controller.autoscale, isFalse);
    // Direct manipulation: the value under the finger moves down with it,
    // less the small distance travelled before vertical panning engaged.
    final moved = h.ctx.yOf(probe) - yBefore;
    expect(moved, inInclusiveRange(80 - 40, 80));
    // The window keeps its size; it only slides.
    expect(h.ctx.valueMax - h.ctx.valueMin, closeTo(span, span * 1e-9));
    // And x panned too.
    expect(h.ctx.scrollOffset, closeTo(60, 2));
  });

  group("TC-GEST-03b vertical panning needs deliberate vertical movement", () {
    testWidgets("a horizontal drag with a little vertical wobble keeps "
        "autoscale on", (tester) async {
      final h = await _pump(tester);
      await tester.drag(_chartFinder, const Offset(-200, 20));
      await tester.pumpAndSettle();
      expect(h.controller.autoscale, isTrue);
      expect(h.ctx.scrollOffset, closeTo(200, 2));
    });

    testWidgets("a long horizontal swipe that drifts keeps autoscale on", (
      tester,
    ) async {
      final h = await _pump(tester);
      // 60 px of vertical travel is over the minimum, but a long way short of
      // half the 400 px of horizontal travel.
      await tester.drag(_chartFinder, const Offset(-400, 60));
      await tester.pumpAndSettle();
      expect(h.controller.autoscale, isTrue);
    });

    testWidgets("a deliberate vertical drag still pans the value axis", (
      tester,
    ) async {
      final h = await _pump(tester);
      await tester.drag(_chartFinder, const Offset(0, 80));
      await tester.pumpAndSettle();
      expect(h.controller.autoscale, isFalse);
    });

    testWidgets("a drag past the default threshold pans", (tester) async {
      final h = await _pump(tester);
      await tester.drag(_chartFinder, const Offset(0, 30));
      await tester.pumpAndSettle();
      expect(h.controller.autoscale, isFalse);
    });

    testWidgets("verticalPanThreshold raises how far a drag must go", (
      tester,
    ) async {
      final h = await _pump(tester, verticalPanThreshold: 60);
      await tester.drag(_chartFinder, const Offset(0, 30));
      await tester.pumpAndSettle();
      expect(h.controller.autoscale, isTrue);
      await tester.drag(_chartFinder, const Offset(0, 100));
      await tester.pumpAndSettle();
      expect(h.controller.autoscale, isFalse);
    });

    testWidgets("a zero threshold still ignores a purely horizontal drag", (
      tester,
    ) async {
      final h = await _pump(tester, verticalPanThreshold: 0);
      await tester.drag(_chartFinder, const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(h.controller.autoscale, isTrue);
    });

    testWidgets("a steep diagonal drag pans both axes", (tester) async {
      final h = await _pump(tester);
      await tester.drag(_chartFinder, const Offset(-60, 80));
      await tester.pumpAndSettle();
      expect(h.controller.autoscale, isFalse);
      expect(h.ctx.scrollOffset, closeTo(60, 2));
    });
  });

  // Pinch geometry is relative to the chart's width, so the same test runs on
  // a phone-sized and a desktop-sized screen.
  group("pinch zoom", () {
    testWidgets("TC-GEST-04 the datum under the focal point stays put", (
      tester,
    ) async {
      final h = await _pump(tester);
      await tester.drag(_chartFinder, const Offset(-400, 0));
      await tester.pumpAndSettle();

      final rect = tester.getRect(_chartFinder);
      final w = rect.width;
      final center = Offset(rect.left + w * 0.5, rect.center.dy);
      final fx = _localX(tester, center.dx);
      final indexBefore = h.ctx.fractionalIndexAtViewportX(fx);
      final extentBefore = h.ctx.slotExtent;

      await _pinch(
        tester,
        center: center,
        startSpan: w * 0.2,
        endSpan: w * 0.6,
        release: false,
      );
      // Mid-gesture, not only at the end.
      expect(h.ctx.slotExtent, closeTo(extentBefore * 3, extentBefore * 0.15));
      expect(
        h.ctx.fractionalIndexAtViewportX(fx),
        closeTo(indexBefore, 1 / extentBefore),
      );
    });

    testWidgets("zooming out holds the focal point too", (tester) async {
      final h = await _pump(tester, slotExtent: 24);
      // Deep enough into the data that zooming out never has to scroll past
      // the first bar, whatever the width.
      await tester.drag(
        _chartFinder,
        Offset(-tester.getSize(_chartFinder).width * 1.5, 0),
      );
      await tester.pumpAndSettle();
      final rect = tester.getRect(_chartFinder);
      final w = rect.width;
      final center = Offset(rect.left + w * 0.5, rect.center.dy);
      final fx = _localX(tester, center.dx);
      final indexBefore = h.ctx.fractionalIndexAtViewportX(fx);
      final extentBefore = h.ctx.slotExtent;

      await _pinch(
        tester,
        center: center,
        startSpan: w * 0.6,
        endSpan: w * 0.3,
        release: false,
      );
      expect(h.ctx.slotExtent, lessThan(extentBefore));
      expect(
        h.ctx.fractionalIndexAtViewportX(fx),
        closeTo(indexBefore, 1 / extentBefore),
      );
    });

    testWidgets("TC-GEST-05 no cumulative drift over many update events", (
      tester,
    ) async {
      final h = await _pump(tester);
      await tester.drag(_chartFinder, const Offset(-500, 0));
      await tester.pumpAndSettle();

      final rect = tester.getRect(_chartFinder);
      final w = rect.width;
      final center = Offset(rect.left + w * 0.3, rect.center.dy);
      final startFx = _localX(tester, center.dx);
      final index = h.ctx.fractionalIndexAtViewportX(startFx);
      final extentBefore = h.ctx.slotExtent;

      // Pinch out (3x) while the midpoint also drifts right by 20 % of the
      // width. Small steps, so there are well over a hundred update events.
      final drift = w * 0.2;
      await _pinch(
        tester,
        center: center,
        startSpan: w * 0.25,
        endSpan: w * 0.75,
        pan: Offset(drift, 0),
        release: false,
      );

      // The content that was under the starting midpoint is still under the
      // (moved) midpoint.
      expect(
        h.ctx.fractionalIndexAtViewportX(startFx + drift),
        closeTo(index, 1 / extentBefore),
      );
      // And the zoom matches the span ratio, not an accumulated error.
      expect(h.ctx.slotExtent, closeTo(extentBefore * 3, extentBefore * 0.15));
    });

    testWidgets("TC-GEST-06 clamped at the maximum and minimum", (
      tester,
    ) async {
      final h = await _pump(tester, maxSlotExtent: 20, minSlotExtent: 4);
      await tester.drag(_chartFinder, const Offset(-400, 0));
      await tester.pumpAndSettle();

      final rect = tester.getRect(_chartFinder);
      final w = rect.width;
      final center = Offset(rect.left + w * 0.5, rect.center.dy);
      final fx = _localX(tester, center.dx);
      final index = h.ctx.fractionalIndexAtViewportX(fx);

      await _pinch(
        tester,
        center: center,
        startSpan: w * 0.1,
        endSpan: w * 0.9,
        release: false,
      );
      expect(h.ctx.slotExtent, 20);
      // Focal point is held even while clamped.
      expect(h.ctx.fractionalIndexAtViewportX(fx), closeTo(index, 1 / 8));
    });

    testWidgets("TC-GEST-06b pinching back reverses without sticking", (
      tester,
    ) async {
      final h = await _pump(tester, maxSlotExtent: 20, minSlotExtent: 4);
      final rect = tester.getRect(_chartFinder);
      final w = rect.width;
      final center = Offset(rect.left + w * 0.5, rect.center.dy);
      final start = h.ctx.slotExtent;
      final low = w * 0.1;
      final high = w * 0.95;
      final step = w * 0.05;

      final a = await tester.startGesture(
        center - Offset(low / 2, 0),
        pointer: 1,
      );
      final b = await tester.startGesture(
        center + Offset(low / 2, 0),
        pointer: 2,
      );
      // Far past the maximum...
      for (var s = low; s <= high; s += step) {
        await a.moveTo(center - Offset(s / 2, 0));
        await b.moveTo(center + Offset(s / 2, 0));
        await tester.pump();
      }
      expect(h.ctx.slotExtent, 20);
      // ...and back to the starting span.
      for (var s = high; s >= low; s -= step) {
        await a.moveTo(center - Offset(s / 2, 0));
        await b.moveTo(center + Offset(s / 2, 0));
        await tester.pump();
      }
      await a.moveTo(center - Offset(low / 2, 0));
      await b.moveTo(center + Offset(low / 2, 0));
      await tester.pump();
      expect(h.ctx.slotExtent, closeTo(start, 0.5));
      await a.up();
      await b.up();
    });

    testWidgets("TC-GEST-06c clamped at the minimum", (tester) async {
      final h = await _pump(tester, minSlotExtent: 4, slotExtent: 10);
      final rect = tester.getRect(_chartFinder);
      await _pinch(
        tester,
        center: rect.center,
        startSpan: rect.width * 0.8,
        endSpan: rect.width * 0.1,
        release: false,
      );
      expect(h.ctx.slotExtent, 4);
    });
  });

  group("mouse wheel", () {
    testWidgets("TC-GEST-07 vertical wheel zooms x at the pointer", (
      tester,
    ) async {
      final h = await _pump(tester);
      await tester.drag(_chartFinder, const Offset(-600, 0));
      await tester.pumpAndSettle();

      final rect = tester.getRect(_chartFinder);
      final at = Offset(rect.left + 250, rect.center.dy);
      final fx = _localX(tester, at.dx);
      final index = h.ctx.fractionalIndexAtViewportX(fx);
      final extent = h.ctx.slotExtent;

      await _wheel(tester, at, const Offset(0, -200)); // scroll up: zoom in
      expect(h.ctx.slotExtent, greaterThan(extent));
      expect(
        h.ctx.fractionalIndexAtViewportX(fx),
        closeTo(index, 0.5 / h.ctx.slotExtent),
      );

      final zoomedIn = h.ctx.slotExtent;
      await _wheel(tester, at, const Offset(0, 400)); // scroll down: zoom out
      expect(h.ctx.slotExtent, lessThan(zoomedIn));
      expect(
        h.ctx.fractionalIndexAtViewportX(fx),
        closeTo(index, 0.5 / h.ctx.slotExtent),
      );
    });

    testWidgets("wheel zoom is clamped", (tester) async {
      final h = await _pump(tester, maxSlotExtent: 16, minSlotExtent: 6);
      final at = tester.getCenter(_chartFinder);
      await _wheel(tester, at, const Offset(0, -5000));
      expect(h.ctx.slotExtent, 16);
      await _wheel(tester, at, const Offset(0, 9000));
      expect(h.ctx.slotExtent, 6);
    });

    testWidgets("TC-GEST-08 horizontal-dominant scroll pans, no zoom", (
      tester,
    ) async {
      final h = await _pump(tester);
      final at = tester.getCenter(_chartFinder);
      await _wheel(tester, at, const Offset(120, 10));
      expect(h.ctx.slotExtent, 8);
      expect(h.ctx.scrollOffset, closeTo(120, 0.001));

      await _wheel(tester, at, const Offset(-50, 0));
      expect(h.ctx.scrollOffset, closeTo(70, 0.001));
      expect(h.ctx.slotExtent, 8);
    });

    testWidgets("a diagonal scroll with equal parts zooms", (tester) async {
      final h = await _pump(tester);
      await _wheel(
        tester,
        tester.getCenter(_chartFinder),
        const Offset(40, -40),
      );
      expect(h.ctx.slotExtent, isNot(8));
    });

    testWidgets("TC-GEST-09 vertical-only wheel pans when zoom is off", (
      tester,
    ) async {
      final h = await _pump(tester, zoomEnabled: false);
      await _wheel(tester, tester.getCenter(_chartFinder), const Offset(0, 90));
      expect(h.ctx.slotExtent, 8);
      expect(h.ctx.scrollOffset, closeTo(90, 0.001));
    });
  });

  group("TC-GEST-10 panEnabled: false", () {
    testWidgets("drag does nothing", (tester) async {
      final h = await _pump(tester, panEnabled: false);
      final before = h.ctx.scrollOffset;
      await tester.drag(_chartFinder, const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(h.ctx.scrollOffset, before);
      expect(h.controller.autoscale, isTrue);
    });

    testWidgets("vertical drag does not pan the value extent", (tester) async {
      final h = await _pump(tester, panEnabled: false);
      final (lo, hi) = (h.ctx.valueMin, h.ctx.valueMax);
      await tester.drag(_chartFinder, const Offset(0, 100));
      await tester.pumpAndSettle();
      expect((h.ctx.valueMin, h.ctx.valueMax), (lo, hi));
      expect(h.controller.autoscale, isTrue);
    });

    testWidgets("horizontal scroll does nothing", (tester) async {
      final h = await _pump(tester, panEnabled: false);
      await _wheel(
        tester,
        tester.getCenter(_chartFinder),
        const Offset(150, 0),
      );
      expect(h.ctx.scrollOffset, 0);
    });

    testWidgets("wheel zoom still works", (tester) async {
      final h = await _pump(tester, panEnabled: false);
      await _wheel(
        tester,
        tester.getCenter(_chartFinder),
        const Offset(0, -200),
      );
      expect(h.ctx.slotExtent, greaterThan(8));
    });

    testWidgets("pinch still zooms", (tester) async {
      final h = await _pump(tester, panEnabled: false);
      await _pinch(
        tester,
        center: tester.getCenter(_chartFinder),
        startSpan: 100,
        endSpan: 250,
      );
      expect(h.ctx.slotExtent, greaterThan(14));
    });
  });

  group("TC-GEST-11 zoomEnabled: false", () {
    testWidgets("pinch does not change the slot extent", (tester) async {
      final h = await _pump(tester, zoomEnabled: false);
      await _pinch(
        tester,
        center: tester.getCenter(_chartFinder),
        startSpan: 100,
        endSpan: 300,
      );
      expect(h.ctx.slotExtent, 8);
    });

    testWidgets("vertical wheel does not zoom", (tester) async {
      final h = await _pump(tester, zoomEnabled: false);
      await _wheel(
        tester,
        tester.getCenter(_chartFinder),
        const Offset(0, -400),
      );
      expect(h.ctx.slotExtent, 8);
    });

    testWidgets("drag still pans", (tester) async {
      final h = await _pump(tester, zoomEnabled: false);
      await tester.drag(_chartFinder, const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(h.ctx.scrollOffset, closeTo(200, 1));
      expect(h.ctx.slotExtent, 8);
    });
  });

  group("TC-GEST-12 pan and zoom both disabled", () {
    testWidgets("no gesture changes the viewport", (tester) async {
      final h = await _pump(tester, panEnabled: false, zoomEnabled: false);
      final center = tester.getCenter(_chartFinder);

      await tester.drag(_chartFinder, const Offset(-300, 40));
      await tester.pumpAndSettle();
      await _wheel(tester, center, const Offset(0, -300));
      await _wheel(tester, center, const Offset(200, 0));
      await _pinch(tester, center: center, startSpan: 100, endSpan: 300);

      expect(h.ctx.scrollOffset, 0);
      expect(h.ctx.slotExtent, 8);
      expect(h.controller.autoscale, isTrue);
    });

    testWidgets("the crosshair still works", (tester) async {
      final h = await _pump(tester, panEnabled: false, zoomEnabled: false);
      final rect = tester.getRect(_chartFinder);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: rect.center);
      await mouse.moveTo(Offset(rect.left + 100, rect.center.dy));
      await tester.pump();
      expect(h.controller.highlightedIndex, isNotNull);
    });
  });

  group("TC-GEST-13 trackpad pinch", () {
    testWidgets("zooms anchored at the focal point", (tester) async {
      final h = await _pump(tester);
      await tester.drag(_chartFinder, const Offset(-500, 0));
      await tester.pumpAndSettle();

      final rect = tester.getRect(_chartFinder);
      final at = Offset(rect.left + 300, rect.center.dy);
      final fx = _localX(tester, at.dx);
      final index = h.ctx.fractionalIndexAtViewportX(fx);
      final extent = h.ctx.slotExtent;

      final pad = TestPointer(7, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(pad.panZoomStart(at));
      for (var i = 1; i <= 10; i++) {
        await tester.sendEventToBinding(
          pad.panZoomUpdate(at, scale: 1 + i * 0.2),
        );
        await tester.pump();
      }
      expect(h.ctx.slotExtent, closeTo(extent * 3, extent * 0.2));
      expect(
        h.ctx.fractionalIndexAtViewportX(fx),
        closeTo(index, 0.5 / h.ctx.slotExtent),
      );
      await tester.sendEventToBinding(pad.panZoomEnd());
      await tester.pump();
    });

    testWidgets("two-finger trackpad pan scrolls x", (tester) async {
      final h = await _pump(tester);
      final at = tester.getCenter(_chartFinder);
      final pad = TestPointer(7, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(pad.panZoomStart(at));
      for (var i = 1; i <= 10; i++) {
        await tester.sendEventToBinding(
          pad.panZoomUpdate(at, pan: Offset(-30.0 * i, 0)),
        );
        await tester.pump();
      }
      await tester.sendEventToBinding(pad.panZoomEnd());
      await tester.pump();
      expect(h.ctx.scrollOffset, closeTo(300, 5));
    });
  });

  group("TC-GEST-14 fast drags and flings", () {
    testWidgets("a fling ends inside the limits", (tester) async {
      final h = await _pump(tester, count: 300);
      await tester.fling(_chartFinder, const Offset(-600, 0), 6000);
      await tester.pumpAndSettle();
      expect(h.ctx.scrollOffset, inInclusiveRange(0, h.ctx.maxScrollOffset));

      await tester.fling(_chartFinder, const Offset(900, 0), 9000);
      await tester.pumpAndSettle();
      expect(h.ctx.scrollOffset, inInclusiveRange(0, h.ctx.maxScrollOffset));
      expect(tester.takeException(), isNull);
    });

    testWidgets("a very fast drag lands on the limit, not beyond", (
      tester,
    ) async {
      final h = await _pump(tester, count: 300);
      await tester.timedDrag(
        _chartFinder,
        const Offset(-20000, 0),
        const Duration(milliseconds: 120),
      );
      await tester.pumpAndSettle();
      expect(h.ctx.scrollOffset, h.ctx.maxScrollOffset);
    });
  });

  group("TC-GEST-15 inside a scrollable parent", () {
    Future<(ChartHarness<int>, ScrollController)> pumpInList(
      WidgetTester tester,
    ) async {
      final h = _chart();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ListView(
            controller: scroll,
            children: [
              const SizedBox(height: 100),
              SizedBox(
                height: 300,
                child: InteractiveChart<int>(
                  controller: h.controller,
                  data: intSeries(0, 1000),
                  timeOf: minuteTime,
                  initialAnchor: ChartAnchor.left,
                  layers: [
                    LineLayer<int>(valueOf: (i) => 100.0 + i % 11),
                    ContextProbe<int>((c) => h.ctx = c),
                  ],
                ),
              ),
              const SizedBox(height: 1500),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (h, scroll);
    }

    testWidgets("horizontal drag pans the chart and leaves the list alone", (
      tester,
    ) async {
      final (h, scroll) = await pumpInList(tester);
      final g = await tester.startGesture(tester.getCenter(_chartFinder));
      for (var i = 0; i < 25; i++) {
        await g.moveBy(const Offset(-10, 0));
        await tester.pump();
      }
      await g.up();
      await tester.pumpAndSettle();
      // Realistic stepped input; Flutter's pan slop (~36 px) is not counted.
      expect(h.ctx.scrollOffset, inInclusiveRange(190, 250));
      expect(scroll.offset, 0);
    });

    testWidgets("a vertical drag scrolls the page and leaves the chart alone", (
      tester,
    ) async {
      // Documented behaviour: inside a vertical scrollable the page wins a
      // vertical drag, so vertical value panning is not available there.
      final (h, scroll) = await pumpInList(tester);
      await tester.drag(_chartFinder, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(100));
      expect(h.controller.autoscale, isTrue);
      expect(h.ctx.scrollOffset, 0);
    });

    testWidgets("wheel over the chart zooms it", (tester) async {
      final (h, _) = await pumpInList(tester);
      await _wheel(
        tester,
        tester.getCenter(_chartFinder),
        const Offset(0, -200),
      );
      expect(h.ctx.slotExtent, greaterThan(8));
    });
  });
}
