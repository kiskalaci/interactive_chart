# Interactive Chart — POC scope notes

This is a proof-of-concept implementation of [requirements.md](requirements.md),
built to validate the core architecture end-to-end rather than to satisfy
every `[M]` requirement. It lives in `lib/interactive_chart/`, is exported
from the package barrel (`uikit.dart`), and has a live example in Widgetbook
under **interactive_chart → InteractiveChart → "Candles + volume + MA"**.

Run it: `flutter build web -t lib/widgetbook/widgetbook.dart` and serve
`build/web/`, or open Widgetbook normally.

## What's implemented

- **Generic data model** (§4.1) — `InteractiveChart<T>` with per-layer
  accessor functions, no concrete datum class. Demo type: `Candle` in
  `demo/candle.dart`.
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
  highlighted index, jump-to-latest.
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

- **No paging (§4.4, all `R-PAGE-*`)**. The chart takes a fixed `List<T>`;
  `didUpdateWidget` handles length changes without resetting pan/zoom
  (R-DATA-9), but there's no load-threshold callback, in-flight guard, or
  exhausted latch.
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
- **No a11y semantics, no RTL handling, no golden/unit test suite** (§12–13).
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

## Verified

Built to web (`flutter build web`) and driven with Playwright against a
live Chromium instance: candles/volume/MA render correctly, pan and
`Ctrl`+wheel anchored zoom both work with no drift, the crosshair shows
value + time badges, and the axis correctly substitutes month/year labels
at calendar boundaries as slotExtent and visible range change. No console
errors during any of the above. `flutter analyze` is clean (only
pre-existing repo-wide info-level lints elsewhere).
