# Interactive Chart — POC scope notes

This is a proof-of-concept implementation of [requirements.md](requirements.md),
built to validate the core architecture end-to-end rather than to satisfy
every `[M]` requirement. It is the `interactive_chart` package (public API in
`lib/interactive_chart.dart`, internals in `lib/src/`) and has a live example
in a separate Widgetbook project, `widgetbook/`, under
**InteractiveChart → "Interactive chart"**.

Run it:

```
cd widgetbook
flutter pub get
flutter run -d chrome
# after adding/changing use cases:
dart run build_runner build -d
```

Tests: `flutter test` from the package root.

## What's implemented

- **Generic data model** (§4.1) — `InteractiveChart<T>` with per-layer
  accessor functions, no concrete datum class. Demo type: `Candle` in
  `lib/candle.dart` (demo-only, not exported from the package barrel).
- **Two independent scale chains** (§5) — ordinal x (index → content px →
  viewport px via `xOf`), linear y with autoscale, padding, and degenerate-
  extent handling.
- **Pan + anchored pinch/wheel zoom** (§6) — a single gesture-start reference
  recomputed fresh each update (no drift on a sustained pinch), pinch to
  zoom, an initial anchor (`left`/`right`, see the deviation note below),
  overscroll into projected slots past the newest datum.
  Panning is two-dimensional on the chart body via drag: a vertical drag
  pans the value extent too, switching autoscale off (a deliberate departure
  from R-SCROLL-6, which specs vertical drag as a no-op while autoscale is
  on — this POC always lets it pan). Vertical panning is otherwise
  drag-only, by design.
  **Wheel/trackpad scroll deviates from R-ZOOM-4**, which specs plain scroll
  as horizontal-pan-only and reserves zoom for a `Ctrl`/`Cmd` modifier: this
  POC is TradingView-style instead — a vertical-dominant scroll zooms x
  (anchored at the pointer, no modifier needed) and a horizontal-dominant
  scroll pans x. A vertical-only wheel still pans when `zoomEnabled` is
  false, for mice with no horizontal scroll axis.
- **Axis-gutter scroll/drag-to-zoom** (R-ZOOM-2, R-SCROLL-6..8) — TradingView-
  style: wheel-scrolling or dragging on the time axis zooms x anchored at the
  pointer; wheel-scrolling or dragging on the value axis zooms y anchored at
  the pointer and switches autoscale off; double-tapping the value axis
  restores autoscale.
- **Optional, self-sizing axes** (§7.1–7.2) — value axis (left/right) and
  time axis (top/bottom), grow-only gutter width.
- **The time-axis tick hierarchy** (§7.3) — this is the flagship behaviour of
  the spec and the POC implements a simplified version end-to-end: weight
  ladder, greedy descending-weight selection, weight-driven formatting (year
  replaces month replaces day at boundaries), a stable superset so panning
  never changes the mark set, quantised slot extent so a pinch doesn't
  flicker it, and projection into the overscroll region with modal-interval
  inference and weekend skipping.
- **Layers** (§8) — `GridLayer`, `LineLayer`, `CandleLayer`, `HistogramLayer`,
  `CrosshairLayer`, each declaring (or opting out of) autoscale extent
  contribution. Each layer builds a real widget tree (`Positioned`/`Stack`
  children, one per visible slot) rather than painting to a `Canvas`, so
  `CandleLayer`, `HistogramLayer`, and `LineLayer` expose per-item
  `onTap`/`onHover` callbacks — not expressible when a whole layer was one
  opaque paint call.
- **Crosshair + readouts** (§9) — hover (desktop) / long-press-drag (touch) /
  tap, value + time badges, projected-slot handling (time only, no value).
- **Controller** (§10) — visible range, slot extent, autoscale toggle,
  highlighted index, jump-to-latest. `jumpToLatest({double? slotExtent})`
  optionally resets zoom to the given slot extent in the same step, which is
  what the demo's "Jump to latest" button does.
- **Prepending keeps the viewport stationary** (R-DATA-10). When
  `didUpdateWidget` sees older data inserted before the previous first datum
  (found by binary-searching the old first timestamp in the new, ascending
  data), it passes the inserted count to `setSlotCount(prepended:)`, which
  shifts the scroll offset by that many slots. The candles on screen stay put
  and `visibleStart` moves past any load threshold, so a paging callback does
  not immediately re-fire. Without this, a chart sitting at the left edge
  kept showing index 0 after every prepend and cascaded through all pages.
  Assumes the data is sorted oldest to newest.
- **Sub-minute bars** (R-TIME-20/21, simplified). Modal-interval inference
  works in seconds (`inferModalIntervalSeconds`), so 10-second or 30-second
  series project their overscroll slots at the right cadence instead of at a
  0-minute interval. Tick labels for weight-10 marks show `hh:mm:ss`.
- **Latest-point marker** — `LineLayer.latestPointBuilder` (`(BuildContext,
  T datum, int index) -> Widget`) draws a caller-supplied widget centred on
  the last datum, e.g. a pulsing "live" dot. It is built only while that
  datum is inside the visible range and has a finite value, and it ignores
  pointer events.
- **Autoscale stays on for horizontal drags.** `panValueByPixels` ignores a
  zero vertical delta, so a purely horizontal pan no longer switches
  autoscale off. Any drag with vertical movement still does (see the
  R-SCROLL-6 deviation above).
- **Browser back/forward-swipe suppression (web only)** — horizontal
  trackpad/wheel scroll while the pointer is over the chart no longer
  triggers the browser's native history-navigation gesture. Implemented as
  a non-passive, capture-phase `wheel` listener on `window` (see
  `src/web/scroll_guard*.dart`) that calls `preventDefault()` only when the
  event's `deltaX != 0` and the pointer is within the chart's current
  on-screen bounds — vertical scroll and anything outside the chart is left
  alone. No-op on non-web platforms via conditional import. Verified by
  dispatching synthetic `WheelEvent`s and checking `window.dispatchEvent`'s
  return value (whether `preventDefault()` fired) both inside and outside
  the chart's bounds.

## What's simplified or out of scope

Trimmed for POC scope — not because they're uninteresting, but because
building all of §1–16 is a multi-milestone effort (see requirements.md §14):

- **Paging (§4.4, `R-PAGE-*`) is demo-side only.** The chart takes a plain
  `List<T>`; `didUpdateWidget` handles appends without resetting pan/zoom
  (R-DATA-9) and prepends without moving the view (R-DATA-10). There is no
  paging API: the widgetbook demo implements the load threshold, in-flight
  guard (R-PAGE-7) and exhausted latch (R-PAGE-8) itself on top of
  `onVisibleRangeChanged`, using a `Future.delayed` in place of a fetch. The
  chart also announces its initial range once after the first frame, so
  unlike R-PAGE-4 a threshold check can fire on the initial load (for
  example when opened at `ChartAnchor.left`). No `failed` state, no
  trailing-direction paging, and no same-frame guarantee beyond the
  prepend compensation above (R-PAGE-12).
- **No render-object tree (R-PERF-1, R-LAYOUT-2)**. Each layer builds a
  `Widget` tree (child-managed style, R-LAYER-1) rather than a `CustomPainter`,
  and the whole widget calls `setState` on every context change
  (pan/zoom/highlight) rather than driving `markNeedsLayout`/`markNeedsPaint`
  directly on render objects. This trades away the painting-layer style's
  perf headroom in exchange for per-item interactivity (`onTap`/`onHover` on
  candles, histogram bars, and line points) and real widget composition —
  costs more per frame than the spec's target architecture (more elements
  than the earlier `CustomPainter` version, which itself already exceeded
  budget) — the old prototype in `lib/chart/` validated the render-object
  approach and would be the basis for a production implementation.
- **Two-pass axis layout is approximated** (R-AXIS-3/4). Axis gutter size is
  carried over from the previous frame's measured labels rather than a true
  dry-layout pass before the viewport is sized. Grow-only sizing (R-AXIS-5)
  is implemented.
- **Tick-hierarchy simplifications**: 6 weight tiers instead of 13 (no
  ISO-week, 12/6/3-hour, or 30/5-minute tiers); `minLabelSpacingPx` is a
  configured constant rather than measured against surviving labels
  (R-TIME-8); interval projection is calendar-day-accurate but not
  calendar-month-accurate (R-TIME-21, e.g. no Jan 31 → Feb 28 stepping).
- **No log value scale** (R-SCALE-5), **no value-axis pan** (a plain vertical
  drag on the value axis always zooms per R-SCROLL-7; a dedicated pan gesture
  is not implemented), **no keyboard navigation** (R-INT-5).
- **No sub-panes** (R-LAYOUT-4/5) — `HistogramLayer` draws in a fixed-fraction
  bottom strip of the single viewport instead of a real stacked pane with its
  own value axis.
- **No a11y semantics, no RTL handling, no golden suite** (§12–13). Only a
  few widget tests exist, in `test/`: prepend compensation, horizontal drag
  keeping autoscale on, `jumpToLatest(slotExtent:)`, and
  `latestPointBuilder`.
- **`GrowthDirection` (R-SCROLL-3) is reworked into `ChartAnchor` and no
  longer mirrors the time axis.** The requirements doc has `left`/`right`
  flip which way time runs on screen (R-TIME-31, R-PLAT-2); this POC instead
  keeps time always left-to-right and uses `ChartAnchor` only to pick the
  *initial* scroll position — `left` opens on the start of the data (an
  intraday chart, empty at market open, filling in as the session
  progresses), `right` opens already scrolled to the newest datum (a
  historic chart). The old name also collided with Flutter's own
  `dart:ui`-level `GrowthDirection` (sliver growth direction), which the
  requirements doc's API sketch didn't anticipate.
- **The scroll-guard's bounds check assumes the Flutter view is full-page**,
  i.e. the Flutter logical-pixel origin coincides with the browser
  viewport's origin. A Flutter view embedded at an offset within a larger
  host page (not the case for this repo's own `web/` demo) would need the
  host element's own offset added in before the containment check.

## Widgetbook demo

The single use case, **"Interactive chart"** (`widgetbook/lib/widgets/`),
combines:

- a Candles / Line toggle (the Line series carries a `PulsingDot` via
  `latestPointBuilder`);
- volume histogram and 20-period moving-average layers, each switched by a
  knob (`Show volume`, `Show MA 20`);
- a live subscription: 10-second candles, one tick per second, updating the
  forming candle in place and appending a new one when the clock enters a
  new bucket (flat candles fill any buckets missed while paused), with
  Pause/Resume;
- pagination: panning near the left edge loads 120 older candles per page,
  up to 10 pages, with a 600 ms simulated fetch and a small bright-green
  spinner in the top-left of the chart area (below the time axis when that
  axis is on top);
- a Light/Dark theme toggle (`MaterialThemeAddon`); chart colours come from
  `ColorPalette` and follow the theme;
- knobs for initial anchor, axis placements, initial slot extent, pan, zoom
  and crosshair.

Known limitation: Widgetbook keys each use case by its URI, which encodes the
knob values, so **changing any knob (or the theme) disposes and recreates the
whole use case**. The generated candles, loaded pages, feed timer, zoom and
scroll all reset. Keeping them would need the demo state held outside the
widget tree (and the chart's viewport saved and restored).

## Verified

Built to web (`flutter build web`) and driven with Playwright against a
live Chromium instance: candles/volume/MA render correctly, pan and
`Ctrl`+wheel anchored zoom both work with no drift, the crosshair shows
value + time badges, and the axis correctly substitutes month/year labels
at calendar boundaries as slotExtent and visible range change. No console
errors during any of the above. `flutter analyze` is clean (only
pre-existing repo-wide info-level lints elsewhere).

That browser verification predates the changes in this revision. Since then,
the package and `widgetbook/` pass `flutter analyze` and the widget tests in
`test/` pass, but the combined widgetbook demo (live feed, pagination,
spinner, pulsing dot, theme toggle) has not been driven in a browser.
