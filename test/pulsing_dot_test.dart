import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart" hide testWidgets;
import "package:interactive_chart/src/widgets/pulsing_dot.dart";

import "support/variants.dart";

const _color = Color(0xFF0000EE);

Widget _app(Widget child) => MaterialApp(home: Center(child: child));

/// The pulse ring and the solid centre dot, in paint order (ring first).
List<Container> _circles(WidgetTester tester) => tester
    .widgetList<Container>(
      find.descendant(
        of: find.byType(PulsingDot),
        matching: find.byType(Container),
      ),
    )
    .toList();

double _ringWidth(WidgetTester tester) =>
    tester.getSize(find.byWidget(_circles(tester).first)).width;

double _ringAlpha(WidgetTester tester) =>
    ((_circles(tester).first.decoration! as BoxDecoration).color!).a;

void main() {
  testWidgets("occupies pulseSize and draws the solid dot in its colour", (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const PulsingDot(color: _color, dotSize: 10, pulseSize: 30)),
    );
    expect(tester.getSize(find.byType(PulsingDot)), const Size.square(30));
    final circles = _circles(tester);
    expect(circles, hasLength(2));
    final dot = circles.last.decoration! as BoxDecoration;
    expect(dot.color, _color);
    expect(dot.shape, BoxShape.circle);
    expect(tester.getSize(find.byWidget(circles.last)), const Size.square(10));
  });

  testWidgets("ring starts at the dot size and grows while fading", (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const PulsingDot(
          color: _color,
          dotSize: 10,
          pulseSize: 30,
          duration: Duration(seconds: 1),
        ),
      ),
    );
    expect(_ringWidth(tester), closeTo(10, 0.01));
    expect(_ringAlpha(tester), closeTo(0.5, 0.01));

    await tester.pump(const Duration(milliseconds: 500));
    final midSize = _ringWidth(tester);
    final midAlpha = _ringAlpha(tester);
    expect(midSize, greaterThan(10));
    expect(midSize, lessThan(30));
    expect(midAlpha, lessThan(0.5));

    await tester.pump(const Duration(milliseconds: 499));
    expect(_ringWidth(tester), greaterThan(midSize));
    expect(_ringAlpha(tester), lessThan(midAlpha));
  });

  testWidgets("repeats: the ring restarts after a full cycle", (tester) async {
    await tester.pumpWidget(
      _app(
        const PulsingDot(
          color: _color,
          dotSize: 10,
          pulseSize: 30,
          duration: Duration(seconds: 1),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(_ringWidth(tester), closeTo(10, 0.5));
  });

  testWidgets("stops animating once removed from the tree", (tester) async {
    await tester.pumpWidget(_app(const PulsingDot(color: _color)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(_app(const SizedBox()));
    expect(find.byType(PulsingDot), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
