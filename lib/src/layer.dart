import "package:flutter/widgets.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/typedefs/value_range.dart";

/// A visual element built into the viewport (§8), as a real widget tree
/// rather than direct canvas painting — so a layer's per-slot elements can
/// carry their own gesture detectors, hover state, and animations.
abstract class ChartLayer<T> {
  const ChartLayer();

  /// Value extent contributed by this layer over `[start, end)` (R-LAYER-7).
  /// Return null to opt out of autoscale (R-SCALE-9) — the default.
  ValueRange? extentFor(List<T> data, int start, int end) => null;

  Widget build(Size size, InteractiveChartContext ctx, List<T> data);
}
