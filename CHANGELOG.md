## Unreleased

* `EventLayer` and `ChartEvent`: small icons for financial events (dividends, earnings, revenue) at the day they happened on. Tapping one opens a configurable card (`EventOverlayConfig`, or `overlayBuilder`) with the event's title and description and a close button. Icons that would overlap when zoomed out are hidden.
* A drag only pans the value axis (switching autoscale off) once its vertical travel reaches `verticalPanThreshold` (new parameter, default 16 px) and half its horizontal travel, so horizontal swipes no longer turn autoscale off by accident.
* `PriceTagLayer`: a horizontal line at the latest value of the dataset and a tag with that value on the value axis. The value is cropped, not rounded, to `precision` decimals (default 2).
* `ChartLayer.buildValueAxisOverlay` and `ChartLayer.measureValueAxisOverlayWidth`: optional hooks for layers that draw on the value-axis gutter.
* **Breaking:** time-axis tick weights are now the exported `TickMarkWeight` enum (each member has a `double value`) instead of `int`. `TimeAxisConfig.formatter` takes `(DateTime, TickMarkWeight)`.
* Added the intraday tick tiers `minute5`, `minute30`, `hour3`, `hour6` and `hour12`, matching TradingView's weights.
* `LineLayer.latestPointBuilder`: optional widget drawn on the series' latest point.
* `InteractiveChartController.jumpToLatest({slotExtent})`: optionally resets zoom too.
* Prepending older data keeps the viewport stationary (R-DATA-10).
* Interval inference for projected time slots works in seconds, so sub-minute bars are supported.
* A horizontal drag no longer switches autoscale off.
* Added a standalone `widgetbook/` project with an "Interactive chart" use case.

## 0.0.1

* TODO: Describe initial release.
