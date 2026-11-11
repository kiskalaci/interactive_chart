import "package:flutter/painting.dart";
import "package:flutter_test/flutter_test.dart";
import "package:interactive_chart/interactive_chart.dart";

String _format(DateTime t, int w) => "x";
String _other(DateTime t, int w) => "y";

void main() {
  group("TimeAxisConfig equality", () {
    test("equal when every field is equal", () {
      expect(const TimeAxisConfig(), const TimeAxisConfig());
      expect(const TimeAxisConfig().hashCode, const TimeAxisConfig().hashCode);
      expect(
        const TimeAxisConfig(placement: TimeAxisPlacement.top),
        const TimeAxisConfig(placement: TimeAxisPlacement.top),
      );
      expect(
        const TimeAxisConfig(formatter: _format),
        const TimeAxisConfig(formatter: _format),
      );
    });

    test("differs when any field differs", () {
      const base = TimeAxisConfig();
      expect(
        base,
        isNot(const TimeAxisConfig(placement: TimeAxisPlacement.top)),
      );
      expect(base, isNot(const TimeAxisConfig(formatter: _format)));
      expect(
        const TimeAxisConfig(formatter: _format),
        isNot(const TimeAxisConfig(formatter: _other)),
      );
      expect(
        base,
        isNot(const TimeAxisConfig(textStyle: TextStyle(fontSize: 9))),
      );
      expect(
        base,
        isNot(
          const TimeAxisConfig(emphasizedTextStyle: TextStyle(fontSize: 9)),
        ),
      );
    });
  });

  group("TimeAxisConfig.copyWith", () {
    const original = TimeAxisConfig(
      placement: TimeAxisPlacement.top,
      formatter: _format,
      textStyle: TextStyle(fontSize: 10),
      emphasizedTextStyle: TextStyle(fontSize: 12),
    );

    test("with no arguments returns an equal config", () {
      expect(original.copyWith(), original);
    });

    test("replaces only the given field", () {
      expect(
        original.copyWith(placement: TimeAxisPlacement.bottom),
        const TimeAxisConfig(
          formatter: _format,
          textStyle: TextStyle(fontSize: 10),
          emphasizedTextStyle: TextStyle(fontSize: 12),
        ),
      );
      expect(original.copyWith(formatter: _other).formatter, _other);
      expect(
        original.copyWith(formatter: _other).placement,
        original.placement,
      );
      expect(
        original.copyWith(textStyle: const TextStyle(fontSize: 8)).textStyle,
        const TextStyle(fontSize: 8),
      );
      expect(
        original
            .copyWith(emphasizedTextStyle: const TextStyle(fontSize: 14))
            .emphasizedTextStyle,
        const TextStyle(fontSize: 14),
      );
    });

    test("does not modify the original", () {
      original.copyWith(placement: TimeAxisPlacement.bottom);
      expect(original.placement, TimeAxisPlacement.top);
    });
  });
}
