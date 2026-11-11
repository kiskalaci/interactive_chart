import "package:flutter/widgets.dart";

/// Finds the item under a point, or null where there is none.
typedef ItemResolver = int? Function(Offset localPosition);

/// One hit target for all the items of a painted layer, in place of one
/// widget per item. It fills its parent but is only hit where [resolve] finds
/// an item, so pointers elsewhere fall through to whatever is beneath, as
/// they did when each item was its own widget.
///
/// [onHover] reports the index on entering an item and null on leaving it;
/// moving straight from one item to the next reports null and then the new
/// index, like neighbouring mouse regions. When the items move under a still
/// pointer (a pan, a zoom or new data), the item now under it is reported
/// after the frame. [onTap] reports the item the tap went down on.
class ItemHitRegion extends StatefulWidget {
  const ItemHitRegion({
    required this.resolve,
    this.onTap,
    this.onHover,
    super.key,
  });

  final ItemResolver resolve;
  final void Function(int index)? onTap;
  final void Function(int? index)? onHover;

  @override
  State<ItemHitRegion> createState() => _ItemHitRegionState();
}

class _ItemHitRegionState extends State<ItemHitRegion> {
  int? _hovered;

  /// Where the mouse is while it is over an item, so a change to the items
  /// beneath it can be re-resolved.
  Offset? _pointer;
  int? _tapped;
  bool _recheckScheduled = false;

  void _hoverAt(Offset? position) {
    _pointer = position;
    final next = position == null ? null : widget.resolve(position);
    if (next == _hovered) {
      return;
    }
    final previous = _hovered;
    _hovered = next;
    final onHover = widget.onHover;
    if (previous != null) {
      onHover?.call(null);
    }
    if (next != null) {
      onHover?.call(next);
    }
  }

  @override
  void didUpdateWidget(ItemHitRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_pointer == null || widget.onHover == null || _recheckScheduled) {
      return;
    }
    // After the frame, like a mouse region's own enter and exit: a callback
    // that sets state must not run in the middle of this build.
    _recheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recheckScheduled = false;
      if (mounted && _pointer != null) {
        _hoverAt(_pointer);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget child = _ItemHitShape(resolve: widget.resolve);
    final onTap = widget.onTap;
    if (onTap != null) {
      child = GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTapDown: (details) => _tapped = widget.resolve(details.localPosition),
        onTapCancel: () => _tapped = null,
        onTap: () {
          final index = _tapped;
          _tapped = null;
          if (index != null) {
            onTap(index);
          }
        },
        child: child,
      );
    }
    if (widget.onHover != null) {
      child = MouseRegion(
        hitTestBehavior: HitTestBehavior.deferToChild,
        onEnter: (event) => _hoverAt(event.localPosition),
        onHover: (event) => _hoverAt(event.localPosition),
        onExit: (_) => _hoverAt(null),
        child: child,
      );
    }
    return child;
  }
}

/// Fills its parent and is hit exactly where [resolve] finds an item.
class _ItemHitShape extends LeafRenderObjectWidget {
  const _ItemHitShape({required this.resolve});

  final ItemResolver resolve;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderItemHitShape(resolve);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderItemHitShape renderObject,
  ) {
    renderObject.resolve = resolve;
  }
}

class _RenderItemHitShape extends RenderBox {
  _RenderItemHitShape(this.resolve);

  ItemResolver resolve;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool hitTestSelf(Offset position) => resolve(position) != null;
}

/// The topmost of [rects] containing [point], as an index into [rects], or
/// null. [rects] must be sorted by their left edge and painted in that order
/// (a later one on top), and none may be wider than [maxWidth].
int? topmostRectAt(List<Rect> rects, Offset point, double maxWidth) {
  // The last rect whose left edge is at or before the point.
  var lo = 0;
  var hi = rects.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (rects[mid].left <= point.dx) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  for (var k = lo - 1; k >= 0 && rects[k].left > point.dx - maxWidth; k--) {
    if (rects[k].contains(point)) {
      return k;
    }
  }
  return null;
}
