// BlockExtents answers range min/max from cached blocks; it must agree with a
// direct scan for every range.
import "dart:math" as math;

import "package:flutter_test/flutter_test.dart";
import "package:interactive_chart/interactive_chart.dart";
import "package:interactive_chart/src/value_axis/block_extents.dart";

void main() {
  final random = math.Random(7);
  // Values with NaN and infinite gaps, including a long all-NaN stretch.
  final values = [
    for (var i = 0; i < 5000; i++)
      if (i % 97 == 0)
        double.nan
      else if (i % 211 == 0)
        double.infinity
      else if (i >= 3000 && i < 3700)
        double.nan
      else
        random.nextDouble() * 1000 - 500,
  ];

  var scanned = 0;
  ValueRange? direct(int start, int end) {
    double? lo, hi;
    for (var i = start; i < end; i++) {
      scanned++;
      final v = values[i];
      if (!v.isFinite) {
        continue;
      }
      lo = lo == null ? v : math.min(lo, v);
      hi = hi == null ? v : math.max(hi, v);
    }
    return lo == null || hi == null ? null : (lo, hi);
  }

  test("agrees with a direct scan on random ranges", () {
    final blocks = BlockExtents(direct, blockSize: 64);
    for (var k = 0; k < 2000; k++) {
      final a = random.nextInt(values.length);
      final b = random.nextInt(values.length + 1);
      final (start, end) = a <= b ? (a, b) : (b, a);
      expect(
        blocks.over(start, end),
        direct(start, end),
        reason: "$start..$end",
      );
    }
  });

  test("edges: block-aligned, whole series, empty, all-NaN ranges", () {
    final blocks = BlockExtents(direct, blockSize: 64);
    for (final (s, e) in [
      (0, values.length),
      (64, 64 * 10),
      (63, 64 * 10 + 1),
      (100, 100),
      (3000, 3700),
      (3001, 3699),
      (2990, 3710),
    ]) {
      expect(blocks.over(s, e), direct(s, e), reason: "$s..$e");
    }
    expect(blocks.over(3000, 3700), isNull);
  });

  test("a wide range is answered from cached blocks", () {
    final blocks = BlockExtents(direct, blockSize: 100)..over(0, 5000);
    expect(blocks.cachedBlocks, 50);
    scanned = 0;
    // Shifted by a few indices: only the two partial blocks are scanned.
    blocks.over(30, 4970);
    expect(scanned, lessThanOrEqualTo(200));
    expect(blocks.cachedBlocks, 50);
  });

  test("short ranges go straight to the function", () {
    final blocks = BlockExtents(direct, blockSize: 100);
    scanned = 0;
    blocks.over(10, 150);
    expect(scanned, 140);
    expect(blocks.cachedBlocks, 0);
  });

  test("unionExtents", () {
    expect(unionExtents(null, null), isNull);
    expect(unionExtents((1, 2), null), (1, 2));
    expect(unionExtents(null, (1, 2)), (1, 2));
    expect(unionExtents((1, 5), (-2, 3)), (-2, 5));
  });
}
