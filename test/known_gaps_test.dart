// Tests for suspected gaps listed in docs/poc_notes.md ("Test plan").
// Each test encodes what the requirements say should happen.
import "dart:math" as math;

import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:interactive_chart/interactive_chart.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/ticks.dart";

class _CaptureLayer extends ChartLayer<double> {
  _CaptureLayer(this.onContext);

  final void Function(InteractiveChartContext ctx) onContext;

  @override
  ValueRange? extentFor(List<double> data, int start, int end) {
    double? lo, hi;
    for (var i = start; i < end; i++) {
      lo = lo == null ? data[i] : (data[i] < lo ? data[i] : lo);
      hi = hi == null ? data[i] : (data[i] > hi ? data[i] : hi);
    }
    return lo == null || hi == null ? null : (lo, hi);
  }

  @override
  Widget build(Size size, InteractiveChartContext ctx, List<double> data) {
    onContext(ctx);
    return const SizedBox.shrink();
  }
}

DateTime _timeOf(int i) => DateTime(2024).add(Duration(minutes: i));

void main() {
  testWidgets("TC-SCALE-07: a live tick above the extent rescales", (
    tester,
  ) async {
    InteractiveChartContext? ctx;
    Widget build(List<double> data) => MaterialApp(
      home: SizedBox(
        width: 800,
        height: 400,
        child: InteractiveChart<double>(
          data: data,
          timeOf: (v) => _timeOf(data.indexOf(v)),
          layers: [_CaptureLayer((c) => ctx = c)],
        ),
      ),
    );

    final base = [for (var i = 0; i < 50; i++) 100.0 + i];
    await tester.pumpWidget(build(base));
    await tester.pump();
    expect(ctx!.valueMax, lessThan(200));

    // Same length, last datum spikes (a live tick updating the last bar).
    final ticked = [...base]..[49] = 1000;
    await tester.pumpWidget(build(ticked));
    await tester.pump();
    expect(ctx!.valueMax, greaterThanOrEqualTo(1000));
  });

  test("TC-SCALE-11: value ticks include the 2.5 step", () {
    // Range 12.5 over 5 ticks -> raw step 2.5, which the 1/2/2.5/5/10
    // progression (R-AXIS-8) keeps instead of rounding up to 5.
    final ticks = niceValueTicks(0, 12.5);
    expect(ticks, contains(2.5));
  });

  testWidgets("TC-CROSS-06: projected slot reports a null highlighted index", (
    tester,
  ) async {
    final reported = <int?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 400,
          child: InteractiveChart<int>(
            data: [for (var i = 0; i < 200; i++) i],
            timeOf: _timeOf,
            onIndexHighlighted: reported.add,
            layers: [LineLayer<int>(valueOf: (i) => i.toDouble())],
          ),
        ),
      ),
    );
    await tester.pump();

    final chart = tester.getRect(find.byType(InteractiveChart<int>));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: chart.topLeft);
    // Far right of the viewport: past the newest datum, inside overscroll.
    await mouse.moveTo(Offset(chart.right - 60, chart.center.dy));
    await tester.pump();

    expect(reported.last, isNull);
  });

  test("TC-PROJ-09: monthly series projects calendar months", () {
    final real = [for (var m = 1; m <= 12; m++) DateTime(2024, m)];
    final projected = projectTimes(real, 3);
    expect(projected, [DateTime(2025), DateTime(2025, 2), DateTime(2025, 3)]);
  });

  test("TC-PROJ-09b: month-end series clamps to the month's length", () {
    // Month-end closes: Jan 31 + 1 month is Feb 29 in 2024, then Mar 31.
    final real = [
      DateTime(2023, 7, 31),
      DateTime(2023, 8, 31),
      DateTime(2023, 9, 30),
      DateTime(2023, 10, 31),
      DateTime(2023, 11, 30),
      DateTime(2023, 12, 31),
      DateTime(2024, 1, 31),
    ];
    expect(projectTimes(real, 3), [
      DateTime(2024, 2, 29),
      DateTime(2024, 3, 31),
      DateTime(2024, 4, 30),
    ]);
  });

  test("TC-PROJ-09c: quarterly series steps three months", () {
    final real = [for (var q = 0; q < 8; q++) DateTime(2023, 1 + q * 3)];
    expect(projectTimes(real, 2), [DateTime(2025), DateTime(2025, 4)]);
  });

  test("TC-PROJ-06: daily series still skips weekends", () {
    // Friday 2024-01-05 -> Monday 2024-01-08.
    final real = [for (var d = 1; d <= 5; d++) DateTime(2024, 1, d)];
    expect(projectTimes(real, 2), [DateTime(2024, 1, 8), DateTime(2024, 1, 9)]);
  });

  test("TC-SCALE-11b: tick steps stay on the 1/2/2.5/5/10 ladder", () {
    for (final range in [0.3, 1.0, 7.0, 12.5, 24.0, 90.0, 1234.0]) {
      final ticks = niceValueTicks(0, range);
      final step = ticks[1] - ticks[0];
      final mantissa =
          step / math.pow(10, (math.log(step) / math.ln10).floor());
      expect(
        [1.0, 2.0, 2.5, 5.0, 10.0].any((m) => (m - mantissa).abs() < 1e-6),
        isTrue,
        reason: "range $range gave step $step",
      );
    }
  });
}
