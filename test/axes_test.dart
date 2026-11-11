// Test plan section 5: axes and axis gutters (TC-AXIS-*).
// See docs/poc_notes.md.
import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart" hide testWidgets;
import "package:interactive_chart/interactive_chart.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/time_axis/time_ticks.dart";

import "support/chart_harness.dart";
import "support/variants.dart";

final _chartFinder = find.byType(InteractiveChart<int>);

/// Labels drawn by the value axis (formatter below prefixes them with "V").
Finder get _valueLabels =>
    find.byWidgetPredicate((w) => w is Text && (w.data ?? "").startsWith("V"));

/// Labels drawn by the time axis (formatter below prefixes them with "T").
Finder get _timeLabels =>
    find.byWidgetPredicate((w) => w is Text && (w.data ?? "").startsWith("T"));

String _v(double v) => "V${v.toStringAsFixed(1)}";
String _t(DateTime t, TickMarkWeight weight) => "T${t.hour}:${t.minute}";

ChartHarness<int> _chart({
  ValueAxisConfig? valueAxis = const ValueAxisConfig(),
  TimeAxisConfig? timeAxis = const TimeAxisConfig(),
  List<double>? values,
  double textScale = 1,
  bool zoomEnabled = true,
  ChartAnchor anchor = ChartAnchor.left,
}) => ChartHarness<int>(
  timeOf: minuteTime,
  anchor: anchor,
  valueAxis: valueAxis,
  timeAxis: timeAxis,
  textScale: textScale,
  zoomEnabled: zoomEnabled,
  layers: () => [LineLayer<int>(valueOf: (i) => values?[i] ?? 100.0 + i % 9)],
);

Future<ChartHarness<int>> _pump(
  WidgetTester tester, {
  ValueAxisConfig? valueAxis = const ValueAxisConfig(),
  TimeAxisConfig? timeAxis = const TimeAxisConfig(),
  int count = 1000,
  double textScale = 1,
  ChartAnchor anchor = ChartAnchor.left,
}) async {
  final h = _chart(
    valueAxis: valueAxis,
    timeAxis: timeAxis,
    textScale: textScale,
    anchor: anchor,
  );
  await tester.pumpWidget(h.app(intSeries(0, count)));
  await tester.pumpAndSettle();
  return h;
}

Future<void> _wheel(WidgetTester tester, Offset at, Offset delta) async {
  final pointer = TestPointer(1, PointerDeviceKind.mouse)..hover(at);
  await tester.sendEventToBinding(pointer.scroll(delta));
  await tester.pump();
}

void main() {
  group("TC-AXIS-01 absent axes give their gutter to the viewport", () {
    const cases = [(true, true), (true, false), (false, true), (false, false)];
    for (final (hasValue, hasTime) in cases) {
      testWidgets("value axis: $hasValue, time axis: $hasTime", (tester) async {
        final h = await _pump(
          tester,
          valueAxis: hasValue ? const ValueAxisConfig() : null,
          timeAxis: hasTime ? const TimeAxisConfig() : null,
        );
        final chart = tester.getSize(_chartFinder);
        final gutterW = chart.width - h.ctx.viewportWidth;
        final gutterH = chart.height - h.ctx.viewportHeight;

        if (hasValue) {
          expect(gutterW, greaterThanOrEqualTo(40));
          expect(gutterW, lessThan(120));
        } else {
          expect(gutterW, 0);
        }
        expect(gutterH, hasTime ? 22 : 0);
      });
    }
  });

  group("TC-AXIS-02 placement", () {
    for (final vp in ValueAxisPlacement.values) {
      for (final tp in TimeAxisPlacement.values) {
        testWidgets("value ${vp.name}, time ${tp.name}", (tester) async {
          final h = await _pump(
            tester,
            valueAxis: ValueAxisConfig(placement: vp, formatter: _v),
            timeAxis: TimeAxisConfig(placement: tp, formatter: _t),
          );
          final chart = tester.getRect(_chartFinder);
          final gutterW = chart.width - h.ctx.viewportWidth;

          for (final e in tester.widgetList<Text>(_valueLabels).indexed) {
            final r = tester.getRect(_valueLabels.at(e.$1));
            if (vp == ValueAxisPlacement.right) {
              expect(r.left, greaterThanOrEqualTo(chart.right - gutterW));
            } else {
              expect(r.right, lessThanOrEqualTo(chart.left + gutterW));
            }
          }
          for (final e in tester.widgetList<Text>(_timeLabels).indexed) {
            final r = tester.getRect(_timeLabels.at(e.$1));
            if (tp == TimeAxisPlacement.bottom) {
              expect(r.top, greaterThanOrEqualTo(chart.bottom - 22));
            } else {
              expect(r.bottom, lessThanOrEqualTo(chart.top + 22));
            }
          }
          expect(_valueLabels, findsWidgets);
          expect(_timeLabels, findsWidgets);
        });
      }
    }
  });

  group("TC-AXIS-03 value gutter is grow-only (R-AXIS-5)", () {
    testWidgets("grows for wider labels, never shrinks while panning", (
      tester,
    ) async {
      // Small values first, then a big spike far to the right.
      final values = [
        for (var i = 0; i < 1000; i++)
          if (i < 500) 1.0 + i % 5 else 2000000.0 + i,
      ];
      final h = _chart(values: values);
      await tester.pumpWidget(h.app(intSeries(0, 1000)));
      await tester.pumpAndSettle();
      final narrow = h.ctx.viewportWidth;

      // Pan to the big values: wider labels appear and the gutter grows.
      await tester.drag(
        _chartFinder,
        const Offset(-3500, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      await tester.drag(
        _chartFinder,
        const Offset(-3500, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      final wide = h.ctx.viewportWidth;
      expect(wide, lessThan(narrow));

      // Pan back to the small values: the gutter does not shrink.
      await tester.drag(
        _chartFinder,
        const Offset(3500, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      await tester.drag(
        _chartFinder,
        const Offset(3500, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(h.ctx.viewportWidth, wide);
    });

    testWidgets("is stable across many small pans", (tester) async {
      final h = await _pump(tester);
      final widths = <double>{};
      for (var i = 0; i < 20; i++) {
        await tester.drag(_chartFinder, const Offset(-60, 0));
        await tester.pumpAndSettle();
        widths.add(h.ctx.viewportWidth);
      }
      expect(widths.length, lessThanOrEqualTo(2));
    });
  });

  group("TC-AXIS-04 custom formatters", () {
    testWidgets("every label on both axes comes from the formatter", (
      tester,
    ) async {
      await _pump(
        tester,
        valueAxis: const ValueAxisConfig(formatter: _v),
        timeAxis: const TimeAxisConfig(formatter: _t),
      );
      final texts = tester.widgetList<Text>(
        find.descendant(of: _chartFinder, matching: find.byType(Text)),
      );
      expect(texts, isNotEmpty);
      for (final t in texts) {
        expect(t.data, anyOf(startsWith("V"), startsWith("T")));
      }
      expect(_valueLabels, findsWidgets);
      expect(_timeLabels, findsWidgets);
    });

    testWidgets("default formatting when none is given", (tester) async {
      await _pump(tester);
      final texts = tester.widgetList<Text>(
        find.descendant(of: _chartFinder, matching: find.byType(Text)),
      );
      expect(
        texts.any((t) => RegExp(r"^\d+\.\d\d$").hasMatch(t.data!)),
        isTrue,
      );
    });
  });

  group("labels are clipped to the gutter", () {
    testWidgets("TC-AXIS-05 value labels beyond 8 px outside are not built", (
      tester,
    ) async {
      final ctx = InteractiveChartContext()
        ..setViewportSize(300, 200)
        ..setValueExtent(0, 100)
        ..valueTicks = [-500, -9, 0, 50, 100, 209, 500];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 60,
              height: 200,
              child: ValueAxisView(
                ctx: ctx,
                config: const ValueAxisConfig(formatter: _v),
              ),
            ),
          ),
        ),
      );
      final labels = tester
          .widgetList<Text>(_valueLabels)
          .map((t) => t.data)
          .toList();
      // y = 200 for 0 and 0 for 100 are in; -9 maps beyond +8 below, 209
      // beyond -8 above, and +/-500 far outside.
      expect(labels, containsAll(["V0.0", "V50.0", "V100.0"]));
      expect(labels, isNot(contains("V500.0")));
      expect(labels, isNot(contains("V-500.0")));
      expect(labels, isNot(contains("V209.0")));
      expect(labels, isNot(contains("V-9.0")));
    });

    testWidgets("TC-AXIS-06 time labels that would cross an edge are dropped", (
      tester,
    ) async {
      final ctx = InteractiveChartContext(slotExtent: 10)
        ..setViewportSize(300, 100)
        ..setSlotCount(30);
      DateTime t(int i) => minuteTime(i);
      ctx.timeTicks = [
        TickMark(
          index: 0,
          time: t(0),
          weight: TickMarkWeight.minute1,
          projected: false,
        ),
        TickMark(
          index: 15,
          time: t(15),
          weight: TickMarkWeight.minute1,
          projected: false,
        ),
        TickMark(
          index: 29,
          time: t(29),
          weight: TickMarkWeight.minute1,
          projected: false,
        ),
      ];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              height: 22,
              child: TimeAxisView(
                ctx: ctx,
                config: TimeAxisConfig(
                  formatter: (time, w) => "TLABEL-${time.minute}",
                ),
              ),
            ),
          ),
        ),
      );
      final labels = tester.widgetList<Text>(_timeLabels).map((e) => e.data);
      // Index 0 sits 5 px from the left edge, index 29 5 px from the right:
      // a ~60 px label would cross either one. Only the middle one survives.
      expect(labels, ["TLABEL-15"]);
    });
  });

  group("gutter gestures", () {
    Rect timeAxis(WidgetTester tester, ChartHarness<int> h) {
      final chart = tester.getRect(_chartFinder);
      return Rect.fromLTWH(
        chart.left,
        chart.bottom - 22,
        h.ctx.viewportWidth,
        22,
      );
    }

    Rect valueAxis(WidgetTester tester, ChartHarness<int> h) {
      final chart = tester.getRect(_chartFinder);
      return Rect.fromLTRB(
        chart.left + h.ctx.viewportWidth,
        chart.top,
        chart.right,
        chart.top + h.ctx.viewportHeight,
      );
    }

    testWidgets("TC-AXIS-07 wheel on the time axis zooms x at the pointer", (
      tester,
    ) async {
      final h = await _pump(tester);
      await tester.drag(_chartFinder, const Offset(-600, 0));
      await tester.pumpAndSettle();
      final axis = timeAxis(tester, h);
      final at = Offset(axis.left + 250, axis.center.dy);
      final index = h.ctx.fractionalIndexAtViewportX(250);
      final extent = h.ctx.slotExtent;

      await _wheel(tester, at, const Offset(0, -200));
      expect(h.ctx.slotExtent, greaterThan(extent));
      expect(
        h.ctx.fractionalIndexAtViewportX(250),
        closeTo(index, 0.5 / h.ctx.slotExtent),
      );
      // x zoom only: the value extent and autoscale are untouched.
      expect(h.controller.autoscale, isTrue);
    });

    testWidgets("TC-AXIS-08 horizontal drag on the time axis zooms x", (
      tester,
    ) async {
      final h = await _pump(tester);
      final axis = timeAxis(tester, h);
      final extent = h.ctx.slotExtent;

      await tester.dragFrom(axis.center, const Offset(120, 0));
      await tester.pumpAndSettle();
      final zoomedIn = h.ctx.slotExtent;
      expect(zoomedIn, greaterThan(extent));

      await tester.dragFrom(axis.center, const Offset(-120, 0));
      await tester.pumpAndSettle();
      expect(h.ctx.slotExtent, lessThan(zoomedIn));
    });

    testWidgets("TC-AXIS-09 wheel on the value axis zooms y at the pointer", (
      tester,
    ) async {
      final h = await _pump(tester);
      final axis = valueAxis(tester, h);
      const localY = 120.0;
      final at = Offset(axis.center.dx, axis.top + localY);
      final value = h.ctx.valueOfViewportY(localY);
      final span = h.ctx.valueMax - h.ctx.valueMin;
      final extent = h.ctx.slotExtent;

      await _wheel(tester, at, const Offset(0, 200)); // down: zoom out
      expect(h.controller.autoscale, isFalse);
      expect(h.ctx.valueMax - h.ctx.valueMin, greaterThan(span));
      expect(h.ctx.valueOfViewportY(localY), closeTo(value, span * 1e-6));
      expect(h.ctx.slotExtent, extent); // x untouched

      final wider = h.ctx.valueMax - h.ctx.valueMin;
      await _wheel(tester, at, const Offset(0, -400)); // up: zoom in
      expect(h.ctx.valueMax - h.ctx.valueMin, lessThan(wider));
      expect(h.ctx.valueOfViewportY(localY), closeTo(value, span * 1e-6));
    });

    testWidgets("TC-AXIS-10 vertical drag on the value axis zooms y", (
      tester,
    ) async {
      final h = await _pump(tester);
      final axis = valueAxis(tester, h);
      final span = h.ctx.valueMax - h.ctx.valueMin;

      await tester.dragFrom(axis.center, const Offset(0, 100));
      await tester.pumpAndSettle();
      expect(h.controller.autoscale, isFalse);
      expect(
        h.ctx.valueMax - h.ctx.valueMin,
        isNot(closeTo(span, span * 1e-3)),
      );
    });

    testWidgets("TC-AXIS-11 double-tap on the value axis restores autoscale", (
      tester,
    ) async {
      final h = await _pump(tester);
      final auto = (h.ctx.valueMin, h.ctx.valueMax);
      final axis = valueAxis(tester, h);
      await _wheel(tester, axis.center, const Offset(0, 300));
      expect(h.controller.autoscale, isFalse);

      await tester.tapAt(axis.center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(axis.center);
      await tester.pumpAndSettle();
      expect(h.controller.autoscale, isTrue);
      expect(h.ctx.valueMin, closeTo(auto.$1, 1e-9));
      expect(h.ctx.valueMax, closeTo(auto.$2, 1e-9));
    });

    testWidgets("axis gestures are ignored when zoom is disabled", (
      tester,
    ) async {
      final h = _chart(zoomEnabled: false);
      await tester.pumpWidget(h.app(intSeries(0, 1000)));
      await tester.pumpAndSettle();
      final axis = valueAxis(tester, h);
      final extent = h.ctx.slotExtent;
      await _wheel(tester, axis.center, const Offset(0, 300));
      await _wheel(tester, timeAxis(tester, h).center, const Offset(0, -300));
      expect(h.controller.autoscale, isTrue);
      expect(h.ctx.slotExtent, extent);
    });
  });

  testWidgets("TC-AXIS-12 text styles reach the right marks", (tester) async {
    const normal = TextStyle(fontSize: 11, color: Color(0xFFAA0000));
    const emphasized = TextStyle(
      fontSize: 11,
      color: Color(0xFF0000AA),
      fontWeight: FontWeight.w700,
    );
    const valueStyle = TextStyle(fontSize: 12, color: Color(0xFF00AA00));
    // Daily bars from 2023-12-01 so there is a year boundary and month
    // boundaries in view, with room on both sides of each label.
    final start = DateTime(2023, 12);
    // Fit the 120 days on the screen, whatever its width, so the year and the
    // February boundary are both in view.
    final screenWidth = currentScreen?.screen.width ?? 800;
    final h = ChartHarness<int>(
      timeOf: (i) => start.add(Duration(days: i)),
      slotExtent: (screenWidth - 100) / 120,
      valueAxis: const ValueAxisConfig(textStyle: valueStyle),
      timeAxis: const TimeAxisConfig(
        textStyle: normal,
        emphasizedTextStyle: emphasized,
      ),
      layers: () => [LineLayer<int>(valueOf: (i) => 10.0 + i % 3)],
    );
    await tester.pumpWidget(h.app(intSeries(0, 120)));
    await tester.pumpAndSettle();

    final texts = tester.widgetList<Text>(
      find.descendant(of: _chartFinder, matching: find.byType(Text)),
    );
    final byLabel = {for (final t in texts) t.data!: t.style!};

    // Year (weight 70) and month (weight 60) marks are emphasized.
    expect(byLabel["2024"]?.color, emphasized.color);
    expect(byLabel["Feb"]?.color, emphasized.color);
    // Day marks (weight 50) use the normal style.
    final dayLabels = byLabel.entries.where(
      (e) => RegExp(r"^\d{1,2}$").hasMatch(e.key),
    );
    // On a narrow screen all 120 days are squeezed together and the
    // hierarchy rightly keeps only the coarser year and month marks.
    if (screenWidth >= 600) {
      expect(dayLabels, isNotEmpty);
    }
    for (final e in dayLabels) {
      expect(e.value.color, normal.color);
    }
    // Value labels use the value style.
    final valueLabels = byLabel.entries.where(
      (e) => RegExp(r"^\d+\.\d\d$").hasMatch(e.key),
    );
    expect(valueLabels, isNotEmpty);
    for (final e in valueLabels) {
      expect(e.value.color, valueStyle.color);
    }
  });

  group("TC-AXIS-14 the largest visible weight is bold", () {
    // Marks at slots 5, 15, 25 with the given weights, 300 px wide, plenty of
    // room so none are dropped. The label text is the weight itself.
    Future<Map<String, FontWeight?>> pumpMarks(
      WidgetTester tester,
      List<TickMarkWeight> weights, {
      TextStyle? style,
    }) async {
      final ctx = InteractiveChartContext(slotExtent: 10)
        ..setViewportSize(300, 100)
        ..setSlotCount(30)
        ..timeTicks = [
          for (var i = 0; i < weights.length; i++)
            TickMark(
              index: 5 + i * 10,
              time: minuteTime(5 + i * 10),
              weight: weights[i],
              projected: false,
            ),
        ];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              height: 22,
              child: TimeAxisView(
                ctx: ctx,
                config: style == null
                    ? TimeAxisConfig(
                        formatter: (time, w) => "T${w.value.toInt()}",
                      )
                    : TimeAxisConfig(
                        formatter: (time, w) => "T${w.value.toInt()}",
                        textStyle: style,
                        emphasizedTextStyle: style,
                      ),
              ),
            ),
          ),
        ),
      );
      return {
        for (final t in tester.widgetList<Text>(_timeLabels))
          t.data!: t.style!.fontWeight,
      };
    }

    testWidgets("only the heaviest marks are bold", (tester) async {
      final weights = await pumpMarks(tester, [
        TickMarkWeight.year,
        TickMarkWeight.day,
        TickMarkWeight.minute1,
      ]);
      expect(weights["T70"], FontWeight.bold);
      expect(weights["T50"], isNot(FontWeight.bold));
      expect(weights["T20"], isNot(FontWeight.bold));
    });

    testWidgets("every mark sharing the top weight is bold", (tester) async {
      final weights = await pumpMarks(tester, [
        TickMarkWeight.day,
        TickMarkWeight.minute1,
        TickMarkWeight.day,
      ]);
      expect(weights["T50"], FontWeight.bold);
      expect(weights["T20"], isNot(FontWeight.bold));
    });

    testWidgets("applies at any tier, not only year or month", (tester) async {
      final weights = await pumpMarks(tester, [
        TickMarkWeight.minute1,
        TickMarkWeight.second,
        TickMarkWeight.minute1,
      ]);
      expect(weights["T20"], FontWeight.bold);
      expect(weights["T10"], isNot(FontWeight.bold));
    });

    testWidgets("a single visible mark is bold", (tester) async {
      final weights = await pumpMarks(tester, [TickMarkWeight.second]);
      expect(weights["T10"], FontWeight.bold);
    });

    testWidgets("a heavier mark that is dropped does not claim the bold", (
      tester,
    ) async {
      // Index 0 sits 5 px from the edge: its label would cross it and is
      // dropped, so the heaviest *visible* mark is the weight-50 one.
      final ctx = InteractiveChartContext(slotExtent: 10)
        ..setViewportSize(300, 100)
        ..setSlotCount(30)
        ..timeTicks = [
          TickMark(
            index: 0,
            time: minuteTime(0),
            weight: TickMarkWeight.year,
            projected: false,
          ),
          TickMark(
            index: 15,
            time: minuteTime(15),
            weight: TickMarkWeight.day,
            projected: false,
          ),
          TickMark(
            index: 25,
            time: minuteTime(25),
            weight: TickMarkWeight.minute1,
            projected: false,
          ),
        ];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              height: 22,
              child: TimeAxisView(
                ctx: ctx,
                config: TimeAxisConfig(
                  formatter: (time, w) => "TLABEL-${w.value.toInt()}",
                ),
              ),
            ),
          ),
        ),
      );
      final weights = {
        for (final t in tester.widgetList<Text>(_timeLabels))
          t.data!: t.style!.fontWeight,
      };
      expect(weights.keys, isNot(contains("TLABEL-70")));
      expect(weights["TLABEL-50"], FontWeight.bold);
      expect(weights["TLABEL-20"], isNot(FontWeight.bold));
    });

    testWidgets("keeps the configured colour and size", (tester) async {
      const style = TextStyle(fontSize: 13, color: Color(0xFF123456));
      await pumpMarks(tester, [
        TickMarkWeight.minute1,
        TickMarkWeight.second,
      ], style: style);
      final bold = tester.widget<Text>(find.text("T20")).style!;
      expect(bold.color, style.color);
      expect(bold.fontSize, 13);
    });

    testWidgets("the bold label stays centred on its slot", (tester) async {
      await pumpMarks(tester, [TickMarkWeight.year, TickMarkWeight.minute1]);
      // Slot 5 of 10 px slots: centre x = 55.
      final rect = tester.getRect(find.text("T70"));
      expect(
        rect.center.dx - tester.getTopLeft(find.byType(TimeAxisView)).dx,
        closeTo(55, 0.01),
      );
    });

    testWidgets("end to end: the year mark is bold when a year is in view", (
      tester,
    ) async {
      // Daily bars from 2023-12-01, fitted to the screen so the year, month
      // and day tiers can all show.
      final start = DateTime(2023, 12);
      final screenWidth = currentScreen?.screen.width ?? 800;
      final h = ChartHarness<int>(
        timeOf: (i) => start.add(Duration(days: i)),
        slotExtent: (screenWidth - 100) / 120,
        layers: () => [LineLayer<int>(valueOf: (i) => 10.0 + i % 3)],
      );
      await tester.pumpWidget(h.app(intSeries(0, 120)));
      await tester.pumpAndSettle();
      final styles = {
        for (final t in tester.widgetList<Text>(
          find.descendant(of: _chartFinder, matching: find.byType(Text)),
        ))
          t.data!: t.style!.fontWeight,
      };
      expect(styles["2024"], FontWeight.bold);
      expect(styles["Feb"], isNot(FontWeight.bold));
    });
  });

  group("TC-AXIS-13 large text scale", () {
    testWidgets("labels stay inside their gutters", (tester) async {
      final h = await _pump(
        tester,
        textScale: 2,
        valueAxis: const ValueAxisConfig(formatter: _v),
        timeAxis: const TimeAxisConfig(formatter: _t),
      );
      expect(tester.takeException(), isNull);

      final chart = tester.getRect(_chartFinder);
      final valueGutter = Rect.fromLTRB(
        chart.left + h.ctx.viewportWidth,
        chart.top,
        chart.right,
        chart.bottom,
      );
      for (var i = 0; i < tester.widgetList(_valueLabels).length; i++) {
        final r = tester.getRect(_valueLabels.at(i));
        expect(
          r.left,
          greaterThanOrEqualTo(valueGutter.left - 0.5),
          reason: "value label $i overflows its gutter",
        );
        expect(r.right, lessThanOrEqualTo(valueGutter.right + 0.5));
      }

      final timeGutterTop =
          chart.bottom - (chart.height - h.ctx.viewportHeight);
      for (var i = 0; i < tester.widgetList(_timeLabels).length; i++) {
        final r = tester.getRect(_timeLabels.at(i));
        expect(
          r.bottom,
          lessThanOrEqualTo(chart.bottom + 0.5),
          reason: "time label $i overflows its gutter",
        );
        expect(r.top, greaterThanOrEqualTo(timeGutterTop - 0.5));
      }
    });

    testWidgets("gutters grow with the text scale", (tester) async {
      final normal = await _pump(tester);
      final gutterW1 =
          tester.getSize(_chartFinder).width - normal.ctx.viewportWidth;
      final gutterH1 =
          tester.getSize(_chartFinder).height - normal.ctx.viewportHeight;

      await tester.pumpWidget(const SizedBox());
      final big = await _pump(tester, textScale: 2);
      final gutterW2 =
          tester.getSize(_chartFinder).width - big.ctx.viewportWidth;
      final gutterH2 =
          tester.getSize(_chartFinder).height - big.ctx.viewportHeight;

      expect(gutterW2, greaterThan(gutterW1));
      expect(gutterH2, greaterThan(gutterH1));
    });
  });
}
