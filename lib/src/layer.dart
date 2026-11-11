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

  /// Optional content painted on top of the value-axis gutter, e.g. a price
  /// tag. [size] is the gutter's own size (its width by the viewport's
  /// height), and `ctx.yOf` maps a value to a y inside it, because the gutter
  /// and the viewport share the same vertical extent. Not called when the
  /// chart has no value axis. Return null (the default) to draw nothing.
  ///
  /// The result sits above the axis labels, so make it ignore pointer events
  /// unless it needs them: the gutter handles value-axis zoom gestures.
  Widget? buildValueAxisOverlay(
    Size size,
    InteractiveChartContext ctx,
    List<T> data,
  ) => null;

  /// The gutter width [buildValueAxisOverlay] needs, so the value axis can
  /// grow to fit it instead of clipping the overlay. Defaults to 0.
  double measureValueAxisOverlayWidth(
    InteractiveChartContext ctx,
    List<T> data,
    TextScaler textScaler,
  ) => 0;
}
