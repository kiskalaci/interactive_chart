import "dart:math" as math;

import "package:flutter/widgets.dart";
import "package:interactive_chart/src/chart_context.dart";

/// A painter for [BufferedLayer], with an optional key for the widget that
/// paints it.
typedef KeyedPainter = ({Key? key, CustomPainter painter});

/// Paints a layer's per-slot content for more slots than are visible, and
/// while the view only scrolls within them, moves the same picture instead of
/// computing and painting it again. A horizontal pan is then a translation of
/// an already painted layer.
///
/// [compute] builds the content for the slots `[start, end)`, with x
/// positions from `ctx.xOf` at the current scroll offset. It covers the
/// visible slots plus [bufferFraction] of them beyond each edge. The content
/// is kept, and its painters reused, until [cacheKey] changes or the visible
/// slots leave that range. [cacheKey] must therefore capture everything
/// other than the scroll offset that the content depends on: the layer, the
/// data (`ctx.dataRevision`), the zoom, the value extent and the viewport
/// height, typically.
///
/// [overlay] is built on top on every build, unmoved, and gets the content
/// and `shift`, how far right the painted content is moved: a point painted
/// at x is on screen at `x + shift`. Use it for hit testing, translating the
/// pointer by `-shift` before looking it up in the content.
class BufferedLayer<C> extends StatefulWidget {
  const BufferedLayer({
    required this.ctx,
    required this.cacheKey,
    required this.compute,
    required this.paintersOf,
    this.overlay,
    super.key,
  });

  /// How many slots beyond each edge of the view are computed, as a fraction
  /// of the visible slots (plus one).
  static const bufferFraction = 0.25;

  final InteractiveChartContext ctx;
  final Object? cacheKey;
  final C Function(int start, int end) compute;

  /// The painters for [compute]'s content, bottom first. Called only when the
  /// content is computed, so the same painter instances are reused while it
  /// is kept.
  final List<KeyedPainter> Function(C content) paintersOf;
  final Widget? Function(C content, double shift)? overlay;

  @override
  State<BufferedLayer<C>> createState() => _BufferedLayerState<C>();
}

class _BufferedLayerState<C> extends State<BufferedLayer<C>> {
  late C _content;
  List<KeyedPainter>? _painters;
  Object? _key;

  /// The slots the content covers, and the scroll offset it was computed at.
  int _start = 0;
  int _end = 0;
  double _scroll = 0;

  bool get _isCurrent {
    final ctx = widget.ctx;
    return _painters != null &&
        _key == widget.cacheKey &&
        ctx.visibleStart >= _start &&
        ctx.visibleEnd <= _end;
  }

  void _compute() {
    final ctx = widget.ctx;
    final visible = ctx.visibleEnd - ctx.visibleStart;
    final pad = (visible * BufferedLayer.bufferFraction).ceil() + 1;
    _start = math.max(0, ctx.visibleStart - pad);
    _end = math.min(ctx.slotCount, ctx.visibleEnd + pad);
    _scroll = ctx.scrollOffset;
    _key = widget.cacheKey;
    _content = widget.compute(_start, _end);
    _painters = widget.paintersOf(_content);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCurrent) {
      _compute();
    }
    final shift = _scroll - widget.ctx.scrollOffset;
    final overlay = widget.overlay?.call(_content, shift);
    return Stack(
      children: [
        Positioned.fill(
          child: Transform.translate(
            offset: Offset(shift, 0),
            // Its own layer, so moving it re-composites the picture
            // instead of painting it again.
            child: RepaintBoundary(
              child: Stack(
                children: [
                  for (final p in _painters!)
                    Positioned.fill(
                      key: p.key,
                      child: CustomPaint(painter: p.painter),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (overlay != null) Positioned.fill(child: overlay),
      ],
    );
  }
}
