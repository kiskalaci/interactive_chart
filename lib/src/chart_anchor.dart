/// Which edge of the viewport the chart is initially scrolled to — i.e.
/// where it starts building its candles from. This is purely about the
/// starting scroll position; it never mirrors the axis, since time always
/// runs left-to-right on screen (see `xOf`).
///
/// [ChartAnchor.left] leaves the viewport at the start of the data, so the
/// earliest slot sits at the left edge — e.g. an intraday chart, which
/// starts empty at market open and fills in candles as the session
/// progresses.
///
/// [ChartAnchor.right] scrolls to the end of the data on first layout, so
/// the newest slot sits at the right edge — e.g. a chart of historic data,
/// which should open already showing the most recent candle.
enum ChartAnchor { left, right }
