import "package:flutter/painting.dart";

/// The laid-out size of short, single-direction (left-to-right) labels, cached
/// by text, style and text scale.
///
/// The axes and the price tag measure their labels on every frame of a pan to
/// place them, and mostly the same labels. Laying out a paragraph is far more
/// expensive than looking up its size, so sizes are kept, least recently used
/// dropped first beyond [capacity]. Only sizes are kept, never painters, so
/// nothing a caller holds can be disposed under it. The cache is cleared when
/// the system's fonts change, since sizes depend on them.
class LabelSizes {
  LabelSizes({this.capacity = 512})
    : assert(capacity > 0, "capacity must be positive");

  /// The cache the chart uses.
  static final instance = LabelSizes();

  final int capacity;

  /// In insertion order, which is least recently used first.
  final _sizes = <(String, TextStyle, TextScaler), Size>{};
  bool _listening = false;

  /// How many labels have been laid out (cache misses), for tests.
  int get layouts => _layouts;
  int _layouts = 0;

  /// How many sizes are cached.
  int get length => _sizes.length;

  /// The size of [text] in [style] at [textScaler], laid out on one line with
  /// no width limit.
  Size of(String text, TextStyle style, TextScaler textScaler) {
    _listenForFontChanges();
    final key = (text, style, textScaler);
    final cached = _sizes.remove(key);
    if (cached != null) {
      _sizes[key] = cached; // now the most recently used
      return cached;
    }
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    final size = painter.size;
    painter.dispose();
    _layouts++;
    _sizes[key] = size;
    if (_sizes.length > capacity) {
      _sizes.remove(_sizes.keys.first);
    }
    return size;
  }

  /// Forgets every size.
  void clear() => _sizes.clear();

  void _listenForFontChanges() {
    if (_listening) {
      return;
    }
    _listening = true;
    PaintingBinding.instance.systemFonts.addListener(clear);
  }
}
