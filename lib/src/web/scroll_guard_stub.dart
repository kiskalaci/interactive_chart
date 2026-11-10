import "package:flutter/rendering.dart";
import "package:interactive_chart/src/web/scroll_guard.dart";

class ScrollGuardImpl implements ScrollGuard {
  // ignore: avoid_unused_constructor_parameters
  ScrollGuardImpl(Rect? Function() getBounds);

  @override
  void dispose() {}
}
