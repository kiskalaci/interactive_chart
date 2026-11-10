import "package:flutter/rendering.dart";
import "package:interactive_chart/src/web/scroll_guard_stub.dart"
    if (dart.library.js_interop) "package:interactive_chart/src/web/scroll_guard_web.dart"
    as impl;

/// Suppresses the browser's native "swipe to navigate back/forward" gesture
/// for horizontal wheel/trackpad scroll while the pointer is over
/// [getBounds] — so panning the chart with a trackpad doesn't kick the user
/// out of the page. A no-op off the web.
///
/// [getBounds] returns the chart viewport's current on-screen rect in
/// browser (CSS-pixel) coordinates; return null while not yet laid out.
/// This assumes the Flutter view's logical-pixel origin coincides with the
/// browser viewport's origin, true for the common full-page embedding but
/// not guaranteed for a Flutter view offset within a larger host page.
abstract class ScrollGuard {
  factory ScrollGuard(Rect? Function() getBounds) = impl.ScrollGuardImpl;

  void dispose();
}
