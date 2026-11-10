import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:interactive_chart/interactive_chart.dart";

void main() {
  testWidgets("latestPointBuilder marks the last datum when visible", (
    tester,
  ) async {
    final controller = InteractiveChartController();
    int? builtIndex;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 400,
          child: InteractiveChart<int>(
            controller: controller,
            data: [for (var i = 0; i < 50; i++) i],
            timeOf: (i) => DateTime(2024).add(Duration(minutes: i)),
            layers: [
              LineLayer<int>(
                valueOf: (i) => i.toDouble(),
                latestPointBuilder: (context, datum, index) {
                  builtIndex = index;
                  return const SizedBox.square(
                    key: Key("marker"),
                    dimension: 10,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key("marker")), findsOneWidget);
    expect(builtIndex, 49);
  });
}
