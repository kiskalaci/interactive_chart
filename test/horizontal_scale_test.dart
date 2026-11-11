// Test plan section 2: horizontal scale, viewport and anchoring (TC-X-*).
// See docs/poc_notes.md.
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart" hide testWidgets;
import "package:interactive_chart/interactive_chart.dart";
import "package:interactive_chart/src/chart_context.dart";

import "support/chart_harness.dart";
import "support/variants.dart";

InteractiveChartContext _ctx({
  int slots = 500,
  double width = 800,
  double slotExtent = 8,
  ChartAnchor anchor = ChartAnchor.left,
  double minSlotExtent = 1,
  double maxSlotExtent = 64,
}) =>
    InteractiveChartContext(
        initialAnchor: anchor,
        slotExtent: slotExtent,
        minSlotExtent: minSlotExtent,
        maxSlotExtent: maxSlotExtent,
      )
      ..setViewportSize(width, 400)
      ..setSlotCount(slots);

/// A chart with no axes, so no gutter changes the viewport after layout.
ChartHarness<int> _bareHarness({
  ChartAnchor anchor = ChartAnchor.left,
  double slotExtent = 8,
  double minSlotExtent = 1,
  double maxSlotExtent = 64,
}) => ChartHarness<int>(
  timeOf: minuteTime,
  anchor: anchor,
  slotExtent: slotExtent,
  minSlotExtent: minSlotExtent,
  maxSlotExtent: maxSlotExtent,
  valueAxis: null,
  timeAxis: null,
  layers: () => [LineLayer(valueOf: (d) => d.toDouble())],
);

void main() {
  group("TC-X-01 xOf and indexAtViewportX round-trip", () {
    for (final extent in [1.0, 2.5, 8.0, 17.3, 64.0]) {
      test("slot extent $extent", () {
        final ctx = _ctx(slotExtent: extent);
        for (final offset in [0.0, 123.4, 999.9]) {
          ctx.jumpTo(offset);
          for (var i = 0; i < ctx.slotCount; i += 7) {
            expect(ctx.indexAtViewportX(ctx.xOf(i)), i);
            expect(
              ctx.fractionalIndexAtViewportX(ctx.xOf(i)),
              closeTo(i + 0.5, 1e-9),
            );
          }
        }
      });
    }

    test("slot edges map to the slot that starts there", () {
      final ctx = _ctx(slotExtent: 10)..jumpTo(0);
      expect(ctx.indexAtViewportX(0), 0);
      expect(ctx.indexAtViewportX(9.999), 0);
      expect(ctx.indexAtViewportX(10), 1);
    });
  });

  group("TC-X-02 visible range covers exactly the slots in view", () {
    /// Brute force: slot i covers content pixels [i*e, (i+1)*e), and is in
    /// view when that interval overlaps [offset, offset + width).
    (int, int) expected(InteractiveChartContext c) {
      final e = c.slotExtent;
      final inView = [
        for (var i = 0; i < c.slotCount; i++)
          if ((i + 1) * e > c.scrollOffset &&
              i * e < c.scrollOffset + c.viewportWidth)
            i,
      ];
      return inView.isEmpty ? (0, 0) : (inView.first, inView.last + 1);
    }

    for (final extent in [2.0, 8.0, 13.7, 40.0]) {
      for (final offset in [0.0, 1.0, 399.5, 800.0, 1234.5, 2999.0]) {
        test("extent $extent, offset $offset", () {
          final ctx = _ctx(slotExtent: extent)..jumpTo(offset);
          expect((ctx.visibleStart, ctx.visibleEnd), expected(ctx));
        });
      }
    }

    test("never includes a projected slot (R-TIME-27)", () {
      final ctx = _ctx(slots: 100)
        ..jumpTo(1000000000); // as far right as allowed
      expect(ctx.visibleEnd, lessThanOrEqualTo(100));
      expect(ctx.visibleStart, lessThanOrEqualTo(ctx.visibleEnd));
    });
  });

  group("initial anchor", () {
    testWidgets("TC-X-03 left opens on the first datum", (tester) async {
      final h = _bareHarness();
      await tester.pumpWidget(h.app(intSeries(0, 500)));
      await tester.pumpAndSettle();
      expect(h.controller.visibleRange.$1, 0);
      expect(h.ctx.scrollOffset, 0);
    });

    testWidgets(
      "TC-X-04 right opens on the newest datum with overscroll after it",
      (tester) async {
        final h = _bareHarness(anchor: ChartAnchor.right);
        await tester.pumpWidget(h.app(intSeries(0, 500)));
        await tester.pumpAndSettle();

        expect(h.ctx.scrollOffset, h.ctx.maxScrollOffset);
        expect(h.controller.visibleRange.$2, 500);
        // Half the viewport is empty space after the newest bar.
        final lastX = h.ctx.xOf(499);
        expect(
          lastX,
          closeTo(h.ctx.viewportWidth / 2 - h.ctx.slotExtent / 2, 0.01),
        );
      },
    );

    testWidgets("TC-X-04b right with axes: newest bar in view after settling", (
      tester,
    ) async {
      final h = ChartHarness<int>(
        timeOf: minuteTime,
        anchor: ChartAnchor.right,
        layers: () => [LineLayer(valueOf: (d) => d.toDouble())],
      );
      await tester.pumpWidget(h.app(intSeries(0, 500)));
      await tester.pumpAndSettle();
      expect(h.controller.visibleRange.$2, 500);
    });

    testWidgets(
      "TC-X-05 applied once: data and viewport changes never re-anchor",
      (tester) async {
        final h = _bareHarness();
        await tester.pumpWidget(h.app(intSeries(0, 500)));
        await tester.pumpAndSettle();
        await tester.drag(
          find.byType(InteractiveChart<int>),
          const Offset(-400, 0),
        );
        await tester.pumpAndSettle();
        final offset = h.ctx.scrollOffset;
        expect(offset, greaterThan(0));

        await tester.pumpWidget(h.app(intSeries(0, 510)));
        await tester.pumpAndSettle();
        expect(h.ctx.scrollOffset, offset);

        final w = screenOf(tester).width;
        await tester.pumpWidget(h.app(intSeries(0, 510), width: w * 0.8));
        await tester.pumpAndSettle();
        expect(h.ctx.scrollOffset, offset);

        await tester.pumpWidget(h.app(intSeries(0, 510), width: w * 0.6));
        await tester.pumpAndSettle();
        expect(h.ctx.scrollOffset, offset);

        await tester.pumpWidget(h.app(intSeries(0, 510)));
        await tester.pumpAndSettle();
        expect(h.ctx.scrollOffset, offset);
      },
    );
  });

  group("overscroll", () {
    testWidgets("TC-X-06 past the newest datum up to half the viewport", (
      tester,
    ) async {
      final h = _bareHarness();
      // More bars than half a (large) viewport, so the overscroll rule applies.
      await tester.pumpWidget(h.app(intSeries(0, 1000)));
      await tester.pumpAndSettle();
      // Drag far further than the content is long.
      for (var i = 0; i < 4; i++) {
        await tester.drag(
          find.byType(InteractiveChart<int>),
          const Offset(-3000, 0),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
      }

      final w = h.ctx.viewportWidth;
      expect(h.ctx.scrollOffset, h.ctx.maxScrollOffset);
      // The newest bar rests at the half-way point: no further.
      expect(h.ctx.xOf(999), closeTo(w / 2 - h.ctx.slotExtent / 2, 0.01));
    });

    testWidgets("TC-X-07 before the oldest datum is not allowed", (
      tester,
    ) async {
      final h = _bareHarness(anchor: ChartAnchor.right);
      await tester.pumpWidget(h.app(intSeries(0, 500)));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(InteractiveChart<int>),
        const Offset(6000, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(h.ctx.scrollOffset, 0);
      expect(h.ctx.xOf(0), closeTo(h.ctx.slotExtent / 2, 0.01));
    });

    test("TC-X-07b jumpTo and panBy clamp at both ends", () {
      final ctx = _ctx(slots: 100)..jumpTo(-500);
      expect(ctx.scrollOffset, 0);
      ctx.jumpTo(1000000000);
      expect(ctx.scrollOffset, ctx.maxScrollOffset);
      ctx.panBy(-1000000000);
      expect(ctx.scrollOffset, 0);
    });
  });

  group("TC-X-08 slot extent is clamped to its bounds", () {
    test("context: initial extent", () {
      expect(_ctx(slotExtent: 0.2).slotExtent, 1);
      expect(_ctx(slotExtent: 500).slotExtent, 64);
      expect(
        _ctx(slotExtent: 10, minSlotExtent: 4, maxSlotExtent: 20).slotExtent,
        10,
      );
    });

    test("context: setSlotExtentAndScroll", () {
      final ctx = _ctx(minSlotExtent: 4, maxSlotExtent: 20)
        ..setSlotExtentAndScroll(1000, 0);
      expect(ctx.slotExtent, 20);
      ctx.setSlotExtentAndScroll(0.01, 0);
      expect(ctx.slotExtent, 4);
    });

    testWidgets("widget: initialSlotExtent outside the bounds", (tester) async {
      var h = _bareHarness(slotExtent: 0.2, minSlotExtent: 2);
      await tester.pumpWidget(h.app(intSeries(0, 100)));
      await tester.pumpAndSettle();
      expect(h.ctx.slotExtent, 2);

      // A new tree: State keeps its initial extent for the widget's lifetime.
      await tester.pumpWidget(const SizedBox());
      h = _bareHarness(slotExtent: 500, maxSlotExtent: 30);
      await tester.pumpWidget(h.app(intSeries(0, 100)));
      await tester.pumpAndSettle();
      expect(h.ctx.slotExtent, 30);
    });
  });

  group("TC-X-09 viewport resize", () {
    testWidgetsOnce("growing re-clamps the scroll offset", (tester) async {
      useLargeSurface(tester);
      final h = _bareHarness(anchor: ChartAnchor.right);
      await tester.pumpWidget(h.app(intSeries(0, 500)));
      await tester.pumpAndSettle();
      expect(h.ctx.scrollOffset, h.ctx.maxScrollOffset);

      await tester.pumpWidget(h.app(intSeries(0, 500), width: 1200));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(h.ctx.viewportWidth, 1200);
      expect(h.ctx.scrollOffset, lessThanOrEqualTo(h.ctx.maxScrollOffset));
      expect(h.ctx.scrollOffset, h.ctx.maxScrollOffset);
    });

    testWidgets("shrinking recomputes the visible range", (tester) async {
      final h = _bareHarness();
      await tester.pumpWidget(h.app(intSeries(0, 500)));
      await tester.pumpAndSettle();
      final wide = h.controller.visibleRange;

      final half = screenOf(tester).width / 2;
      await tester.pumpWidget(h.app(intSeries(0, 500), width: half));
      await tester.pumpAndSettle();
      final narrow = h.controller.visibleRange;

      expect(narrow.$1, wide.$1);
      expect(narrow.$2 - narrow.$1, lessThan(wide.$2 - wide.$1));
      expect(narrow.$2 - narrow.$1, closeTo(half / 8, 1.5));
    });

    testWidgetsOnce("to zero width and back", (tester) async {
      useLargeSurface(tester);
      final h = _bareHarness();
      await tester.pumpWidget(h.app(intSeries(0, 500)));
      await tester.pumpAndSettle();
      await tester.pumpWidget(h.app(intSeries(0, 500), width: 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(h.controller.visibleRange, (0, 0));

      await tester.pumpWidget(h.app(intSeries(0, 500)));
      await tester.pumpAndSettle();
      expect(h.controller.visibleRange.$2, greaterThan(50));
    });
  });

  group("TC-X-10 data shorter than the viewport", () {
    for (final anchor in ChartAnchor.values) {
      testWidgets("anchor ${anchor.name}", (tester) async {
        final h = _bareHarness(anchor: anchor);
        await tester.pumpWidget(h.app(intSeries(0, 20))); // 160 px of 800
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(h.controller.visibleRange, (0, 20));
        expect(h.ctx.scrollOffset, 0);
        expect(h.ctx.maxScrollOffset, 0);
        expect(h.ctx.xOf(0), closeTo(4, 0.01));
      });
    }

    testWidgets("dragging has nowhere to go", (tester) async {
      final h = _bareHarness();
      await tester.pumpWidget(h.app(intSeries(0, 20)));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(InteractiveChart<int>),
        const Offset(-200, 0),
      );
      await tester.pumpAndSettle();
      expect(h.ctx.scrollOffset, 0);
    });
  });
}
