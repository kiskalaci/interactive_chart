import "package:flutter_test/flutter_test.dart";
import "package:interactive_chart/interactive_chart.dart";

void main() {
  group("TickMarkWeight", () {
    test("values rank from second (finest) to year (coarsest)", () {
      final values = [for (final w in TickMarkWeight.values) w.value];
      expect(values, [10, 20, 21, 22, 30, 31, 32, 33, 50, 60, 70]);
      expect(values, orderedEquals([...values]..sort()));
    });

    test("comparison operators follow the value", () {
      expect(TickMarkWeight.year > TickMarkWeight.month, isTrue);
      expect(TickMarkWeight.month >= TickMarkWeight.month, isTrue);
      expect(TickMarkWeight.hour1 < TickMarkWeight.day, isTrue);
      expect(TickMarkWeight.minute1 <= TickMarkWeight.minute1, isTrue);
      expect(TickMarkWeight.second > TickMarkWeight.minute1, isFalse);
    });

    test("compareTo sorts coarsest last", () {
      final sorted = [
        TickMarkWeight.day,
        TickMarkWeight.year,
        TickMarkWeight.second,
      ]..sort();
      expect(sorted, [
        TickMarkWeight.second,
        TickMarkWeight.day,
        TickMarkWeight.year,
      ]);
    });
  });
}
