// Test plan section 12: live data (TC-LIVE-*). A LiveHost (test/support/
// hosts.dart) ticks once a second on a fake clock: ten-second bars, the
// forming bar updated in place and a new bar appended at each boundary.
// See docs/poc_notes.md.
import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:interactive_chart/interactive_chart.dart";
import "package:interactive_chart/src/ticks.dart";

import "support/hosts.dart";

final _key = GlobalKey<LiveHostState>();
final _chartFinder = find.byType(InteractiveChart<LiveBar>);

LiveHostState get _host => _key.currentState!;

Future<void> _pump(
  WidgetTester tester, {
  ChartAnchor anchor = ChartAnchor.right,
  bool crosshair = false,
  int history = 100,
}) async {
  await tester.pumpWidget(
    LiveHost(key: _key, anchor: anchor, crosshair: crosshair, history: history),
  );
  await tester.pump();
}

Future<void> _ticks(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  group("TC-LIVE-01 one-second ticks for a minute", () {
    testWidgets("the last bar updates each tick and the viewport stays put", (
      tester,
    ) async {
      await _pump(tester);
      // Move away from the live edge so a follow-the-end bug would show.
      await tester.drag(_chartFinder, const Offset(300, 0));
      await tester.pump();
      final offset = _host.ctx.scrollOffset;
      final extent = _host.ctx.slotExtent;
      final range = _host.controller.visibleRange;
      final startBars = _host.bars.length;

      for (var i = 1; i <= 60; i++) {
        await tester.pump(const Duration(seconds: 1));
        expect(_host.ticks, i);
        expect(_host.bars.last.close, _host.closeAt(i), reason: "tick $i");
      }
      expect(tester.takeException(), isNull);
      expect(_host.bars.length, startBars + 6);
      expect(_host.ctx.scrollOffset, offset);
      expect(_host.ctx.slotExtent, extent);
      // The first visible bar is unchanged. (The end may grow: new bars fill
      // the overscroll space at the right.)
      expect(_host.controller.visibleRange.$1, range.$1);
    });

    testWidgets("bar times stay unique and ten seconds apart", (tester) async {
      await _pump(tester);
      await _ticks(tester, 95);
      for (var i = 1; i < _host.bars.length; i++) {
        expect(
          _host.bars[i].time.difference(_host.bars[i - 1].time),
          const Duration(seconds: 10),
          reason: "bars $i",
        );
      }
    });
  });

  group("TC-LIVE-02 bar rollover", () {
    testWidgets("a new bar appears exactly at each 10-second boundary", (
      tester,
    ) async {
      await _pump(tester);
      final start = _host.bars.length;
      for (var i = 1; i <= 30; i++) {
        await tester.pump(const Duration(seconds: 1));
        expect(_host.bars.length, start + i ~/ 10, reason: "after $i ticks");
      }
    });

    testWidgets("projected slots continue at the ten-second cadence", (
      tester,
    ) async {
      await _pump(tester);
      await _ticks(tester, 25);
      final real = [for (final b in _host.bars) b.time];
      final projected = projectTimes(real, 5);
      expect(projected.first, real.last.add(const Duration(seconds: 10)));
      for (var i = 1; i < projected.length; i++) {
        expect(
          projected[i].difference(projected[i - 1]),
          const Duration(seconds: 10),
        );
      }
      // The chart's own projected marks sit on that grid, after the last bar.
      final marks = _host.ctx.timeTicks.where((m) => m.projected).toList();
      expect(marks, isNotEmpty);
      for (final m in marks) {
        expect(m.time.isAfter(real.last), isTrue);
        expect(m.time.second % 10, 0);
      }
    });
  });

  group("TC-LIVE-03 ticks during a gesture", () {
    testWidgets("a drag carries on without a jump", (tester) async {
      await _pump(tester, anchor: ChartAnchor.left);
      final origin = tester.getTopLeft(_chartFinder);
      final start = _host.ctx.scrollOffset;
      final finger = await tester.startGesture(origin + const Offset(600, 200));

      var x = 600.0;
      for (var i = 0; i < 25; i++) {
        x -= 8; // dragging left moves further into the newest side
        await finger.moveTo(origin + Offset(x, 200));
        await tester.pump(const Duration(seconds: 1)); // a tick lands
      }
      await finger.up();
      await tester.pump();
      expect(tester.takeException(), isNull);
      // 25 ticks added bars and updated the last one; the drag still moved the
      // view by exactly the distance travelled.
      expect(_host.bars.length, 102);
      expect(_host.ctx.scrollOffset, closeTo(start + 200, 0.5));
    });

    testWidgets("a pinch carries on without a jump", (tester) async {
      await _pump(tester);
      final c = tester.getCenter(_chartFinder);
      final a = await tester.startGesture(c - const Offset(50, 0), pointer: 1);
      final b = await tester.startGesture(c + const Offset(50, 0), pointer: 2);

      final extents = <double>[];
      for (var span = 100.0; span <= 300; span += 4) {
        await a.moveTo(c - Offset(span / 2, 0));
        await b.moveTo(c + Offset(span / 2, 0));
        await tester.pump(const Duration(milliseconds: 400)); // ticks land
        extents.add(_host.ctx.slotExtent);
      }
      await a.up();
      await b.up();
      expect(_host.ticks, greaterThan(15));
      expect(extents.last, greaterThan(extents.first * 1.5));
      // No step between consecutive samples is a jump.
      for (var i = 1; i < extents.length; i++) {
        expect(extents[i] / extents[i - 1], lessThan(1.1), reason: "step $i");
        expect(extents[i], greaterThanOrEqualTo(extents[i - 1] * 0.99));
      }
    });

    testWidgets("a long-press crosshair drag survives ticks", (tester) async {
      await _pump(tester, crosshair: true);
      final origin = tester.getTopLeft(_chartFinder);
      final finger = await tester.startGesture(origin + const Offset(300, 200));
      await tester.pump(const Duration(milliseconds: 600));
      expect(_host.controller.highlightedIndex, isNotNull);
      final index = _host.controller.highlightedIndex;

      await _ticks(tester, 12);
      expect(_host.controller.highlightedIndex, index);
      await finger.up();
      await tester.pump();
      expect(_host.controller.highlightedIndex, isNull);
    });
  });

  group("TC-LIVE-04 ticks while the crosshair is shown", () {
    final badges = find.byWidgetPredicate(
      (w) => w is Container && w.color == const Color(0xFF222BBB),
    );

    String? valueBadge(WidgetTester tester) {
      for (final t in tester.widgetList<Text>(
        find.descendant(of: badges, matching: find.byType(Text)),
      )) {
        if (RegExp(r"^\d+\.\d\d$").hasMatch(t.data!)) {
          return t.data;
        }
      }
      return null;
    }

    testWidgets("on the forming bar the readout follows the ticks", (
      tester,
    ) async {
      await _pump(tester, crosshair: true);
      final origin = tester.getTopLeft(_chartFinder);
      final last = _host.bars.length - 1;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(
        location: origin + Offset(_host.ctx.xOf(last), 100),
      );
      await mouse.moveTo(origin + Offset(_host.ctx.xOf(last) + 0.5, 100));
      await tester.pump();
      expect(_host.controller.highlightedIndex, last);

      for (var i = 1; i <= 8; i++) {
        await tester.pump(const Duration(seconds: 1));
        expect(_host.controller.highlightedIndex, last);
        expect(valueBadge(tester), _host.bars[last].close.toStringAsFixed(2));
      }
    });

    testWidgets("after a rollover the crosshair stays on its bar, frozen", (
      tester,
    ) async {
      await _pump(tester, crosshair: true);
      final origin = tester.getTopLeft(_chartFinder);
      final last = _host.bars.length - 1;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(
        location: origin + Offset(_host.ctx.xOf(last), 100),
      );
      await mouse.moveTo(origin + Offset(_host.ctx.xOf(last) + 0.5, 100));
      await tester.pump();

      await _ticks(tester, 10); // crosses the boundary: a new last bar
      expect(_host.bars.length, last + 2);
      expect(_host.controller.highlightedIndex, last);
      final frozen = _host.bars[last].close;
      await _ticks(tester, 5);
      expect(_host.bars[last].close, frozen);
      expect(valueBadge(tester), frozen.toStringAsFixed(2));
    });
  });

  testWidgets("TC-LIVE-05 an hour of ticks: frame cost stays flat", (
    tester,
  ) async {
    await _pump(tester);
    Future<int> batch(int ticks) async {
      final watch = Stopwatch()..start();
      await _ticks(tester, ticks);
      return watch.elapsedMicroseconds;
    }

    final first = await batch(300);
    for (var i = 0; i < 10; i++) {
      await batch(300);
    }
    final last = await batch(300);

    expect(_host.ticks, 3600);
    expect(_host.bars.length, 100 + 360);
    expect(tester.takeException(), isNull);
    // Allow generous noise; the point is that cost does not grow with the
    // length of the series (a leak or an O(n) per-tick pass would).
    expect(
      last,
      lessThan(first * 4 + 200000),
      reason: "first batch ${first}us, last batch ${last}us",
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
