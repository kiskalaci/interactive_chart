// Runs widget tests across screen sizes and environments.
//
//   import "package:flutter_test/flutter_test.dart" hide testWidgets;
//   import "support/variants.dart";
//
// `testWidgets` here runs the body once per variant: five screen sizes
// (sm, m, l, xl, xxl) in each of two environments (a phone-like one and a
// browser-like one). The chart harness fills the screen, so layout, gestures
// and callbacks are exercised at every size. Tests whose arithmetic depends
// on one exact geometry use `testWidgetsOnce`, which runs a single time at the
// default size.
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart" as ft;
import "package:flutter_test/flutter_test.dart" show Timeout, WidgetTester;

/// Logical screen sizes. Widths follow common device classes: a phone, a
/// tablet in portrait, a small laptop, a desktop and a large desktop.
enum ScreenSize {
  sm(360, 640),
  m(768, 1024),
  l(1024, 768),
  xl(1440, 900),
  xxl(1920, 1080);

  const ScreenSize(this.width, this.height);
  final double width;
  final double height;
  Size get size => Size(width, height);
}

/// What the app is running on.
enum Env {
  /// A phone or tablet: Android, a dense display (3x), touch input.
  mobile(TargetPlatform.android, 3),

  /// A desktop browser: a desktop platform, a standard display (1x), mouse
  /// and trackpad input.
  browser(TargetPlatform.macOS, 1);

  const Env(this.platform, this.devicePixelRatio);
  final TargetPlatform platform;
  final double devicePixelRatio;
}

class ScreenConfig {
  const ScreenConfig(this.screen, this.env);
  final ScreenSize screen;
  final Env env;

  @override
  String toString() => "${screen.name}/${env.name}";
}

/// The logical size of the test screen right now.
Size screenOf(WidgetTester tester) =>
    tester.view.physicalSize / tester.view.devicePixelRatio;

/// The variant of the test that is currently running (null for tests started
/// with `testWidgetsOnce`).
ScreenConfig? currentScreen;

/// Every screen size in every environment.
final screenVariant = ft.ValueVariant<ScreenConfig>({
  for (final env in Env.values)
    for (final screen in ScreenSize.values) ScreenConfig(screen, env),
});

/// Runs [callback] once for every [ScreenConfig], with the test surface sized
/// and the platform set accordingly.
void testWidgets(
  String description,
  Future<void> Function(WidgetTester tester) callback, {
  Timeout? timeout,
  bool skip = false,
}) {
  ft.testWidgets(
    description,
    (tester) async {
      final config = screenVariant.currentValue!;
      currentScreen = config;
      tester.view.devicePixelRatio = config.env.devicePixelRatio;
      tester.view.physicalSize =
          config.screen.size * config.env.devicePixelRatio;
      debugDefaultTargetPlatformOverride = config.env.platform;
      try {
        await callback(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        currentScreen = null;
        tester.view.reset();
      }
    },
    variant: screenVariant,
    timeout: timeout,
    skip: skip,
  );
}

/// A single run at the framework's default size, for tests that pin an exact
/// geometry (or are too slow to repeat).
void testWidgetsOnce(
  String description,
  Future<void> Function(WidgetTester tester) callback, {
  Timeout? timeout,
  bool skip = false,
}) {
  ft.testWidgets(description, callback, timeout: timeout, skip: skip);
}
