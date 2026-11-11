// Axis and price-tag labels are measured through a shared size cache, and
// the time axis only formats and measures the marks that can show.
import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart" hide testWidgets;
import "package:interactive_chart/interactive_chart.dart";
import "package:interactive_chart/src/painting/label_sizes.dart";
import "package:interactive_chart/src/time_axis/time_ticks.dart";

import "support/chart_harness.dart";
import "support/variants.dart";

const _style = TextStyle(fontSize: 11);

Size _measured(String text, TextStyle style, TextScaler scaler) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  )..layout();
  final size = painter.size;
  painter.dispose();
  return size;
}

void main() {
  group("LabelSizes", () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test("returns the laid-out size, and lays out each label once", () {
      final sizes = LabelSizes();
      for (final text in ["12:30", "2024", "Mar", "1,234.56", ""]) {
        expect(
          sizes.of(text, _style, TextScaler.noScaling),
          _measured(text, _style, TextScaler.noScaling),
        );
      }
      expect(sizes.layouts, 5);
      sizes
        ..of("12:30", _style, TextScaler.noScaling)
        ..of("2024", _style, TextScaler.noScaling);
      expect(sizes.layouts, 5);
    });

    test("style and text scale are part of the key", () {
      final sizes = LabelSizes();
      final plain = sizes.of("12:30", _style, TextScaler.noScaling);
      final bold = sizes.of(
        "12:30",
        _style.copyWith(fontWeight: FontWeight.bold),
        TextScaler.noScaling,
      );
      final scaled = sizes.of("12:30", _style, const TextScaler.linear(2));
      expect(sizes.layouts, 3);
      expect(scaled.width, closeTo(plain.width * 2, 1));
      expect(
        bold,
        _measured(
          "12:30",
          _style.copyWith(fontWeight: FontWeight.bold),
          TextScaler.noScaling,
        ),
      );
      // An equal style built separately is the same key.
      sizes.of("12:30", const TextStyle(fontSize: 11), TextScaler.noScaling);
      expect(sizes.layouts, 3);
    });

    test("keeps at most capacity sizes, dropping the least recently used", () {
      final sizes = LabelSizes(capacity: 3)
        ..of("a", _style, TextScaler.noScaling)
        ..of("b", _style, TextScaler.noScaling)
        ..of("c", _style, TextScaler.noScaling)
        ..of("a", _style, TextScaler.noScaling) // a is now the most recent
        ..of("d", _style, TextScaler.noScaling); // drops b
      expect(sizes.length, 3);
      expect(sizes.layouts, 4);
      sizes.of("a", _style, TextScaler.noScaling);
      expect(sizes.layouts, 4);
      sizes.of("b", _style, TextScaler.noScaling);
      expect(sizes.layouts, 5);
    });

    testWidgetsOnce("a system font change clears it", (tester) async {
      final sizes = LabelSizes()..of("12:30", _style, TextScaler.noScaling);
      expect(sizes.length, 1);
      // ignore: invalid_use_of_protected_member
      await tester.binding.handleSystemMessage(<String, dynamic>{
        "type": "fontsChange",
      });
      expect(sizes.length, 0);
    });
  });

  group("time axis", () {
    /// The labels as the time axis placed them before: every mark measured,
    /// those that do not fit dropped.
    List<(String, double)> expectedLabels(
      ChartHarness<int> h,
      TimeAxisConfig config,
    ) {
      final width = h.ctx.viewportWidth;
      return [
        for (final mark in h.ctx.timeTicks)
          if (config.format(mark.time, mark.weight) case final text)
            if (_measured(
                  text,
                  mark.weight >= TickMarkWeight.month
                      ? config.emphasizedTextStyle
                      : config.textStyle,
                  TextScaler.noScaling,
                ).width
                case final w)
              if (h.ctx.xOf(mark.index) - w / 2 >= 0 &&
                  h.ctx.xOf(mark.index) + w / 2 <= width)
                (text, h.ctx.xOf(mark.index)),
      ];
    }

    List<(String, double)> shownLabels(WidgetTester tester) {
      final axis = find.byType(TimeAxisView);
      final origin = tester.getTopLeft(axis);
      return [
        for (final e
            in find
                .descendant(of: axis, matching: find.byType(Text))
                .evaluate())
          (
            (e.widget as Text).data!,
            tester.getRect(find.byWidget(e.widget)).center.dx - origin.dx,
          ),
      ];
    }

    testWidgets("shows the same labels as measuring every mark", (
      tester,
    ) async {
      const config = TimeAxisConfig();
      final h = ChartHarness<int>(timeOf: minuteTime, valueAxis: null);
      await tester.pumpWidget(h.app(intSeries(0, 5000)));
      await tester.pumpAndSettle();
      for (final scroll in [
        0.0,
        333.3,
        9000.0,
        39990.0,
        h.ctx.maxScrollOffset,
      ]) {
        h.ctx.jumpTo(scroll);
        await tester.pump();
        final expected = expectedLabels(h, config);
        final shown = shownLabels(tester);
        expect(expected, isNotEmpty);
        expect([for (final l in shown) l.$1], [for (final l in expected) l.$1]);
        for (final (k, (_, x)) in shown.indexed) {
          // Centred on its mark; the bold one can be pulled in at an edge.
          expect(x, closeTo(expected[k].$2, 3), reason: "at $scroll");
        }
      }
    });

    testWidgets("only marks inside the axis are formatted", (tester) async {
      var formatted = 0;
      final config = TimeAxisConfig(
        formatter: (t, w) {
          formatted++;
          return defaultTimeLabel(t, w);
        },
      );
      final h = ChartHarness<int>(
        timeOf: minuteTime,
        slotExtent: 2,
        valueAxis: null,
        timeAxis: config,
      );
      await tester.pumpWidget(h.app(intSeries(0, 50000)));
      await tester.pumpAndSettle();
      h.ctx.jumpTo(40000);
      await tester.pump();
      expect(h.ctx.timeTicks.length, greaterThan(1000));
      final inside = h.ctx.timeTicks
          .where(
            (m) =>
                h.ctx.xOf(m.index) >= 0 &&
                h.ctx.xOf(m.index) <= h.ctx.viewportWidth,
          )
          .length;
      formatted = 0;
      h.ctx.panBy(5);
      await tester.pump();
      expect(formatted, lessThanOrEqualTo(inside + 1));
      expect(formatted, greaterThan(0));
    });
  });

  testWidgets("panning back over the same labels lays none out again", (
    tester,
  ) async {
    final h = ChartHarness<int>(
      timeOf: minuteTime,
      layers: () => [
        LineLayer<int>(valueOf: (i) => 10.0 + i % 2),
        PriceTagLayer<int>(valueOf: (i) => 10.0 + i % 2),
      ],
    );
    await tester.pumpWidget(h.app(intSeries(0, 3000)));
    await tester.pumpAndSettle();
    h.ctx.jumpTo(8000);
    await tester.pump();
    for (final dx in [40.0, 40.0, -40.0, -40.0]) {
      h.ctx.panBy(dx);
      await tester.pump();
    }
    final layouts = LabelSizes.instance.layouts;
    for (final dx in [40.0, 40.0, -40.0, -40.0]) {
      h.ctx.panBy(dx);
      await tester.pump();
    }
    // Drag with a finger too.
    await tester.drag(find.byType(InteractiveChart<int>), const Offset(30, 0));
    await tester.drag(find.byType(InteractiveChart<int>), const Offset(-30, 0));
    await tester.pumpAndSettle();
    expect(LabelSizes.instance.layouts, layouts);
    expect(tester.takeException(), isNull);
  });

  testWidgets("a wheel zoom keeps axis labels on their marks", (tester) async {
    final h = ChartHarness<int>(timeOf: minuteTime, valueAxis: null);
    await tester.pumpWidget(h.app(intSeries(0, 3000)));
    await tester.pumpAndSettle();
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final axis = find.byType(TimeAxisView);
    await tester.sendEventToBinding(pointer.hover(tester.getCenter(axis)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 300)));
    await tester.pump();
    final origin = tester.getTopLeft(axis);
    for (final e
        in find.descendant(of: axis, matching: find.byType(Text)).evaluate()) {
      final rect = tester.getRect(find.byWidget(e.widget));
      expect(rect.left, greaterThanOrEqualTo(origin.dx - 0.01));
      expect(
        rect.right,
        lessThanOrEqualTo(origin.dx + h.ctx.viewportWidth + 0.01),
      );
    }
  });
}
