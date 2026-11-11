// Test plan section 14: lifecycle and robustness (TC-LIFE-*). See
// docs/poc_notes.md.
import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart" hide testWidgets;
import "package:interactive_chart/interactive_chart.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/value_axis/value_ticks.dart";

import "support/chart_harness.dart";
import "support/variants.dart";

final _chartFinder = find.byType(InteractiveChart<int>);

Widget _chart({
  List<int>? data,
  List<ChartLayer<int>>? layers,
  ChartAnchor anchor = ChartAnchor.left,
  double slotExtent = 8,
  double minSlotExtent = 1,
  double maxSlotExtent = 64,
  ValueAxisConfig? valueAxis = const ValueAxisConfig(),
  TimeAxisConfig? timeAxis = const TimeAxisConfig(),
  InteractiveChartController? controller,
  bool crosshair = true,
  double? width,
  double? height,
  void Function(InteractiveChartContext)? onContext,
}) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      // Fills the screen unless a size is given.
      width: width ?? double.infinity,
      height: height ?? double.infinity,
      child: InteractiveChart<int>(
        controller: controller,
        data: data ?? intSeries(0, 400),
        timeOf: minuteTime,
        initialAnchor: anchor,
        initialSlotExtent: slotExtent,
        minSlotExtent: minSlotExtent,
        maxSlotExtent: maxSlotExtent,
        valueAxis: valueAxis,
        timeAxis: timeAxis,
        crosshairEnabled: crosshair,
        layers: [
          ...(layers ?? [LineLayer<int>(valueOf: (i) => 100.0 + i % 11)]),
          if (onContext != null) ContextProbe<int>(onContext),
        ],
      ),
    ),
  ),
);

class _Pulse extends StatefulWidget {
  const _Pulse();
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: c, child: const SizedBox.square(dimension: 10));
}

void main() {
  group("TC-LIFE-01 disposal at awkward moments", () {
    testWidgets("mid-drag", (tester) async {
      await tester.pumpWidget(_chart());
      await tester.pumpAndSettle();
      final finger = await tester.startGesture(tester.getCenter(_chartFinder));
      await finger.moveBy(const Offset(-80, 0));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await finger.moveBy(const Offset(-80, 0));
      await finger.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets("mid-pinch", (tester) async {
      await tester.pumpWidget(_chart());
      await tester.pumpAndSettle();
      final c = tester.getCenter(_chartFinder);
      final a = await tester.startGesture(c - const Offset(50, 0), pointer: 1);
      final b = await tester.startGesture(c + const Offset(50, 0), pointer: 2);
      for (var s = 60.0; s < 140; s += 10) {
        await a.moveTo(c - Offset(s, 0));
        await b.moveTo(c + Offset(s, 0));
        await tester.pump();
      }
      await tester.pumpWidget(const SizedBox());
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets("with a long-press timer still pending", (tester) async {
      await tester.pumpWidget(_chart());
      await tester.pumpAndSettle();
      final finger = await tester.startGesture(tester.getCenter(_chartFinder));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(const SizedBox()); // before the 500 ms fires
      await tester.pump(const Duration(seconds: 1));
      await finger.up();
      expect(tester.takeException(), isNull);
      // The test framework fails on any timer left pending, so passing here
      // also shows the timer was cancelled.
    });

    testWidgets("while a marker animation is running", (tester) async {
      await tester.pumpWidget(
        _chart(
          layers: [
            LineLayer<int>(
              valueOf: (i) => 100.0 + i % 11,
              latestPointBuilder: (_, _, _) => const _Pulse(),
            ),
          ],
          anchor: ChartAnchor.right,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(_Pulse), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets("before the first frame's post-frame callbacks run", (
      tester,
    ) async {
      // The chart schedules post-frame work (the initial range announcement
      // and gutter growth); unmounting immediately must not trip them.
      await tester.pumpWidget(_chart(anchor: ChartAnchor.right));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets("with the mouse hovering over it", (tester) async {
      await tester.pumpWidget(_chart());
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(_chartFinder));
      await mouse.moveTo(tester.getCenter(_chartFinder) + const Offset(10, 0));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await mouse.moveTo(const Offset(5, 5));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group("TC-LIFE-02 changing the layers between builds", () {
    testWidgets("add, remove and swap; autoscale follows", (tester) async {
      late InteractiveChartContext ctx;
      Widget build(List<ChartLayer<int>> layers) => _chart(
        layers: layers,
        valueAxis: null,
        timeAxis: null,
        onContext: (c) => ctx = c,
      );

      await tester.pumpWidget(
        build([LineLayer<int>(valueOf: (i) => 100.0 + i % 11)]),
      );
      await tester.pumpAndSettle();
      expect(ctx.valueMax, lessThan(120));

      // Add a layer with a much larger range.
      await tester.pumpWidget(
        build([
          LineLayer<int>(valueOf: (i) => 100.0 + i % 11),
          LineLayer<int>(valueOf: (i) => 5000.0 + i % 7),
        ]),
      );
      await tester.pumpAndSettle();
      expect(ctx.valueMax, greaterThan(5000));

      // Remove it again.
      await tester.pumpWidget(
        build([LineLayer<int>(valueOf: (i) => 100.0 + i % 11)]),
      );
      await tester.pumpAndSettle();
      expect(ctx.valueMax, lessThan(120));

      // Swap the type: lines for candles with a different range.
      await tester.pumpWidget(
        build([
          CandleLayer<int>(
            openOf: (i) => 300,
            highOf: (i) => 340,
            lowOf: (i) => 280,
            closeOf: (i) => 320,
            upColor: const Color(0xFF00AA00),
          ),
        ]),
      );
      await tester.pumpAndSettle();
      expect(ctx.valueMin, greaterThan(250));
      expect(ctx.valueMax, greaterThan(340));
      expect(tester.takeException(), isNull);
    });

    testWidgets("an empty layer list renders nothing and does not throw", (
      tester,
    ) async {
      await tester.pumpWidget(_chart(layers: const []));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets("pan and zoom survive a layer change", (tester) async {
      late InteractiveChartContext ctx;
      await tester.pumpWidget(_chart(onContext: (c) => ctx = c));
      await tester.pumpAndSettle();
      await tester.drag(_chartFinder, const Offset(-200, 0));
      await tester.pumpAndSettle();
      final offset = ctx.scrollOffset;
      await tester.pumpWidget(
        _chart(
          layers: [LineLayer<int>(valueOf: (i) => 7.0 * (i % 5))],
          onContext: (c) => ctx = c,
        ),
      );
      await tester.pumpAndSettle();
      expect(ctx.scrollOffset, offset);
    });
  });

  testWidgets("TC-LIFE-03 axes can appear and disappear at runtime", (
    tester,
  ) async {
    late InteractiveChartContext ctx;
    Widget build(ValueAxisConfig? v, TimeAxisConfig? t) =>
        _chart(valueAxis: v, timeAxis: t, onContext: (c) => ctx = c);
    const v = ValueAxisConfig();
    const t = TimeAxisConfig();

    await tester.pumpWidget(build(v, t));
    await tester.pumpAndSettle();
    final full = tester.getSize(_chartFinder);
    final withBoth = (ctx.viewportWidth, ctx.viewportHeight);
    expect(withBoth.$1, lessThan(full.width));
    expect(withBoth.$2, full.height - 22);

    await tester.pumpWidget(build(null, t));
    await tester.pumpAndSettle();
    expect(
      (ctx.viewportWidth, ctx.viewportHeight),
      (full.width, full.height - 22),
    );

    await tester.pumpWidget(build(null, null));
    await tester.pumpAndSettle();
    expect((ctx.viewportWidth, ctx.viewportHeight), (full.width, full.height));

    await tester.pumpWidget(build(v, null));
    await tester.pumpAndSettle();
    expect(ctx.viewportWidth, lessThan(full.width));
    expect(ctx.viewportHeight, full.height);

    await tester.pumpWidget(build(v, t));
    await tester.pumpAndSettle();
    expect((ctx.viewportWidth, ctx.viewportHeight), withBoth);
    expect(tester.takeException(), isNull);
  });

  group("TC-LIFE-04 initial-only parameters", () {
    testWidgets("initialAnchor and initialSlotExtent are read once", (
      tester,
    ) async {
      late InteractiveChartContext ctx;
      await tester.pumpWidget(_chart(onContext: (c) => ctx = c));
      await tester.pumpAndSettle();
      await tester.drag(_chartFinder, const Offset(-200, 0));
      await tester.pumpAndSettle();
      final offset = ctx.scrollOffset;
      final extent = ctx.slotExtent;

      await tester.pumpWidget(
        _chart(
          anchor: ChartAnchor.right,
          slotExtent: 30,
          onContext: (c) => ctx = c,
        ),
      );
      await tester.pumpAndSettle();
      expect(ctx.scrollOffset, offset);
      expect(ctx.slotExtent, extent);
    });

    testWidgets("min and max slot extent are read once too", (tester) async {
      late InteractiveChartContext ctx;
      await tester.pumpWidget(
        _chart(maxSlotExtent: 20, onContext: (c) => ctx = c),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _chart(maxSlotExtent: 200, onContext: (c) => ctx = c),
      );
      await tester.pumpAndSettle();

      final pointer = TestPointer(1, PointerDeviceKind.mouse)
        ..hover(tester.getCenter(_chartFinder));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -5000)));
      await tester.pump();
      expect(ctx.slotExtent, 20, reason: "the limits changed after mount");
    });
  });

  group("TC-LIFE-05 zero-size and unbounded constraints", () {
    for (final (w, h) in [(0.0, 0.0), (0.0, 400.0), (800.0, 0.0)]) {
      testWidgets("${w}x$h renders nothing and does not throw", (tester) async {
        late InteractiveChartContext ctx;
        await tester.pumpWidget(
          _chart(width: w, height: h, onContext: (c) => ctx = c),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (w == 0) {
          expect((ctx.visibleStart, ctx.visibleEnd), (0, 0));
        }
      });
    }

    testWidgets("zero then real size", (tester) async {
      late InteractiveChartContext ctx;
      await tester.pumpWidget(
        _chart(width: 0, height: 0, onContext: (c) => ctx = c),
      );
      await tester.pumpWidget(_chart(onContext: (c) => ctx = c));
      await tester.pumpAndSettle();
      expect(ctx.visibleEnd, greaterThan(0));
    });

    testWidgets("a tiny chart (1x1) is fine", (tester) async {
      await tester.pumpWidget(_chart(width: 1, height: 1));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets("unbounded height gives a clear message", (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ListView(
            children: [
              InteractiveChart<int>(
                data: intSeries(0, 10),
                timeOf: minuteTime,
                layers: [LineLayer<int>(valueOf: (i) => i.toDouble())],
              ),
            ],
          ),
        ),
      );
      final error = tester.takeException();
      expect(error, isA<FlutterError>());
      final text = (error! as FlutterError).toStringDeep();
      expect(text, contains("InteractiveChart"));
      expect(text, contains("unbounded"));
      expect(text, contains("SizedBox"));
    });

    testWidgets("unbounded width gives a clear message", (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 300,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                InteractiveChart<int>(
                  data: intSeries(0, 10),
                  timeOf: minuteTime,
                  layers: [LineLayer<int>(valueOf: (i) => i.toDouble())],
                ),
              ],
            ),
          ),
        ),
      );
      final error = tester.takeException();
      expect(error, isA<FlutterError>());
      expect(
        (error! as FlutterError).toStringDeep(),
        contains("bounded width"),
      );
    });
  });

  group("TC-LIFE-06 theme changes", () {
    const light = Color(0xFF1155CC);
    const dark = Color(0xFFEE8844);

    Widget themed(
      Color line,
      Color axisText,
      void Function(InteractiveChartContext) onContext,
    ) => _chart(
      layers: [LineLayer<int>(valueOf: (i) => 100.0 + i % 11, color: line)],
      valueAxis: ValueAxisConfig(textStyle: TextStyle(color: axisText)),
      timeAxis: TimeAxisConfig(textStyle: TextStyle(color: axisText)),
      onContext: onContext,
    );

    testWidgets("colours update and the view state is kept", (tester) async {
      late InteractiveChartContext ctx;
      await tester.pumpWidget(themed(light, Colors.black, (c) => ctx = c));
      await tester.pumpAndSettle();
      await tester.drag(_chartFinder, const Offset(-200, 0));
      await tester.pumpAndSettle();
      final offset = ctx.scrollOffset;
      final extent = ctx.slotExtent;
      final autoscale = (ctx.valueMin, ctx.valueMax);

      expect(
        find.byWidgetPredicate((w) => w is ColoredBox && w.color == light),
        findsWidgets,
      );

      await tester.pumpWidget(themed(dark, Colors.white, (c) => ctx = c));
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate((w) => w is ColoredBox && w.color == light),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate((w) => w is ColoredBox && w.color == dark),
        findsWidgets,
      );
      final axisLabel = tester.widget<Text>(
        find.descendant(of: _chartFinder, matching: find.byType(Text)).first,
      );
      expect(axisLabel.style!.color, Colors.white);
      expect(ctx.scrollOffset, offset);
      expect(ctx.slotExtent, extent);
      expect((ctx.valueMin, ctx.valueMax), autoscale);
    });

    testWidgets("an app-level ThemeData switch keeps the chart alive", (
      tester,
    ) async {
      late InteractiveChartContext ctx;
      Widget app(Brightness b) => MaterialApp(
        theme: ThemeData(brightness: b),
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 800,
            height: 400,
            child: Builder(
              builder: (context) => InteractiveChart<int>(
                data: intSeries(0, 400),
                timeOf: minuteTime,
                initialAnchor: ChartAnchor.left,
                layers: [
                  LineLayer<int>(
                    valueOf: (i) => 100.0 + i % 11,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  ContextProbe<int>((c) => ctx = c),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(Brightness.light));
      await tester.pumpAndSettle();
      await tester.drag(_chartFinder, const Offset(-150, 0));
      await tester.pumpAndSettle();
      final offset = ctx.scrollOffset;
      await tester.pumpWidget(app(Brightness.dark));
      await tester.pumpAndSettle();
      expect(ctx.scrollOffset, offset);
      expect(tester.takeException(), isNull);
    });
  });

  group("TC-LIFE-07 extreme values", () {
    final labelFinder = find.descendant(
      of: _chartFinder,
      matching: find.byType(Text),
    );

    List<String> valueLabels(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(labelFinder))
        if (RegExp(r"^-?[\d.]+(e[+-]?\d+)?$").hasMatch(t.data!) &&
            t.data!.contains("."))
          t.data!,
    ];

    Future<InteractiveChartContext> pump(
      WidgetTester tester,
      double Function(int) value, {
      int count = 120,
    }) async {
      late InteractiveChartContext ctx;
      await tester.pumpWidget(
        _chart(
          data: intSeries(0, count),
          layers: [LineLayer<int>(valueOf: value)],
          onContext: (c) => ctx = c,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return ctx;
    }

    testWidgets("1e12 with a span of a few hundred", (tester) async {
      final ctx = await pump(tester, (i) => 1e12 + i * 5);
      expect(ctx.valueMax.isFinite, isTrue);
      expect(ctx.yOf(1e12 + 100).isFinite, isTrue);
      final labels = valueLabels(tester);
      expect(labels, isNotEmpty);
      expect(labels.toSet().length, labels.length, reason: "$labels");
      for (final l in labels) {
        expect(l, startsWith("1000000000"));
      }
    });

    testWidgets("1e-8 does not collapse to 0.00", (tester) async {
      final ctx = await pump(tester, (i) => 1e-8 * (1 + i % 9));
      final labels = valueLabels(tester);
      expect(labels, isNotEmpty);
      expect(
        labels.toSet().length,
        labels.length,
        reason: "all labels equal: $labels",
      );
      expect(labels.any((l) => l == "0.00"), isFalse, reason: "$labels");
      expect(ctx.valueMax, greaterThan(ctx.valueMin));
    });

    testWidgets("a tiny span around 1.0 keeps its precision", (tester) async {
      await pump(tester, (i) => 1.0 + (i % 10) * 2e-6);
      final labels = valueLabels(tester);
      expect(labels.toSet().length, labels.length, reason: "$labels");
    });

    testWidgets("negative and huge together", (tester) async {
      await pump(tester, (i) => i.isEven ? -1e9 : 1e9);
      expect(valueLabels(tester), isNotEmpty);
    });

    testWidgets("the gutter stays inside the chart", (tester) async {
      final ctx = await pump(tester, (i) => 1e15 + i);
      expect(ctx.viewportWidth, greaterThan(100));
    });

    test("valueDecimals", () {
      expect(valueDecimals(const []), 2);
      expect(valueDecimals([0, 10, 20]), 2);
      expect(valueDecimals([0, 2.5, 5]), 2);
      expect(valueDecimals([0, 0.25, 0.5]), 2);
      expect(valueDecimals([0, 0.025, 0.05]), 3);
      expect(valueDecimals([0, 5e-6, 1e-5]), 6);
      expect(valueDecimals([1, 1 + 1e-9, 1 + 2e-9]), 9);
      expect(valueDecimals([3, 3, 3]), 2);
      expect(valueDecimals([0, double.nan]), 2);
      expect(valueDecimals([0, 1e-30, 2e-30]), 12); // capped
    });

    test("niceValueTicks on extreme ranges", () {
      for (final (lo, hi) in [
        (1e12, 1e12 + 100),
        (1e-9, 3e-9),
        (-1e15, 1e15),
        (0.0, 1e-12),
      ]) {
        final ticks = niceValueTicks(lo, hi);
        expect(ticks, isNotEmpty, reason: "$lo..$hi");
        for (final t in ticks) {
          expect(t.isFinite, isTrue);
        }
      }
    });
  });

  group("TC-LIFE-08 mount and unmount cycles", () {
    testWidgets("no controller is left attached and no timers are left over", (
      tester,
    ) async {
      final controller = InteractiveChartController();
      addTearDown(controller.dispose);

      for (var cycle = 0; cycle < 25; cycle++) {
        await tester.pumpWidget(
          _chart(controller: controller, anchor: ChartAnchor.right),
        );
        await tester.pump();
        expect(controller.isAttached, isTrue);

        // Touch a few things so timers, listeners and highlights exist.
        final finger = await tester.startGesture(
          tester.getCenter(_chartFinder),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await finger.up();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: tester.getCenter(_chartFinder));
        await mouse.moveTo(
          tester.getCenter(_chartFinder) + const Offset(20, 0),
        );
        await tester.pump();
        await mouse.removePointer();

        await tester.pumpWidget(const SizedBox());
        expect(controller.isAttached, isFalse, reason: "cycle $cycle");
      }
      expect(tester.takeException(), isNull);
      // Reaching the end also shows no timer or ticker was left running: the
      // framework fails the test otherwise.
    });

    testWidgets("an unmounted chart's context is disposed", (tester) async {
      late InteractiveChartContext ctx;
      await tester.pumpWidget(_chart(onContext: (c) => ctx = c));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      expect(() => ctx.addListener(() {}), throwsFlutterError);
    });

    testWidgets("repeated remounts reuse nothing stale", (tester) async {
      late InteractiveChartContext ctx;
      for (var i = 0; i < 5; i++) {
        await tester.pumpWidget(_chart(onContext: (c) => ctx = c));
        await tester.pumpAndSettle();
        expect(ctx.scrollOffset, 0, reason: "mount $i started mid-way");
        await tester.drag(_chartFinder, const Offset(-120, 0));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      }
    });
  });
}
