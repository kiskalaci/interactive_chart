import "package:flutter/material.dart";
import "package:flutter/gestures.dart";
import "package:flutter_test/flutter_test.dart" hide testWidgets;
import "package:interactive_chart/interactive_chart.dart";

import "support/variants.dart";

void main() {
  testWidgets("jumpToLatest(slotExtent:) resets zoom and scrolls to the end", (
    tester,
  ) async {
    final controller = InteractiveChartController();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 400,
          child: InteractiveChart<int>(
            controller: controller,
            data: [for (var i = 0; i < 500; i++) i],
            timeOf: (i) => DateTime(2024).add(Duration(minutes: i)),
            initialSlotExtent: 8,
            layers: [LineLayer<int>(valueOf: (i) => i.toDouble())],
          ),
        ),
      ),
    );
    await tester.pump();
    // Zoom in with the wheel.
    final center = tester.getCenter(find.byType(InteractiveChart<int>));
    final pointer = TestPointer(1, PointerDeviceKind.mouse)..hover(center);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -400)));
    await tester.pump();
    expect(controller.slotExtent, isNot(8));

    controller.jumpToLatest(slotExtent: 8);
    await tester.pump();
    expect(controller.slotExtent, 8);
    expect(controller.visibleRange.$2, greaterThanOrEqualTo(500));
  });
}
