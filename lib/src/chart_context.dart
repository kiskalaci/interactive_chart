import "dart:math" as math;

import "package:flutter/foundation.dart";
import "package:interactive_chart/src/ticks.dart";

/// Which edge of the viewport the chart is initially scrolled to — i.e.
/// where it starts building its candles from. This is purely about the
/// starting scroll position; it never mirrors the axis, since time always
/// runs left-to-right on screen (see [xOf]).
///
/// [ChartAnchor.left] leaves the viewport at the start of the data, so the
/// earliest slot sits at the left edge — e.g. an intraday chart, which
/// starts empty at market open and fills in candles as the session
/// progresses.
///
/// [ChartAnchor.right] scrolls to the end of the data on first layout, so
/// the newest slot sits at the right edge — e.g. a chart of historic data,
/// which should open already showing the most recent candle.
enum ChartAnchor { left, right }

/// Inclusive-exclusive index range: `[start, end)`.
typedef IndexRange = (int start, int end);

/// A decimal `(min, max)` pair.
typedef ValueRange = (double min, double max);

/// Shared render/interaction state for one [InteractiveChart].
///
/// Deliberately generic over nothing: it knows about slots, pixels and
/// timestamps only. Anything datum-shaped (accessors, extents) is computed
/// by the widget/layers and pushed in via the setters below, mirroring the
/// requirements' separation between the context (§5) and layers (§8).
class InteractiveChartContext extends ChangeNotifier {
  InteractiveChartContext({
    this.initialAnchor = ChartAnchor.right,
    double slotExtent = 8,
    this.minSlotExtent = 1,
    this.maxSlotExtent = 64,
  }) : _slotExtent = slotExtent.clamp(minSlotExtent, maxSlotExtent);

  ChartAnchor initialAnchor;
  final double minSlotExtent;
  final double maxSlotExtent;

  bool _initialAnchorApplied = false;

  double _slotExtent;
  double get slotExtent => _slotExtent;

  double _scrollOffset = 0;
  double get scrollOffset => _scrollOffset;

  double viewportWidth = 0;
  double viewportHeight = 0;

  int slotCount = 0;

  /// [visibleStart, visibleEnd) clamped to real data — never includes a
  /// projected slot (R-TIME-27).
  int visibleStart = 0;
  int visibleEnd = 0;

  bool autoscale = true;
  double valueMin = 0;
  double valueMax = 1;

  List<double> valueTicks = const [];
  List<TickMark> timeTicks = const [];

  int? highlightedIndex;
  DateTime? highlightedProjectedTime;

  /// How far past the newest datum overscroll is allowed (R-SCROLL-4).
  double get maxOverscrollPx => viewportWidth * 0.5;

  /// How many projected (data-less) slots the overscroll region can hold.
  int get projectedSlotCount =>
      minSlotExtent > 0 ? (maxOverscrollPx / minSlotExtent).ceil() : 0;

  double get contentExtent => slotCount * _slotExtent;

  double get minScrollOffset => 0;

  double get maxScrollOffset => math.max(
    minScrollOffset,
    contentExtent - viewportWidth + maxOverscrollPx,
  );

  void setViewportSize(double width, double height) {
    if (viewportWidth == width && viewportHeight == height) {
      return;
    }
    viewportWidth = width;
    viewportHeight = height;
    _applyInitialAnchorIfNeeded();
    _clampScroll();
    _recomputeVisibleRange();
  }

  void setSlotCount(int count) {
    if (slotCount == count) {
      return;
    }
    slotCount = count;
    _applyInitialAnchorIfNeeded();
    _clampScroll();
    _recomputeVisibleRange();
  }

  /// Scrolls to [initialAnchor] the first time the viewport has a real size
  /// — i.e. exactly once, so later data changes never reset pan/zoom
  /// (R-DATA-9).
  void _applyInitialAnchorIfNeeded() {
    if (_initialAnchorApplied || viewportWidth <= 0) {
      return;
    }
    _initialAnchorApplied = true;
    _scrollOffset = initialAnchor == ChartAnchor.left
        ? minScrollOffset
        : maxScrollOffset;
  }

  /// Sets slot extent (zoom) and scroll offset together, anchored — the
  /// caller is expected to have derived both from a single gesture-start
  /// reference (see the widget's scale-gesture handler) so a combined
  /// pan+pinch never drifts.
  void setSlotExtentAndScroll(double newSlotExtent, double newScrollOffset) {
    _slotExtent = newSlotExtent.clamp(minSlotExtent, maxSlotExtent);
    _scrollOffset = newScrollOffset;
    _clampScroll();
    _recomputeVisibleRange();
    notifyListeners();
  }

  void panBy(double deltaContentPx) {
    _scrollOffset += deltaContentPx;
    _clampScroll();
    _recomputeVisibleRange();
    notifyListeners();
  }

  /// Pans the value extent by a screen-space pixel delta, switching out of
  /// autoscale into a manual extent — the value-axis counterpart of [panBy].
  /// Positive [deltaPx] (pointer/content moving down) shifts the visible
  /// value window down, matching direct-manipulation drag semantics.
  void panValueByPixels(double deltaPx) {
    final span = valueMax - valueMin;
    if (span <= 0 || viewportHeight <= 0) {
      return;
    }
    final deltaValue = deltaPx / viewportHeight * span;
    autoscale = false;
    valueMin += deltaValue;
    valueMax += deltaValue;
    notifyListeners();
  }

  void jumpTo(double offset) {
    _scrollOffset = offset;
    _clampScroll();
    _recomputeVisibleRange();
    notifyListeners();
  }

  // ignore: avoid_positional_boolean_parameters
  void setHighlighted(int? index, {DateTime? projectedTime}) {
    if (highlightedIndex == index &&
        highlightedProjectedTime == projectedTime) {
      return;
    }
    highlightedIndex = index;
    highlightedProjectedTime = projectedTime;
    notifyListeners();
  }

  void setAutoscale(bool value) {
    if (autoscale == value) {
      return;
    }
    autoscale = value;
    notifyListeners();
  }

  void setValueExtent(double min, double max) {
    valueMin = min;
    valueMax = max;
  }

  /// Zooms the value extent by [factor] around [anchorValue], switching out
  /// of autoscale into a manual extent (R-SCROLL-7) — the value-axis
  /// counterpart of [setSlotExtentAndScroll]'s anchored x zoom. `factor < 1`
  /// shrinks the range (zoom in); `factor > 1` grows it (zoom out).
  void zoomValueExtent(double factor, double anchorValue) {
    autoscale = false;
    valueMin = anchorValue - (anchorValue - valueMin) * factor;
    valueMax = anchorValue + (valueMax - anchorValue) * factor;
    notifyListeners();
  }

  /// Lets the owning widget announce state that changed outside of a
  /// gesture (e.g. the very first layout) to controller/callback listeners.
  void announce() => notifyListeners();

  /// The single `xOf` every layer must use (R-SCALE-2) — index to viewport
  /// pixel, centred on the slot. Time always runs left-to-right; only the
  /// initial scroll position depends on [initialAnchor].
  double xOf(int index) {
    final contentPixel = index * _slotExtent + _slotExtent / 2;
    return contentPixel - _scrollOffset;
  }

  double yOf(double value) {
    final span = valueMax - valueMin;
    if (span <= 0) {
      return viewportHeight / 2;
    }
    return viewportHeight - (value - valueMin) / span * viewportHeight;
  }

  double valueOfViewportY(double viewportY) {
    final span = valueMax - valueMin;
    return valueMin + (viewportHeight - viewportY) / viewportHeight * span;
  }

  /// Fractional index under a viewport-space x — used to anchor zoom.
  double fractionalIndexAtViewportX(double viewportX) =>
      (_scrollOffset + viewportX) / _slotExtent;

  int indexAtViewportX(double viewportX) =>
      fractionalIndexAtViewportX(viewportX).floor();

  void _clampScroll() {
    _scrollOffset = _scrollOffset.clamp(
      minScrollOffset,
      math.max(minScrollOffset, maxScrollOffset),
    );
  }

  void _recomputeVisibleRange() {
    if (slotCount == 0 || viewportWidth == 0) {
      visibleStart = 0;
      visibleEnd = 0;
      return;
    }
    final i0 = indexAtViewportX(0);
    final i1 = indexAtViewportX(viewportWidth);
    final lo = math.min(i0, i1);
    final hi = math.max(i0, i1);
    visibleStart = lo.clamp(0, math.max(0, slotCount - 1));
    visibleEnd = (hi + 1).clamp(visibleStart, slotCount);
  }
}
