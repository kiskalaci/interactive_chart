// Test plan section 11: paging integration (TC-PAGE-*). The library has no
// paging API, so these drive the documented pattern (see PagingHost in
// test/support/hosts.dart) through onVisibleRangeChanged. See
// docs/poc_notes.md.
import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:interactive_chart/interactive_chart.dart";

import "support/chart_harness.dart";
import "support/hosts.dart";

final _chartFinder = find.byType(InteractiveChart<int>);

/// Records fetches and lets a test complete each one when it chooses.
class _Script {
  final pending = <Completer<List<int>>>[];
  final asked = <int>[];

  Future<List<int>> fetch(int beforeId) {
    asked.add(beforeId);
    final c = Completer<List<int>>();
    pending.add(c);
    return c.future;
  }

  /// Completes the oldest pending fetch with [count] older ids.
  void complete(int count, {int? before}) {
    final c = pending.removeAt(0);
    final end = before ?? asked[asked.length - pending.length - 1];
    c.complete([for (var i = end - count; i < end; i++) i]);
  }

  void completeEmpty() => pending.removeAt(0).complete(const []);
}

final _key = GlobalKey<PagingHostState>();

Future<_Script> _pump(
  WidgetTester tester, {
  ChartAnchor anchor = ChartAnchor.right,
  int maxPages = 1000,
  double Function(int)? valueOf,
}) async {
  final script = _Script();
  await tester.pumpWidget(
    PagingHost(
      key: _key,
      fetch: script.fetch,
      anchor: anchor,
      maxPages: maxPages,
      valueOf: valueOf,
    ),
  );
  await tester.pumpAndSettle();
  return script;
}

PagingHostState get _host => _key.currentState!;

/// Drags to the oldest data.
Future<void> _toStart(WidgetTester tester) async {
  await tester.drag(_chartFinder, const Offset(4000, 0), warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("TC-PAGE-01 entering the threshold zone issues one request", (
    tester,
  ) async {
    final script = await _pump(tester);
    expect(_host.requests, 0, reason: "nothing near the start yet");

    await _toStart(tester);
    expect(_host.requests, 1);
    expect(script.asked, [1000]);
  });

  testWidgets(
    "TC-PAGE-02 dwelling in the zone does not issue a second request",
    (tester) async {
      final script = await _pump(tester);
      await _toStart(tester);
      expect(_host.requests, 1);

      // Keep nudging around inside the zone while the request is in flight.
      for (final dx in [30.0, -20.0, 40.0, -15.0, 50.0]) {
        await tester.drag(_chartFinder, Offset(dx, 0), warnIfMissed: false);
        await tester.pumpAndSettle();
      }
      final pointer = TestPointer(1);
      pointer.hover(tester.getCenter(_chartFinder));
      await tester.pump(const Duration(seconds: 1));
      expect(_host.requests, 1);
      expect(script.pending.length, 1);
    },
  );

  group("TC-PAGE-03 a page landing at the left edge", () {
    testWidgets("shifts the view and does not cascade", (tester) async {
      final script = await _pump(tester, anchor: ChartAnchor.left);
      // Opened at the start: the initial announce asks for the first page.
      expect(_host.requests, 1);
      expect(_host.controller.visibleRange.$1, 0);

      script.complete(120);
      await tester.pumpAndSettle();
      expect(_host.data.length, 520);
      expect(_host.controller.visibleRange.$1, 120);

      // Nothing more is requested without the user doing anything.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(_host.requests, 1);
    });

    testWidgets("the same bars stay under the same pixels", (tester) async {
      final script = await _pump(tester, anchor: ChartAnchor.left);
      final idAtX = _host.data[_host.ctx.indexAtViewportX(300)];
      script.complete(120);
      await tester.pumpAndSettle();
      expect(_host.data[_host.ctx.indexAtViewportX(300)], idAtX);
    });
  });

  group("TC-PAGE-04 exhausted latch", () {
    testWidgets("no request after the source reports no more history", (
      tester,
    ) async {
      final script = await _pump(tester);
      await _toStart(tester);
      expect(_host.requests, 1);
      script.completeEmpty();
      await tester.pumpAndSettle();
      expect(_host.exhausted, isTrue);

      for (var i = 0; i < 4; i++) {
        await tester.drag(
          _chartFinder,
          const Offset(300, 0),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        await tester.drag(
          _chartFinder,
          const Offset(-60, 0),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
      }
      expect(_host.requests, 1);
    });
  });

  testWidgets(
    "TC-PAGE-05 pages too small to clear the threshold stop at the cap",
    (tester) async {
      final script = await _pump(tester, anchor: ChartAnchor.left, maxPages: 3);
      expect(_host.requests, 1);

      // Each 5-bar page leaves the view inside the threshold, and the chart
      // does not re-announce after a prepend, so the next request waits for
      // the next interaction. The host stops at three pages.
      for (var page = 1; page <= 3; page++) {
        script.complete(5);
        await tester.pumpAndSettle();
        expect(_host.pagesLoaded, page);
        expect(_host.controller.visibleRange.$1, lessThanOrEqualTo(20));
        // A nudge back to the very start is the next interaction.
        await tester.drag(
          _chartFinder,
          const Offset(500, 0),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        if (page < 3) {
          expect(_host.requests, page + 1);
        }
      }
      expect(_host.requests, 3);
      expect(script.pending, isEmpty);
      await tester.drag(
        _chartFinder,
        const Offset(500, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(_host.requests, 3);
    },
  );

  testWidgets("TC-PAGE-06 a result arriving after dispose is discarded", (
    tester,
  ) async {
    final script = await _pump(tester);
    await _toStart(tester);
    expect(script.pending.length, 1);

    await tester.pumpWidget(const SizedBox());
    script.complete(120);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    "TC-PAGE-07 a page landing mid-drag neither jumps nor stops the drag",
    (tester) async {
      final script = await _pump(tester);
      // Get close to the start, outside the threshold zone.
      var guard = 0;
      while (_host.controller.visibleRange.$1 > 100 && guard++ < 40) {
        await tester.drag(
          _chartFinder,
          const Offset(200, 0),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
      }
      expect(_host.requests, 0);

      // A held drag towards the start, in small steps, from near the left.
      final origin = tester.getTopLeft(_chartFinder);
      var fingerX = 100.0;
      final finger = await tester.startGesture(origin + Offset(fingerX, 200));
      guard = 0;
      while (_host.requests == 0 && guard++ < 300) {
        fingerX += 8;
        await finger.moveTo(origin + Offset(fingerX, 200));
        await tester.pump();
      }
      expect(_host.requests, 1);
      for (var i = 0; i < 2; i++) {
        fingerX += 8;
        await finger.moveTo(origin + Offset(fingerX, 200));
        await tester.pump();
      }
      final idUnderFinger = _host.data[_host.ctx.indexAtViewportX(fingerX)];
      final offsetBefore = _host.ctx.scrollOffset;

      // The page lands while the finger is still down.
      script.complete(120);
      await tester.pump(); // the future's continuation runs after this frame
      await tester.pump(); // ...and the rebuild it scheduled
      expect(_host.data[_host.ctx.indexAtViewportX(fingerX)], idUnderFinger);
      expect(_host.ctx.scrollOffset, closeTo(offsetBefore + 120 * 8, 0.001));

      // The drag carries on from there: 30 px further moves the view 30 px.
      final afterPage = _host.ctx.scrollOffset;
      fingerX -= 30;
      await finger.moveTo(origin + Offset(fingerX, 200));
      await tester.pump();
      expect(
        _host.ctx.scrollOffset,
        closeTo(afterPage + 30, 0.5),
        reason: "the view jumped when the page landed during the drag",
      );
      await finger.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "TC-PAGE-08 a prepend outside the view leaves extent and marks alone",
    (tester) async {
      // Older bars are wildly out of scale; they must not move the extent.
      final script = await _pump(
        tester,
        valueOf: (id) => id < 1000 ? 1e6 : 100.0 + id % 13,
      );
      await tester.drag(
        _chartFinder,
        const Offset(500, 0),
        warnIfMissed: false,
      ); // mid-history
      await tester.pumpAndSettle();
      expect(_host.requests, 0);

      List<String> onScreenMarks() => [
        for (final m in _host.ctx.timeTicks)
          if (_host.ctx.xOf(m.index) >= 0 &&
              _host.ctx.xOf(m.index) <= _host.ctx.viewportWidth)
            "${m.time.toIso8601String()}:${m.weight}",
      ];

      final extent = (_host.ctx.valueMin, _host.ctx.valueMax);
      final marks = onScreenMarks();
      expect(marks, isNotEmpty);

      // Force a load by hand, as a caller prefetching ahead of the threshold.
      _host.prepend(120);
      await tester.pumpAndSettle();
      expect(script.pending, isEmpty);

      expect((_host.ctx.valueMin, _host.ctx.valueMax), extent);
      expect(onScreenMarks(), marks);
    },
  );

  testWidgets("TC-PAGE-09 a live append during a load: both land, in order", (
    tester,
  ) async {
    final script = await _pump(tester);
    await _toStart(tester);
    expect(script.pending.length, 1);
    final before = _host.controller.visibleRange;

    _host.appendLive(2);
    await tester.pumpAndSettle();
    expect(
      _host.controller.visibleRange,
      before,
      reason: "an append moved the view",
    );

    script.complete(120);
    await tester.pumpAndSettle();

    expect(_host.data.first, 880);
    expect(_host.data.last, 1401);
    expect(_host.data.length, 400 + 120 + 2);
    for (var i = 1; i < _host.data.length; i++) {
      expect(
        _host.data[i],
        _host.data[i - 1] + 1,
        reason: "gap or reorder at $i",
      );
    }
    expect(_host.controller.visibleRange.$1, before.$1 + 120);
    expect(_host.requests, 1);
  });

  testWidgets(
    "TC-PAGE-10 opened at the start: the initial announce loads at most once",
    (tester) async {
      final script = await _pump(tester, anchor: ChartAnchor.left);
      expect(_host.requests, 1);
      expect(script.pending.length, 1);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(_host.requests, 1);
    },
  );

  testWidgets("opened at the end: the initial announce loads nothing", (
    tester,
  ) async {
    await _pump(tester, anchor: ChartAnchor.right);
    expect(_host.requests, 0);
    expect(minuteTime(0), isA<DateTime>());
  });
}
