# Improvement ideas

Ideas for taking the POC further: performance, animation, visual styles and
open spec features. Each section is ordered by priority. See
[poc_notes.md](poc_notes.md) for what is implemented today and
[requirements.md](requirements.md) for the full specification.

Suggested order: performance items 1–3, then smooth autoscale and momentum
pan. Together they change how the chart feels more than anything else here.

## Performance

### 1. Stop rebuilding the whole chart on every change

`_onContextChanged` in `lib/src/interactive_chart_widget.dart` calls
`setState` on any context change. Moving the crosshair therefore rebuilds
every candle, line segment and axis label (TC-PERF-04 already expects this).

- Split the context's notifications into separate listenables: viewport and
  scale, highlight, and data.
- Wrap each layer in a `ListenableBuilder` and a `RepaintBoundary`, with each
  layer declaring which listenables it depends on.
- The crosshair then rebuilds only itself, and hover becomes nearly free.

### 2. Paint the shapes and keep one hit-test layer

Each candle is `Positioned → MouseRegion → GestureDetector → Stack →
2×Positioned → ColoredBox` (`lib/src/layers/candle_layer.dart`). At 1 px slots
on a wide screen that is about 2,000 candles × 7 elements per frame. The
per-item `onTap`/`onHover` API can stay without a widget per item:

- Draw candles with a `CustomPainter`, batched into one path per colour (up
  wicks and bodies, then down wicks and bodies).
- Put one `MouseRegion` and one `GestureDetector` over the viewport, map the
  pointer to an index with `ctx.indexAtViewportX`, and call `onTap(index)`.
- Do the same for `HistogramLayer` and the line layer's hit targets.

### 3. Draw the line as one path

`LineLayer` builds a rotated 1 px `ColoredBox` per segment. This is slow and
also looks worse: no anti-aliasing at the joins, gaps at sharp angles and no
round caps. A single `Path` stroked with `StrokeJoin.round` is faster and
renders better.

### 4. Make panning a translate, not a repaint

Paint content in content coordinates into a picture covering a buffer (for
example 1.5× the viewport). During a horizontal pan only a
`Transform.translate(-scrollOffset)` changes, which is compositing only.
Repaint when the view leaves the buffer, or when the zoom, value extent or
data changes.

### 5. Level of detail when zoomed far out

`minSlotExtent` is 1 px, so the chart cannot zoom out past one bar per pixel.
Aggregating bars per pixel column (min/max/first/last, the M4 approach) would
allow zooming out to years of 1-minute data. Keep per-range extents in a
sparse table or segment tree so autoscale stays fast over large ranges.

### 6. Cache label layout

`TextPainter`s are created in `value_axis.dart`, `time_axis.dart` and
`price_tag_layer.dart`. Reusing laid-out painters keyed by
`(text, style, textScaler)` avoids measuring the same labels again every
frame.

### 7. Measure it in CI

TC-PERF-01..05 are only planned. An `integration_test` using `traceAction`
around a scripted pan and pinch, reporting frame times, would show whether
items 1–4 help. The result could be published next to the coverage report.

## Animations

- **Smooth autoscale.** Ease `valueMin`/`valueMax` towards the target with a
  short spring instead of snapping on each new visible range. The most
  noticeable polish item.
- **Momentum pan.** There is no fling yet. A `FrictionSimulation` on drag end,
  with a bounce at the overscroll limit, makes touch feel native.
- **Animated jump.** `animateToLatest({duration, curve})` on the controller,
  alongside `jumpToLatest`.
- **Live ticks.**
  - Tween the last candle's close and the line's endpoint between updates.
  - Briefly flash the `PriceTagLayer` green or red on an up or down tick.
  - Optional countdown to bar close under the tag.
- **Entrance (opt-in).** The line draws itself in (trimmed with `PathMetric`)
  and candles grow from their open price.
- **Crosshair.** Ease the snap between slots and fade the badges in and out.

## Visual styles

- **Theming first.** About 40 colours are hardcoded as layer defaults. A
  `ChartTheme` (a `ThemeExtension` or `InheritedWidget`) with light and dark
  presets would let every layer pick up colours automatically. Possible
  presets: Classic, Midnight, Monochrome and Neon (glow from a blurred stroke
  underneath).
- **Candle styles.** Hollow candles, OHLC bars, Heikin-Ashi (a data transform
  plus the same layer), rounded bodies, volume-weighted body width.
- **Line styles.**
  - Step line.
  - Smoothed line, using monotone cubic so it never overshoots real highs and
    lows.
  - Dashed projection.
  - Stroke gradient by value.
- **Baseline chart.** Two-tone fill above and below a reference level such as
  the previous close, building on `_AreaFillPainter`.
- **Band layer.** Fill between two series, for Bollinger bands, ranges and
  confidence intervals. With an MA/EMA line this covers most indicators.
- **Background layers.** Session shading for pre- and after-market hours,
  alternating grid bands, a dashed grid, and a faint watermark (symbol or
  interval) behind the data.

## Open features from the spec

- **Follow mode (R-SCROLL-5).** While the view is at the right edge, keep
  following new bars as they are appended.
- **Value scales.** Log scale (R-SCALE-5) and a percentage mode for comparing
  several symbols.
- **Sub-panes (R-LAYOUT-4/5)** with their own value axis, instead of
  `HistogramLayer`'s fixed bottom strip.
- **Keyboard navigation (R-INT-5)** (arrows, +/−, Home/End) and accessibility
  semantics.

## Housekeeping

- `pubspec.yaml` still has `description: "A new Flutter package project."`
  and `flutter: ">=1.17.0"`. The code uses null-aware collection elements and
  needs Dart ^3.12, so the Flutter lower bound should match.
- `web: 1.1.2` is pinned exactly. A caret range (`^1.1.2`) avoids clashes
  with apps that also depend on `web`.
- Golden tests (TC-GOLD) would catch visual regressions once themes and
  styles are added.
