## Unreleased

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
