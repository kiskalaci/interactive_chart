import "package:flutter/widgets.dart";

/// The geometry of one painted candle, in the layer's coordinates.
@immutable
class CandleShape {
  const CandleShape({
    required this.index,
    required this.up,
    required this.wick,
    required this.body,
  });

  /// The datum's index.
  final int index;

  /// Whether the candle closed at or above its open.
  final bool up;

  /// The 1 px line from high to low.
  final Rect wick;

  /// Open to close: at least 1 px tall, and 1 px wide on a very thin slot.
  final Rect body;
}

/// Paints [candles]: every wick and body as a rectangle in its candle's
/// colour, in one picture instead of a widget per candle.
class CandlePainter extends CustomPainter {
  const CandlePainter({
    required this.candles,
    required this.upColor,
    required this.downColor,
  });

  final List<CandleShape> candles;
  final Color upColor;
  final Color downColor;

  @override
  void paint(Canvas canvas, Size size) {
    final up = Paint()..color = upColor;
    final down = Paint()..color = downColor;
    for (final candle in candles) {
      final paint = candle.up ? up : down;
      canvas
        ..drawRect(candle.wick, paint)
        ..drawRect(candle.body, paint);
    }
  }

  /// Painting only: a layer's taps and hovers go through its hit region.
  @override
  bool hitTest(Offset position) => false;

  @override
  bool shouldRepaint(CandlePainter old) =>
      !identical(old.candles, candles) ||
      old.upColor != upColor ||
      old.downColor != downColor;
}

/// Paints [bars] as rectangles of one [color], in one picture.
class BarPainter extends CustomPainter {
  const BarPainter({required this.bars, required this.color});

  final List<Rect> bars;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (final bar in bars) {
      canvas.drawRect(bar, paint);
    }
  }

  /// Painting only: a layer's taps and hovers go through its hit region.
  @override
  bool hitTest(Offset position) => false;

  @override
  bool shouldRepaint(BarPainter old) =>
      !identical(old.bars, bars) || old.color != color;
}

/// Strokes each run of [runs] as one connected line: a polyline with round
/// joins, so sharp turns have no notches or gaps. A run needs at least two
/// points to draw anything; separate runs are not joined, which is how a gap
/// in the data shows.
class LinePainter extends CustomPainter {
  const LinePainter({
    required this.runs,
    required this.color,
    required this.strokeWidth,
  });

  final List<List<Offset>> runs;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (final run in runs) {
      if (run.length < 2) {
        continue;
      }
      path.moveTo(run.first.dx, run.first.dy);
      for (var i = 1; i < run.length; i++) {
        path.lineTo(run[i].dx, run[i].dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// Painting only: a layer's taps and hovers go through its hit region.
  @override
  bool hitTest(Offset position) => false;

  @override
  bool shouldRepaint(LinePainter old) =>
      !identical(old.runs, runs) ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
