import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:interactive_chart/interactive_chart.dart";

void main() {
  testWidgets("prepending older data keeps the viewport stationary", (
    tester,
  ) async {
    final base = DateTime(2024);
    List<int> series(int from, int to) => [for (var i = from; i < to; i++) i];
    DateTime timeOf(int i) => base.add(Duration(minutes: i));

    final controller = InteractiveChartController();
    Widget build(List<int> data) => MaterialApp(
      home: SizedBox(
        width: 800,
        height: 400,
        child: InteractiveChart<int>(
          controller: controller,
          data: data,
          timeOf: timeOf,
          initialAnchor: ChartAnchor.left,
          layers: [LineLayer<int>(valueOf: (i) => i.toDouble())],
        ),
      ),
    );

    await tester.pumpWidget(build(series(1000, 1200)));
    await tester.pump();
    final (startBefore, _) = controller.visibleRange;
    expect(startBefore, 0);

    // Prepend 120 older items; the same candles must stay on screen.
    await tester.pumpWidget(build(series(880, 1200)));
    await tester.pump();
    final (startAfter, _) = controller.visibleRange;
    expect(startAfter, 120);
  });

  _autoscaleTests();
}

void _autoscaleTests() {
  testWidgets("horizontal drag keeps autoscale on", (tester) async {
    final controller = InteractiveChartController();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 400,
          child: InteractiveChart<int>(
            controller: controller,
            data: [for (var i = 0; i < 200; i++) i],
            timeOf: (i) => DateTime(2024).add(Duration(minutes: i)),
            layers: [LineLayer<int>(valueOf: (i) => i.toDouble())],
          ),
        ),
      ),
    );
    await tester.drag(
      find.byType(InteractiveChart<int>),
      const Offset(-100, 0),
    );
    await tester.pump();
    expect(controller.autoscale, isTrue);
  });
}
