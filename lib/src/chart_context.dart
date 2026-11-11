import "dart:math" as math;

import "package:flutter/foundation.dart";
import "package:interactive_chart/src/chart_anchor.dart";
import "package:interactive_chart/src/time_axis/time_ticks.dart";

/// Shared render/interaction state for one `InteractiveChart`.
///
/// Deliberately generic over nothing: it knows about slots, pixels and
/// timestamps only. Anything datum-shaped (accessors, extents) is computed
/// by the widget/layers and pushed in via the setters below, mirroring the
/// requirements' separation between the context (§5) and layers (§8).
///
/// Listeners of the context itself hear about every change. Two narrower
/// listenables split them by kind, so a change only rebuilds what reads it:
/// [viewChanges] for scroll, zoom and the value extent, and
/// [highlightChanges] for the crosshair's slot. Moving the crosshair then
/// rebuilds the crosshair alone, not every candle on screen.
class InteractiveChartContext extends ChangeNotifier {
  InteractiveChartContext({
    this.initialAnchor = ChartAnchor.right,
    double slotExtent = 8,
    this.minSlotExtent = 1,
    this.maxSlotExtent = 64,
  }) : _slotExtent = slotExtent.clamp(minSlotExtent, maxSlotExtent);

  ChartAnchor initialAnchor;
  final double minSlotExtent;

  final _view = _Signal();
  final _highlight = _Signal();

  /// Notifies when the view changes: scroll, zoom, the value extent or
  /// autoscale. Never for a highlight change.
  Listenable get viewChanges => _view;

  /// Notifies when [highlightedIndex] or [highlightedProjectedTime] changes,
  /// and for nothing else.
  Listenable get highlightChanges => _highlight;

  void _notifyView() {
    _view.fire();
    notifyListeners();
  }

  final double maxSlotExtent;

  bool _initialAnchorApplied = false;

  double _slotExtent;
  double get slotExtent => _slotExtent;

  double _scrollOffset = 0;
  double get scrollOffset => _scrollOffset;

  double viewportWidth = 0;
  double viewportHeight = 0;

  int slotCount = 0;

  /// Bumped every time the chart's parent rebuilds it (new data, data edited
  /// in place, or new layers). Anything cached from the data, such as a
  /// layer's painted geometry, is stale once it changes.
  int dataRevision = 0;

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

  /// While set, the view is pinned to a position that depends on the viewport
  /// width (the newest datum against the right edge), and is re-applied when
  /// the width changes. Without it, a value-axis gutter that grows after the
  /// view was placed (wider labels for a new range) narrows the viewport and
  /// leaves the newest bar slightly out of view. Any scroll, zoom or data
  /// change drops the pin.
  double Function()? _pin;

  /// Pins the view to the offset [offsetFor] returns, now and whenever the
  /// viewport width changes, until the user or the data moves it.
  // A setter cannot express "pin to a computed offset".
  // ignore: use_setters_to_change_properties
  void pinTo(double Function() offsetFor) {
    _pin = offsetFor;
  }

  void setViewportSize(double width, double height) {
    if (viewportWidth == width && viewportHeight == height) {
      return;
    }
    final widthChanged = viewportWidth != width;
    viewportWidth = width;
    viewportHeight = height;
    final wasApplied = _initialAnchorApplied;
    _applyInitialAnchorIfNeeded();
    if (wasApplied && widthChanged && _pin != null) {
      _scrollOffset = _pin!();
    }
    _clampScroll();
    _recomputeVisibleRange();
  }

  /// [prepended] is how many slots were inserted before the previous first
  /// one (R-DATA-10): the scroll offset moves by that many slots so the
  /// visible candles stay exactly where they were.
  void setSlotCount(int count, {int prepended = 0}) {
    if (slotCount == count) {
      return;
    }
    slotCount = count;
    if (_initialAnchorApplied) {
      _pin = null; // the data moved: the view no longer follows the edge
    }
    if (_initialAnchorApplied && prepended > 0) {
      _scrollOffset += prepended * _slotExtent;
    }
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
    if (initialAnchor == ChartAnchor.left) {
      _scrollOffset = minScrollOffset;
    } else {
      _scrollOffset = maxScrollOffset;
      pinTo(() => maxScrollOffset);
    }
  }

  /// Sets slot extent (zoom) and scroll offset together, anchored — the
  /// caller is expected to have derived both from a single gesture-start
  /// reference (see the widget's scale-gesture handler) so a combined
  /// pan+pinch never drifts.
  void setSlotExtentAndScroll(double newSlotExtent, double newScrollOffset) {
    _pin = null;
    _slotExtent = newSlotExtent.clamp(minSlotExtent, maxSlotExtent);
    _scrollOffset = newScrollOffset;
    _clampScroll();
    _recomputeVisibleRange();
    _notifyView();
  }

  void panBy(double deltaContentPx) {
    _pin = null;
    _scrollOffset += deltaContentPx;
    _clampScroll();
    _recomputeVisibleRange();
    _notifyView();
  }

  /// Pans the value extent by a screen-space pixel delta, switching out of
  /// autoscale into a manual extent — the value-axis counterpart of [panBy].
  /// Positive [deltaPx] (pointer/content moving down) shifts the visible
  /// value window down, matching direct-manipulation drag semantics.
  void panValueByPixels(double deltaPx) {
    final span = valueMax - valueMin;
    // A purely horizontal drag has no vertical movement and must not drop
    // the chart out of autoscale.
    if (deltaPx == 0 || span <= 0 || viewportHeight <= 0) {
      return;
    }
    final deltaValue = deltaPx / viewportHeight * span;
    autoscale = false;
    valueMin += deltaValue;
    valueMax += deltaValue;
    _notifyView();
  }

  void jumpTo(double offset) {
    _pin = null;
    _scrollOffset = offset;
    _clampScroll();
    _recomputeVisibleRange();
    _notifyView();
  }

  // ignore: avoid_positional_boolean_parameters
  void setHighlighted(int? index, {DateTime? projectedTime}) {
    if (highlightedIndex == index &&
        highlightedProjectedTime == projectedTime) {
      return;
    }
    highlightedIndex = index;
    highlightedProjectedTime = projectedTime;
    _highlight.fire();
    notifyListeners();
  }

  // Public API mirrors Controller.setAutoscale.
  // ignore: avoid_positional_boolean_parameters
  void setAutoscale(bool value) {
    if (autoscale == value) {
      return;
    }
    autoscale = value;
    _notifyView();
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
    _notifyView();
  }

  /// Lets the owning widget announce state that changed outside of a
  /// gesture (e.g. the very first layout) to controller/callback listeners.
  void announce() => _notifyView();

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
    // Slot i covers content pixels [i * extent, (i + 1) * extent). It is in
    // view when that interval overlaps [offset, offset + width), so the last
    // slot is the one holding the viewport's right edge — a slot that merely
    // starts at the edge is not visible.
    final first = (_scrollOffset / _slotExtent).floor();
    final end = ((_scrollOffset + viewportWidth) / _slotExtent).ceil();
    visibleStart = first.clamp(0, math.max(0, slotCount - 1));
    visibleEnd = end.clamp(visibleStart, slotCount);
  }

  @override
  void dispose() {
    _view.dispose();
    _highlight.dispose();
    super.dispose();
  }
}

/// A [ChangeNotifier] that can be fired from outside.
class _Signal extends ChangeNotifier {
  void fire() => notifyListeners();
}
