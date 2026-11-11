// EventLayer: icons for financial events, and the details card opened by
// tapping one. See docs/poc_notes.md.
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart" hide testWidgets;
import "package:interactive_chart/interactive_chart.dart";

import "support/chart_harness.dart";
import "support/variants.dart";

/// One bar per day from 2024-01-01 (a Monday), so slot `i` is day `i`.
DateTime _day(int i) => DateTime(2024).add(Duration(days: i));

ChartEvent _event(
  int day, {
  String title = "Dividend",
  String description = "0.25 per share",
  IconData icon = Icons.paid,
}) => ChartEvent(
  time: _day(day).add(const Duration(hours: 15)), // time of day is ignored
  title: title,
  description: description,
  icon: icon,
);

ChartHarness<int> _harness(
  List<ChartEvent> events, {
  double bottomInsetFraction = 0,
  EventOverlayConfig overlay = const EventOverlayConfig(),
  Widget Function(BuildContext, ChartEvent, VoidCallback)? overlayBuilder,
  void Function(ChartEvent)? onEventTap,
}) => ChartHarness<int>(
  timeOf: _day,
  valueAxis: null,
  timeAxis: null,
  layers: () => [
    const LineLayer<int>(valueOf: _value),
    EventLayer<int>(
      events: events,
      timeOf: _day,
      bottomInsetFraction: bottomInsetFraction,
      overlay: overlay,
      overlayBuilder: overlayBuilder,
      onEventTap: onEventTap,
    ),
  ],
);

double _value(int i) => 100.0 + i % 7;

final _chartFinder = find.byType(InteractiveChart<int>);

Future<ChartHarness<int>> _pump(
  WidgetTester tester,
  List<ChartEvent> events, {
  int count = 30,
  double bottomInsetFraction = 0,
  EventOverlayConfig overlay = const EventOverlayConfig(),
  Widget Function(BuildContext, ChartEvent, VoidCallback)? overlayBuilder,
  void Function(ChartEvent)? onEventTap,
}) async {
  final h = _harness(
    events,
    bottomInsetFraction: bottomInsetFraction,
    overlay: overlay,
    overlayBuilder: overlayBuilder,
    onEventTap: onEventTap,
  );
  await tester.pumpWidget(h.app(List.generate(count, (i) => i)));
  await tester.pumpAndSettle();
  return h;
}

void main() {
  group("markers", () {
    testWidgets("one icon per event, centred on its day's slot", (
      tester,
    ) async {
      final h = await _pump(tester, [_event(3), _event(10, icon: Icons.star)]);
      final origin = tester.getTopLeft(_chartFinder);
      expect(
        tester.getCenter(find.byIcon(Icons.paid)).dx - origin.dx,
        closeTo(h.ctx.xOf(3), 0.001),
      );
      expect(
        tester.getCenter(find.byIcon(Icons.star)).dx - origin.dx,
        closeTo(h.ctx.xOf(10), 0.001),
      );
    });

    testWidgets("icons rest on the bottom of the viewport by default", (
      tester,
    ) async {
      final h = await _pump(tester, [_event(3)]);
      final origin = tester.getTopLeft(_chartFinder);
      final marker = tester.getRect(find.byKey(ValueKey(_event(3))));
      expect(marker.bottom - origin.dy, closeTo(h.ctx.viewportHeight, 0.001));
    });

    testWidgets("bottomInsetFraction lifts the icons above a bottom strip", (
      tester,
    ) async {
      final h = await _pump(tester, [_event(3)], bottomInsetFraction: 0.25);
      final origin = tester.getTopLeft(_chartFinder);
      final marker = tester.getRect(find.byKey(ValueKey(_event(3))));
      expect(
        marker.bottom - origin.dy,
        closeTo(h.ctx.viewportHeight * 0.75, 0.001),
      );
    });

    testWidgets("events on the same day stack upwards", (tester) async {
      await _pump(tester, [
        _event(3, title: "A"),
        _event(3, title: "B", icon: Icons.star),
      ]);
      final first = tester.getRect(find.byIcon(Icons.paid));
      final second = tester.getRect(find.byIcon(Icons.star));
      expect(second.center.dx, first.center.dx);
      expect(second.bottom, lessThan(first.top));
    });

    testWidgets("icons that would overlap are hidden", (tester) async {
      // Slots 8 px apart, icons 22 px wide: days 3 and 4 collide, day 20 is
      // far from both.
      await _pump(tester, [
        _event(3),
        _event(4, icon: Icons.star),
        _event(20, icon: Icons.flag),
      ]);
      expect(find.byIcon(Icons.paid), findsNothing);
      expect(find.byIcon(Icons.star), findsNothing);
      expect(find.byIcon(Icons.flag), findsOneWidget);
    });

    testWidgets("they come back when zoomed in far enough", (tester) async {
      final h = await _pump(tester, [_event(3), _event(4, icon: Icons.star)]);
      expect(find.byIcon(Icons.paid), findsNothing);

      h.ctx.setSlotExtentAndScroll(30, 0);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.paid), findsOneWidget);
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets("hiding does not depend on how far the chart is panned", (
      tester,
    ) async {
      final h = await _pump(tester, [
        _event(100),
        _event(101, icon: Icons.star),
        _event(110, icon: Icons.flag),
      ], count: 400);
      h.ctx.jumpTo(h.ctx.xOf(95) + h.ctx.scrollOffset - 20);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.paid), findsNothing);
      expect(find.byIcon(Icons.star), findsNothing);
      // 9 slots x 8 px = 72 px from the pair: clear of it.
      expect(find.byIcon(Icons.flag), findsOneWidget);
    });

    testWidgets("events on one day stay stacked and are not hidden", (
      tester,
    ) async {
      await _pump(tester, [_event(3), _event(3, icon: Icons.star)]);
      expect(find.byIcon(Icons.paid), findsOneWidget);
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets("a day with no datum gets no marker", (tester) async {
      // Only 30 bars: day 80 has none.
      await _pump(tester, [_event(80)]);
      expect(find.byIcon(Icons.paid), findsNothing);
    });

    testWidgets("only events in the visible range are built", (tester) async {
      final h = await _pump(tester, [_event(2), _event(900)], count: 1000);
      expect(find.byIcon(Icons.paid), findsOneWidget);
      h.ctx.jumpTo(h.ctx.maxScrollOffset);
      await tester.pumpAndSettle();
      expect(h.ctx.visibleStart, greaterThan(2));
      expect(find.byKey(ValueKey(_event(2))), findsNothing);
    });

    testWidgets("an event moves with the chart when panned", (tester) async {
      final h = await _pump(tester, [_event(10)], count: 400);
      final before = tester.getCenter(find.byIcon(Icons.paid)).dx;
      h.ctx.panBy(40);
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.byIcon(Icons.paid)).dx, before - 40);
    });

    testWidgets("no events draws nothing and does not affect autoscale", (
      tester,
    ) async {
      final h = await _pump(tester, const []);
      expect(find.byType(Icon), findsNothing);
      expect(h.ctx.valueMax, lessThan(120));
    });
  });

  group("details card", () {
    testWidgets("tapping an icon opens the card in the middle of the chart", (
      tester,
    ) async {
      final h = await _pump(tester, [
        _event(3, title: "Q1 earnings", description: "EPS 1.20, beat by 0.05"),
      ]);
      expect(find.byKey(EventLayer.overlayKey), findsNothing);

      await tester.tap(find.byIcon(Icons.paid));
      await tester.pumpAndSettle();

      expect(find.text("Q1 earnings"), findsOneWidget);
      expect(find.text("EPS 1.20, beat by 0.05"), findsOneWidget);
      expect(find.byKey(EventLayer.closeButtonKey), findsOneWidget);
      final origin = tester.getTopLeft(_chartFinder);
      final centre = tester.getCenter(find.byKey(EventLayer.overlayKey));
      expect(centre.dx - origin.dx, closeTo(h.ctx.viewportWidth / 2, 0.5));
      expect(centre.dy - origin.dy, closeTo(h.ctx.viewportHeight / 2, 0.5));
    });

    testWidgets("the close button closes it", (tester) async {
      await _pump(tester, [_event(3)]);
      await tester.tap(find.byIcon(Icons.paid));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(EventLayer.closeButtonKey));
      await tester.pumpAndSettle();
      expect(find.byKey(EventLayer.overlayKey), findsNothing);
    });

    testWidgets("a tap outside the card closes it", (tester) async {
      await _pump(tester, [_event(3)]);
      await tester.tap(find.byIcon(Icons.paid));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getTopLeft(_chartFinder) + const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.byKey(EventLayer.overlayKey), findsNothing);
    });

    testWidgets("dismissOnBarrierTap: false keeps it open", (tester) async {
      await _pump(tester, [
        _event(3),
      ], overlay: const EventOverlayConfig(dismissOnBarrierTap: false));
      await tester.tap(find.byIcon(Icons.paid));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getTopLeft(_chartFinder) + const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.byKey(EventLayer.overlayKey), findsOneWidget);
    });

    testWidgets("a tap on the card itself does not close it", (tester) async {
      await _pump(tester, [_event(3, description: "Body text")]);
      await tester.tap(find.byIcon(Icons.paid));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Body text"));
      await tester.pumpAndSettle();
      expect(find.byKey(EventLayer.overlayKey), findsOneWidget);
    });

    testWidgets("the card is configurable", (tester) async {
      await _pump(
        tester,
        [_event(3, title: "Styled")],
        overlay: const EventOverlayConfig(
          backgroundColor: Color(0xFF010203),
          maxWidth: 150,
          titleStyle: TextStyle(fontSize: 20, color: Color(0xFFAABBCC)),
          closeButton: Text("X", style: TextStyle(fontSize: 10)),
        ),
      );
      await tester.tap(find.byIcon(Icons.paid));
      await tester.pumpAndSettle();

      final card = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byKey(EventLayer.overlayKey),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((card.decoration as BoxDecoration).color, const Color(0xFF010203));
      expect(tester.getSize(find.byKey(EventLayer.overlayKey)).width, 150);
      expect(tester.widget<Text>(find.text("Styled")).style!.fontSize, 20);
      await tester.tap(find.text("X"));
      await tester.pumpAndSettle();
      expect(find.byKey(EventLayer.overlayKey), findsNothing);
    });

    testWidgets("overlayBuilder replaces the card", (tester) async {
      await _pump(
        tester,
        [_event(3, title: "Custom")],
        overlayBuilder: (context, event, close) => GestureDetector(
          onTap: close,
          child: Text("Custom: ${event.title}"),
        ),
      );
      await tester.tap(find.byIcon(Icons.paid));
      await tester.pumpAndSettle();
      expect(find.text("Custom: Custom"), findsOneWidget);
      expect(find.byKey(EventLayer.closeButtonKey), findsNothing);
      await tester.tap(find.text("Custom: Custom"));
      await tester.pumpAndSettle();
      expect(find.text("Custom: Custom"), findsNothing);
    });

    testWidgets("onEventTap reports the tapped event", (tester) async {
      final tapped = <ChartEvent>[];
      final event = _event(3);
      await _pump(tester, [event], onEventTap: tapped.add);
      await tester.tap(find.byIcon(Icons.paid));
      await tester.pumpAndSettle();
      expect(tapped, [event]);
    });

    testWidgets("the card stays open across a pan and new data", (
      tester,
    ) async {
      final h = await _pump(tester, [_event(3)], count: 400);
      await tester.tap(find.byIcon(Icons.paid));
      await tester.pumpAndSettle();
      h.ctx.panBy(30);
      await tester.pumpWidget(h.app(List.generate(401, (i) => i)));
      await tester.pumpAndSettle();
      expect(find.byKey(EventLayer.overlayKey), findsOneWidget);
    });

    testWidgets("the card closes when its event is removed", (tester) async {
      final h = _harness([_event(3)]);
      await tester.pumpWidget(h.app(List.generate(30, (i) => i)));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.paid));
      await tester.pumpAndSettle();
      expect(find.byKey(EventLayer.overlayKey), findsOneWidget);

      final without = _harness(const []);
      await tester.pumpWidget(without.app(List.generate(30, (i) => i)));
      await tester.pumpAndSettle();
      expect(find.byKey(EventLayer.overlayKey), findsNothing);
    });

    testWidgets("dragging the chart still pans (taps do not eat drags)", (
      tester,
    ) async {
      final h = await _pump(tester, [_event(3)], count: 400);
      await tester.drag(_chartFinder, const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(h.ctx.scrollOffset, closeTo(100, 2));
    });
  });
}
