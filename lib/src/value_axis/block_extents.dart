import "dart:math" as math;

import "package:interactive_chart/src/typedefs/value_range.dart";

/// The union of two extents, either of which may be missing.
ValueRange? unionExtents(ValueRange? a, ValueRange? b) {
  if (a == null) {
    return b;
  }
  if (b == null) {
    return a;
  }
  return (math.min(a.$1, b.$1), math.max(a.$2, b.$2));
}

/// The extent of a series over index ranges, answered from cached extents of
/// fixed blocks of [blockSize] indices, so a wide range costs a lookup per
/// block plus at most two partial blocks instead of a pass over every index.
///
/// [extentOf] gives the extent of `[start, end)`, or null when it has none;
/// the extent of a range must be the union of the extents of its parts (a
/// min/max over the data is). Blocks are computed on first use and kept, so
/// a [BlockExtents] belongs to one version of the data. Ranges shorter than
/// [minRange] go straight to [extentOf].
class BlockExtents {
  BlockExtents(this.extentOf, {this.blockSize = 256, int? minRange})
    : minRange = math.max(minRange ?? 2 * blockSize, 2 * blockSize),
      assert(blockSize > 0, "blockSize must be positive");

  final ValueRange? Function(int start, int end) extentOf;
  final int blockSize;
  final int minRange;

  final _blocks = <int, ValueRange?>{};

  /// How many blocks have been computed so far.
  int get cachedBlocks => _blocks.length;

  /// The extent over `[start, end)`.
  ValueRange? over(int start, int end) {
    if (end - start < minRange) {
      return extentOf(start, end);
    }
    // Whole blocks [first, last); minRange >= 2 blocks keeps first < last.
    final first = (start + blockSize - 1) ~/ blockSize;
    final last = end ~/ blockSize;
    var extent = start < first * blockSize
        ? extentOf(start, first * blockSize)
        : null;
    for (var b = first; b < last; b++) {
      extent = unionExtents(
        extent,
        _blocks.putIfAbsent(
          b,
          () => extentOf(b * blockSize, (b + 1) * blockSize),
        ),
      );
    }
    if (last * blockSize < end) {
      extent = unionExtents(extent, extentOf(last * blockSize, end));
    }
    return extent;
  }
}
