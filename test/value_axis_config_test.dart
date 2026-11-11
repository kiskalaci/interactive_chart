import "package:flutter/painting.dart";
import "package:flutter_test/flutter_test.dart";
import "package:interactive_chart/interactive_chart.dart";

String _format(double v) => "x";
String _other(double v) => "y";

void main() {
  group("ValueAxisConfig equality", () {
    test("equal when every field is equal", () {
      expect(const ValueAxisConfig(), const ValueAxisConfig());
      expect(
        const ValueAxisConfig().hashCode,
        const ValueAxisConfig().hashCode,
      );
      expect(
        const ValueAxisConfig(placement: ValueAxisPlacement.left),
        const ValueAxisConfig(placement: ValueAxisPlacement.left),
      );
      expect(
        const ValueAxisConfig(formatter: _format),
        const ValueAxisConfig(formatter: _format),
      );
    });

    test("differs when any field differs", () {
      const base = ValueAxisConfig();
      expect(
        base,
        isNot(const ValueAxisConfig(placement: ValueAxisPlacement.left)),
      );
      expect(base, isNot(const ValueAxisConfig(formatter: _format)));
      expect(
        const ValueAxisConfig(formatter: _format),
        isNot(const ValueAxisConfig(formatter: _other)),
      );
      expect(
        base,
        isNot(const ValueAxisConfig(textStyle: TextStyle(fontSize: 9))),
      );
    });
  });

  group("ValueAxisConfig.copyWith", () {
    const original = ValueAxisConfig(
      placement: ValueAxisPlacement.left,
      formatter: _format,
      textStyle: TextStyle(fontSize: 10),
    );

    test("with no arguments returns an equal config", () {
      expect(original.copyWith(), original);
    });

    test("replaces only the given field", () {
      expect(
        original.copyWith(placement: ValueAxisPlacement.right),
        const ValueAxisConfig(
          placement: ValueAxisPlacement.right,
          formatter: _format,
          textStyle: TextStyle(fontSize: 10),
        ),
      );
      final withFormatter = original.copyWith(formatter: _other);
      expect(withFormatter.formatter, _other);
      expect(withFormatter.placement, original.placement);
      expect(
        original.copyWith(textStyle: const TextStyle(fontSize: 8)).textStyle,
        const TextStyle(fontSize: 8),
      );
    });

    test("does not modify the original", () {
      original.copyWith(placement: ValueAxisPlacement.right);
      expect(original.placement, ValueAxisPlacement.left);
    });
  });
}
