import "dart:js_interop";

import "package:flutter/rendering.dart";
import "package:interactive_chart/src/web/scroll_guard.dart";
import "package:web/web.dart" as web;

class ScrollGuardImpl implements ScrollGuard {
  ScrollGuardImpl(this._getBounds) {
    _listener = ((web.Event event) {
      final wheel = event as web.WheelEvent;
      if (wheel.deltaX == 0) {
        return;
      }
      final bounds = _getBounds();
      if (bounds == null) {
        return;
      }
      if (bounds.contains(
        Offset(wheel.clientX.toDouble(), wheel.clientY.toDouble()),
      )) {
        event.preventDefault();
      }
    }).toJS;

    // Capture phase + non-passive: runs before, and is allowed to cancel,
    // the browser's own back/forward-swipe handling for this wheel event.
    web.window.addEventListener(
      "wheel",
      _listener,
      web.AddEventListenerOptions(passive: false, capture: true) as JSAny,
    );
  }

  final Rect? Function() _getBounds;
  late final JSFunction _listener;

  @override
  void dispose() {
    web.window.removeEventListener("wheel", _listener);
  }
}
