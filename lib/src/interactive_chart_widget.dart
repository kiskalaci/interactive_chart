import "dart:math" as math;

import "package:flutter/gestures.dart";
import "package:flutter/widgets.dart";
import "package:interactive_chart/src/axis/time_axis.dart";
import "package:interactive_chart/src/axis/value_axis.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/controller.dart";
import "package:interactive_chart/src/layer.dart";
import "package:interactive_chart/src/ticks.dart";
import "package:interactive_chart/src/web/scroll_guard.dart";
export "package:interactive_chart/src/axis/time_axis.dart";
export "package:interactive_chart/src/axis/value_axis.dart";
export "package:interactive_chart/src/chart_context.dart"
    show ChartAnchor, IndexRange, ValueRange;
export "package:interactive_chart/src/controller.dart";
export "package:interactive_chart/src/layer.dart";

/// A pan/zoom two-dimensional chart viewport, generic over a caller-owned
/// datum type `T` (R-DATA-1, R-API-1).
///
/// This is a proof-of-concept implementation of
/// `lib/interactive_chart/docs/requirements.md` — see
/// `lib/interactive_chart/docs/poc_notes.md` for what is and isn't covered.
class InteractiveChart<T> extends StatefulWidget {
  const InteractiveChart({
    required this.data,
    required this.timeOf,
    required this.layers,
    this.initialAnchor = ChartAnchor.right,
    this.initialSlotExtent = 8,
    this.minSlotExtent = 1,
    this.maxSlotExtent = 64,
    this.valueAxis,
    this.timeAxis,
    this.controller,
    this.panEnabled = true,
    this.zoomEnabled = true,
    this.crosshairEnabled = true,
    this.onVisibleRangeChanged,
    this.onIndexHighlighted,
    super.key,
  });

  final List<T> data;
  final DateTime Function(T datum) timeOf;
  final List<ChartLayer<T>> layers;
  final ChartAnchor initialAnchor;
  final double initialSlotExtent;
  final double minSlotExtent;
  final double maxSlotExtent;

  /// Null means "no value axis" (R-API-3) — the viewport reclaims the gutter.
  final ValueAxisConfig? valueAxis;

  /// Null means "no time axis".
  final TimeAxisConfig? timeAxis;
  final InteractiveChartController? controller;
  final bool panEnabled;
  final bool zoomEnabled;
  final bool crosshairEnabled;
  final void Function(int start, int end)? onVisibleRangeChanged;
  final void Function(int? index)? onIndexHighlighted;

  @override
  State<InteractiveChart<T>> createState() => _InteractiveChartState<T>();
}

class _InteractiveChartState<T> extends State<InteractiveChart<T>> {
  late InteractiveChartContext ctx;
  InteractiveChartController? _ownedController;

  double _valueAxisWidth = 56;
  static const double _timeAxisHeight = 22;

  int? _lastAutoscaleStart;
  int? _lastAutoscaleEnd;
  int _lastDataLength = -1;

  double? _lastTickSlotExtentBucket;
  int _lastTickSlotCount = -1;

  double? _gestureStartSlotExtent;
  double? _gestureStartContentPixelAtFocal;

  final _viewportKey = GlobalKey();
  late final ScrollGuard _scrollGuard;

  @override
  void initState() {
    super.initState();
    ctx = InteractiveChartContext(
      initialAnchor: widget.initialAnchor,
      slotExtent: widget.initialSlotExtent,
      minSlotExtent: widget.minSlotExtent,
      maxSlotExtent: widget.maxSlotExtent,
    );
    ctx
      ..setSlotCount(widget.data.length)
      ..addListener(_onContextChanged);
    _attachController();
    // Prevents the browser's native "swipe to navigate back/forward" for
    // horizontal trackpad scroll while the pointer is over the chart —
    // otherwise panning with a trackpad can kick the user off the page.
    // No-op outside of a web build.
    _scrollGuard = ScrollGuard(_viewportBounds);
    // The very first layout doesn't go through a gesture, so ctx never
    // calls notifyListeners() for it (see _recomputeDerivedState) — nudge
    // once, post-frame, so a controller/onVisibleRangeChanged listener sees
    // the initial range instead of the pre-layout default.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ctx.announce();
      }
    });
  }

  void _attachController() {
    (widget.controller ?? (_ownedController = InteractiveChartController()))
        .attach(ctx);
  }

  @override
  void didUpdateWidget(covariant InteractiveChart<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data.length != oldWidget.data.length) {
      // R-DATA-9: appending/changing data must not reset pan/zoom.
      ctx.setSlotCount(widget.data.length);
    }
    if (widget.controller != oldWidget.controller) {
      _ownedController?.dispose();
      _ownedController = null;
      _attachController();
    }
  }

  void _onContextChanged() {
    widget.onVisibleRangeChanged?.call(ctx.visibleStart, ctx.visibleEnd);
    widget.onIndexHighlighted?.call(ctx.highlightedIndex);
    // POC simplification of R-PERF-1/R-LAYOUT-2: a real implementation keeps
    // this to render-object markNeedsPaint and never rebuilds the widget
    // tree. Rebuilding here is simple and correct but costs more than
    // necessary on every pan/zoom frame.
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    ctx.removeListener(_onContextChanged);
    _ownedController?.dispose();
    ctx.dispose();
    _scrollGuard.dispose();
    super.dispose();
  }

  Rect? _viewportBounds() {
    final renderObject = _viewportKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  void _recomputeDerivedState() {
    _maybeAutoscale();
    _maybeRebuildTimeTicks();
    _maybeGrowValueAxisWidth();
  }

  void _maybeAutoscale() {
    if (ctx.autoscale) {
      final s = ctx.visibleStart;
      final e = ctx.visibleEnd;
      if (s != _lastAutoscaleStart ||
          e != _lastAutoscaleEnd ||
          widget.data.length != _lastDataLength) {
        _lastAutoscaleStart = s;
        _lastAutoscaleEnd = e;
        _lastDataLength = widget.data.length;

        double? lo, hi;
        for (final layer in widget.layers) {
          final r = layer.extentFor(widget.data, s, e);
          if (r == null) {
            continue;
          }
          lo = lo == null ? r.$1 : math.min(lo, r.$1);
          hi = hi == null ? r.$2 : math.max(hi, r.$2);
        }
        lo ??= 0;
        hi ??= 1;
        if (lo == hi) {
          lo -= 0.5;
          hi += 0.5;
        }
        final pad = (hi - lo) * 0.05;
        ctx.setValueExtent(lo - pad, hi + pad);
      }
    }
    ctx.valueTicks = niceValueTicks(ctx.valueMin, ctx.valueMax);
  }

  double _quantizeSlotExtent(double slotExtent) {
    // R-TIME-11: quantise to steps-per-doubling so a sustained pinch doesn't
    // flicker the tick set every frame.
    const stepsPerDoubling = 6.0;
    final log2 = math.log(slotExtent) / math.ln2;
    return (log2 * stepsPerDoubling).round() / stepsPerDoubling;
  }

  void _maybeRebuildTimeTicks() {
    if (widget.data.isEmpty) {
      ctx.timeTicks = const [];
      return;
    }
    final bucket = _quantizeSlotExtent(ctx.slotExtent);
    if (bucket == _lastTickSlotExtentBucket &&
        widget.data.length == _lastTickSlotCount) {
      return;
    }
    _lastTickSlotExtentBucket = bucket;
    _lastTickSlotCount = widget.data.length;

    final realTimes = [for (final d in widget.data) widget.timeOf(d)];
    final projected = projectTimes(realTimes, ctx.projectedSlotCount);
    ctx.timeTicks = buildTickMarks(
      times: [...realTimes, ...projected],
      realCount: realTimes.length,
      slotExtent: ctx.slotExtent,
    );
  }

  void _maybeGrowValueAxisWidth() {
    if (widget.valueAxis == null) {
      return;
    }
    final measured = measureValueAxisWidth(ctx, widget.valueAxis!);
    if (measured > _valueAxisWidth) {
      // Grow-only (R-AXIS-5); scheduled post-frame since this mutates state
      // read during the layout pass currently in progress.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _valueAxisWidth = measured);
        }
      });
    }
  }

  // --- gestures -------------------------------------------------------

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStartSlotExtent = ctx.slotExtent;
    final focalX = details.localFocalPoint.dx;
    _gestureStartContentPixelAtFocal = ctx.scrollOffset + focalX;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final startExtent = _gestureStartSlotExtent;
    final startContentPixel = _gestureStartContentPixelAtFocal;
    if (startExtent == null || startContentPixel == null) {
      return;
    }

    final domainIndexAtFocal = startContentPixel / startExtent;
    final newSlotExtent = widget.zoomEnabled
        ? (startExtent * details.scale).clamp(
            widget.minSlotExtent,
            widget.maxSlotExtent,
          )
        : startExtent;

    final focalX = details.localFocalPoint.dx;
    final newContentPixelAtFocal = domainIndexAtFocal * newSlotExtent;
    final newScrollOffset = widget.panEnabled || widget.zoomEnabled
        ? newContentPixelAtFocal - focalX
        : ctx.scrollOffset;

    ctx.setSlotExtentAndScroll(newSlotExtent, newScrollOffset);

    if (widget.panEnabled) {
      ctx.panValueByPixels(details.focalPointDelta.dy);
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _gestureStartSlotExtent = null;
    _gestureStartContentPixelAtFocal = null;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final dx = event.scrollDelta.dx;
    final dy = event.scrollDelta.dy;
    // TradingView-style: a vertical-dominant wheel/trackpad scroll zooms x,
    // anchored at the pointer — this is the primary way to zoom, no modifier
    // needed. A horizontal-dominant scroll (trackpad, or shift+wheel) pans x
    // instead; vertical panning stays drag-only (see _onScaleUpdate).
    if (widget.zoomEnabled && dy != 0 && dy.abs() >= dx.abs()) {
      final factor = math.exp(-dy * 0.0015);
      final focalX = event.localPosition.dx;
      final domainIndexAtFocal = ctx.fractionalIndexAtViewportX(focalX);
      final newSlotExtent = (ctx.slotExtent * factor).clamp(
        widget.minSlotExtent,
        widget.maxSlotExtent,
      );
      final newScrollOffset = domainIndexAtFocal * newSlotExtent - focalX;
      ctx.setSlotExtentAndScroll(newSlotExtent, newScrollOffset);
    } else if (widget.panEnabled) {
      // Zoom disabled, or a horizontal-dominant scroll: pan instead, falling
      // back to `dy` for mice with no horizontal scroll axis.
      ctx.panBy(dx != 0 ? dx : dy);
    }
  }

  void _updateHighlight(Offset localPosition) {
    if (!widget.crosshairEnabled) {
      return;
    }
    final index = ctx.indexAtViewportX(localPosition.dx);
    if (index < 0) {
      ctx.setHighlighted(null);
      return;
    }
    if (index < widget.data.length) {
      ctx.setHighlighted(index);
    } else {
      final realTimes = [for (final d in widget.data) widget.timeOf(d)];
      final projected = projectTimes(realTimes, index - widget.data.length + 1);
      ctx.setHighlighted(index, projectedTime: projected.last);
    }
  }

  void _clearHighlight() => ctx.setHighlighted(null);

  // --- axis gutter scroll/drag-to-zoom (R-ZOOM-2, R-SCROLL-6..8) --------
  //
  // TradingView-style: scrolling or dragging on the time axis zooms x
  // (time); scrolling or dragging on the value axis zooms y (value),
  // switching autoscale off; double-tapping the value axis restores it.
  // Each event re-anchors on the pointer's *current* position against the
  // *current* ctx state (like the main viewport's plain-wheel zoom), so
  // there is no gesture-start bookkeeping and no drift across many events.

  void _zoomTimeAxisAt(double focalX, double factor) {
    final domainIndexAtFocal = ctx.fractionalIndexAtViewportX(focalX);
    final newSlotExtent = (ctx.slotExtent * factor).clamp(
      widget.minSlotExtent,
      widget.maxSlotExtent,
    );
    final newContentPixelAtFocal = domainIndexAtFocal * newSlotExtent;
    final newScrollOffset = newContentPixelAtFocal - focalX;
    ctx.setSlotExtentAndScroll(newSlotExtent, newScrollOffset);
  }

  void _onTimeAxisPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    _zoomTimeAxisAt(
      event.localPosition.dx,
      math.exp(-event.scrollDelta.dy * 0.0015),
    );
  }

  void _onTimeAxisDragUpdate(DragUpdateDetails details) {
    _zoomTimeAxisAt(
      details.localPosition.dx,
      math.exp(details.delta.dx * 0.008),
    );
  }

  void _zoomValueAxisAt(double focalY, double factor) {
    ctx.zoomValueExtent(factor, ctx.valueOfViewportY(focalY));
  }

  void _onValueAxisPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    _zoomValueAxisAt(
      event.localPosition.dy,
      math.exp(event.scrollDelta.dy * 0.0015),
    );
  }

  void _onValueAxisDragUpdate(DragUpdateDetails details) {
    _zoomValueAxisAt(
      details.localPosition.dy,
      math.exp(-details.delta.dy * 0.008),
    );
  }

  Widget _wrapTimeAxisGutter(Widget child) {
    if (!widget.zoomEnabled) {
      return child;
    }
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: _onTimeAxisPointerSignal,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: _onTimeAxisDragUpdate,
        child: child,
      ),
    );
  }

  Widget _wrapValueAxisGutter(Widget child) {
    if (!widget.zoomEnabled) {
      return child;
    }
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: _onValueAxisPointerSignal,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: _onValueAxisDragUpdate,
        onDoubleTap: () => ctx.setAutoscale(true),
        child: child,
      ),
    );
  }

  // --- build ------------------------------------------------------------

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final valueAxisWidth = widget.valueAxis != null ? _valueAxisWidth : 0.0;
      final timeAxisHeight = widget.timeAxis != null ? _timeAxisHeight : 0.0;
      final viewportWidth = math.max(
        0.0,
        constraints.maxWidth - valueAxisWidth,
      );
      final viewportHeight = math.max(
        0.0,
        constraints.maxHeight - timeAxisHeight,
      );

      ctx.setViewportSize(viewportWidth, viewportHeight);
      _recomputeDerivedState();

      final viewport = SizedBox(
        key: _viewportKey,
        width: viewportWidth,
        height: viewportHeight,
        child: ClipRect(child: _buildLayers(viewportWidth, viewportHeight)),
      );

      final valueAxisWidget = widget.valueAxis == null
          ? null
          : SizedBox(
              width: _valueAxisWidth,
              height: viewportHeight,
              child: _wrapValueAxisGutter(
                ValueAxisView(ctx: ctx, config: widget.valueAxis!),
              ),
            );

      final timeAxisWidget = widget.timeAxis == null
          ? null
          : SizedBox(
              height: _timeAxisHeight,
              width: viewportWidth,
              child: _wrapTimeAxisGutter(
                TimeAxisView(ctx: ctx, config: widget.timeAxis!),
              ),
            );

      final valueOnRight =
          (widget.valueAxis?.placement ?? ValueAxisPlacement.right) ==
          ValueAxisPlacement.right;
      final timeOnBottom =
          (widget.timeAxis?.placement ?? TimeAxisPlacement.bottom) ==
          TimeAxisPlacement.bottom;

      Widget row(Widget middle) => Row(
        children: [
          if (!valueOnRight) SizedBox(width: valueAxisWidth),
          Expanded(child: middle),
          if (valueOnRight) SizedBox(width: valueAxisWidth),
        ],
      );

      final mainRow = Row(
        children: [
          if (!valueOnRight && valueAxisWidget != null) valueAxisWidget,
          Expanded(child: viewport),
          if (valueOnRight && valueAxisWidget != null) valueAxisWidget,
        ],
      );

      return SizedBox(
        width: constraints.maxWidth,
        height: constraints.maxHeight,
        child: Column(
          children: [
            if (!timeOnBottom && timeAxisWidget != null) row(timeAxisWidget),
            Expanded(child: mainRow),
            if (timeOnBottom && timeAxisWidget != null) row(timeAxisWidget),
          ],
        ),
      );
    },
  );

  Widget _buildLayers(double width, double height) {
    final size = Size(width, height);
    Widget stack = Stack(
      children: [
        for (final layer in widget.layers)
          Positioned.fill(child: layer.build(size, ctx, widget.data)),
      ],
    );

    if (widget.crosshairEnabled) {
      stack = MouseRegion(
        onHover: (event) => _updateHighlight(event.localPosition),
        onExit: (_) => _clearHighlight(),
        child: GestureDetector(
          onLongPressMoveUpdate: (details) =>
              _updateHighlight(details.localPosition),
          onLongPressEnd: (_) => _clearHighlight(),
          onTapUp: (details) => _updateHighlight(details.localPosition),
          child: stack,
        ),
      );
    }

    return Listener(
      onPointerSignal: _onPointerSignal,
      child: GestureDetector(
        onScaleStart: (widget.panEnabled || widget.zoomEnabled)
            ? _onScaleStart
            : null,
        onScaleUpdate: (widget.panEnabled || widget.zoomEnabled)
            ? _onScaleUpdate
            : null,
        onScaleEnd: (widget.panEnabled || widget.zoomEnabled)
            ? _onScaleEnd
            : null,
        child: stack,
      ),
    );
  }
}
