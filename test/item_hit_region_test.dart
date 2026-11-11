// Unit tests for the shared hit region of painted layers (ItemHitRegion and
// topmostRectAt). Layer-level behaviour is in test/layers_test.dart.
import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:interactive_chart/src/painting/item_hit_region.dart";

void main() {
  group("topmostRectAt", () {
    test("empty list", () {
      expect(topmostRectAt(const [], Offset.zero, 10), isNull);
    });

    test(
      "finds the rect under the point, with open right and bottom edges",
      () {
        final rects = [
          for (var i = 0; i < 10; i++) Rect.fromLTWH(i * 10.0, 0, 8, 8),
        ];
        expect(topmostRectAt(rects, Offset.zero, 8), 0);
        expect(topmostRectAt(rects, const Offset(7.99, 7.99), 8), 0);
        expect(topmostRectAt(rects, const Offset(8, 4), 8), isNull); // gap
        expect(topmostRectAt(rects, const Offset(4, 8), 8), isNull); // below
        expect(topmostRectAt(rects, const Offset(55, 4), 8), 5);
        expect(topmostRectAt(rects, const Offset(-1, 4), 8), isNull);
        expect(topmostRectAt(rects, const Offset(97.9, 4), 8), 9);
        expect(topmostRectAt(rects, const Offset(98, 4), 8), isNull);
        expect(topmostRectAt(rects, const Offset(200, 4), 8), isNull);
      },
    );

    test("where rects overlap the later one wins", () {
      final rects = [
        for (var i = 0; i < 10; i++) Rect.fromLTWH(i * 4.0, 0, 12, 12),
      ];
      // x = 10 is inside rects 0 (0..12), 1 (4..16) and 2 (8..20).
      expect(topmostRectAt(rects, const Offset(10, 5), 12), 2);
      expect(topmostRectAt(rects, const Offset(1, 5), 12), 0);
      expect(topmostRectAt(rects, const Offset(47, 5), 12), 9);
    });

    test("a lower rect is found when the later ones miss vertically", () {
      final rects = [
        const Rect.fromLTWH(0, 0, 12, 12),
        const Rect.fromLTWH(4, 50, 12, 12),
      ];
      expect(topmostRectAt(rects, const Offset(6, 6), 12), 0);
      expect(topmostRectAt(rects, const Offset(6, 55), 12), 1);
    });
  });

  group("ItemHitRegion", () {
    // Items are 20 px wide columns at x = 20 * i .. 20 * i + 10.
    int? columns(Offset p) {
      final i = p.dx ~/ 20;
      return p.dx - i * 20 < 10 ? i : null;
    }

    Future<void> pump(
      WidgetTester tester, {
      void Function(int)? onTap,
      void Function(int?)? onHover,
      VoidCallback? onBelowTap,
    }) => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onBelowTap,
              ),
            ),
            Positioned.fill(
              child: ItemHitRegion(
                resolve: columns,
                onTap: onTap,
                onHover: onHover,
              ),
            ),
          ],
        ),
      ),
    );

    testWidgets("taps report the item; misses fall through", (tester) async {
      final taps = <int>[];
      var below = 0;
      await pump(tester, onTap: taps.add, onBelowTap: () => below++);
      await tester.tapAt(const Offset(45, 100));
      await tester.tapAt(const Offset(55, 100)); // between items
      await tester.tapAt(const Offset(61, 100));
      expect(taps, [2, 3]);
      expect(below, 1);
    });

    testWidgets("a tap that moves off before lifting reports where it went "
        "down", (tester) async {
      final taps = <int>[];
      await pump(tester, onTap: taps.add);
      final gesture = await tester.startGesture(const Offset(41, 100));
      await gesture.moveTo(const Offset(43, 100));
      await gesture.up();
      expect(taps, [2]);
    });

    testWidgets("hover reports enter, moves between items and exit", (
      tester,
    ) async {
      final hovers = <int?>[];
      await pump(tester, onHover: hovers.add);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 100));
      await tester.pump();
      await mouse.moveTo(const Offset(5, 100)); // same item: nothing new
      await mouse.moveTo(const Offset(15, 100)); // off it
      await mouse.moveTo(const Offset(21, 100));
      await mouse.moveTo(const Offset(41, 100)); // over the gap to item 2
      await mouse.removePointer();
      await tester.pump();
      expect(hovers, [0, null, 1, null, 2, null]);
    });

    testWidgets("with only a hover callback an item still covers what is "
        "below it, like a mouse region; a miss falls through", (tester) async {
      var below = 0;
      await pump(tester, onHover: (_) {}, onBelowTap: () => below++);
      await tester.tapAt(const Offset(45, 100));
      expect(below, 0);
      await tester.tapAt(const Offset(55, 100));
      expect(below, 1);
    });

    testWidgets("items moving under a still mouse are re-resolved", (
      tester,
    ) async {
      final hovers = <int?>[];
      var shift = 0.0;
      Widget app() => Directionality(
        textDirection: TextDirection.ltr,
        child: ItemHitRegion(
          resolve: (p) => columns(p.translate(shift, 0)),
          onHover: hovers.add,
        ),
      );
      await tester.pumpWidget(app());
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(45, 100));
      await tester.pump();
      expect(hovers, [2]);
      shift = 20;
      await tester.pumpWidget(app());
      await tester.pump();
      expect(hovers, [2, null, 3]);
      // Shifted onto a gap: an exit.
      shift = 30;
      await tester.pumpWidget(app());
      await tester.pump();
      expect(hovers, [2, null, 3, null]);
    });
  });
}
