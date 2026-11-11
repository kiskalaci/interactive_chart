import "dart:async";
import "dart:math" as math;

import "package:flutter/gestures.dart";
import "package:flutter/widgets.dart";
import "package:interactive_chart/src/time_axis/time_axis.dart";
import "package:interactive_chart/src/time_axis/time_axis_config.dart";
import "package:interactive_chart/src/time_axis/time_axis_placement.dart";
import "package:interactive_chart/src/value_axis/value_axis.dart";
import "package:interactive_chart/src/value_axis/value_axis_config.dart";
import "package:interactive_chart/src/value_axis/value_axis_placement.dart";
import "package:interactive_chart/src/chart_anchor.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/controller.dart";
import "package:interactive_chart/src/layer.dart";
import "package:interactive_chart/src/time_axis/time_ticks.dart";
import "package:interactive_chart/src/value_axis/value_ticks.dart";
import "package:interactive_chart/src/web/scroll_guard.dart";
export "package:interactive_chart/src/time_axis/time_axis.dart";
export "package:interactive_chart/src/time_axis/time_axis_config.dart";
export "package:interactive_chart/src/time_axis/time_axis_placement.dart";
export "package:interactive_chart/src/value_axis/value_axis.dart";
export "package:interactive_chart/src/value_axis/value_axis_config.dart";
export "package:interactive_chart/src/value_axis/value_axis_placement.dart";
export "package:interactive_chart/src/chart_anchor.dart";
export "package:interactive_chart/src/typedefs/index_range.dart";
export "package:interactive_chart/src/typedefs/value_range.dart";
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

  /// The series, sorted oldest to newest by [timeOf]. Appending, updating the
  /// last datum and prepending older data keep the current pan and zoom.
  /// Unsorted data does not throw, but axis labels, projected slots and
  /// prepend detection are undefined.
  final List<T> data;
  final DateTime Function(T datum) timeOf;
  final List<ChartLayer<T>> layers;

  /// Where the chart opens. Read once when the chart is first laid out;
  /// changing it later does not move the view.
  final ChartAnchor initialAnchor;

  /// The zoom the chart opens at. Read once; changing it later does not
  /// re-zoom. Use [InteractiveChartController.jumpToLatest] with `slotExtent`
  /// to reset zoom programmatically.
  final double initialSlotExtent;

  /// The zoom limits. Read once when the chart is created; changing them
  /// later has no effect.
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
  static const double _timeAxisBaseHeight = 22;

  /// Set at the start of each build so the axis measurements honour the
  /// user's text scale.
  TextScaler _textScaler = TextScaler.noScaling;

  /// The time axis grows with the text scale (never below its base height).
  double get _timeAxisHeight =>
      _timeAxisBaseHeight * math.max(1.0, _textScaler.scale(1));

  int? _lastAutoscaleStart;
  int? _lastAutoscaleEnd;
  int _lastDataLength = -1;

  /// Set whenever the parent rebuilds this widget (new data, in-place edits
  /// or different layers), so autoscale re-reads the visible values even if
  /// the visible range and the data length are unchanged (R-SCALE-10).
  bool _autoscaleDirty = true;

  /// Whether autoscale was on at the last check. Switching it back on after
  /// a manual extent must recompute even though the range and data are
  /// unchanged.
  bool _wasAutoscaling = true;

  double? _lastTickSlotExtentBucket;
  int _lastTickSlotCount = -1;
  int _lastTickProjectedCount = -1;

  double? _gestureStartSlotExtent;
  double? _gestureStartContentPixelAtFocal;
  double? _gestureStartFocalX;

  /// Viewport x of the most recent pointer-down. A one-finger drag starts
  /// from here rather than from where Flutter's slop ends, so the chart
  /// follows the finger from the first pixel.
  double? _lastPointerDownX;
  double? _lastPointerDownY;

  /// Where the current gesture started vertically, and how much vertical
  /// movement has already been applied to the value extent.
  double? _gestureStartFocalY;
  double _appliedDy = 0;

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
    _autoscaleDirty = true;
    if (widget.data.length != oldWidget.data.length) {
      // R-DATA-9: appending/changing data must not reset pan/zoom.
      final prepended = _prependedCount(oldWidget.data, widget.data);
      ctx.setSlotCount(widget.data.length, prepended: prepended);
      final startExtent = _gestureStartSlotExtent;
      final startPixel = _gestureStartContentPixelAtFocal;
      if (prepended > 0 && startExtent != null && startPixel != null) {
        // A gesture in progress measures from the content pixel under its
        // start focal point. Older data moved that pixel right by the
        // prepended width, so move the reference too, or the next update
        // would snap the view back by that amount.
        _gestureStartContentPixelAtFocal = startPixel + prepended * startExtent;
      }
    }
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?.detach(ctx);
      _ownedController?.dispose();
      _ownedController = null;
      _attachController();
    }
  }

  /// How many items were inserted before the old first datum (R-DATA-10),
  /// found by binary-searching the old first timestamp in the new, ascending
  /// data. Zero unless older data really was prepended.
  int _prependedCount(List<T> oldData, List<T> newData) {
    if (oldData.isEmpty || newData.length <= oldData.length) {
      return 0;
    }
    final target = widget.timeOf(oldData.first);
    var lo = 0;
    var hi = newData.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (widget.timeOf(newData[mid]).isBefore(target)) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final found = lo < newData.length && widget.timeOf(newData[lo]) == target;
    return found ? lo : 0;
  }

  void _onContextChanged() {
    widget.onVisibleRangeChanged?.call(ctx.visibleStart, ctx.visibleEnd);
    // R-TIME-29: a projected (data-less) slot has no datum to report.
    widget.onIndexHighlighted?.call(
      ctx.highlightedProjectedTime == null ? ctx.highlightedIndex : null,
    );
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
    _longPressTimer?.cancel();
    widget.controller?.detach(ctx);
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
    final reEnabled = ctx.autoscale && !_wasAutoscaling;
    _wasAutoscaling = ctx.autoscale;
    if (ctx.autoscale) {
      final s = ctx.visibleStart;
      final e = ctx.visibleEnd;
      if (s != _lastAutoscaleStart ||
          e != _lastAutoscaleEnd ||
          widget.data.length != _lastDataLength ||
          _autoscaleDirty ||
          reEnabled) {
        _autoscaleDirty = false;
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
    // The overscroll region grows and shrinks with the viewport width, so the
    // projected marks must follow (a window made wider needs labels further
    // right). Rounded up to a multiple of 16 so a continuous resize does not
    // rebuild the whole set on every pixel.
    final projectedCount = (ctx.projectedSlotCount + 15) ~/ 16 * 16;
    if (bucket == _lastTickSlotExtentBucket &&
        widget.data.length == _lastTickSlotCount &&
        projectedCount == _lastTickProjectedCount) {
      return;
    }
    _lastTickSlotExtentBucket = bucket;
    _lastTickSlotCount = widget.data.length;
    _lastTickProjectedCount = projectedCount;

    final realTimes = [for (final d in widget.data) widget.timeOf(d)];
    final projected = projectTimes(realTimes, projectedCount);
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
    var measured = measureValueAxisWidth(
      ctx,
      widget.valueAxis!,
      textScaler: _textScaler,
    );
    for (final layer in widget.layers) {
      measured = math.max(
        measured,
        layer.measureValueAxisOverlayWidth(ctx, widget.data, _textScaler),
      );
    }
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
    final focalX = details.pointerCount == 1 && _lastPointerDownX != null
        ? _lastPointerDownX!
        : details.localFocalPoint.dx;
    _gestureStartFocalX = focalX;
    _gestureStartFocalY = details.pointerCount == 1 && _lastPointerDownY != null
        ? _lastPointerDownY!
        : details.localFocalPoint.dy;
    _appliedDy = 0;
    _gestureStartContentPixelAtFocal = ctx.scrollOffset + focalX;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_crosshairActive) {
      return; // the finger is dragging the crosshair, not the chart
    }
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

    // With panning on, the content under the gesture's start focal point
    // follows the fingers. With panning off, a zoom stays anchored at the
    // *start* focal point, so a one-finger drag (scale 1) cannot scroll.
    final focalX = widget.panEnabled
        ? details.localFocalPoint.dx
        : (_gestureStartFocalX ?? details.localFocalPoint.dx);
    final newContentPixelAtFocal = domainIndexAtFocal * newSlotExtent;
    final newScrollOffset = newContentPixelAtFocal - focalX;

    ctx.setSlotExtentAndScroll(newSlotExtent, newScrollOffset);

    if (widget.panEnabled) {
      // Cumulative from the gesture's start, so the slop distance travelled
      // before the gesture was recognised is applied too.
      final total =
          details.localFocalPoint.dy -
          (_gestureStartFocalY ?? details.localFocalPoint.dy);
      ctx.panValueByPixels(total - _appliedDy);
      _appliedDy = total;
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _gestureStartSlotExtent = null;
    _gestureStartFocalX = null;
    _gestureStartFocalY = null;
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

  // --- touch crosshair ---------------------------------------------------
  //
  // A tap places the crosshair; a long press shows it and then follows the
  // finger until release. This uses raw pointer events rather than gesture
  // recognisers on purpose: a recogniser that is hit everywhere joins every
  // touch's gesture arena and delays pan and pinch recognition by a touch
  // slop. While the crosshair is being dragged, pan and zoom updates are
  // ignored instead.

  Timer? _longPressTimer;
  int? _touchPointer;
  Offset? _touchDownPosition;
  Duration? _touchDownTime;
  bool _crosshairActive = false;

  void _onTouchDown(PointerDownEvent event) {
    if (!mounted) {
      return; // a gesture that began before this chart was removed
    }
    if (!widget.crosshairEnabled || event.kind == PointerDeviceKind.mouse) {
      return;
    }
    if (_touchPointer != null) {
      // A second finger: this is a pinch, not a crosshair gesture.
      _endTouchCrosshair(clear: true);
      return;
    }
    _touchPointer = event.pointer;
    _touchDownPosition = event.localPosition;
    _touchDownTime = event.timeStamp;
    _longPressTimer = Timer(kLongPressTimeout, () {
      final at = _touchDownPosition;
      if (at != null && mounted) {
        _crosshairActive = true;
        _updateHighlight(at);
      }
    });
  }

  void _onTouchMove(PointerMoveEvent event) {
    if (!mounted) {
      return; // a gesture that began before this chart was removed
    }
    if (event.pointer != _touchPointer) {
      return;
    }
    if (_crosshairActive) {
      _updateHighlight(event.localPosition);
    } else if ((event.localPosition - _touchDownPosition!).distance >
        kTouchSlop) {
      _longPressTimer?.cancel(); // it is a drag, not a long press
    }
  }

  void _onTouchUp(PointerUpEvent event) {
    if (!mounted) {
      return; // a gesture that began before this chart was removed
    }
    if (event.pointer != _touchPointer) {
      return;
    }
    final wasActive = _crosshairActive;
    final moved =
        (event.localPosition - _touchDownPosition!).distance > kTouchSlop;
    final quick = event.timeStamp - _touchDownTime! < kLongPressTimeout;
    _endTouchCrosshair(clear: wasActive);
    if (!wasActive && !moved && quick) {
      _updateHighlight(event.localPosition); // a tap
    }
  }

  void _onTouchCancel(PointerCancelEvent event) {
    if (!mounted) {
      return; // a gesture that began before this chart was removed
    }
    if (event.pointer == _touchPointer) {
      _endTouchCrosshair(clear: _crosshairActive);
    }
  }

  void _endTouchCrosshair({required bool clear}) {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _touchPointer = null;
    _touchDownPosition = null;
    _touchDownTime = null;
    _crosshairActive = false;
    if (clear) {
      _clearHighlight();
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
      assert(() {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          throw FlutterError.fromParts([
            ErrorSummary("InteractiveChart was given unbounded constraints."),
            ErrorDescription(
              "It fills the space it is given, so it needs a bounded width "
              "and height, but it received $constraints.",
            ),
            ErrorHint(
              "Wrap it in a SizedBox, Expanded, Flexible or AspectRatio, or "
              "give its scrollable parent a fixed extent.",
            ),
          ]);
        }
        return true;
      }(), "InteractiveChart requires bounded constraints.");
      _textScaler = MediaQuery.textScalerOf(context);
      // An axis is only laid out when the chart is big enough to hold it and
      // still leave a viewport; in a tiny (or animating-from-zero) chart it
      // is dropped rather than overflowing.
      final showValueAxis =
          widget.valueAxis != null && constraints.maxWidth > _valueAxisWidth;
      final showTimeAxis =
          widget.timeAxis != null && constraints.maxHeight > _timeAxisHeight;
      final valueAxisWidth = showValueAxis ? _valueAxisWidth : 0.0;
      final timeAxisHeight = showTimeAxis ? _timeAxisHeight : 0.0;
      final viewportWidth = math.max<double>(
        0,
        constraints.maxWidth - valueAxisWidth,
      );
      final viewportHeight = math.max<double>(
        0,
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

      final valueAxisWidget = !showValueAxis
          ? null
          : SizedBox(
              width: _valueAxisWidth,
              height: viewportHeight,
              child: _wrapValueAxisGutter(
                Stack(
                  children: [
                    Positioned.fill(
                      child: ValueAxisView(ctx: ctx, config: widget.valueAxis!),
                    ),
                    for (final layer in widget.layers)
                      if (layer.buildValueAxisOverlay(
                            Size(_valueAxisWidth, viewportHeight),
                            ctx,
                            widget.data,
                          )
                          case final overlay?)
                        Positioned.fill(child: overlay),
                  ],
                ),
              ),
            );

      final timeAxisWidget = !showTimeAxis
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
        child: stack,
      );
    }

    return Listener(
      onPointerSignal: _onPointerSignal,
      onPointerDown: (event) {
        if (!mounted) {
          return;
        }
        _lastPointerDownX = event.localPosition.dx;
        _lastPointerDownY = event.localPosition.dy;
        _onTouchDown(event);
      },
      onPointerMove: _onTouchMove,
      onPointerUp: _onTouchUp,
      onPointerCancel: _onTouchCancel,
      child: GestureDetector(
        // Opaque so pan and zoom work anywhere in the viewport. The default
        // defers to the children, which left empty space dead whenever the
        // crosshair's mouse region (itself always hit) was not present.
        behavior: HitTestBehavior.opaque,
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
