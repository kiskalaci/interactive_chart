// Test plan section 10: controller and callbacks (TC-CTRL-*, TC-CB-*).
// TC-CTRL-05 is in test/jump_to_latest_test.dart. See docs/poc_notes.md.
import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart" hide testWidgets;
import "package:interactive_chart/interactive_chart.dart";

import "support/chart_harness.dart";
import "support/variants.dart";

final _chartFinder = find.byType(InteractiveChart<int>);

class _Notifications {
  _Notifications(ChangeNotifier source) {
    source.addListener(() => count++);
  }
  int count = 0;
}

Widget _app(
  InteractiveChartController? controller, {
  List<int>? data,
  void Function(int, int)? onRange,
  void Function(int?)? onIndex,
  ChartAnchor anchor = ChartAnchor.left,
  double? width,
}) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      // Fills the screen unless a width is given.
      width: width ?? double.infinity,
      height: double.infinity,
      child: InteractiveChart<int>(
        controller: controller,
        data: data ?? intSeries(0, 600),
        timeOf: minuteTime,
        initialAnchor: anchor,
        onVisibleRangeChanged: onRange,
        onIndexHighlighted: onIndex,
        layers: [LineLayer<int>(valueOf: (i) => 100.0 + i % 13)],
      ),
    ),
  ),
);

void main() {
  group("TC-CTRL-01 an unattached controller", () {
    test("getters return neutral values", () {
      final c = InteractiveChartController();
      expect(c.isAttached, isFalse);
      expect(c.visibleRange, (0, 0));
      expect(c.slotExtent, 0);
      expect(c.autoscale, isTrue);
      expect(c.highlightedIndex, isNull);
      c.dispose();
    });

    test("methods are no-ops", () {
      final c = InteractiveChartController();
      expect(c.jumpToLatest, returnsNormally);
      expect(() => c.jumpToLatest(slotExtent: 12), returnsNormally);
      expect(() => c.setAutoscale(false), returnsNormally);
      expect(c.clearHighlight, returnsNormally);
      c.dispose();
    });

    testWidgets("attached once the chart is mounted", (tester) async {
      final c = InteractiveChartController();
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();
      expect(c.isAttached, isTrue);
      expect(c.visibleRange.$2, greaterThan(0));
      expect(c.slotExtent, 8);
    });
  });

  group("TC-CTRL-02 notifications", () {
    testWidgets("pan, zoom, highlight and autoscale each notify", (
      tester,
    ) async {
      final c = InteractiveChartController();
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();
      final n = _Notifications(c);

      await tester.drag(_chartFinder, const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(n.count, greaterThan(0), reason: "pan");

      var before = n.count;
      final pointer = TestPointer(1, PointerDeviceKind.mouse)
        ..hover(tester.getCenter(_chartFinder));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
      await tester.pump();
      expect(n.count, greaterThan(before), reason: "zoom");

      before = n.count;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(_chartFinder));
      await mouse.moveTo(tester.getCenter(_chartFinder) + const Offset(30, 0));
      await tester.pump();
      expect(n.count, greaterThan(before), reason: "highlight");

      before = n.count;
      c.setAutoscale(false);
      expect(n.count, greaterThan(before), reason: "autoscale");
    });

    testWidgets("setting a value it already has does not notify", (
      tester,
    ) async {
      final c = InteractiveChartController();
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();
      final n = _Notifications(c);
      c
        ..setAutoscale(true) // already on
        ..clearHighlight(); // nothing highlighted
      expect(n.count, 0);
    });
  });

  group("TC-CTRL-03 setAutoscale", () {
    testWidgets("is reflected in the getter and the extent", (tester) async {
      final h = ChartHarness<int>(
        timeOf: minuteTime,
        valueAxis: null,
        timeAxis: null,
        layers: () => [LineLayer<int>(valueOf: (i) => 100.0 + i % 13)],
      );
      await tester.pumpWidget(h.app(intSeries(0, 600)));
      await tester.pumpAndSettle();
      expect(h.controller.autoscale, isTrue);

      h.controller.setAutoscale(false);
      await tester.pumpAndSettle();
      expect(h.controller.autoscale, isFalse);
      final manual = (h.ctx.valueMin, h.ctx.valueMax);
      await tester.drag(
        _chartFinder,
        const Offset(-3000, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect((h.ctx.valueMin, h.ctx.valueMax), manual);

      h.controller.setAutoscale(true);
      await tester.pumpAndSettle();
      expect(h.controller.autoscale, isTrue);
    });
  });

  group("TC-CTRL-04 jumpToLatest", () {
    testWidgets("shows the newest datum and leaves the zoom alone", (
      tester,
    ) async {
      final c = InteractiveChartController();
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();
      expect(c.visibleRange.$2, lessThan(600));

      final extent = c.slotExtent;
      c.jumpToLatest();
      await tester.pumpAndSettle();
      expect(c.visibleRange.$2, 600);
      expect(c.slotExtent, extent);
    });

    testWidgets("is a no-op when already there", (tester) async {
      final c = InteractiveChartController();
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();
      c.jumpToLatest();
      await tester.pumpAndSettle();
      final range = c.visibleRange;
      c.jumpToLatest();
      await tester.pumpAndSettle();
      expect(c.visibleRange, range);
    });

    testWidgets("with less data than the viewport", (tester) async {
      final c = InteractiveChartController();
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(c, data: intSeries(0, 20)));
      await tester.pumpAndSettle();
      c.jumpToLatest();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(c.visibleRange, (0, 20));
    });
  });

  group("TC-CTRL-06 jumpToLatest(slotExtent:) is clamped", () {
    for (final (asked, expected) in [
      (500.0, 64.0),
      (0.01, 1.0),
      (20.0, 20.0),
    ]) {
      testWidgets("asking for $asked gives $expected", (tester) async {
        final c = InteractiveChartController();
        addTearDown(c.dispose);
        await tester.pumpWidget(_app(c));
        await tester.pumpAndSettle();
        c.jumpToLatest(slotExtent: asked);
        await tester.pumpAndSettle();
        expect(c.slotExtent, expected);
        expect(c.visibleRange.$2, 600);
      });
    }
  });

  testWidgets("TC-CTRL-07 clearHighlight removes the crosshair", (
    tester,
  ) async {
    final c = InteractiveChartController();
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(_chartFinder));
    await mouse.moveTo(tester.getCenter(_chartFinder) + const Offset(20, 0));
    await tester.pump();
    expect(c.highlightedIndex, isNotNull);

    c.clearHighlight();
    await tester.pump();
    expect(c.highlightedIndex, isNull);
  });

  group("TC-CTRL-08 swapping the controller", () {
    testWidgets("the old one is detached and stops receiving events", (
      tester,
    ) async {
      final a = InteractiveChartController();
      final b = InteractiveChartController();
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      await tester.pumpWidget(_app(a));
      await tester.pumpAndSettle();
      expect(a.isAttached, isTrue);

      await tester.pumpWidget(_app(b));
      await tester.pumpAndSettle();
      expect(b.isAttached, isTrue);
      expect(a.isAttached, isFalse);

      final na = _Notifications(a);
      final nb = _Notifications(b);
      await tester.drag(_chartFinder, const Offset(-150, 0));
      await tester.pumpAndSettle();
      expect(nb.count, greaterThan(0));
      expect(na.count, 0, reason: "the old controller still gets events");

      // Calling the old one does nothing to the chart.
      final range = b.visibleRange;
      a.jumpToLatest();
      await tester.pumpAndSettle();
      expect(b.visibleRange, range);
    });

    testWidgets("from an external controller to none and back", (tester) async {
      final a = InteractiveChartController();
      addTearDown(a.dispose);
      await tester.pumpWidget(_app(a));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_app(null));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(a.isAttached, isFalse);

      await tester.pumpWidget(_app(a));
      await tester.pumpAndSettle();
      expect(a.isAttached, isTrue);
      a.jumpToLatest();
      await tester.pumpAndSettle();
      expect(a.visibleRange.$2, 600);
    });
  });

  group("TC-CTRL-09 and 10 lifecycle", () {
    testWidgets("TC-CTRL-09 works without a controller", (tester) async {
      await tester.pumpWidget(_app(null));
      await tester.pumpAndSettle();
      await tester.drag(_chartFinder, const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Unmounting disposes the internal controller without complaint.
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });

    testWidgets("the chart does not dispose an external controller", (
      tester,
    ) async {
      final c = InteractiveChartController();
      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      // Still usable by its owner: add and remove a listener, then dispose.
      var called = 0;
      void listener() => called++;
      expect(() => c.addListener(listener), returnsNormally);
      c.removeListener(listener);
      expect(c.dispose, returnsNormally);
      expect(called, 0);
    });

    testWidgets("TC-CTRL-10 an external controller is detached on unmount", (
      tester,
    ) async {
      final c = InteractiveChartController();
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();
      expect(c.isAttached, isTrue);

      await tester.pumpWidget(const SizedBox());
      expect(c.isAttached, isFalse);
      // Safe to call afterwards: nothing is listening to a dead context.
      expect(c.jumpToLatest, returnsNormally);
      expect(() => c.setAutoscale(false), returnsNormally);
      expect(c.clearHighlight, returnsNormally);
      expect(c.visibleRange, (0, 0));
    });

    testWidgets(
      "a controller can move to a new chart after the first is gone",
      (tester) async {
        final c = InteractiveChartController();
        addTearDown(c.dispose);
        await tester.pumpWidget(_app(c));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(_app(c, data: intSeries(0, 300)));
        await tester.pumpAndSettle();
        expect(c.isAttached, isTrue);
        c.jumpToLatest();
        await tester.pumpAndSettle();
        expect(c.visibleRange.$2, 300);
      },
    );
  });

  group("onVisibleRangeChanged", () {
    testWidgets("TC-CB-01 called once after the first frame with the range", (
      tester,
    ) async {
      final calls = <(int, int)>[];
      final c = InteractiveChartController();
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(c, onRange: (s, e) => calls.add((s, e))));
      await tester.pumpAndSettle();
      expect(calls.length, 1);
      expect(calls.single, c.visibleRange);
      expect(calls.single.$1, 0);
      expect(calls.single.$2, greaterThan(20));
    });

    testWidgets("TC-CB-02 called with the new range on pan and zoom", (
      tester,
    ) async {
      final calls = <(int, int)>[];
      final c = InteractiveChartController();
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(c, onRange: (s, e) => calls.add((s, e))));
      await tester.pumpAndSettle();
      calls.clear();

      await tester.drag(_chartFinder, const Offset(-240, 0));
      await tester.pumpAndSettle();
      expect(calls, isNotEmpty);
      expect(calls.last, c.visibleRange);
      expect(calls.last.$1, greaterThan(20));

      calls.clear();
      final pointer = TestPointer(1, PointerDeviceKind.mouse)
        ..hover(tester.getCenter(_chartFinder));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -300)));
      await tester.pump();
      expect(calls, isNotEmpty);
      expect(calls.last, c.visibleRange);
    });

    testWidgets(
      "TC-CB-03 data and size changes without input: pinned behaviour",
      (tester) async {
        // setSlotCount and viewport resizes recompute the range but do not
        // notify, so a caller learns about them from the next interaction. If
        // that ever changes (for example to support paging after a prepend),
        // this test should change deliberately.
        final calls = <(int, int)>[];
        await tester.pumpWidget(
          _app(
            null,
            onRange: (s, e) => calls.add((s, e)),
            data: intSeries(100, 600),
          ),
        );
        await tester.pumpAndSettle();
        calls.clear();

        await tester.pumpWidget(
          _app(
            null,
            onRange: (s, e) => calls.add((s, e)),
            data: intSeries(50, 600),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          _app(
            null,
            onRange: (s, e) => calls.add((s, e)),
            data: intSeries(50, 600),
            width: screenOf(tester).width * 0.6,
          ),
        );
        await tester.pumpAndSettle();
        expect(calls, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group("TC-CB-04 onIndexHighlighted", () {
    testWidgets("reports the index on hover and null on exit", (tester) async {
      final reported = <int?>[];
      await tester.pumpWidget(_app(null, onIndex: reported.add));
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(_chartFinder);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(
        location: origin + const Offset(84, 100),
      ); // slot 10
      await mouse.moveTo(origin + const Offset(85, 100));
      await tester.pump();
      expect(reported.last, 10);

      await mouse.moveTo(origin + const Offset(204, 100)); // slot 25
      await tester.pump();
      expect(reported.last, 25);

      await mouse.moveTo(
        tester.getBottomRight(_chartFinder) + const Offset(50, 50),
      );
      await tester.pump();
      expect(reported.last, isNull);
    });

    testWidgets("is not called with a stale index after the pointer leaves", (
      tester,
    ) async {
      final reported = <int?>[];
      await tester.pumpWidget(_app(null, onIndex: reported.add));
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(_chartFinder));
      await mouse.moveTo(tester.getCenter(_chartFinder) + const Offset(10, 0));
      await tester.pump();
      await mouse.moveTo(
        tester.getBottomRight(_chartFinder) + const Offset(50, 50),
      );
      await tester.pump();
      reported.clear();

      await tester.drag(_chartFinder, const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(reported.where((i) => i != null), isEmpty);
    });
  });
}
