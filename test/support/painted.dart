// Reads what the painted layers draw: their geometry (from the painters) and
// the rendered pixels.
import "package:flutter/rendering.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:interactive_chart/src/painting/shape_painters.dart";

Iterable<CustomPainter> _painters(WidgetTester tester) => [
  for (final w in tester.widgetList<CustomPaint>(find.byType(CustomPaint)))
    ?w.painter,
];

/// The painted candles, in viewport coordinates (empty if none are painted).
List<CandleShape> paintedCandles(WidgetTester tester) => [
  for (final p in _painters(tester))
    if (p is CandlePainter) ...p.candles,
];

/// The painted histogram bars, in viewport coordinates.
List<Rect> paintedBars(WidgetTester tester) => [
  for (final p in _painters(tester))
    if (p is BarPainter) ...p.bars,
];

/// The gap-free runs of points of every painted line, in viewport
/// coordinates.
List<List<Offset>> paintedLineRuns(WidgetTester tester) => [
  for (final p in _painters(tester))
    if (p is LinePainter) ...p.runs,
];

/// The colour of every painted line.
List<Color> paintedLineColors(WidgetTester tester) => [
  for (final p in _painters(tester))
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
