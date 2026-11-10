import "package:flutter/material.dart";

/// Chart colors for the widgetbook demos, adapted to the active theme.
class ColorPalette {
  const ColorPalette._({
    required this.blue,
    required this.green,
    required this.red,
    required this.purple,
  });

  static const _light = ColorPalette._(
    blue: Color(0xFF2563EB),
    green: Color(0xFF22C55E),
    red: Color(0xFFEF4444),
    purple: Color(0xFF9333EA),
  );

  static const _dark = ColorPalette._(
    blue: Color(0xFF60A5FA),
    green: Color(0xFF4ADE80),
    red: Color(0xFFF87171),
    purple: Color(0xFFC084FC),
  );

  final Color blue;
  final Color green;
  final Color red;
  final Color purple;

  static ColorPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;
}
