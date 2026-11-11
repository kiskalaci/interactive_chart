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

Tests, from the package root:

```
flutter test                      # Dart VM, every widget test at 10 variants
flutter test --platform chrome    # the same suite in a real browser (about 5 min)
```

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
  `CrosshairLayer`, `PriceTagLayer`, `EventLayer`, each declaring (or opting out of) autoscale extent
  contribution. Each layer returns a widget, so layers compose with the rest
  of Flutter. `CandleLayer` and `HistogramLayer` paint all their items in one
  `CustomPainter` (`lib/src/painting/shape_painters.dart`), and `LineLayer`'s
  stroke is still one rotated box per segment. Per-item `onTap`/`onHover`
  callbacks on candles, bars and line points go through one `ItemHitRegion`
  per layer (`lib/src/painting/item_hit_region.dart`), which looks the item up
  in the painted geometry: a candle answers for its slot column, a bar for its
  rectangle, a line point for a 12 px square (the later point wins where they
  overlap). The region is only hit over an item, so pointers elsewhere reach
  the layers beneath. A mouse that stays still while the items move under it
  (pan, zoom, new data) is re-resolved after the frame. The number of widgets
  no longer grows with the visible slots (TC-LAYER-02b).
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
  0-minute interval. Tick labels for `TickMarkWeight.second` marks show
  `hh:mm:ss`.
- **Latest-point marker** — `LineLayer.latestPointBuilder` (`(BuildContext,
  T datum, int index) -> Widget`) draws a caller-supplied widget centred on
  the last datum, e.g. a pulsing "live" dot. It is built only while that
  datum is inside the visible range and has a finite value, and it ignores
  pointer events.
- **Autoscale follows data changes, not only range changes.** Every parent
  rebuild of the chart marks autoscale dirty, so a live tick that moves the
  last bar's high or low outside the current extent rescales immediately
  (R-SCALE-10). Pans and zooms that don't change the data don't trigger it.
- **Crosshair moves rebuild only the crosshair** (R-PERF-4). The context
  splits its notifications: `viewChanges` (scroll, zoom, value extent,
  autoscale) rebuilds the chart and every layer, while `highlightChanges`
  rebuilds only layers whose `ChartLayer.dependsOnHighlight` is true
  (`CrosshairLayer`). Each layer paints inside its own `RepaintBoundary`, so
  the crosshair repainting does not repaint the candles under it. A custom
  layer that draws something for the highlighted slot must override
  `dependsOnHighlight`. Hovering a projected slot reads only the newest
  bars' times, so its cost does not grow with the data length.
- **Visible range is exact.** `[visibleStart, visibleEnd)` holds precisely the
  slots that overlap the viewport; a slot starting on the right edge is not
  counted.
- **`panEnabled: false` really disables dragging.** A zoom then stays
  anchored at the gesture's start focal point.
- **A page prepended mid-drag does not move the view.**
- **Pan and pinch work on empty space** with or without the crosshair, and a
  tiny chart drops axes that do not fit instead of overflowing.
- **Unbounded constraints give a clear debug message.**
- **Value labels show enough decimals** for tiny ranges and huge values.
- **`jumpToLatest` and the right anchor stay against the right edge** when the
  viewport narrows afterwards (for example when the value-axis gutter grows for
  a new range). The view is pinned until the user, or a data change, moves it.
- **Time-axis marks follow the viewport width.** The projected (overscroll)
  region grows with the viewport, so the marks are rebuilt when its slot count
  changes, rounded up to a multiple of 16 so a continuous window resize does
  not rebuild them on every pixel.
- **Axis gutters honour the text scale.**
- **Tick weights are the `TickMarkWeight` enum** (exported), not integers,
  and follow TradingView's ladder: `second` (10), `minute1` (20), `minute5`
  (21), `minute30` (22), `hour1` (30), `hour3` (31), `hour6` (32), `hour12`
  (33), `day` (50), `month` (60), `year` (70). Each member has a `double
  value`, and the enum is comparable. `timeWeight` picks the coarsest tier
  crossed from the wall-clock fields (so it is DST-safe), and
  `TimeAxisConfig.formatter` receives a `TickMarkWeight`. Hour and minute
  marks all use the `hh:mm` label; sub-minute marks use `hh:mm:ss`.
- **`PriceTagLayer`** marks the latest price: a 1 px horizontal line across
  the viewport at the value of the **last datum of the whole dataset** (not the
  last visible one, so it survives panning back in time), and a tag with that
  value on the value axis. `valueOf` picks the value (for candles, usually the
  close). The text is **cropped, never rounded**, to `precision` digits after
  the decimal separator (default 2, padded with zeros): `29.999` shows as
  `29.99`. It crops the shortest round-trip decimal text of the double
  (`truncateToDecimals`), so `0.29` stays `0.29` rather than `0.28`. A NaN
  newest value falls back to the last finite one. When the level is outside
  the vertical range the tag sticks to the top or bottom edge of the axis and
  the line is not drawn. It does not contribute to autoscale, and it is drawn
  on the axis only when the chart has one. To paint on the gutter, which is
  outside the layers' viewport, `ChartLayer` gained two optional hooks:
  `buildValueAxisOverlay` (stacked over the axis labels; gets the gutter size)
  and `measureValueAxisOverlayWidth` (so the grow-only gutter widens to fit
  the tag instead of clipping it).
- **`EventLayer`** marks financial events (dividends, earnings, revenue and
  so on). A `ChartEvent` has a `time` (only its *day* counts), a `title`, a
  `description`, an `IconData` and a colour. Each event is a small round icon
  at the first datum of its day, resting `bottomInsetFraction` of the viewport
  height above the bottom edge (pass a `HistogramLayer`'s `heightFraction` to
  sit just above its strip); events on the same day stack upwards. A day with
  no datum (weekend, holiday) gets no icon, and only events in the visible
  range are built. When zoomed out so far that the icons of neighbouring days
  would overlap (closer than the marker's width), **all the icons that touch
  are hidden**, as on TradingView, and come back on zooming in. The choice is
  made over all events, not just the visible ones, so it depends on the zoom
  only and does not flicker while panning. A day's stack of same-day events
  counts as one icon column. Tapping an icon opens a card in the middle of the chart
  with the title, description and a close button, over a dimmed barrier. The
  card is configured through `EventOverlayConfig` (colours, radius, padding,
  max width, shadow, text styles, close-button content, whether a tap outside
  closes it) or replaced entirely with `overlayBuilder`. `onEventTap` reports
  taps. The open card is tracked by event (`ChartEvent` is `Equatable`), so
  it survives pans, zooms and new data and closes when its event is removed.
  Put the layer last in the list so its icons and card sit above the others.
  Layers have no state of their own, so the layer builds a small stateful
  widget to remember which card is open.
- **Equal-weight time marks are tie-broken by index**, so labels are stable
  when data is appended or the zoom changes.
- **The crosshair time badge shows the time of day** and can be formatted with
  `CrosshairLayer.timeFormatter`; badges are kept inside the viewport.
- **Touch crosshair** (tap, long press and drag) uses raw pointer events and
  works anywhere in the viewport without delaying pan or pinch.
- **The latest-point marker keeps its state** across pans, zooms and appends.
- **Controllers detach** when replaced or when the chart is disposed.
- **Re-enabling autoscale rescales immediately**, including after a manual
  value zoom and on double-tap of the value axis.
- **Value-axis ticks use the 1/2/2.5/5/10 ladder** (R-AXIS-8).
- **`onIndexHighlighted` reports `null` over a projected slot** (R-TIME-29).
  The crosshair still shows the projected time badge; there is no separate
  `onProjectedTimeHighlighted` callback yet.
- **Autoscale stays on for horizontal drags.** A drag pans the value axis
  (and so switches autoscale off) only once its vertical travel reaches
  `max(verticalPanThreshold, 0.5 × its horizontal travel)`; `verticalPanThreshold` is an `InteractiveChart` parameter, default 16 px. The wobble of a horizontal swipe
  therefore leaves autoscale alone, and so does a long swipe that drifts,
  while a deliberate vertical or steep diagonal drag still pans (see the
  R-SCROLL-6 deviation above). Once engaged, vertical panning stays on for the
  rest of that gesture. It starts from the threshold rather than jumping to
  catch up, so the content ends up the threshold distance short of the
  finger. Wheel and trackpad scrolling are unaffected.
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
- **No render-object tree (R-PERF-1, R-LAYOUT-2)**. The whole widget calls
  `setState` on every view change (pan/zoom/value extent) and rebuilds its
  layers, rather than driving `markNeedsLayout`/`markNeedsPaint` directly on
  render objects. The layers themselves are now cheap to rebuild: the
  per-slot items are painted, not built as widgets (see **Layers** above).
- **Two-pass axis layout is approximated** (R-AXIS-3/4). Axis gutter size is
  carried over from the previous frame's measured labels rather than a true
  dry-layout pass before the viewport is sized. Grow-only sizing (R-AXIS-5)
  is implemented.
- **Tick-hierarchy simplifications**: 11 weight tiers instead of 13 (no
  ISO-week tier and no sub-second tier); `minLabelSpacingPx` is a
  configured constant rather than measured against surviving labels
  (R-TIME-8); interval projection is calendar-day-accurate for
  daily-or-finer series and calendar-month-accurate for monthly-or-coarser
  ones (Jan 31 → Feb 28/29 → Mar 31, quarterly, yearly). Cadences between a
  day and 28 days (e.g. weekly) use fixed steps with no weekend skipping,
  and a 28-day cadence is treated as monthly.
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

The main use case, **"Interactive chart"** (`widgetbook/lib/widgets/`),
combines:

- a Candles / Line toggle (the Line series carries a `PulsingDot` via
  `latestPointBuilder`);
- volume histogram and 20-period moving-average layers, each switched by a
  knob (`Show volume`, `Show MA 20`);
- a latest-price line and axis tag (`PriceTagLayer`), with knobs for visibility
  and precision (`Show price tag`, `Price tag precision`);
- financial events (`EventLayer`): dividend, earnings and revenue icons above
  the volume histogram, one or more per day the data covers (today gets all
  three, so they stack; earlier days get one, so the layer's overlap hiding
  shows when zoomed out). Tapping one opens the details card. Knobs show or
  hide each kind and switch off dismissing the card by tapping outside it;
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

A second use case, **"Chart events"** (`events_widgetbook.dart`), shows
`EventLayer` on its own: a daily chart with quarterly dividend, earnings and
revenue events (earnings and revenue share a day, to show stacking) above the
volume histogram, with a knob per kind, one for dismissing the card by tapping
outside it, and one for the initial slot extent. Zoom out to see overlapping
icons hide.

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

## Test plan

This plan lists the tests needed before the library can be called production
ready. It covers every feature listed under "What's implemented", plus the
robustness, performance and platform checks the requirements doc asks for in
§11–§13 (`R-TEST-*`, `R-PERF-*`). Cases marked ✅ already exist in `test/`;
everything else is still to write.

### How to read the tables

- **ID**: `TC-<AREA>-<NN>`. Keep IDs stable once a test exists, and put the ID
  in the test's name so failures can be traced back here.
- **Level**: **U** unit (pure Dart, no widgets), **W** widget test
  (`flutter_test`), **G** golden, **I** integration on a real device or
  browser (`integration_test` or Playwright for web), **P** performance
  (profile-mode benchmark), **M** manual/exploratory.
- **Pri**: **P0** blocks release, **P1** should pass before release, **P2**
  hardening.
- ✅ (fixed) marks a gap that was confirmed by a failing test in `test/known_gaps_test.dart` and has since been fixed; ⚠ marks a case where the current code is expected to **fail or deviate**
  from the requirement. Each needs a decision: fix the code, or accept the
  deviation and record it under "What's simplified or out of scope".

### Screen sizes and environments

Every widget test runs once per variant: five screen sizes in each of two
environments, so 10 runs per test (`test/support/variants.dart`).

| Size | Logical px | | Environment | Target platform | Pixel ratio |
|---|---|---|---|---|---|
| `sm` | 360 × 640 | | `mobile` | Android | 3× |
| `m` | 768 × 1024 | | `browser` | macOS (a desktop browser) | 1× |
| `l` | 1024 × 768 | | | | |
| `xl` | 1440 × 900 | | | | |
| `xxl` | 1920 × 1080 | | | | |

- The shared harness (`ChartHarness.app`, and the `PagingHost` and `LiveHost`
  helpers) makes the chart fill the screen, so layout, gestures and callbacks
  are exercised at every width. Test geometry is therefore relative: use
  `screenOf(tester)` or the chart's own size, never a fixed 800 px.
- `testWidgets` (imported from `support/variants.dart`, hiding the framework's)
  runs the matrix. `testWidgetsOnce` runs a single time at the default size, for
  tests that set their own surface (`useLargeSurface`) or are heavy and
  size-independent (the 50 000-bar layer test, the hour of live ticks).
- The environments set the target platform and pixel ratio. Input devices are
  still chosen by each test (mouse for hover and wheel, touch for drags and
  pinch), so mouse-only tests also run in the `mobile` environment.
- `flutter test --platform chrome` compiles the suite to JavaScript and runs
  it in Chrome, which also exercises the web build of the package (the
  `dart:js_interop` scroll guard) under the same matrix.

### Fixtures and conventions

- **Data**: one deterministic generator per cadence (10 s, 1 min, 1 h, daily
  trading days, monthly), seeded, with helpers to insert NaN gaps, duplicate
  timestamps, and weekend or holiday gaps. Do not use `DateTime.now()` in
  tests; pass a fixed start time.
- **Viewport**: pump the chart in a fixed `SizedBox` (800×400 unless the case
  says otherwise) inside `MaterialApp`, so slot and pixel arithmetic is exact.
- **Time**: use `fakeAsync` / `tester.pump(duration)` for anything timer or
  animation based (live feed, pulsing marker, paging delays).
- **Pointer input**: drive mouse hover, wheel, and trackpad with `TestPointer`
  (`PointerDeviceKind.mouse` / `trackpad`), touch with `tester.drag`,
  `tester.timedDrag` and `startGesture` for multi-touch pinch.
- **Assertions**: read state through `InteractiveChartController`
  (`visibleRange`, `slotExtent`, `autoscale`, `highlightedIndex`) rather than
  by inspecting private fields. Where layout positions matter, assert with
  `tester.getRect` on keyed widgets.
- **Goldens**: fixed font (load a test font, no system fonts), fixed device
  pixel ratio, light and dark variants.

### 1. Data model and data updates (§4.1, §4.3)

Implemented in `test/data_model_test.dart` (shared helpers in
`test/support/chart_harness.dart`), all passing. Two notes from writing
them: TC-DATA-12 is "must not crash" only, because unsorted data is
documented as undefined behaviour on `InteractiveChart.data`; and the right
initial anchor is applied before the value-axis gutter has finished growing,
so the first offset can sit up to a gutter-growth short of the final maximum
(the newest bar is still in view; TC-DATA-15 asserts that tolerance).

| ID | Case | Expected | Lvl | Pri |
|---|---|---|---|---|
| TC-DATA-01 | ✅ Chart with a custom datum type (record, plain class, `int`) | Renders through accessor functions only; no dependency on `Candle` | W | P0 |
| TC-DATA-02 | ✅ Empty `data` list | No exception; no layers draw content; axes render without labels; visible range `(0, 0)` | W | P0 |
| TC-DATA-03 | ✅ Single datum | Renders one slot; autoscale uses the degenerate-extent rule (TC-SCALE-04) | W | P0 |
| TC-DATA-04 | ✅ Append one datum while the view is mid-history (R-DATA-9) | Visible range, slot extent and scroll offset unchanged | W | P0 |
| TC-DATA-05 | ✅ Append while the view is at the right edge | View stays where it was (no follow mode, R-SCROLL-5 not implemented). Pin current behaviour so a future follow mode is a deliberate change | W | P1 |
| TC-DATA-06 | ✅ Prepend 120 items while at the left edge (R-DATA-10) | `visibleStart` moves from 0 to 120; same data stays on screen (`test/prepend_test.dart`) | W | P0 |
| TC-DATA-07 | ✅ Prepend while mid-history and zoomed in | Visible range shifts by exactly the prepended count; on-screen x of a given datum unchanged to < 0.5 px | W | P0 |
| TC-DATA-08 | ✅ Prepend and append in the same update | View shifts by the prepended count only | W | P0 |
| TC-DATA-09 | ✅ Replace the data with an unrelated list of the same or larger length (old first timestamp not present) | Prepend count is 0; no shift, no exception | W | P0 |
| TC-DATA-10 | ✅ Data shrinks (length decreases) | Scroll is re-clamped; visible range stays inside `[0, length)`; no index-out-of-range in any layer | W | P0 |
| TC-DATA-11 | ✅ Duplicate timestamps at the old first position | Binary search finds the first match; documented result for the prepended count | U | P2 |
| TC-DATA-12 | ✅ Unsorted data | Behaviour is documented (assert in debug mode, or define it as undefined). No crash | W | P2 |
| TC-DATA-13 | ✅ In-place update of the last datum, same length (live tick) | New values are drawn on the next frame; viewport unchanged | W | P0 |
| TC-DATA-14 | ✅ NaN / ±infinity values in each accessor (R-DATA-8) | Skipped in drawing and in extent; line breaks at the gap; no exception | W | P0 |
| TC-DATA-15 | ✅ Prepend before the initial anchor has been applied (viewport still 0×0) | Initial anchor wins; no double shift | W | P1 |

### 2. Horizontal scale, viewport and anchoring (§5, §6.1)

Implemented in `test/horizontal_scale_test.dart`, all passing. Writing them
found one bug, now fixed: when the viewport's right edge landed exactly on a
slot boundary, `visibleEnd` included one extra slot that was not on screen
(TC-X-02). The context now computes the range as
`[floor(offset / extent), ceil((offset + width) / extent))`.

Found by running the whole suite across screen sizes (not tied to one plan
row): after `jumpToLatest()` the value-axis gutter could grow and narrow the
viewport by about 11 px at `sm`, leaving the newest bar out of view, and the
time-axis marks for the overscroll region were not rebuilt when the viewport
grew wider. Both are fixed (see "What's implemented").

Test-writing gotchas, handled in `test/support/chart_harness.dart`: a
`SizedBox` wider than the default 800 px test screen is silently clamped (use
`useLargeSurface(tester)`), and `initialSlotExtent` / `initialAnchor` are read
once, so a second chart with different initial values needs a fresh widget
tree (pump a `SizedBox()` in between).

| ID | Case | Expected | Lvl | Pri |
|---|---|---|---|---|
| TC-X-01 | ✅ `xOf(i)` against `indexAtViewportX(x)` across zoom levels | Round-trips to the same index; slot centre maps to the slot | U | P0 |
| TC-X-02 | ✅ Visible range culling | `[visibleStart, visibleEnd)` covers exactly the slots intersecting the viewport, clamped to real data | U | P0 |
| TC-X-03 | ✅ `initialAnchor: left` | Opens with `visibleStart == 0` | W | P0 |
| TC-X-04 | ✅ `initialAnchor: right` | Opens at max scroll offset, newest datum visible with overscroll space after it | W | P0 |
| TC-X-05 | ✅ Initial anchor is applied only once | Later data changes or viewport resizes never re-anchor | W | P0 |
| TC-X-06 | ✅ Overscroll past the newest datum (R-SCROLL-4) | Allowed up to half the viewport width, no further | W | P0 |
| TC-X-07 | ✅ Overscroll before the oldest datum | Not allowed (min scroll offset is 0) | W | P1 |
| TC-X-08 | ✅ `initialSlotExtent` outside `[minSlotExtent, maxSlotExtent]` | Clamped | U | P1 |
| TC-X-09 | ✅ Viewport resize (window or parent shrinks or grows) | Scroll re-clamped; no jump beyond the clamp; visible range recomputed | W | P0 |
| TC-X-10 | ✅ Data shorter than the viewport | Content fits; scroll limits are consistent; no negative ranges | W | P1 |

### 3. Value scale and autoscale (§5, R-SCALE-*)

Implemented in `test/value_scale_test.dart` (TC-SCALE-07 and TC-SCALE-11 are in
`test/known_gaps_test.dart`), all passing. Writing them found one more bug,
now fixed: after a manual value zoom, re-enabling autoscale (the controller's
`setAutoscale(true)` or a double-tap on the value axis) did not rescale,
because the widget recomputed only when the visible range or data changed. It
now also recomputes when autoscale goes from off to on (TC-SCALE-09 and 09b).

Two behaviours the tests pin down: with nothing to scale, the fallback
extent is `0..1` *plus* the 5 % padding (`-0.05..1.05`), and a flat series
spans `value ± 0.5` before padding.

| ID | Case | Expected | Lvl | Pri |
|---|---|---|---|---|
| TC-SCALE-01 | ✅ Autoscale uses only the visible range (R-SCALE-8) | Extent equals min/max of contributing layers over visible indices, plus 5 % padding | W | P0 |
| TC-SCALE-02 | ✅ Layers that opt out (`GridLayer`, `HistogramLayer` default, `LineLayer(contributesToExtent: false)`) | Excluded from extent | U | P0 |
| TC-SCALE-03 | ✅ `HistogramLayer(contributesToExtent: true)` | Contributes `(0, max)` | U | P1 |
| TC-SCALE-04 | ✅ Degenerate extent: all visible values equal, or one datum (R-SCALE-11) | Extent is value ± 0.5 before padding; no divide-by-zero | U | P0 |
| TC-SCALE-05 | ✅ No contributing layer has data in range | Extent falls back to `0..1` | U | P1 |
| TC-SCALE-06 | ✅ Pan within the same index range (R-SCALE-10) | Autoscale is not recomputed | W | P1 |
| TC-SCALE-07 | ✅ (fixed) Live tick raises the last candle's high above the current extent, length unchanged | Spec: extent updates ("or the underlying data changes"). Current code recomputes only when range or length changes, so the new high can be clipped | W | P0 |
| TC-SCALE-08 | ✅ Autoscale off, then data changes | Manual extent is kept | W | P0 |
| TC-SCALE-09 | ✅ `setAutoscale(true)` after a manual extent | Extent is recomputed immediately | W | P0 |
| TC-SCALE-10 | ✅ `yOf` / `valueOfViewportY` inverse | Round-trips within floating-point tolerance | U | P0 |
| TC-SCALE-11 | ✅ (fixed) Value tick steps (R-AXIS-8) | Spec asks for a 1/2/2.5/5/10 progression; `niceValueTicks` produces 1/2/5/10 only | U | P1 |
| TC-SCALE-12 | ✅ Value ticks across magnitudes (0.0001 to 1e9, negative ranges, ranges crossing zero) | Ticks are ascending, evenly stepped, inside the extent, about 5 of them | U | P0 |

### 4. Pan and zoom gestures (§6)

Implemented in `test/gestures_test.dart` (TC-GEST-02 stays in
`test/prepend_test.dart`), all passing. Writing them found one more bug, now
fixed: with `panEnabled: false` and `zoomEnabled: true`, a one-finger drag
still scrolled the chart, because the scroll offset followed the moving focal
point even at scale 1. With panning off, a zoom now stays anchored at the
gesture's *start* focal point (TC-GEST-10).

Behaviours the tests pin down, worth knowing when writing more:

- Flutter's scale recogniser only starts after a pan slop of about 36 px (or
  an 18 px span change) and then re-bases from that point, so a drag pans by
  the distance moved *after* the slop. `tester.drag` compensates for this;
  hand-built drags do not.
- Pointer events arrive one pointer at a time, so at the moment a pinch is
  accepted the midpoint can be off by half a step. The tests therefore use
  small steps (about 2 px of span) and a 1 px tolerance in the starting slot
  size.
- Inside a vertical `ListView`, a vertical drag over the chart scrolls the
  page (the list's drag recogniser wins at 18 px), so vertical value panning
  is not available there; a horizontal drag still pans the chart, and the
  wheel still zooms it.
- Trackpad pinch and two-finger pan arrive as `PointerPanZoom*` events and
  work through the same scale handler.

| ID | Case | Expected | Lvl | Pri |
|---|---|---|---|---|
| TC-GEST-01 | ✅ Horizontal drag | Pans x by the drag distance; clamped at both ends | W | P0 |
| TC-GEST-02 | ✅ Purely horizontal drag | Autoscale stays on (`test/prepend_test.dart`) | W | P0 |
| TC-GEST-03 | ✅ Drag with vertical movement | Pans the value extent and switches autoscale off (documented deviation from R-SCROLL-6) | W | P0 |
| TC-GEST-04b | ✅ Nothing jumps when a pinch ends (bug found and fixed) | Lifting one finger and moving the other no longer shifts the view by the distance that finger travelled during the pinch (the gesture used to restart from the finger's original touch-down point); releasing both fingers, a fresh drag, a finger added to a drag, and a trackpad pinch after a click elsewhere all stay anchored | W | P0 |
| TC-GEST-03b | ✅ Vertical panning needs deliberate vertical movement | A horizontal drag with a little wobble, or a long swipe that drifts, keeps autoscale on; a vertical or steep diagonal drag still pans | W | P0 |
| TC-GEST-04 | ✅ Two-finger pinch, focal point fixed | Datum under the focal point stays under it (< 0.5 px) through the whole gesture | W | P0 |
| TC-GEST-05 | ✅ Sustained pinch over 100+ update events | No cumulative drift (gesture-start reference) | W | P0 |
| TC-GEST-06 | ✅ Pinch past `minSlotExtent` / `maxSlotExtent` | Clamped; focal point still held at the clamp | W | P0 |
| TC-GEST-07 | ✅ Vertical-dominant mouse wheel | Zooms x anchored at the pointer | W | P0 |
| TC-GEST-08 | ✅ Horizontal-dominant wheel or trackpad scroll | Pans x; no zoom | W | P0 |
| TC-GEST-09 | ✅ Vertical-only wheel with `zoomEnabled: false` | Pans x | W | P0 |
| TC-GEST-10 | ✅ `panEnabled: false` | Drag and horizontal scroll do nothing; zoom still works | W | P0 |
| TC-GEST-11 | ✅ `zoomEnabled: false` | Pinch and wheel do not change slot extent | W | P0 |
| TC-GEST-12 | ✅ Both disabled | No gesture changes the viewport; crosshair still works | W | P1 |
| TC-GEST-13 | ✅ Trackpad pinch (`PointerPanZoom*` events on desktop) | Zooms anchored, same as touch pinch | W | P1 |
| TC-GEST-14 | ✅ Fling / fast drag | Ends clamped, no overshoot past limits | W | P2 |
| TC-GEST-15 | ✅ Chart inside a scrollable parent (`ListView`) | Horizontal drag pans the chart; vertical page scroll behaviour is defined and documented | W | P1 |

### 5. Axes and axis gutters (§7.1–7.2, R-ZOOM-2, R-SCROLL-6..8)

Implemented in `test/axes_test.dart`, all passing. Bug found and fixed:
the axis gutters were measured without the user's text scale, so at 2× text
the value labels overflowed their gutter and the time labels were clipped.
Both gutters now honour `MediaQuery.textScalerOf` (the time axis grows with the
scale, never below 22 px). TC-AXIS-05 and 06 exercise `ValueAxisView` and
`TimeAxisView` directly.

| ID | Case | Expected | Lvl | Pri |
|---|---|---|---|---|
| TC-AXIS-01 | ✅ All four present/absent combinations of value and time axis (R-TEST-2) | Viewport reclaims the gutter of any absent axis | W | P0 |
| TC-AXIS-02 | ✅ Value axis left vs right; time axis top vs bottom | Gutters sit on the right side; viewport and the other axis are aligned | W, G | P0 |
| TC-AXIS-03 | ✅ Value gutter grows when a wider label appears (R-AXIS-5) | Width grows; it never shrinks while panning | W | P0 |
| TC-AXIS-04 | ✅ Custom `ValueAxisConfig.formatter` / `TimeAxisConfig.formatter` | Used for every label | W | P0 |
| TC-AXIS-05 | ✅ Value labels outside the viewport (beyond ±8 px) | Not rendered | W | P2 |
| TC-AXIS-06 | ✅ Time label that would cross a viewport edge (R-TIME-15) | Dropped, not clipped | W | P0 |
| TC-AXIS-07 | ✅ Wheel on the time axis | Zooms x anchored at the pointer x | W | P0 |
| TC-AXIS-08 | ✅ Horizontal drag on the time axis | Zooms x; right drag zooms in | W | P1 |
| TC-AXIS-09 | ✅ Wheel on the value axis | Zooms y anchored at the pointer y; autoscale off | W | P0 |
| TC-AXIS-10 | ✅ Vertical drag on the value axis | Zooms y; autoscale off | W | P1 |
| TC-AXIS-11 | ✅ Double-tap on the value axis | Autoscale back on, extent recomputed | W | P0 |
| TC-AXIS-12 | ✅ Text styles (`textStyle`, `emphasizedTextStyle` for weight ≥ `TickMarkWeight.month`) | Applied to the right marks | W | P1 |
| TC-AXIS-14 | ✅ The largest visible weight is bold | Only the heaviest surviving marks are bold, at any tier | W | P1 |
| TC-AXIS-13 | ✅ Text scale factor 2.0 (accessibility font size) | Labels and gutters grow; no overlap or overflow errors | W | P1 |

### 6. Time-axis tick hierarchy (§7.3, R-TEST-4)

Implemented in `test/time_ticks_test.dart`. Bug found and fixed:
`buildTickMarks` sorted candidates by weight only and `List.sort` is not
stable, so which of two equal-weight neighbours got the label was arbitrary.
Labels could change when data was appended or the zoom changed, and the first
datum could lose its label to an equal-weight neighbour (R-TIME-2). Ties now go
to the earlier slot.

With the finer intraday tiers, TC-PROJ-10 (appending a datum that matches the
projection) exempts the final mark in the window: a 5-minute mark entering the
window can displace the 1-minute mark at its edge (see R-TIME-30).

| ID | Case | Expected | Lvl | Pri |
|---|---|---|---|---|
| TC-TIME-01 | ✅ `timeWeight` per tier: year, month, day, 12/6/3/1 hour, 30/5/1 minute, second | `TickMarkWeight` year / month / day / hour12 / hour6 / hour3 / hour1 / minute30 / minute5 / minute1 / second | U | P0 |
| TC-TIME-02 | ✅ First datum | Always `TickMarkWeight.year` (R-TIME-2) | U | P0 |
| TC-TIME-03 | ✅ Greedy selection | Higher weights win; no two accepted marks closer than `minLabelSpacingPx` (56 px) | U | P0 |
| TC-TIME-04 | ✅ Pan at fixed zoom (R-TIME-9) | Mark set unchanged; marks only translate | W | P0 |
| TC-TIME-05 | ✅ Sustained pinch (R-TIME-11) | Mark set changes only when the quantised slot-extent bucket changes (6 steps per doubling); no flicker between adjacent frames | W | P0 |
| TC-TIME-06 | ✅ Labels by weight | Year → `2024`, month → `Mar`, day → `14`, hour/minute tiers → `hh:mm`, second → `hh:mm:ss` | U | P0 |
| TC-TIME-10 | ✅ `TickMarkWeight` ordering (`tick_mark_weight_test.dart`) | Values ascend second → year; `>`, `>=`, `<`, `<=` and `compareTo` follow the value | U | P1 |
| TC-TIME-07 | ✅ Calendar edge cases: month end, year end, leap day, DST transitions in local time | Weights are correct on each boundary; no duplicated or missing label | U | P0 |
| TC-TIME-08 | ✅ Mark set includes projected slots (R-TIME-24) | Scrolling into overscroll does not change the mark set | W | P0 |
| TC-TIME-09 | ✅ Full zoom sweep from min to max slot extent on a daily series | At every bucket, labels never overlap and the coarsest boundary is labelled | W, G | P1 |

### 7. Interval inference and projected slots (§7.3.5, R-TEST-7)

Implemented in `test/time_ticks_test.dart` (with section 6). The projected
mark set after appending a bar that matches the projection is identical
(TC-PROJ-10, R-TIME-30).

| ID | Case | Expected | Lvl | Pri |
|---|---|---|---|---|
| TC-PROJ-01 | ✅ `inferModalIntervalSeconds` on daily trading data with weekends | Returns 86 400 (modal, not mean) | U | P0 |
| TC-PROJ-02 | ✅ 1-minute data with missing bars | Returns 60 | U | P0 |
| TC-PROJ-03 | ✅ 10-second and 30-second data | Returns 10 and 30 | U | P0 |
| TC-PROJ-04 | ✅ Fewer than 2 points | Falls back to 1 day | U | P1 |
| TC-PROJ-05 | ✅ Sample size limit | Only the trailing `sampleSize` deltas are used | U | P2 |
| TC-PROJ-06 | ✅ `projectTimes` on daily data | Steps by a day and skips Saturday and Sunday | U | P0 |
| TC-PROJ-07 | ✅ `projectTimes` on intraday data | Fixed-step, no weekend skipping | U | P0 |
| TC-PROJ-08 | ✅ `projectTimes` with empty data | Daily steps from now, no exception (inject the clock to test) | U | P2 |
| TC-PROJ-09 | ✅ (fixed) Monthly series across Jan 31 → Feb 28 and a leap February (R-TIME-21) | Spec: calendar-correct. Current code: fixed-duration steps | U | P1 |
| TC-PROJ-10 | ✅ Append a datum whose time equals the projected time (R-TIME-30) | Mark set is identical before and after | W | P1 |

### 8. Layers (§8)

Implemented in `test/layers_test.dart`. Bug found and fixed: the latest-point
marker had no key, so its position in the layer's `Stack` shifted whenever the
number of line segments changed (a pan, a zoom or an appended bar) and a
stateful marker, such as a pulsing animation, was recreated each time. It is
now keyed. A negative histogram value is clamped to nothing by the stack's
constraints rather than throwing (TC-HIST-02b pins this). `GridLayer` also draws
a vertical line at every visible time mark, which TC-GRID-01 covers.

| ID | Case | Expected | Lvl | Pri |
|---|---|---|---|---|
| TC-LAYER-01 | ✅ Layer order | Later layers draw on top of earlier ones | W, G | P0 |
| TC-LAYER-02 | ✅ Only visible slots are built (R-PERF-2) | Number of child widgets per layer is O(visible slots), not O(data length) | W | P0 |
| TC-LAYER-03 | ✅ Custom `ChartLayer` subclass | Receives size, context and data; its `extentFor` feeds autoscale | W | P1 |
| TC-GRID-01 | ✅ `GridLayer` | One line per value tick, at `yOf(tick)`, in the configured colour | W, G | P1 |
| TC-CANDLE-01 | ✅ Up vs down candles (`close >= open` is up) | `upColor` / `downColor`; `close == open` counts as up | W | P0 |
| TC-CANDLE-02 | ✅ Body width | `max(minBodyWidth, slotExtent × bodyWidthRatio)`; a flat candle body is at least 1 px tall | W | P1 |
| TC-CANDLE-03 | ✅ Slot extent < 2 px | Body collapses to a 1 px line | W | P2 |
| TC-CANDLE-04 | ✅ Wick spans high to low | Pixel-correct | G | P1 |
| TC-CANDLE-05 | ✅ Any OHLC value is NaN | Candle skipped; extent ignores it | W | P0 |
| TC-CANDLE-06 | ✅ `onTap` / `onHover` | Tap reports the index; hover enter reports the index, exit reports `null` | W | P0 |
| TC-HIST-01 | ✅ Bars scale to the local maximum within the visible range; strip height is `heightFraction` of the viewport | Tallest visible bar fills the strip | W | P0 |
| TC-HIST-02 | ✅ All visible values ≤ 0 or NaN | Nothing drawn | W | P1 |
| TC-HIST-03 | ✅ `onTap` / `onHover` | As TC-CANDLE-06 | W | P1 |
| TC-LINE-01 | ✅ Segments between consecutive finite points | One segment per pair; correct start, length and angle | W | P0 |
| TC-LINE-02 | ✅ NaN in the middle of the series (R-DATA-8) | Line breaks; no segment across the gap | W | P0 |
| TC-LINE-03 | ✅ `fill: true` | A gradient under the line: strongest (`fillTopOpacity`, 0.4) at the highest point of the line in view, fading to `fillBottomOpacity` (0) at the bottom of the viewport; nothing above the line; checked on rendered pixels | W | P2 |
| TC-LINE-03b | ✅ Fill opacities and gaps | `fillTopOpacity` / `fillBottomOpacity` set the two ends; a NaN gap leaves a gap in the shading; no fill by default | W | P2 |
| TC-LINE-04 | ✅ Point hit targets | Built only when `onPointTap` or `onPointHover` is set; 12 px targets centred on points | W | P1 |
| TC-LINE-05 | ✅ `latestPointBuilder` with the last datum visible | Builder called with the last datum and index; marker rendered (`test/latest_point_test.dart`) | W | P0 |
| TC-LINE-06 | ✅ `latestPointBuilder` with the last datum scrolled out of view | Builder not called; no marker | W | P0 |
| TC-LINE-07 | ✅ `latestPointBuilder` when the last value is NaN | No marker | W | P1 |
| TC-LINE-08 | ✅ Marker position | Marker centre equals `(xOf(last), yOf(value))` for odd and even marker sizes | W | P0 |
| TC-LINE-09 | ✅ Marker ignores pointer events | Hover and drag over the marker behave as if it were not there | W | P0 |
| TC-LINE-10 | ✅ Live tick moves the last value | Marker moves with it; a stateful marker (e.g. animation) keeps its state across ticks | W | P1 |
| TC-EVENT-01 | ✅ Markers (`test/event_layer_test.dart`) | One icon per event, centred on its day's slot, resting on the bottom (or `bottomInsetFraction` up); same-day events stack; days without a datum and off-screen events are not built | W | P0 |
| TC-EVENT-05 | ✅ Overlap | Icons closer than a marker width are hidden (every icon of a touching cluster), return when zoomed in, and the result does not change with the pan offset; same-day stacks are not hidden | W | P0 |
| TC-EVENT-02 | ✅ Details card | Tapping an icon opens a card centred in the viewport with title, description and close button; the button, or a tap outside, closes it; a tap on the card does not | W | P0 |
| TC-EVENT-03 | ✅ Card configuration | `EventOverlayConfig` fields apply, `overlayBuilder` replaces the card, `dismissOnBarrierTap: false` keeps it open, `onEventTap` fires | W | P1 |
| TC-EVENT-04 | ✅ Card lifetime | Stays open across pans and appended data; closes when its event is removed; a drag over the chart still pans | W | P1 |
| TC-PRICE-01 | ✅ `truncateToDecimals` | Crops toward zero, never rounds (`1.999` → `1.99`, `-1.239` → `-1.23`), pads with zeros, no `-0.00`, correct for exponent-form doubles, `0.29` stays `0.29` | U | P0 |
| TC-PRICE-02 | ✅ Tag text (`test/price_tag_layer_test.dart`) | Newest value cropped to `precision` (default 2) | W | P0 |
| TC-PRICE-03 | ✅ Line | 1 px, full viewport width, at `yOf(latest)` | W | P0 |
| TC-PRICE-04 | ✅ Tag position | On the value axis (left or right), centred on the line; stuck to the edge when the level is off-screen, with no line | W | P1 |
| TC-PRICE-05 | ✅ Latest of the whole dataset | Still tagged when scrolled away from the newest bar; updates on append; a NaN newest value falls back to the last finite one | W | P0 |
| TC-PRICE-06 | ✅ Gutter and autoscale | The axis widens so a wide tag is not clipped; the layer does not affect autoscale; no tag without a value axis; empty data draws nothing | W | P1 |

### 9. Crosshair and readouts (§9)

Implemented in `test/crosshair_test.dart` (TC-CROSS-06 is in
`test/known_gaps_test.dart`). Bugs found and fixed:

- The time badge showed only the date, so every intraday bar read the same.
  It now shows the time of day too (seconds only when non-zero), and
  `CrosshairLayer.timeFormatter` overrides it (R-TIME-16).
- Badges were clipped by the viewport at its edges. They are now pulled back
  inside it.
- Touch tap and long press only registered over a drawn element, because the
  recogniser used the default hit behaviour, and a long press showed nothing
  until the finger moved. Touch is now handled with raw pointer events (a
  timer plus a slop check) instead of gesture recognisers. A recogniser hit
  everywhere joins every touch's gesture arena and delays pan and pinch by a
  touch slop, so this keeps both exact. Pan and zoom updates are ignored while
  the crosshair is being dragged. A one-finger drag also starts from the
  pointer-down position, and vertical value panning is applied cumulatively,
  so neither loses the slop distance.

TC-CROSS-09: the `index < 0` branch is unreachable through the viewport (the
scroll offset is never negative), so the test pins that the first pixel
highlights slot 0.

| ID | Case | Expected | Lvl | Pri |
|---|---|---|---|---|
| TC-CROSS-01 | ✅ Mouse hover over a real slot | Vertical and horizontal lines, value badge (2 decimals), time badge | W | P0 |
| TC-CROSS-02 | ✅ Mouse exit | Crosshair cleared | W | P0 |
| TC-CROSS-03 | ✅ Long-press drag on touch | Crosshair follows; cleared on release | W | P0 |
| TC-CROSS-04 | ✅ Tap | Crosshair placed at the tapped slot | W | P1 |
| TC-CROSS-05 | ✅ Hover over a projected slot (R-TIME-29) | Time badge only, using the projected time; no value line or badge | W | P0 |
| TC-CROSS-06 | ✅ (fixed) `onIndexHighlighted` over a projected slot | Spec: reports `null`. Current code reports the raw projected index | W | P1 |
| TC-CROSS-07 | ✅ `crosshairEnabled: false` | No crosshair on hover, tap or long-press | W | P0 |
| TC-CROSS-08 | ✅ `CrosshairLayer` without `valueOf` / `timeOf` | Missing badges are omitted; no exception | W | P1 |
| TC-CROSS-09 | ✅ Hover left of the first slot | Highlight cleared | W | P2 |
| TC-CROSS-10 | ✅ Badges near viewport edges | Badges are not clipped | W, G | P1 |

### 10. Controller and callbacks (§10)

Implemented in `test/controller_test.dart` (TC-CTRL-05 is in
`test/jump_to_latest_test.dart`). Bug found and fixed: a controller was never
detached when the chart replaced it or was disposed, so a swapped-out
controller kept receiving the chart's events, and a controller used after its
chart was gone was left attached to a disposed context. Charts now call the new
`InteractiveChartController.detach`. TC-CB-03 pins that data and size changes
do not call `onVisibleRangeChanged`.

| ID | Case | Expected | Lvl | Pri |
|---|---|---|---|---|
| TC-CTRL-01 | ✅ Getters before attach | `visibleRange == (0, 0)`, `slotExtent == 0`, `autoscale == true`, `highlightedIndex == null`; methods are no-ops | U | P0 |
| TC-CTRL-02 | ✅ Listener notifications | Controller notifies on pan, zoom, highlight and autoscale changes | W | P0 |
| TC-CTRL-03 | ✅ `setAutoscale(false/true)` | Reflected in `autoscale`; the y extent behaves accordingly | W | P0 |
| TC-CTRL-04 | ✅ `jumpToLatest()` | Scrolls to the newest datum; slot extent unchanged | W | P0 |
| TC-CTRL-05 | ✅ `jumpToLatest(slotExtent: 8)` after zooming | Slot extent 8, view ends at the newest datum (`test/jump_to_latest_test.dart`) | W | P0 |
| TC-CTRL-06 | ✅ `jumpToLatest(slotExtent:)` with a value outside min/max | Clamped | W | P1 |
| TC-CTRL-07 | ✅ `clearHighlight()` | Crosshair removed | W | P1 |
| TC-CTRL-08 | ✅ Swap the controller instance on the widget | Old one detached, new one attached; no events delivered to the old one | W | P0 |
| TC-CTRL-09 | ✅ No controller passed | An internal one is created and disposed with the widget | W | P1 |
| TC-CTRL-10 | ✅ Dispose the controller | Listener removed from the context; no leaks (`LeakTracker`) | W | P1 |
| TC-CB-01 | ✅ `onVisibleRangeChanged` on first layout | Called exactly once after the first frame with the initial range | W | P0 |
| TC-CB-02 | ✅ `onVisibleRangeChanged` on pan and zoom | Called with the new range | W | P0 |
| TC-CB-03 | ✅ Data updates without user input | Behaviour is defined and documented (today: no call from `setSlotCount`) | W | P1 |
| TC-CB-04 | ✅ `onIndexHighlighted` | Called with the index on hover and `null` on exit | W | P0 |

### 11. Paging integration (§4.4, R-TEST-8)

Implemented in `test/paging_test.dart`, driving a `PagingHost`
(`test/support/hosts.dart`) that implements the documented pattern. Bug found
and fixed: when a page was prepended in the middle of a drag, the gesture's
stored start position was in absolute content pixels, so the next update
snapped the view back by exactly the prepended width (120 slots at 8 px is
960 px). The reference is now shifted along with the data (TC-PAGE-07). The
chart has no fling inertia, so "mid-fling" is tested as a held, moving drag.

The library has no paging API yet, so these cases test the documented
pattern: a caller drives loading from `onVisibleRangeChanged`. Write them
against a small test harness that implements that pattern, and move them to
the library when a paging API exists.

| ID | Case | Expected | Lvl | Pri |
|---|---|---|---|---|
| TC-PAGE-01 | ✅ Pan into the threshold zone | Exactly one load request | W | P0 |
| TC-PAGE-02 | ✅ Dwell or keep panning in the zone while a request is in flight (R-PAGE-7) | No second request | W | P0 |
| TC-PAGE-03 | ✅ Regression: page lands while the view is at the left edge | View shifts by the page size and no further request fires without user input (no cascade) | W | P0 |
| TC-PAGE-04 | ✅ Exhausted latch (R-PAGE-8) | No request after the source reports exhausted | W | P0 |
| TC-PAGE-05 | ✅ Page too small to clear the threshold (R-PAGE-9) | Requests stop at a defined cap | W | P1 |
| TC-PAGE-06 | ✅ Widget disposed while a request is in flight (R-PAGE-11) | Result discarded; no `setState` after dispose | W | P0 |
| TC-PAGE-07 | ✅ Prepend during an active fling (R-PAGE-13) | Fling neither jumps nor stops | W | P1 |
| TC-PAGE-08 | ✅ Prepend outside the visible range (R-PAGE-19) | Value extent and on-screen tick marks unchanged | W | P0 |
| TC-PAGE-09 | ✅ Live append arrives while a page is loading | Both applied; view stable; order of data correct | W | P0 |
| TC-PAGE-10 | ✅ Opened at `ChartAnchor.left` | Initial announce triggers at most one load (documented deviation from R-PAGE-4) | W | P1 |

### 12. Live data

Implemented in `test/live_data_test.dart`, with a `LiveHost` that ticks once a
second on a fake clock (ten-second bars, the last bar updated in place, a new
bar at each boundary). TC-LIVE-05 runs 3 600 ticks and checks that the cost of
the last 300 ticks stays close to the first 300 (it measures time only, not
memory; it uses generous bounds because wall-clock timing is noisy). The
tests also found the empty-space drag bug listed under section 14.

| ID | Case | Expected | Lvl | Pri |
|---|---|---|---|---|
| TC-LIVE-01 | ✅ One-second ticks updating the last bar for 60 s (fake clock) | Last bar updates each tick; viewport stable; no exceptions | W | P0 |
| TC-LIVE-02 | ✅ Bar rollover at a 10-second boundary | New bar appended; projected slots continue at 10 s cadence | W | P0 |
| TC-LIVE-03 | ✅ Ticks while the user is mid-drag or mid-pinch | Gesture continues without a jump | W | P0 |
| TC-LIVE-04 | ✅ Ticks while the crosshair is shown | Crosshair stays on the same index; readout updates if it is the last bar | W | P1 |
| TC-LIVE-05 | ✅ One hour of ticks (3 600 updates) | Frame time and memory stay flat | P | P1 |

### 13. Web scroll guard

| ID | Case | Expected | Lvl | Pri |
|---|---|---|---|---|
| TC-WEB-01 | Wheel with `deltaX != 0` inside the chart bounds | `preventDefault()` called | I | P0 |
| TC-WEB-02 | Same event outside the chart bounds | Not prevented | I | P0 |
| TC-WEB-03 | Vertical-only wheel inside the chart | Not prevented | I | P0 |
| TC-WEB-04 | Chart disposed | Listener removed; later events are not prevented | I | P0 |
| TC-WEB-05 | Two charts on one page | Each guards only its own bounds | I | P1 |
| TC-WEB-06 | Non-web build | Stub used; no `dart:js_interop` import in the compiled app | U | P1 |
| TC-WEB-07 | ⚠ Flutter view embedded at an offset in a host page | Spec-level expectation: guarded correctly. Current code assumes a full-page view | I | P2 |
| TC-WEB-08 | Chrome, Safari and Firefox, macOS trackpad swipe | No back/forward navigation while over the chart; works normally outside it | M | P0 |

### 14. Lifecycle and robustness

Implemented in `test/lifecycle_test.dart`. Bugs found and fixed:

- **A drag that began before unmount used the disposed context.** The pointer-up
  is still routed to the removed `Listener`, and the touch handler then called
  into the disposed state. Pointer handlers now ignore events once unmounted.
- **Pan and zoom did nothing on empty space when the crosshair was off.** The
  pan/zoom `GestureDetector` deferred to its children, and the crosshair's
  mouse region (always hit) had been hiding it. It is now opaque, so a drag or
  pinch works anywhere in the viewport.
- **A tiny chart overflowed.** An axis bigger than the chart (a 1 x 1 chart, or
  one animating up from zero) threw `RenderFlex overflowed`. Axes are now only
  laid out when there is room for them and a viewport.
- **Unbounded constraints** (a chart in a `Column` or a horizontal `ListView`)
  gave an obscure layout error. In debug mode it is now a clear message that
  asks for a bounded width and height.
- **Tiny and huge value scales.** Value labels always had two decimals, so a
  range around 1e-8 printed every tick as `0.00`. The default format now
  shows as many decimals as the tick step needs (never fewer than two), on the
  axis and in the crosshair badge (`valueDecimals`).

`initialAnchor`, `initialSlotExtent`, `minSlotExtent` and `maxSlotExtent` are
read once; this is now documented on the fields and pinned by TC-LIFE-04.
TC-LIFE-08 does not use `leak_tracker`; it checks over 25 mount/unmount cycles
that the controller is detached, the context is disposed and no timer or
ticker is left running (the test framework fails on any left pending).

| ID | Case | Expected | Lvl | Pri |
|---|---|---|---|---|
| TC-LIFE-01 | ✅ Dispose mid-gesture, mid-animation and with a pending post-frame callback | No exceptions; no `setState` after dispose | W | P0 |
| TC-LIFE-02 | ✅ Change the `layers` list (add, remove, swap type) between builds | Renders the new set; autoscale recomputed | W | P0 |
| TC-LIFE-03 | ✅ Change `valueAxis` / `timeAxis` from present to `null` and back at runtime | Layout updates without exceptions | W | P0 |
| TC-LIFE-04 | ✅ Change `initialAnchor` / `initialSlotExtent` after mount | Ignored (initial-only); documented | W | P1 |
| TC-LIFE-05 | ✅ Zero-size and unbounded constraints | Zero size renders nothing; unbounded gives a clear assertion message | W | P1 |
| TC-LIFE-06 | ✅ Theme change (light ↔ dark) | Colours from caller-provided config update; state kept | W | P1 |
| TC-LIFE-07 | ✅ Very large values (1e12) and very small (1e-8) | Labels format; no overflow or precision collapse in scales | U | P1 |
| TC-LIFE-08 | ✅ Memory leak check over mount/unmount cycles | No leaked controllers, listeners or tickers (`leak_tracker`) | W | P1 |

### 15. Performance (§11)

| ID | Case | Expected | Lvl | Pri |
|---|---|---|---|---|
| TC-PERF-01 | R-PERF-3 budget: 60 visible candles, 3 lines, grid, crosshair, 50k data loaded, on a 2020-class mobile device | ≤ 8 ms per frame for build + layout + paint during pan. Expect this to fail with the widget-per-slot design; the result decides whether to move to render objects | P | P0 |
| TC-PERF-02 | Per-frame work during pan with 1k vs 50k items | Frame time independent of data length (R-PERF-2) | P | P0 |
| TC-PERF-03 | Zoomed fully out (slot extent 1 px) on a wide desktop viewport | Frame time recorded; worst case documented | P | P1 |
| TC-PERF-04 | ✅ Crosshair movement | Hover and tap rebuild and repaint only the layers whose `dependsOnHighlight` is true (the crosshair); the others are neither rebuilt nor repainted (R-PERF-4). Covered by `test/rebuild_scope_test.dart` | W | P1 |
| TC-PERF-05 | Live feed at 1 tick/s with 10k items | Frame time per tick within budget; time-tick rebuild cost recorded | P | P1 |

### 16. Visual regression (goldens, R-TEST-5)

| ID | Case | Expected | Lvl | Pri |
|---|---|---|---|---|
| TC-GOLD-01 | Each layer alone on a fixed dataset and zoom, light and dark | Matches golden | G | P1 |
| TC-GOLD-02 | All four axis placements | Matches golden | G | P1 |
| TC-GOLD-03 | Time axis at each zoom bucket of a daily series | Matches golden | G | P1 |
| TC-GOLD-04 | Crosshair over a real slot and over a projected slot | Matches golden | G | P1 |
| TC-GOLD-05 | Line with gaps, fill, and a latest-point marker | Matches golden | G | P2 |

### 17. Platforms (§12)

| ID | Case | Expected | Lvl | Pri |
|---|---|---|---|---|
| TC-PLAT-01 | Web (Chrome, Safari, Firefox): pan, wheel zoom, trackpad pan and pinch, crosshair | All work; no console errors | I | P0 |
| TC-PLAT-02 | macOS / Windows desktop: mouse, wheel, trackpad | All work | I | P1 |
| TC-PLAT-03 | iOS / Android: drag, pinch, long-press crosshair, tap | All work; no conflict with system back gestures | I | P0 |
| TC-PLAT-04 | High-DPI displays (DPR 1, 2, 3) | 1 px lines stay crisp; no gaps between segments | M, G | P1 |

### 18. Widgetbook demo smoke test (R-TEST-6)

Manual, run before each release against `widgetbook/`. It checks the demo
still exercises every feature; it doesn't replace the automated cases above.

| ID | Case | Expected | Lvl | Pri |
|---|---|---|---|---|
| TC-DEMO-01 | Open "Interactive chart" | Candles, volume, MA and axes render; feed shows Live and ticks every second | M | P1 |
| TC-DEMO-02 | Candles / Line toggle | Series switches; pulsing dot on the latest line point | M | P1 |
| TC-DEMO-03 | Pan to the left edge | Spinner shows top-left, one page loads, view does not jump; stops after 10 pages | M | P1 |
| TC-DEMO-04 | Pause, wait 30 s, resume | Missed bars filled flat; cadence stays 10 s | M | P1 |
| TC-DEMO-05 | Zoom in, then "Jump to latest" | Zoom resets to the initial slot extent and the view shows the newest bar | M | P1 |
| TC-DEMO-06 | Each knob, and the theme toggle | Applies (use case is recreated, by design of Widgetbook) | M | P2 |

### Exit criteria for production readiness

- All P0 cases written and passing in CI on every pull request (unit, widget
  and goldens on Linux; web integration on Chrome).
- All P1 cases written; any failures have an issue and an owner.
- Every ⚠ case resolved: either the code is fixed, or the deviation is
  accepted and documented in this file.
- TC-PERF-01 measured on a real device, with the result recorded here and an
  architecture decision taken if it misses the budget.
- Line coverage of `lib/src/` at 90 % or more, with no untested public API.
- TC-PLAT-01 and TC-PLAT-03 run on real browsers and devices within the
  release window.
