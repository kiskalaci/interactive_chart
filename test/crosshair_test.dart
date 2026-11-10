// Test plan section 9: crosshair and readouts (TC-CROSS-*). TC-CROSS-06 is in
// test/known_gaps_test.dart. See docs/poc_notes.md.
import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart" hide testWidgets;
import "package:interactive_chart/interactive_chart.dart";

import "support/chart_harness.dart";
import "support/variants.dart";

const _lineColor = Color(0xFF111AAA);
const _badgeColor = Color(0xFF222BBB);

final _chartFinder = find.byType(InteractiveChart<int>);

CrosshairLayer<int> _crosshair({
  bool withValue = true,
  bool withTime = true,
  DateTime Function(int)? timeOf,
}) => CrosshairLayer<int>(
  valueOf: withValue ? (i) => 100.0 + i % 20 : null,
  timeOf: withTime ? (timeOf ?? minuteTime) : null,
  lineColor: _lineColor,
  labelBackground: _badgeColor,
);

ChartHarness<int> _chart({
  bool crosshairEnabled = true,
  ChartAnchor anchor = ChartAnchor.left,
  CrosshairLayer<int>? crosshair,
  DateTime Function(int)? timeOf,
}) => ChartHarness<int>(
  timeOf: timeOf ?? minuteTime,
  anchor: anchor,
  crosshairEnabled: crosshairEnabled,
  valueAxis: null,
  timeAxis: null,
  layers: () => [
    LineLayer<int>(valueOf: (i) => 100.0 + i % 20),
    crosshair ?? _crosshair(timeOf: timeOf),
  ],
);

Future<ChartHarness<int>> _pump(
  WidgetTester tester, {
  int count = 400,
  bool crosshairEnabled = true,
  ChartAnchor anchor = ChartAnchor.left,
  CrosshairLayer<int>? crosshair,
  DateTime Function(int)? timeOf,
}) async {
  final h = _chart(
    crosshairEnabled: crosshairEnabled,
    anchor: anchor,
    crosshair: crosshair,
    timeOf: timeOf,
  );
  await tester.pumpWidget(h.app(intSeries(0, count)));
  await tester.pumpAndSettle();
  return h;
}

Finder get _lines => find.byWidgetPredicate(
  (w) => w is ColoredBox && w.color == _lineColor,
  description: "crosshair line",
);

Finder get _badges => find.byWidgetPredicate(
  (w) => w is Container && w.color == _badgeColor,
  description: "crosshair badge",
);

List<String> _badgeTexts(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(
    find.descendant(of: _badges, matching: find.byType(Text)),
  ))
    t.data!,
];

Future<TestGesture> _hover(WidgetTester tester, Offset at) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: at);
  await mouse.moveTo(at + const Offset(0.5, 0));
  await tester.pump();
  return mouse;
}

Offset _slotPoint(WidgetTester tester, ChartHarness<int> h, int i) =>
    tester.getTopLeft(_chartFinder) + Offset(h.ctx.xOf(i), 100);

void main() {
  group("TC-CROSS-01 hover over a real slot", () {
    testWidgets("lines, value badge and time badge", (tester) async {
      final h = await _pump(tester);
      final origin = tester.getTopLeft(_chartFinder);
      await _hover(tester, _slotPoint(tester, h, 12));

      expect(h.controller.highlightedIndex, 12);
      // A vertical and a horizontal line.
      expect(_lines, findsNWidgets(2));
      final rects = [for (var i = 0; i < 2; i++) tester.getRect(_lines.at(i))];
      final vertical = rects.firstWhere((r) => r.width == 1);
      final horizontal = rects.firstWhere((r) => r.height == 1);
      expect(vertical.left - origin.dx, closeTo(h.ctx.xOf(12), 1e-6));
      expect(vertical.height, h.ctx.viewportHeight);
      expect(horizontal.top - origin.dy, closeTo(h.ctx.yOf(112), 1e-6));
      expect(horizontal.width, h.ctx.viewportWidth);

      // Value badge with two decimals, then the time badge.
      final texts = _badgeTexts(tester);
      expect(texts.length, 2);
      expect(texts, contains("112.00"));
    });

    testWidgets("the readout moves with the pointer", (tester) async {
      final h = await _pump(tester);
      final mouse = await _hover(tester, _slotPoint(tester, h, 5));
      expect(h.controller.highlightedIndex, 5);
      await mouse.moveTo(_slotPoint(tester, h, 30));
      await tester.pump();
      expect(h.controller.highlightedIndex, 30);
      expect(_badgeTexts(tester), contains("110.00")); // 100 + 30 % 20
    });

    testWidgets("it snaps to the slot centre, not the pointer", (tester) async {
      final h = await _pump(tester);
      final origin = tester.getTopLeft(_chartFinder);
      // Anywhere inside slot 9 (x from 72 to 80).
      await _hover(tester, origin + const Offset(73, 100));
      final vertical = [
        for (var i = 0; i < 2; i++) tester.getRect(_lines.at(i)),
      ].firstWhere((r) => r.width == 1);
      expect(vertical.left - origin.dx, closeTo(h.ctx.xOf(9), 1e-6));
    });
  });

  group("time badge precision (R-TIME-16)", () {
    testWidgets("minute bars show the time of day, not just the date", (
      tester,
    ) async {
      DateTime morning(int i) =>
          DateTime(2024, 1, 1, 9).add(Duration(minutes: i));
      final h = await _pump(tester, timeOf: morning);
      await _hover(tester, _slotPoint(tester, h, 12)); // 09:12
      final time = _badgeTexts(tester).firstWhere((t) => t.contains("-"));
      expect(time, contains("2024-01-01"));
      expect(time, contains("09:12"));
    });

    testWidgets("second bars show seconds", (tester) async {
      DateTime t(int i) =>
          DateTime(2024, 3, 5, 9, 30).add(Duration(seconds: 10 * i));
      final h = await _pump(tester, timeOf: t);
      await _hover(tester, _slotPoint(tester, h, 7)); // 09:31:10
      final time = _badgeTexts(tester).firstWhere((x) => x.contains("-"));
      expect(time, contains("09:31:10"));
    });

    testWidgets("daily bars show the date only", (tester) async {
      DateTime t(int i) => DateTime(2024, 3, 5).add(Duration(days: i));
      final h = await _pump(tester, timeOf: t);
      await _hover(tester, _slotPoint(tester, h, 3));
      final time = _badgeTexts(tester).firstWhere((x) => x.contains("-"));
      expect(time, "2024-03-08");
    });

    testWidgets("a custom timeFormatter is used", (tester) async {
      final h = await _pump(
        tester,
        crosshair: CrosshairLayer<int>(
          valueOf: (i) => 100.0 + i % 20,
          timeOf: minuteTime,
          timeFormatter: (t) => "T=${t.minute}",
          lineColor: _lineColor,
          labelBackground: _badgeColor,
        ),
      );
      await _hover(tester, _slotPoint(tester, h, 12));
      expect(_badgeTexts(tester), contains("T=12"));
    });
  });

  testWidgets("TC-CROSS-02 pointer exit clears the crosshair", (tester) async {
    final h = await _pump(tester);
    final mouse = await _hover(tester, _slotPoint(tester, h, 12));
    expect(h.controller.highlightedIndex, 12);
    expect(_lines, findsNWidgets(2));

    await mouse.moveTo(
      tester.getBottomRight(_chartFinder) + const Offset(40, 40),
    );
    await tester.pump();
    expect(h.controller.highlightedIndex, isNull);
    expect(_lines, findsNothing);
    expect(_badges, findsNothing);
  });

  group("touch", () {
    testWidgets(
      "TC-CROSS-03 long-press drag follows the finger, release clears",
      (tester) async {
        final h = await _pump(tester);
        final start = _slotPoint(tester, h, 10);
        final finger = await tester.startGesture(start);
        await tester.pump(const Duration(milliseconds: 600)); // long press
        expect(h.controller.highlightedIndex, 10);

        await finger.moveTo(_slotPoint(tester, h, 25));
        await tester.pump();
        expect(h.controller.highlightedIndex, 25);
        expect(_lines, findsNWidgets(2));
        // The chart did not pan underneath the finger.
        expect(h.ctx.scrollOffset, 0);

        await finger.up();
        await tester.pump();
        expect(h.controller.highlightedIndex, isNull);
        expect(_lines, findsNothing);
      },
    );

    testWidgets("TC-CROSS-04 a tap places the crosshair at that slot", (
      tester,
    ) async {
      final h = await _pump(tester);
      await tester.tapAt(_slotPoint(tester, h, 18));
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.controller.highlightedIndex, 18);

      // It stays until something else moves it (there is no pointer exit on
      // touch), and a second tap moves it.
      await tester.tapAt(_slotPoint(tester, h, 40));
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.controller.highlightedIndex, 40);
    });

    testWidgets("TC-CROSS-03b long press and tap work on empty space", (
      tester,
    ) async {
      final h = await _pump(tester);
      final origin = tester.getTopLeft(_chartFinder);
      // Bottom of the viewport: no line, candle or other element is drawn
      // there, so only a pointer-level handler can see the touch.
      final empty = origin + Offset(h.ctx.xOf(14), h.ctx.viewportHeight - 4);

      await tester.tapAt(empty);
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.controller.highlightedIndex, 14);

      final finger = await tester.startGesture(
        origin + Offset(h.ctx.xOf(30), h.ctx.viewportHeight - 4),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(h.controller.highlightedIndex, 30);
      await finger.up();
      await tester.pump();
      expect(h.controller.highlightedIndex, isNull);
    });

    testWidgets("a drag pans the chart and shows no crosshair", (tester) async {
      final h = await _pump(tester);
      await tester.drag(_chartFinder, const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(h.ctx.scrollOffset, greaterThan(150));
      expect(h.controller.highlightedIndex, isNull);
    });
  });

  group("TC-CROSS-05 hover over a projected slot (R-TIME-29)", () {
    testWidgets("time badge only, with the projected time", (tester) async {
      final h = await _pump(tester, anchor: ChartAnchor.right);
      // Far right of the viewport: past the newest bar, in the overscroll.
      final origin = tester.getTopLeft(_chartFinder);
      await _hover(tester, origin + Offset(h.ctx.viewportWidth - 40, 100));

      final index = h.controller.highlightedIndex!;
      expect(index, greaterThanOrEqualTo(400));
      expect(h.ctx.highlightedProjectedTime, isNotNull);

      // Only the vertical line: no horizontal line and no value badge.
      expect(_lines, findsOneWidget);
      expect(tester.getRect(_lines).width, 1);
      final texts = _badgeTexts(tester);
      expect(texts.length, 1);
      // The projected time continues the 1-minute cadence.
      expect(
        texts.single,
        contains(minuteTime(index).minute.toString().padLeft(2, "0")),
      );
    });

    testWidgets("moving back onto a real slot restores the value readout", (
      tester,
    ) async {
      final h = await _pump(tester, anchor: ChartAnchor.right);
      final origin = tester.getTopLeft(_chartFinder);
      final mouse = await _hover(
        tester,
        origin + Offset(h.ctx.viewportWidth - 40, 100),
      );
      expect(_badgeTexts(tester).length, 1);

      await mouse.moveTo(origin + Offset(h.ctx.xOf(390), 100));
      await tester.pump();
      expect(h.ctx.highlightedProjectedTime, isNull);
      expect(_badgeTexts(tester).length, 2);
      expect(_lines, findsNWidgets(2));
    });
  });

  group("TC-CROSS-07 crosshairEnabled: false", () {
    testWidgets("hover, tap and long-press do nothing", (tester) async {
      final h = await _pump(tester, crosshairEnabled: false);
      final at = _slotPoint(tester, h, 12);

      await _hover(tester, at);
      expect(h.controller.highlightedIndex, isNull);

      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.controller.highlightedIndex, isNull);

      final finger = await tester.startGesture(at);
      await tester.pump(const Duration(milliseconds: 700));
      await finger.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(h.controller.highlightedIndex, isNull);
      await finger.up();

      expect(_lines, findsNothing);
      expect(_badges, findsNothing);
    });

    testWidgets("panning and zooming still work", (tester) async {
      final h = await _pump(tester, crosshairEnabled: false);
      await tester.drag(_chartFinder, const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(h.ctx.scrollOffset, closeTo(200, 2));
    });
  });

  group("TC-CROSS-08 a crosshair without valueOf or timeOf", () {
    testWidgets("neither: just the vertical line", (tester) async {
      final h = await _pump(
        tester,
        crosshair: _crosshair(withValue: false, withTime: false),
      );
      await _hover(tester, _slotPoint(tester, h, 12));
      expect(tester.takeException(), isNull);
      expect(_lines, findsOneWidget);
      expect(_badges, findsNothing);
    });

    testWidgets("no valueOf: no horizontal line or value badge", (
      tester,
    ) async {
      final h = await _pump(tester, crosshair: _crosshair(withValue: false));
      await _hover(tester, _slotPoint(tester, h, 12));
      expect(_lines, findsOneWidget);
      expect(_badgeTexts(tester).length, 1); // the time badge
    });

    testWidgets("no timeOf: no time badge", (tester) async {
      final h = await _pump(tester, crosshair: _crosshair(withTime: false));
      await _hover(tester, _slotPoint(tester, h, 12));
      expect(_lines, findsNWidgets(2));
      expect(_badgeTexts(tester), ["112.00"]);
    });
  });

  testWidgets("TC-CROSS-09 the very first pixel highlights the first slot", (
    tester,
  ) async {
    // The index < 0 branch cannot be reached through the viewport (the
    // scroll offset is never negative), so the leftmost pixel is slot 0.
    final h = await _pump(tester);
    await _hover(
      tester,
      tester.getTopLeft(_chartFinder) + const Offset(0.2, 100),
    );
    expect(h.controller.highlightedIndex, 0);
  });

  group("TC-CROSS-10 badges stay inside the viewport", () {
    Future<void> expectInside(WidgetTester tester) async {
      final chart = tester.getRect(_chartFinder);
      expect(_badges, findsWidgets);
      for (var i = 0; i < tester.widgetList(_badges).length; i++) {
        final r = tester.getRect(_badges.at(i));
        expect(
          r.left,
          greaterThanOrEqualTo(chart.left - 0.01),
          reason: "badge $i left",
        );
        expect(
          r.right,
          lessThanOrEqualTo(chart.right + 0.01),
          reason: "badge $i right",
        );
        expect(
          r.top,
          greaterThanOrEqualTo(chart.top - 0.01),
          reason: "badge $i top",
        );
        expect(
          r.bottom,
          lessThanOrEqualTo(chart.bottom + 0.01),
          reason: "badge $i bottom",
        );
      }
    }

    testWidgets("at the left edge", (tester) async {
      final h = await _pump(tester);
      await _hover(tester, _slotPoint(tester, h, 0));
      await expectInside(tester);
    });

    testWidgets("at the right edge", (tester) async {
      final h = await _pump(tester, anchor: ChartAnchor.right);
      final origin = tester.getTopLeft(_chartFinder);
      await _hover(tester, origin + Offset(h.ctx.viewportWidth - 3, 100));
      await expectInside(tester);
    });

    testWidgets("in the middle", (tester) async {
      final h = await _pump(tester);
      await _hover(tester, _slotPoint(tester, h, 40));
      await expectInside(tester);
    });

    testWidgets("with the value near the top and bottom of the extent", (
      tester,
    ) async {
      final h = await _pump(tester);
      // Make the highest and lowest visible points sit on the viewport edge.
      h.controller.setAutoscale(false);
      h.ctx.setValueExtent(100, 119);
      await tester.pumpAndSettle();
      final mouse = await _hover(tester, _slotPoint(tester, h, 19)); // 119: top
      await expectInside(tester);
      await mouse.moveTo(_slotPoint(tester, h, 20)); // value 100: very bottom
      await tester.pump();
      await expectInside(tester);
    });
  });
}
