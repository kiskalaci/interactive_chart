# Interactive Chart — Requirements

Status: **Draft**
Owner: Laszlo Kiska
Last updated: 2026-09-10
Package: `uikit` (Flutter)
Target location: `lib/interactive_chart/`

---

## 1. Purpose

Build an interactive, two-dimensional scrolling and zoomable charting widget for
Flutter. The primary use case is financial time series (OHLC candles, volume,
technical indicators), but the core must be **generic**: any series of decimal
values bounded by a min/max extent and keyed by a time point must be
renderable without special-casing.

The widget is composed of a **viewport** (the scrollable/zoomable plotting area)
and a set of **modular content layers** stacked inside it, plus **optional axis
widgets** that reserve space around the viewport.

This document supersedes the exploratory prototype in [lib/chart/](../../chart/).
That prototype validated the render-object approach (see
[chart.dart](../../chart/core/chart.dart), [plot_render_object.dart](../../chart/plot/plot_render_object.dart))
and its concepts are carried forward here as requirements, not as code to keep.

---

## 2. Goals and non-goals

### 2.1 Goals

- One widget that pans and zooms independently on both axes.
- Content layers are composable, independently authored, and lazily rendered.
- Axes are optional and self-sizing; content reclaims their space when absent.
- Data-source agnostic: OHLC, single-value series, band series, discrete markers.
- 60 fps pan/zoom on a mid-tier mobile device with 50k data points loaded.
- Works on mobile (touch), desktop (mouse + trackpad + keyboard) and web.

### 2.2 Non-goals (v1)

- Chart types with no time domain (pie, radar, scatter over two value axes).
- Drawing tools / user-authored annotations that persist (trend lines, fibs).
  The layer API must not preclude them, but they are not built in v1.
- Server-side or headless rendering.
- Built-in indicator maths library. Indicators are supplied as pre-computed
  series by the caller; the library only renders them.
- Animated transitions between datasets.

### 2.3 Priorities

Requirements are tagged **[M]** must-have (v1), **[S]** should-have (v1 if
time permits), **[C]** could-have (post-v1). Every requirement has a stable ID
so tests and PRs can reference it.

---

## 3. Terminology

| Term | Meaning |
| --- | --- |
| **Datum** | One record in a series. Has a time point and one or more decimal values. |
| **Series** | An ordered, time-ascending list of data of one type. |
| **Slot** | The horizontal band allocated to one datum index. Width = *slot extent*. |
| **Slot extent** | Pixel width of one slot at the current zoom level (the prototype's `itemExtent`). |
| **Viewport** | The clipped plotting rectangle, excluding axis gutters. |
| **Layer** | A visual element painted into the viewport (candles, area, grid, crosshair…). |
| **Value axis** | The vertical axis. Domain is decimal values. |
| **Time axis** | The horizontal axis. Domain is time points or slot indices. |
| **Growth direction** | The side new data is appended to: `right` (default) or `left`. |
| **Value extent** | The `(min, max)` decimal pair currently mapped to viewport height. |
| **Autoscale** | Value extent derived automatically from the visible slot range. |
| **Tick mark** | One candidate label position on the time axis, bound to a slot index. |
| **Projected slot** | A slot beyond the end of the data, in the overscroll region. It has a time point but no datum. |
| **Tick weight** | The importance rank of a tick mark, from the coarsest calendar boundary it crosses (year > month > day > hour > minute > second). Modelled as the `TickMarkWeight` enum, each member carrying a numeric `value` (see R-TIME-1). Drives both which marks survive and how they are formatted. |

---

## 4. Data model

### 4.1 Generic datum

- **R-DATA-1 [M]** The library must not require a concrete datum class. The
  chart is parameterised over a caller-owned type `T`, and values are read
  through accessor functions supplied per layer.
- **R-DATA-2 [M]** Each series must expose a time point per index, and one or
  more decimal values per index, via accessors of the shape
  `double Function(T datum)` and `DateTime Function(T datum)`.
- **R-DATA-3 [M]** The following value shapes must be supported out of the box:
  - single value (line, area, indicator),
  - OHLC quadruple (candle, bar),
  - low/high band (range fill, Bollinger channel),
  - a non-negative magnitude (volume, histogram).
- **R-DATA-4 [M]** Series must be indexable in O(1) and their length known
  eagerly. Random access by index is the basis of viewport culling.
- **R-DATA-5 [M]** Series must be documented as required to be sorted ascending
  by time. The library asserts this in debug mode only; it must not sort.

### 4.2 Decimal precision

- **R-DATA-6 [M]** The rendering pipeline operates on `double`. Callers holding
  higher-precision values (e.g. `package:decimal`) keep them in their own datum
  type and convert in the accessor. Rationale: Skia takes `double`; converting
  once per visible datum per frame is cheap, and precision loss below one
  logical pixel is not observable.
- **R-DATA-7 [M]** All *labels* (axis ticks, crosshair readouts, tooltips) must
  be produced by a caller-supplied formatter that receives the original datum
  or the original decimal value — never a pre-rounded `double`. This is how
  precision-sensitive callers keep exact display values.
- **R-DATA-8 [M]** `NaN`, `infinity`, and null values must be treated as gaps:
  skipped in path construction, excluded from extent computation, and never
  painted. A gap must break a line/area path rather than interpolate across it.

### 4.3 Mutation

- **R-DATA-9 [M]** Appending data at the growth edge must not reset the current
  pan/zoom, and must not rebuild layers that did not change.
- **R-DATA-10 [M]** Prepending data (loading older history) must keep the
  currently visible data visually stationary — the scroll offset is adjusted by
  the number of prepended slots so the user does not see a jump.
- **R-DATA-11 [M]** The chart must notify the caller when the viewport
  approaches either end of the loaded range so more data can be paged in.
  Specified in §4.4.
- **R-DATA-12 [C]** In-place update of the last datum (a live ticking candle)
  must repaint only the affected layers.

---

### 4.4 Paging and end-of-data notification

A chart is a window onto a range the caller usually cannot hold in memory in
full. The widget must tell the caller when the user is about to run out of
data, in time to fetch more before the edge is visible.

#### 4.4.1 Trigger

- **R-PAGE-1 [M]** A paging callback fires when the visible slot range comes
  within `loadThresholdSlots` of either end of the loaded range. Default: one
  viewport's worth of slots, so a page is requested roughly one screen before
  the user can see the edge.
- **R-PAGE-2 [M]** The threshold is expressed in **slots**, not pixels, so it
  is zoom-invariant: zoomed out, one screen is more data, and the trigger
  correctly fires earlier in absolute terms.
- **R-PAGE-3 [M]** The check is O(1), derived from the visible index range
  already computed each layout, and coalesced to at most one evaluation per
  frame.
- **R-PAGE-4 [M]** The callback does **not** fire for the initial load. The
  caller supplies the first page; the chart pages outward from it. A chart
  constructed with empty data renders an empty state and requests nothing.

#### 4.4.2 Contract

- **R-PAGE-5 [M]** The callback is asynchronous and returns a result, so the
  chart knows both when the load finished and whether anything remains:

  ```dart
  typedef PageLoader = Future<PageOutcome> Function(PageRequest request);

  class PageRequest {
    final PageDirection direction;   // .older | .newer
    final DateTime anchorTime;       // time point at the edge being extended
    final int anchorIndex;           // its current slot index
    final int suggestedCount;        // slots needed to clear the threshold
  }

  enum PageOutcome { loaded, exhausted, failed }
  ```

- **R-PAGE-6 [M]** `suggestedCount` is a hint sized to clear the threshold at
  the current zoom. Callers may return more or fewer data; returning fewer is
  handled by R-PAGE-9.
- **R-PAGE-7 [M]** **At most one in-flight request per direction.** A second
  request in the same direction must never be issued while one is pending —
  the single most likely bug in a naive implementation, where a fling fires the
  callback on every frame it spends inside the trigger zone.
- **R-PAGE-8 [M]** `exhausted` **latches**: that direction is never requested
  again. Cleared only by an explicit `controller.resetPaging(direction)` or by
  replacing the dataset. Without a latch, a chart scrolled to the true start of
  history re-requests on every frame forever.
- **R-PAGE-9 [M]** If a completed `loaded` still leaves the viewport inside the
  trigger zone, the chart may immediately request again — necessary when the
  source returns small pages — but consecutive automatic requests without
  intervening user interaction are capped (`maxConsecutivePageLoads`,
  default 3). Hitting the cap pauses paging in that direction until the next
  gesture, and is reported in debug builds.
- **R-PAGE-10 [M]** `failed` does not latch and does not retry automatically.
  It surfaces through the paging state (R-PAGE-15) so the caller can show a
  retry affordance and call `controller.retryPaging(direction)`. Built-in
  backoff is deliberately out of scope — retry policy belongs to the caller's
  data layer.
- **R-PAGE-11 [M]** In-flight results must be discarded if the widget is
  disposed or the dataset is replaced wholesale before they arrive. A stale
  prepend must never be applied to a different dataset.

#### 4.4.3 Applying a page

- **R-PAGE-12 [M]** Prepending applies the data change and the compensating
  scroll-offset adjustment (R-DATA-10) **in the same frame**. No intermediate
  frame may show the content shifted.
- **R-PAGE-13 [M]** A page arriving mid-fling must not teleport or halt the
  fling. The content extent grows and the existing scroll simulation continues
  against the new extent.
- **R-PAGE-14 [M]** While a request is pending, the leading edge stays clamped
  per R-SCROLL-4. An optional loading affordance may occupy a configurable
  leading gutter; it must not resize the viewport (no layout thrash on every
  page).
- **R-PAGE-15 [S]** Paging state — `idle | loading | exhausted | failed`, per
  direction — is exposed on the controller and to an optional builder, so the
  caller can render a spinner or a retry button in the gutter.
- **R-PAGE-16 [S]** Trailing-direction paging (`newer`) supports gap-fill after
  a dropped connection, using the same machinery.

#### 4.4.4 Interaction with the rest of the chart

Prepending renumbers every slot index, which touches three caches:

- **R-PAGE-17 [M]** Tick weights are **not** recomputed wholesale. Only the
  newly prepended slots, plus the previously-first datum — whose R-TIME-2
  "highest weight" was an artefact of having no predecessor and must be
  re-derived against its new one — are recalculated. O(page), not O(n).
- **R-PAGE-18 [M]** Tick marks are stored against a stable base offset (or
  datum identity) so a prepend shifts the mark set by a constant rather than
  rewriting every entry. Marks must not visibly change as a result of a
  prepend outside the visible range.
- **R-PAGE-19 [M]** A prepend outside the visible range must not change the
  value extent — autoscale is computed over the visible range only (R-SCALE-8),
  so loading history must never rescale the chart under the user.

## 5. Coordinate system and scales

- **R-SCALE-1 [M]** Two independent scale chains:
  - **x**: slot index (or time) → content-space pixels → viewport pixels,
  - **y**: decimal value → viewport pixels.
- **R-SCALE-2 [M]** The x chain is two-stage, as in the prototype
  ([chart_context.dart](../../chart/core/chart_context.dart)): a *content scale*
  maps index → absolute content pixels, and a *viewport scale* maps content
  pixels → on-screen pixels given the current scroll offset. Layers must use a
  single `xOf(index)` helper and never compose the two themselves.
- **R-SCALE-3 [M]** Two x-domain modes:
  - **ordinal** (default): slot index is the domain; every datum gets equal
    width. Non-trading gaps (weekends, halts) collapse. This is the expected
    behaviour for OHLC.
  - **time**: real timestamps are the domain; gaps are proportional to elapsed
    time. Required for irregular sampling and for non-financial series.
- **R-SCALE-4 [M]** The y scale is linear in v1.
- **R-SCALE-5 [S]** A logarithmic y scale must be selectable per chart. Layers
  must not assume linearity — they must go through the scale for every point.
- **R-SCALE-6 [M]** Both scales must expose an inverse mapping (pixel → domain).
  Hit-testing, crosshair snapping, and drag-to-pan depend on it.
- **R-SCALE-7 [M]** The value extent has three sources, in precedence order:
  1. an explicit extent supplied by the caller,
  2. a manual extent produced by the user dragging/zooming the value axis,
  3. autoscale over the visible slot range (default).
- **R-SCALE-8 [M]** Autoscale must consider every layer that opts into extent
  contribution, take the union of their extents, and apply configurable padding
  (fractional, e.g. 5% top and bottom) so extremes are not flush to the edge.
- **R-SCALE-9 [M]** A layer may opt out of extent contribution (e.g. a volume
  histogram drawn in its own sub-region must not compress the price scale).
- **R-SCALE-10 [M]** Autoscale must be recomputed only when the visible index
  range or the underlying data changes — not on every frame of a pan that stays
  within the same range.
- **R-SCALE-11 [M]** Degenerate extents (min == max, or a single visible datum)
  must produce a valid, non-zero-height scale rather than a division by zero.

---

## 6. Scrolling and zooming

### 6.1 Horizontal (time)

- **R-SCROLL-1 [M]** Horizontal panning is driven by a Flutter `ViewportOffset`
  so the widget participates in the standard scrolling system: physics, fling,
  overscroll, `Scrollable` semantics, and scroll-position restoration.
- **R-SCROLL-2 [M]** Content extent is `slotCount × slotExtent`. Changing zoom
  changes `slotExtent` and therefore the content extent; the scroll offset must
  be re-derived so the anchor point stays put (see R-ZOOM-3).
- **R-SCROLL-3 [M]** **Growth direction** is configurable as `right` (default,
  time increases rightwards, newest at the right edge) or `left` (time increases
  leftwards, used when browsing historic data backwards). Switching it mirrors
  the viewport scale's domain without re-laying-out layers.
- **R-SCROLL-4 [M]** Overscroll past the newest datum must be allowed up to a
  configurable amount (default: half the viewport width) so the newest candle is
  not stuck against the axis gutter. This region is filled with **projected
  slots** that carry time points but no data (§7.3.5). Overscroll past the
  oldest datum is clamped by default.
- **R-SCROLL-5 [S]** A "follow" mode: while the viewport is at the growth edge,
  appending data keeps the viewport pinned to the edge. Panning away from the
  edge disengages follow; a "jump to latest" call re-engages it.

### 6.2 Vertical (value)

- **R-SCROLL-6 [M]** Vertical panning is only meaningful when autoscale is off.
  Dragging vertically inside the viewport with autoscale on must be a no-op for
  the scale (it may still be consumed by an enclosing scrollable).
- **R-SCROLL-7 [M]** Dragging on the **value axis gutter** adjusts the value
  extent (drag = pan, vertical drag with modifier or pinch = zoom) and
  implicitly switches the chart out of autoscale into manual extent.
- **R-SCROLL-8 [M]** A double-tap / double-click on the value axis restores
  autoscale.

### 6.3 Zoom

- **R-ZOOM-1 [M]** Horizontal zoom changes `slotExtent` between a configurable
  `minSlotExtent` and `maxSlotExtent` (defaults: 1.0 and 64.0 logical pixels).
- **R-ZOOM-2 [M]** Zoom input sources: pinch (touch), `Ctrl`/`Cmd` + wheel and
  trackpad pinch (desktop/web), horizontal drag on the **time axis gutter**,
  and `+`/`-` keys when focused.
- **R-ZOOM-3 [M]** Zoom is anchored: the domain value under the gesture's focal
  point must remain under the focal point after the zoom. Anchoring must be
  exact to within one logical pixel across a sustained pinch, with no drift.
- **R-ZOOM-4 [M]** Plain wheel / two-finger scroll pans horizontally; it must
  not zoom. Shift + wheel is an alias for horizontal pan on platforms that emit
  only vertical wheel deltas.
- **R-ZOOM-5 [S]** Vertical zoom via pinch is independent of horizontal zoom
  when autoscale is off (true 2D zoom). With autoscale on, vertical pinch is
  ignored.
- **R-ZOOM-6 [M]** Zoom state must be programmatically readable and settable
  through the controller (R-API-6), including "fit visible range" and
  "reset to defaults" operations.
- **R-ZOOM-7 [M]** Gesture arbitration must be explicit and documented: a chart
  placed inside a vertically scrolling page must claim horizontal drags and
  pinches, and yield vertical drags to the page when vertical interaction is
  disabled.

---

## 7. Composition and layout

### 7.1 Structure

```
InteractiveChart
├── TimeAxis      (optional; top or bottom)
├── ValueAxis     (optional; left or right)
└── Viewport      (clipped, scrollable, zoomable)
    ├── GridLayer
    ├── CandleLayer / OhlcBarLayer / AreaLayer / LineLayer / HistogramLayer
    ├── IndicatorLayer…            (n of them, painted in order)
    └── CrosshairLayer             (topmost)
```

- **R-LAYOUT-1 [M]** Layers are supplied as an ordered child list. Paint order
  equals list order; the last child paints on top.
- **R-LAYOUT-2 [M]** Every layer receives the shared chart context (scales,
  visible index range, slot extent, growth direction) through the render tree,
  not through `InheritedWidget` rebuilds. Panning must not trigger a widget
  rebuild — only a relayout/repaint of the render objects.
- **R-LAYOUT-3 [M]** Adding or removing a layer must not reset scroll or zoom.

### 7.2 Optional axes

- **R-AXIS-1 [M]** Both axes are optional and independent. Valid combinations:
  none, time only, value only, both.
- **R-AXIS-2 [M]** When an axis is absent, the viewport expands to occupy its
  space. No reserved gutter, no placeholder padding.
- **R-AXIS-3 [M]** Axes are **self-sizing**. The value axis measures the widest
  formatted tick label at the current extent and reports that width plus
  padding; the time axis measures the tallest formatted label and reports that
  height plus padding. Both use a dry-layout pass before the viewport is laid
  out, exactly as the prototype does in
  [chart.dart:207-229](../../chart/core/chart.dart#L207-L229).
- **R-AXIS-4 [M]** Layout is a two-pass algorithm and must be documented as such:
  1. dry-layout each present axis against loosened constraints to learn its
     gutter size,
  2. subtract gutters from the incoming constraints, then lay out the viewport
     and the axes at their final sizes.
- **R-AXIS-5 [M]** Axis gutter size must be stable across a pan. If the widest
  tick label changes as data scrolls by (e.g. `9.5` → `10.5`), the gutter must
  not jitter frame to frame. Mitigation: measure against a caller-supplied
  sample/measurement string, or quantise the measured width, or (default) only
  grow the gutter within a session and never shrink it during an active gesture.
- **R-AXIS-6 [M]** **Value axis placement** is `left` or `right`, defaulting to
  the side the data grows toward (`right` growth → right-hand value axis), which
  keeps the latest value next to its label. The caller may override.
- **R-AXIS-7 [M]** **Time axis placement** is `bottom` (default) or `top`.
- **R-AXIS-8 [M]** Value-axis tick generation must produce human-readable steps
  (1/2/2.5/5/10 progression) and must adapt tick count to the available height
  so labels never collide. Time-axis tick generation is governed by §7.3.
- **R-AXIS-9 [M]** Tick labels are produced by a caller-supplied formatter
  (see R-DATA-7). Defaults are provided for `double` and `DateTime`.
- **R-AXIS-10 [S]** The value axis may show a pinned "current value" badge at
  the last datum's y position, and the time axis a pinned badge under the
  crosshair.
- **R-AXIS-11 [C]** Two value axes simultaneously (left and right) with
  independent extents, for overlaying series of different magnitudes.

### 7.3 Time axis tick hierarchy

The time axis must behave like TradingView's: when not every time point can be
labelled, only the *most significant* ones survive, ranked by the coarsest
calendar boundary they cross. Zooming in admits progressively finer marks.

#### 7.3.1 Weights

- **R-TIME-1 [M]** Every datum carries a **tick weight**, derived once from the
  coarsest calendar boundary crossed between the previous datum's time point
  and its own. The default ladder (higher wins):

  | Weight | Assigned when, relative to the previous datum | Default label |
  | ---: | --- | --- |
  | 70 | the year changes | `2025` |
  | 60 | the month changes | `Feb` |
  | 55 | the ISO week changes *(optional, off by default)* | `12` |
  | 50 | the day changes | `12` |
  | 33 | a 12-hour boundary is crossed | `12:00` |
  | 32 | a 6-hour boundary is crossed | `18:00` |
  | 31 | a 3-hour boundary is crossed | `21:00` |
  | 30 | the hour changes | `14:00` |
  | 22 | a 30-minute boundary is crossed | `14:30` |
  | 21 | a 5-minute boundary is crossed | `14:35` |
  | 20 | the minute changes | `14:36` |
  | 10 | the second changes | `14:36:05` |
  | 0 | anything finer | `14:36:05.250` |

  The ladder is exposed as the `TickMarkWeight` enum rather than as bare
  integers: each member carries its numeric `value` (a `double`) and the enum
  is `Comparable` with `>`, `>=`, `<`, `<=`. The tiers and values match
  TradingView's (`second` 10, `minute1` 20, `minute5` 21, `minute30` 22,
  `hour1` 30, `hour3` 31, `hour6` 32, `hour12` 33, `day` 50, `month` 60,
  `year` 70). Formatters and styles key off the enum, never off a magic
  number.

- **R-TIME-2 [M]** The first datum in the dataset takes the highest weight, so
  the range always opens with maximum context.
- **R-TIME-3 [M]** Weight is a property of a **datum relative to its
  predecessor in the dataset**, not of an absolute calendar grid. With the
  ordinal domain (R-SCALE-3) the first *trading* day of a month carries the
  month weight even though the 1st is absent from the data. This is the
  behaviour that makes the axis correct across weekends and holidays, and it is
  the reason marks bind to indices rather than to timestamps.
- **R-TIME-4 [M]** Boundary detection runs in a configurable timezone
  (default: the device's local zone). "The month changed" is timezone-dependent,
  and a chart of an exchange's session must be able to pin to that exchange's
  zone. Changing the timezone recomputes all weights.
- **R-TIME-5 [M]** Weights are computed once at data load, O(n), and updated
  incrementally on append or prepend in O(1) amortised per datum. They must
  never be recomputed during pan or zoom.
- **R-TIME-6 [S]** The caller may supply its own weight function, for domains
  where the calendar ladder is not the right hierarchy (e.g. a series where
  session open matters more than midnight).

#### 7.3.2 Selection algorithm

- **R-TIME-7 [M]** Given the current slot extent, the axis selects marks
  greedily from the highest weight downwards:
  1. compute the minimum spacing in indices,
     `minIndexGap = ceil(minLabelSpacingPx / slotExtent)`;
  2. walk weight levels from highest to lowest;
  3. within a level, accept a mark only if it is at least `minIndexGap` indices
     from every already-accepted mark, on both sides;
  4. stop when a level contributes no new marks.

  A mark accepted at a coarser level is never displaced by a finer one.
- **R-TIME-8 [M]** `minLabelSpacingPx` is derived from **measured** label
  widths at the current text style and scale factor, plus a configurable
  padding — not a hard-coded constant. It must account for the widest label the
  surviving levels can produce, so `2025` and `14:36:05` do not collide.
- **R-TIME-9 [M]** Marks are built over the **whole dataset** (or a superset of
  the visible range extended by the cache extent), then clipped to the viewport.
  Building over the exact visible window would let marks appear and disappear as
  their neighbours scroll out of view; building over a stable superset means
  panning at fixed zoom never changes which marks exist — they only translate.
- **R-TIME-10 [M]** The selected mark set is a pure function of
  `(dataset, slotExtent, minLabelSpacingPx, timezone)`. It must be cached and
  recomputed only when one of those changes — not per frame, and not on pan.
- **R-TIME-11 [M]** To avoid churn during a continuous pinch, `slotExtent` is
  quantised for the purpose of mark selection (e.g. to a small number of steps
  per doubling). Labels may translate continuously while the *set* changes only
  at quantised thresholds.

#### 7.3.3 Rendering

- **R-TIME-12 [M]** A mark's label format is chosen by its **weight**, not by
  the zoom level: a month-weight mark renders `Feb` whatever the zoom, and a
  year-weight mark renders `2025`. This is what produces TradingView's
  characteristic mixed axis — `Nov  Dec  2025  Feb  Mar` — where the year label
  replaces January because January *is* the year boundary.
- **R-TIME-13 [M]** The weight→formatter mapping is caller-overridable per
  weight, with locale-aware defaults.
- **R-TIME-14 [S]** Higher-weight marks may be emphasised (heavier font weight,
  higher-contrast colour, longer tick line), configurable per weight, defaulting
  to a subtle two-tier treatment: boundary marks (year, month) emphasised,
  everything else normal.
- **R-TIME-15 [M]** A mark whose label would be clipped by the viewport edge or
  by an axis gutter is dropped rather than truncated or overlapped.
- **R-TIME-16 [M]** The crosshair's time badge (R-INT-2) always shows the full
  precision of the datum under the cursor, independent of the axis's chosen
  weight — the hierarchy governs the axis only.

#### 7.3.4 Worked example (acceptance criterion)

Dataset: daily bars, 2024-01-01 → 2026-01-01 (~520 trading days). Viewport
900 px wide. This table is a **test fixture**, not an illustration —
R-TEST-6 asserts it.

| Zoom | Slot extent | Visible slots | `minIndexGap` | Surviving weights | Axis reads |
| --- | ---: | ---: | ---: | --- | --- |
| Fully out | ~1.7 px | ~520 (all) | ~24 | 70, 60 (partially) | `2024  Apr  Jul  Oct  2025  Apr  Jul  Oct  2026` |
| Medium | ~8 px | ~110 | ~5 | 70, 60 | `2025  Feb  Mar  Apr  May` |
| In | ~30 px | ~30 | ~2 | 70, 60, 50 | `Mar  3  10  17  24  Apr  7` |
| Fully in | ~64 px | ~14 | 1 | 70, 60, 50 | `10  11  12  13  Apr  2  3  4` |

Note in rows 3 and 4 that the month name appears *in place of* the day number
at the month boundary, and the year would likewise replace the month at a year
boundary. That substitution — never both labels stacked at one position — is
the core acceptance behaviour.

#### 7.3.5 Projected time points beyond the data

When the user scrolls into the overscroll region past the newest datum
(R-SCROLL-4), the time axis must keep labelling — showing the dates that
*would* follow, exactly as TradingView continues its axis into empty space to
the right of the last bar. Without this, the axis simply stops mid-gutter and
the user loses their bearings at precisely the moment they are looking at the
most recent, most important data.

- **R-TIME-18 [M]** The slot space extends beyond the data by
  `maxProjectedSlots = ceil(maxOverscrollPx / minSlotExtent)`. Slots in
  `[slotCount, slotCount + maxProjectedSlots)` are **projected**: they have a
  time point, a tick weight, and an x position, but no datum.
- **R-TIME-19 [M]** Projected time points are produced by a **projector**,
  `DateTime Function(int slotsAfterLast)`, resolved in this precedence:
  1. a projector supplied by the caller;
  2. an explicit `interval` supplied by the caller, stepped calendar-aware;
  3. an interval **inferred** from the data.
- **R-TIME-20 [M]** Interval inference takes the *modal* delta between
  consecutive time points over the last N data (default N = 100), not the mean
  and not the last delta. Rationale: gaps (weekends, halts, missing bars) make
  the mean wrong and make the last delta unstable — after a weekend the last
  delta on a daily series is 3 days, which would project Tue, Fri, Mon…
- **R-TIME-21 [M]** Stepping must be **calendar-aware**, not fixed-duration.
  A monthly series projects by adding one month (Jan 31 → Feb 28), not 30 days;
  a daily series adds one day across DST transitions rather than 24 hours.
- **R-TIME-22 [M]** The default projector for intervals of a day or coarser
  skips weekends, since the primary use case is exchange data. This is
  configurable (`SessionCalendar`), and callers with a real trading calendar —
  holidays, half days — supply their own projector under R-TIME-19. Naive
  weekend-skipping is a *default*, never an assumption baked into the core.
- **R-TIME-23 [M]** Projected slots receive tick weights by the same rule as
  real data (R-TIME-1: coarsest boundary crossed relative to the previous
  slot), and enter the **same** greedy selection as real marks (R-TIME-7).
  There is one ladder and one selection pass — projected marks are not a
  separate rendering path. A month or year boundary falling in projected space
  is emphasised exactly as one falling in real data.
- **R-TIME-24 [M]** Mark building (R-TIME-9) covers
  `[0, slotCount + maxProjectedSlots)`, so scrolling into the void does not
  change the mark set — projected marks translate like any other.
- **R-TIME-25 [M]** Projected marks render identically to real ones by default.
  A `projectedLabelStyle` override may dim them; there must be no *structural*
  difference (no different tick length, no separator) unless configured.
- **R-TIME-26 [M]** The grid layer must draw its vertical lines at projected
  marks too, so the grid does not stop dead at the last bar.

**Projected slots are not data.** The following are hard invariants:

- **R-TIME-27 [M]** Layers are never asked to paint a projected slot. The
  visible index range handed to layers is clamped to `[0, slotCount)`; the
  projected range is delivered separately and only the time axis, the grid, and
  the crosshair consume it.
- **R-TIME-28 [M]** Projected slots never contribute to autoscale (R-SCALE-8).
  Scrolling into empty space must not change the value extent.
- **R-TIME-29 [M]** The crosshair over a projected slot shows the projected
  **time** badge only — no value readout, no tooltip row for a datum that does
  not exist. `onIndexHighlighted` reports `null`; a separate
  `onProjectedTimeHighlighted(DateTime)` carries the time for callers that want
  it. Hit-testing must never return a projected index where a datum index is
  expected.
- **R-TIME-30 [M]** When real data arrives for a slot that was projected, the
  slot becomes real. If the arriving timestamp matches the projection, the mark
  set must be unchanged — no visual jump at the moment of append, which is the
  common case on a live feed. If it does not match, marks from that index
  onward are rebuilt. The one allowed exception is the mark at the very edge
  of the window: appending a slot can bring a heavier tier (e.g. a 5-minute
  mark) into range, and that mark outranks, and so displaces, a lighter
  neighbour within `minIndexGap` of it.
- **R-TIME-31 [S]** Under growth direction `left` (R-SCROLL-3) the same
  projection applies at the mirrored edge. Projection is only ever applied at
  the **growth** edge: the opposite edge is unloaded history, where fabricating
  dates would contradict data that R-DATA-11 may still page in.
- **R-TIME-32 [C]** `projectionEnabled: false` disables the whole mechanism;
  the axis then simply ends at the last datum.

*Example.* Daily bars ending Fri 2026-01-30, scrolled fully to the newest data
with ~40 px slots and half a viewport of overscroll. The axis reads
`26  27  28  29  30 │ Feb  3  4  5  6` — the projected slots skip the weekend,
and `Feb` appears at Mon 2026-02-02 because that projected slot crosses a month
boundary and so wins the month weight, replacing its day number.

#### 7.3.6 Time-domain mode

- **R-TIME-17 [M]** Under the `time` x-domain (R-SCALE-3) the same weight ladder
  and the same greedy descending selection apply, but candidate positions are
  real calendar boundaries rather than data indices, and the minimum-gap test is
  in pixels rather than indices. Layers and formatters are unaffected; only the
  candidate generation differs.

### 7.4 Sub-panes

- **R-LAYOUT-4 [S]** A chart may be split into stacked panes (price on top,
  volume/RSI/MACD below) that share one time axis and one horizontal scroll
  offset, each with its own value extent and optional value axis.
- **R-LAYOUT-5 [S]** Pane heights are proportional by default and resizable by
  dragging the divider.

---

## 8. Content layers

- **R-LAYER-1 [M]** A layer is a render object with access to the chart context.
  Two authoring styles must be supported:
  - **painting layers** — paint directly to the canvas over the visible index
    range (area, line, candles as paths, grid, crosshair);
  - **child-managed layers** — build one child widget per visible slot, with
    lazy creation/recycling as the viewport moves, as in
    [plot_render_object.dart](../../chart/plot/plot_render_object.dart). Needed
    when a per-slot element must be a real widget (interactive marker, badge).
- **R-LAYER-2 [M]** Layers must only touch data in the visible index range
  (plus a configurable cache extent of leading/trailing slots so paths and
  moving averages are continuous at the edges).
- **R-LAYER-3 [M]** v1 ships: `GridLayer`, `LineLayer`, `AreaLayer`,
  `CandleLayer`, `OhlcBarLayer`, `HistogramLayer` (volume), `CrosshairLayer`,
  `MarkerLayer`.
- **R-LAYER-4 [M]** `CandleLayer` requirements: body from open/close, wick from
  low/high, up/down/doji colours, configurable body-to-slot width ratio and
  minimum body width, hollow and filled variants, correct rendering when
  `slotExtent` < 2 px (degrade to a 1 px line at the correct colour).
- **R-LAYER-5 [M]** `AreaLayer`/`LineLayer` requirements: gradient or solid
  fill, configurable stroke, gap handling per R-DATA-8, optional stepped and
  smoothed (monotone cubic) interpolation.
- **R-LAYER-6 [M]** An indicator is not a distinct type — it is a `LineLayer`,
  `AreaLayer`, or `HistogramLayer` bound to a caller-computed series. The docs
  must show MA, Bollinger, and MACD built this way, with no library-side maths.
- **R-LAYER-7 [M]** Every layer must declare whether it contributes to
  autoscale (R-SCALE-9) and what its value extent is over a given index range.
- **R-LAYER-8 [M]** Layer styling comes from the caller, with defaults resolved
  from the `uikit` theme (see [lib/theme/](../../theme/)); no hard-coded colours.
- **R-LAYER-9 [C]** Public documentation for authoring a third-party layer,
  with a worked example.

---

## 9. Interaction and readout

- **R-INT-1 [M]** A crosshair follows the pointer on desktop and a long-press
  drag on touch, snapping horizontally to the nearest slot centre and reading
  the exact value at that slot.
- **R-INT-2 [M]** The crosshair must project labelled badges onto whichever
  axes are present, and must degrade gracefully when they are absent.
- **R-INT-3 [M]** A caller-supplied builder renders the tooltip/legend content
  for the highlighted index; the library positions it inside the viewport bounds
  and flips it to avoid the pointer and the viewport edges.
- **R-INT-4 [M]** Callbacks: `onIndexHighlighted(int?)`, `onSlotTapped(int)`,
  `onVisibleRangeChanged(start, end)`, `onExtentChanged(min, max)`. All must be
  debounced/coalesced to at most one call per frame.
- **R-INT-5 [S]** Keyboard: arrow keys move the highlighted slot, `Home`/`End`
  jump to the oldest/newest datum, `+`/`-` zoom, `Esc` clears the highlight.
- **R-INT-6 [M]** All interactions are individually disableable
  (`panEnabled`, `zoomEnabled`, `crosshairEnabled`, `valueAxisDragEnabled`) so
  the widget can be embedded read-only, e.g. as a sparkline.
- **R-INT-7 [C]** Range selection by drag, reporting the selected time span.

---

## 10. Public API sketch

Illustrative, not binding — it exists to pin down the shape the requirements
imply.

```dart
InteractiveChart<Candle>(
  controller: chartController,        // R-API-6
  data: candles,                      // List<Candle>, time-ascending
  timeOf: (c) => c.openTime,
  growthDirection: GrowthDirection.right,
  xDomain: XDomain.ordinal,           // or XDomain.time
  valueScale: ValueScale.linear,      // or .log
  valueExtent: ValueExtent.autoscale(padding: 0.05),
  timeAxis: TimeAxis(
    placement: TimeAxisPlacement.bottom,
    timezone: exchangeZone,           // R-TIME-4
    // weight -> formatter; defaults are locale-aware (R-TIME-13)
    formatters: {
      TickWeight.year:  (t) => DateFormat.y().format(t),
      TickWeight.month: (t) => DateFormat.MMM().format(t),
      TickWeight.day:   (t) => DateFormat.d().format(t),
    },
    emphasize: {TickWeight.year, TickWeight.month},   // R-TIME-14
    // labels continue past the last datum into the overscroll region (§7.3.5)
    projection: TimeProjection.infer(calendar: SessionCalendar.weekdays),
    // …or TimeProjection.of((slotsAfterLast) => myCalendar.next(slotsAfterLast))
  ),                                  // nullable — omit to reclaim the gutter
  valueAxis: ValueAxis(
    placement: ValueAxisPlacement.right,
    formatter: (v) => v.toStringAsFixed(2),
  ),                                  // nullable
  layers: [
    GridLayer(),
    HistogramLayer(valueOf: (c) => c.volume, contributesToExtent: false),
    CandleLayer(
      openOf:  (c) => c.open,
      highOf:  (c) => c.high,
      lowOf:   (c) => c.low,
      closeOf: (c) => c.close,
    ),
    LineLayer(valueOf: (c) => c.ma20),
    CrosshairLayer(tooltipBuilder: (context, index) => …),
  ],
  onVisibleRangeChanged: (start, end) => …,

  // §4.4 — fires ~one screen before the edge is visible; at most one
  // in-flight request per direction; `exhausted` latches.
  loadThresholdSlots: LoadThreshold.oneViewport,
  onLoadPage: (request) async {
    final page = await api.candles(
      before: request.anchorTime,
      count: request.suggestedCount,
    );
    if (page.isEmpty) return PageOutcome.exhausted;
    setState(() => candles.insertAll(0, page));
    return PageOutcome.loaded;
  },
)
```

- **R-API-1 [M]** The widget is generic over the datum type; no `dynamic` in
  the public surface.
- **R-API-2 [M]** Every configuration object is `const`-constructible and
  implements value equality, so rebuilds with identical config are cheap no-ops.
- **R-API-3 [M]** Null means "absent", not "default": a null axis is no axis.
- **R-API-4 [M]** The widget is usable with zero optional arguments beyond data,
  accessors, and one layer.
- **R-API-5 [M]** No mandatory dependency on `Scrollable` in the caller's tree —
  the widget owns its scroll machinery internally.
- **R-API-6 [M]** An optional `InteractiveChartController` exposes and mutates
  visible range, zoom level, value extent, autoscale on/off, highlighted index,
  and "jump to latest"; it notifies listeners on change and is disposable.
- **R-API-7 [S]** Exported through a single barrel file, mirroring the
  package's existing export style in [uikit.dart](../../uikit.dart).

---

## 11. Performance

- **R-PERF-1 [M]** Pan and zoom must not rebuild the widget tree. Scroll offset
  changes drive `markNeedsLayout`/`markNeedsPaint` on render objects only.
- **R-PERF-2 [M]** Per-frame work must be O(visible slots), not O(dataset).
- **R-PERF-3 [M]** Budget: ≤ 8 ms per frame for layout + paint with 60 visible
  candles, 3 indicator lines, grid, and crosshair, on a 2020-class mobile
  device, with 50k data loaded.
- **R-PERF-4 [M]** The viewport is a repaint boundary; the crosshair layer is
  its own repaint boundary so pointer movement does not repaint the candles.
- **R-PERF-5 [M]** No allocation of `Paint`, `Path`, or `TextPainter` objects
  per datum per frame. Paints are cached on the layer; text painters are pooled
  or cached per label string.
- **R-PERF-6 [M]** Autoscale extent computation must be cached and invalidated
  only per R-SCALE-10.
- **R-PERF-7 [S]** Benchmarks live in the repo and run in CI, failing on
  regression beyond a threshold.

---

## 12. Theming, accessibility, platform

- **R-THEME-1 [M]** All colours and text styles resolve from the `uikit` theme
  by default, with per-chart and per-layer overrides.
- **R-THEME-2 [M]** Light and dark themes both legible; up/down colours must be
  configurable for red/green colour-vision deficiency.
- **R-A11Y-1 [M]** The chart exposes a semantics node with a caller-supplied
  label and the current visible time range and value extent.
- **R-A11Y-2 [S]** The highlighted datum is announced to screen readers when it
  changes via keyboard navigation.
- **R-A11Y-3 [M]** Respect `MediaQuery.disableAnimations` and text scaling —
  axis gutters must grow with the text scale factor.
- **R-PLAT-1 [M]** Supported: iOS, Android, macOS, Windows, Linux, Web (CanvasKit
  and the Skwasm/HTML renderer where Flutter supports it).
- **R-PLAT-2 [M]** RTL locales: the value axis `left`/`right` placement is
  absolute, not directional, and must not flip with `Directionality`. Time
  direction is governed solely by growth direction.

---

## 13. Testing

- **R-TEST-1 [M]** Unit tests for scales, inverse mapping, tick generation,
  autoscale (including degenerate extents), and index-range culling.
- **R-TEST-2 [M]** Widget tests for the two-pass axis layout across all four
  present/absent axis combinations, asserting the viewport reclaims gutter space.
- **R-TEST-3 [M]** Gesture tests: anchored zoom holds its focal point; pan
  clamping and overscroll; prepend keeps the view stationary (R-DATA-10).
- **R-TEST-8 [M]** Paging: a fling that dwells in the trigger zone issues
  exactly one request (R-PAGE-7); `exhausted` is never re-requested
  (R-PAGE-8); small pages that fail to clear the threshold stop at the cap
  (R-PAGE-9); a result arriving after dispose or dataset replacement is
  discarded (R-PAGE-11); prepend during an active fling neither teleports nor
  halts it (R-PAGE-13); a prepend outside the visible range leaves both the
  value extent and the rendered tick marks unchanged (R-PAGE-18/19).
- **R-TEST-4 [M]** Time axis hierarchy: the §7.3.4 table is encoded as a
  fixture and asserted at each zoom level; weight assignment is asserted across
  weekends, month ends, year ends, DST transitions, and leap days; panning at
  fixed zoom is asserted to translate marks without changing the set (R-TIME-9);
  a sustained pinch is asserted not to flicker the set between adjacent frames
  (R-TIME-11).
- **R-TEST-7 [M]** Projected slots: interval inference returns the modal delta
  across weekend gaps and missing bars (R-TIME-20); monthly series project
  calendar-correctly across Jan 31 → Feb 28 and a leap February (R-TIME-21);
  the §7.3.5 example axis is asserted verbatim; appending a datum whose
  timestamp matches the projection leaves the mark set byte-identical
  (R-TIME-30); scrolling fully into projected space leaves the value extent
  unchanged (R-TIME-28) and passes no projected index to any layer (R-TIME-27).
- **R-TEST-5 [S]** Golden tests for each layer at a fixed dataset and zoom,
  plus the time axis at each zoom level in the §7.3.4 table.
- **R-TEST-6 [M]** A Widgetbook use-case per layer and per axis configuration,
  matching the pattern in [lib/widgetbook/](../../widgetbook/), including a
  zoom slider that exercises the full time-axis hierarchy by hand.

---

## 14. Milestones

| # | Deliverable | Covers |
| --- | --- | --- |
| 1 | Core viewport: scales, scroll offset, visible-range culling, one line layer | R-SCALE-*, R-SCROLL-1..4, R-LAYER-1..2 |
| 2 | Optional self-sizing axes, two-pass layout, value tick generation | R-AXIS-* |
| 2b | Time axis weight ladder, greedy selection, weight-based formatting | R-TIME-* |
| 3 | Anchored zoom, gesture arbitration, growth direction | R-ZOOM-*, R-SCROLL-5 |
| 4 | Layer set: candle, OHLC bar, area, histogram, grid | R-LAYER-3..8 |
| 5 | Crosshair, tooltips, callbacks, controller | R-INT-*, R-API-6 |
| 5b | Paging: trigger, in-flight guard, exhausted latch, stationary prepend | R-PAGE-*, R-DATA-10..11 |
| 6 | Autoscale refinements, value-axis drag, log scale | R-SCALE-5, R-SCROLL-7..8 |
| 7 | Performance pass, benchmarks, goldens, Widgetbook | R-PERF-*, R-TEST-* |
| 8 | Sub-panes | R-LAYOUT-4..5 |

---

## 15. Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Axis gutter jitter during pan changes viewport width every frame, causing scale thrash | Visible wobble, wasted layout | R-AXIS-5; treat gutter width as sticky during an active gesture |
| Anchored zoom drift accumulating over a long pinch | Chart "slides" under the fingers | Recompute from the gesture's initial domain anchor each update, never incrementally |
| Gesture conflicts inside a scrolling page | Chart unusable when embedded | R-ZOOM-7; explicit gesture recognizer arena policy, documented |
| Two-stage x scale duplicated in every layer | Divergent bugs per layer | R-SCALE-2; a single `xOf(index)` on the context, layers never compose scales |
| Ordinal vs time domain leaking into layer code | Layers break in one mode | Layers address data by index only; the context owns the domain mode |
| Time-axis marks flickering during a pinch as `minIndexGap` crosses a threshold | Labels visibly popping in and out | R-TIME-11 quantised slot extent; R-TIME-9 build over a stable superset |
| Time weights recomputed on pan, or the whole ladder rebuilt on every append | Frame drops on live data | R-TIME-5 incremental O(1) append; R-TIME-10 cache keyed on the four inputs |
| Timezone mismatch between weight assignment and label formatting | Month label lands one bar off the actual boundary | Single timezone setting feeds both (R-TIME-4); DST and leap-day cases in R-TEST-4 |
| A projected index leaks into a layer, an accessor, or a hit test | Range error or a phantom candle at the edge | R-TIME-27..29 make projected slots a separate range that never reaches layers; asserted in R-TEST-7 |
| Inferred interval wrong (irregular series, mixed granularity) | Nonsense future dates on the axis | R-TIME-20 modal inference; caller override (R-TIME-19); R-TIME-32 to switch projection off entirely |
| Projection disagrees with the real trading calendar (holidays) | Labels shift when real data lands | R-TIME-30 rebuilds from the divergent index; callers with a real calendar supply a projector |
| Paging callback re-fires every frame while the viewport sits in the trigger zone | Request storm, duplicated data, rate-limit ban | R-PAGE-7 single in-flight request per direction; R-PAGE-3 one evaluation per frame |
| Reaching true start of history without an exhausted signal | Infinite re-request loop against an empty response | R-PAGE-8 latch; R-PAGE-9 consecutive-load cap as a backstop |
| Prepend applied a frame before the offset compensation | Visible jump every time history loads | R-PAGE-12 same-frame application; asserted in R-TEST-8 |
| Prepend invalidating the whole weight/mark cache | O(n) hitch on every page, worsening as history grows | R-PAGE-17 O(page) weight recompute; R-PAGE-18 base-offset mark storage |

---

## 16. Open questions

1. **Growth direction vs. axis placement** — this doc assumes "left/right" in
   the brief refers to two separate things: the direction data grows
   (R-SCROLL-3) and which side the value axis sits on (R-AXIS-6), with the
   latter defaulting to follow the former. Confirm that reading.
2. **Ordinal vs. time as the v1 default** — ordinal is assumed default because
   the primary use case is OHLC. Confirm.
3. Do sub-panes (R-LAYOUT-4) need to land in v1, or is a single pane with a
   bottom-anchored volume histogram enough?
4. Should the library ship any indicator maths, or stay render-only (R-LAYER-6)?
5. Is there a real requirement for higher-than-`double` precision at render
   time, or is formatter-level precision (R-DATA-7) sufficient?
6. Maximum dataset size to design for — is 50k (R-PERF-3) the right target, or
   does history paging (R-DATA-11) make it unbounded?
7. Should the ISO-week weight (55) be on by default for daily data, or stay
   opt-in as specified? TradingView omits it; it helps non-financial series.
8. When the leftmost visible mark is a fine one, should the axis inject a
   pinned context label (e.g. `Mar 2025`) at the leading edge so the coarse
   context is never scrolled off? TradingView does not; it may still be worth
   it for narrow embeds.
9. Confirm the default timezone: device-local (as specified), UTC, or required
   from the caller with no default.
10. Should weekend-skipping really be the default projector for daily+ data
    (R-TIME-22)? It is right for exchange data and wrong for, say, a daily
    sensor reading. The alternative is inferring it — if the loaded history
    contains no weekend bars, skip weekends when projecting.
11. Should projected slots exist at all when the newest datum is far in the
    past (a static historical dataset)? Projecting "future" dates onto a chart
    that ends in 2019 may read as a bug rather than a feature.
12. Does the chart ever **evict** data at the far end after many pages, or does
    the loaded range only grow? Eviction bounds memory on a long session but
    means a user scrolling back re-requests data they already had, and it
    interacts badly with the exhausted latch. Unbounded growth is assumed for
    v1 — confirm that is acceptable at the R-PERF-3 dataset size.
13. Should `onLoadPage` mutating a caller-owned list (as in the §10 sketch) be
    the supported pattern, or should the chart own an append/prepend-only data
    source object? The latter is harder to misuse — it can enforce ordering and
    apply R-PAGE-12's same-frame compensation itself — but it is a heavier API.
