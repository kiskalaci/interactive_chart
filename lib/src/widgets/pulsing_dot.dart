import "package:flutter/material.dart";

/// A solid dot with a ring that continuously expands and fades — the usual
/// "live" marker for the latest point of a streaming series.
class PulsingDot extends StatefulWidget {
  const PulsingDot({
    required this.color,
    this.dotSize = 8,
    this.pulseSize = 24,
    this.duration = const Duration(milliseconds: 1400),
    super.key,
  });

  final Color color;

  /// Diameter of the solid centre dot.
  final double dotSize;

  /// Diameter the pulse ring grows to. This is also the widget's own size.
  final double pulseSize;

  final Duration duration;

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.pulseSize,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_controller.value);
        final ringSize =
            widget.dotSize + (widget.pulseSize - widget.dotSize) * t;
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: ringSize,
              height: ringSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.5 * (1 - t)),
              ),
            ),
            Container(
              width: widget.dotSize,
              height: widget.dotSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
              ),
            ),
          ],
        );
      },
    ),
  );
}
