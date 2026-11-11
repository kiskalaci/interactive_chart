// PriceTagLayer: a line at the latest value across the chart and a tag on the
// value axis. See docs/poc_notes.md.
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart" hide testWidgets;
import "package:interactive_chart/interactive_chart.dart";
import "package:interactive_chart/src/value_axis/value_ticks.dart";

import "support/chart_harness.dart";
import "support/variants.dart";

const _lineColor = Color(0xFF123456);
const _tagColor = Color(0xFF654321);

final _chartFinder = find.byType(InteractiveChart<int>);
final _lineFinder = find.byWidgetPredicate(
  (w) => w is ColoredBox && w.color == _lineColor,
  description: "price line",
);
final _tagFinder = find.byWidgetPredicate(
  (w) => w is Container && w.color == _tagColor,
  description: "price tag",
);

/// The datum value is `i + 0.999`, so the newest of `count` data is
/// `count - 1 + 0.999`: a value that rounding would push up to the next
/// integer.
double _valueOf(int i) => i + 0.999;

ChartHarness<int> _harness({
  int precision = 2,
  ValueAxisConfig? valueAxis = const ValueAxisConfig(),
}) => ChartHarness<int>(
  timeOf: minuteTime,
  valueAxis: valueAxis,
  layers: () => [
    // A series, so autoscale frames the values.
    const LineLayer<int>(valueOf: _valueOf),
    PriceTagLayer<int>(
      valueOf: _valueOf,
      precision: precision,
      lineColor: _lineColor,
      tagColor: _tagColor,
    ),
  ],
);

void main() {
  group("truncateToDecimals crops instead of rounding", () {
    final cases = <(double, int, String)>[
      (1.239, 2, "1.23"),
      (1.999, 2, "1.99"),
      (-1.239, 2, "-1.23"),
      (0.29, 2, "0.29"), // binary 0.28999... must not become 0.28
      (1.005, 2, "1.00"),
      (5, 2, "5.00"),
      (5.5, 0, "5"),
      (5.999, 0, "5"),
      (0.5, 0, "0"),
      (123.456789, 4, "123.4567"),
      (1.5, 4, "1.5000"),
      (0, 2, "0.00"),
      (-0.001, 2, "0.00"), // no negative zero
      (1e-7, 2, "0.00"),
      (1.5e-7, 9, "0.000000150"),
      (1e21, 2, "1000000000000000000000.00"),
      (1.5e21, 1, "1500000000000000000000.0"),
      (123456789.987654, 3, "123456789.987"),
    ];
    for (final (value, decimals, expected) in cases) {
      test("$value at $decimals -> $expected", () {
        expect(truncateToDecimals(value, decimals), expected);
      });
    }

    test("non-finite values are passed through", () {
      expect(truncateToDecimals(double.nan, 2), "NaN");
      expect(truncateToDecimals(double.infinity, 2), "Infinity");
    });
  });

  group("PriceTagLayer", () {
    testWidgets("the tag shows the newest value cropped, not rounded", (
      tester,
    ) async {
      final h = _harness();
      await tester.pumpWidget(h.app(intSeries(0, 30)));
      await tester.pumpAndSettle();
      // 29.999 rounds to 30.00; cropping gives 29.99.
      expect(find.text("29.99"), findsOneWidget);
      // (The axis's own "30.00" tick label is not the tag.)
      expect(
        find.descendant(of: _tagFinder, matching: find.text("30.00")),
        findsNothing,
      );
    });

    testWidgets("precision sets the digits after the separator", (
      tester,
    ) async {
      final h = _harness(precision: 0);
      await tester.pumpWidget(h.app(intSeries(0, 30)));
      await tester.pumpAndSettle();
      expect(find.text("29"), findsOneWidget);

      final wide = _harness(precision: 5);
      await tester.pumpWidget(wide.app(intSeries(0, 30)));
      await tester.pumpAndSettle();
      expect(find.text("29.99900"), findsOneWidget);
    });

    testWidgets("the line crosses the whole viewport at the value", (
      tester,
    ) async {
      final h = _harness();
      await tester.pumpWidget(h.app(intSeries(0, 30)));
      await tester.pumpAndSettle();

      final origin = tester.getTopLeft(_chartFinder);
      expect(_lineFinder, findsOneWidget);
      final line = tester.getRect(_lineFinder);
      expect(line.top - origin.dy, closeTo(h.ctx.yOf(_valueOf(29)), 0.001));
      expect(line.height, 1);
      expect(line.left - origin.dx, 0);
      expect(line.width, h.ctx.viewportWidth);
    });

    testWidgets("the tag sits on the value axis, centred on the line", (
      tester,
    ) async {
      final h = _harness();
      await tester.pumpWidget(h.app(intSeries(0, 30)));
      await tester.pumpAndSettle();

      final viewportRight =
          tester.getTopLeft(_chartFinder).dx + h.ctx.viewportWidth;
      final tag = tester.getRect(_tagFinder);
      final line = tester.getRect(_lineFinder);
      expect(tag.left, closeTo(viewportRight, 0.001));
      expect(tag.center.dy, closeTo(line.center.dy, 0.6));
    });

    testWidgets("the tag follows the latest datum, not the visible ones", (
      tester,
    ) async {
      final h = _harness();
      await tester.pumpWidget(h.app(intSeries(0, 400)));
      await tester.pumpAndSettle();
      h.ctx.jumpTo(0);
      await tester.pumpAndSettle();

      // Slot 399 is far off to the right, but its value is still tagged.
      expect(h.ctx.visibleEnd, lessThan(399));
      expect(find.text("399.99"), findsOneWidget);
    });

    testWidgets("the tag updates when a newer datum arrives", (tester) async {
      final h = _harness();
      await tester.pumpWidget(h.app(intSeries(0, 30)));
      await tester.pumpAndSettle();
      await tester.pumpWidget(h.app(intSeries(0, 31)));
      await tester.pumpAndSettle();
      expect(find.text("30.99"), findsOneWidget);
      expect(find.text("29.99"), findsNothing);
    });

    testWidgets("a NaN newest value falls back to the last finite one", (
      tester,
    ) async {
      final h = ChartHarness<int>(
        timeOf: minuteTime,
        layers: () => [
          LineLayer<int>(valueOf: (i) => i + 0.5),
          PriceTagLayer<int>(
            valueOf: (i) => i == 29 ? double.nan : i + 0.5,
            tagColor: _tagColor,
          ),
        ],
      );
      await tester.pumpWidget(h.app(intSeries(0, 30)));
      await tester.pumpAndSettle();
      expect(find.text("28.50"), findsOneWidget);
    });

    testWidgets("empty data draws nothing", (tester) async {
      final h = _harness();
      await tester.pumpWidget(h.app(const []));
      await tester.pumpAndSettle();
      expect(_lineFinder, findsNothing);
      expect(_tagFinder, findsNothing);
    });

    testWidgets("without a value axis only the line is drawn", (tester) async {
      final h = _harness(valueAxis: null);
      await tester.pumpWidget(h.app(intSeries(0, 30)));
      await tester.pumpAndSettle();
      expect(_lineFinder, findsOneWidget);
      expect(_tagFinder, findsNothing);
      expect(find.text("29.99"), findsNothing);
    });

    testWidgets("works with the value axis on the left", (tester) async {
      final h = _harness(
        valueAxis: const ValueAxisConfig(placement: ValueAxisPlacement.left),
      );
      await tester.pumpWidget(h.app(intSeries(0, 30)));
      await tester.pumpAndSettle();
      final tag = tester.getRect(_tagFinder);
      final chartLeft = tester.getTopLeft(_chartFinder).dx;
      expect(tag.left, closeTo(chartLeft, 0.001));
      expect(tag.right, lessThanOrEqualTo(chartLeft + 80));
    });

    testWidgets("the axis grows so a wide tag is not clipped", (tester) async {
      // Seven digits after the separator are far wider than the tick labels.
      final h = _harness(precision: 7);
      await tester.pumpWidget(h.app(intSeries(0, 30)));
      await tester.pumpAndSettle();
      final tag = tester.getRect(_tagFinder);
      final text = tester.getRect(find.text("29.9990000"));
      expect(text.left, greaterThanOrEqualTo(tag.left));
      expect(text.right, lessThanOrEqualTo(tag.right));
      expect(tester.takeException(), isNull);
    });

    testWidgets("off-screen levels stick the tag to the axis edge", (
      tester,
    ) async {
      final h = _harness();
      await tester.pumpWidget(h.app(intSeries(0, 30)));
      await tester.pumpAndSettle();
      h.ctx
        ..setAutoscale(false)
        ..setValueExtent(1000, 2000); // the latest value (29.999) is far below
      await tester.pumpAndSettle();

      final origin = tester.getTopLeft(_chartFinder);
      final tag = tester.getRect(_tagFinder);
      expect(tag.bottom - origin.dy, closeTo(h.ctx.viewportHeight, 0.001));
      expect(_lineFinder, findsNothing);
    });

    testWidgets("it does not take part in autoscale", (tester) async {
      final h = ChartHarness<int>(
        timeOf: minuteTime,
        layers: () => [
          LineLayer<int>(valueOf: (i) => 1.0 * i),
          PriceTagLayer<int>(valueOf: (i) => 1e6),
        ],
      );
      await tester.pumpWidget(h.app(intSeries(0, 30)));
      await tester.pumpAndSettle();
      expect(h.ctx.valueMax, lessThan(100));
    });
  });
}
