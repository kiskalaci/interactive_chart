// Reads what the painted layers draw: their geometry (from the painters) and
// the rendered pixels.
import "package:flutter/rendering.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:interactive_chart/interactive_chart.dart";
import "package:interactive_chart/src/painting/shape_painters.dart";

/// Every painter under a chart, with how far right it is shifted on screen:
/// a painted layer moves its picture while the view pans (BufferedLayer), so
/// its geometry is in the coordinates it was painted at.
Iterable<(CustomPainter, double)> _painters(WidgetTester tester) sync* {
  for (final element in find.byType(CustomPaint).evaluate()) {
    final painter = (element.widget as CustomPaint).painter;
    if (painter == null) {
      continue;
    }
    var shift = 0.0;
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is Transform) {
        shift = widget.transform.getTranslation().x;
        return false;
      }
      return widget is! InteractiveChart;
    });
    yield (painter, shift);
  }
}

/// The painted candles, in viewport coordinates (empty if none are painted).
/// Painted layers cover a margin beyond the view, so this can include
/// candles just off screen.
List<CandleShape> paintedCandles(WidgetTester tester) => [
  for (final (p, dx) in _painters(tester))
    if (p is CandlePainter)
      for (final c in p.candles)
        CandleShape(
          index: c.index,
          lastIndex: c.lastIndex,
          up: c.up,
          wick: c.wick.shift(Offset(dx, 0)),
          body: c.body.shift(Offset(dx, 0)),
        ),
];

/// The painted histogram bars, in viewport coordinates.
List<Rect> paintedBars(WidgetTester tester) => [
  for (final (p, dx) in _painters(tester))
    if (p is BarPainter)
      for (final r in p.bars) r.shift(Offset(dx, 0)),
];

/// The gap-free runs of points of every painted line, in viewport
/// coordinates.
List<List<Offset>> paintedLineRuns(WidgetTester tester) => [
  for (final (p, dx) in _painters(tester))
    if (p is LinePainter)
      for (final run in p.runs) [for (final o in run) o.translate(dx, 0)],
];

/// The colour of every painted line.
List<Color> paintedLineColors(WidgetTester tester) => [
  for (final (p, _) in _painters(tester))
    if (p is LinePainter) p.color,
];

/// How many straight segments the painted lines are made of.
int paintedLineSegments(WidgetTester tester) => [
  for (final run in paintedLineRuns(tester)) run.length - 1,
].fold(0, (a, b) => a + b);

/// The colour of the pixel at [at] (logical screen coordinates) of the
/// rendered app.
Future<Color> colorAt(WidgetTester tester, Offset at) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData();
    final width = image.width;
    image.dispose();
    return (data!, width);
  });
  final (data, width) = bytes!;
  final i = (at.dy.floor() * width + at.dx.floor()) * 4;
  return Color.fromARGB(
    data.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}
