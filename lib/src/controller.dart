import "package:flutter/foundation.dart";
import "package:interactive_chart/src/chart_context.dart";

/// R-API-6 (subset): programmatic read/write access to visible range, zoom,
/// autoscale and highlighted index, plus "jump to latest". Attached to the
/// widget's internal [InteractiveChartContext] once the widget mounts.
class InteractiveChartController extends ChangeNotifier {
  InteractiveChartContext? _ctx;

  void attach(InteractiveChartContext ctx) {
    if (_ctx == ctx) {
      return;
    }
    _ctx?.removeListener(notifyListeners);
    _ctx = ctx;
    ctx.addListener(notifyListeners);
  }

  bool get isAttached => _ctx != null;

  IndexRange get visibleRange =>
      _ctx == null ? (0, 0) : (_ctx!.visibleStart, _ctx!.visibleEnd);

  double get slotExtent => _ctx?.slotExtent ?? 0;

  bool get autoscale => _ctx?.autoscale ?? true;

  int? get highlightedIndex => _ctx?.highlightedIndex;

  void setAutoscale(bool value) => _ctx?.setAutoscale(value);

  /// Scrolls to the newest data (R-SCROLL-5's manual counterpart: "jump to
  /// latest").
  void jumpToLatest() {
    final ctx = _ctx;
    if (ctx == null) {
      return;
    }
    ctx.jumpTo(ctx.contentExtent - ctx.viewportWidth);
  }

  void clearHighlight() => _ctx?.setHighlighted(null);

  @override
  void dispose() {
    _ctx?.removeListener(notifyListeners);
    super.dispose();
  }
}
