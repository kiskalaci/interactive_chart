import "dart:async";
import "dart:math" as math;

import "package:flutter/material.dart";
import "package:interactive_chart/candle.dart";
import "package:interactive_chart/interactive_chart.dart";
import "package:interactive_chart_widgetbook/color_palette.dart";
import "package:interactive_chart_widgetbook/time_mark_label.dart";
import "package:widgetbook/widgetbook.dart";
import "package:widgetbook_annotation/widgetbook_annotation.dart" as widgetbook;

/// One chart that combines the library's main features:
///
/// - a candle / line series toggle,
/// - an optional volume histogram,
/// - a latest-price line and axis tag (`PriceTagLayer`),
/// - a live subscription (10-second candles, one tick per second), and
/// - pagination that loads older history as the user pans back in time.
@widgetbook.UseCase(
  name: "Chart (subscription + pagination)",
  type: InteractiveChart,
)
Widget interactiveChartUseCase(BuildContext context) => _InteractiveChartDemo(
  initialAnchor: context.knobs.object.dropdown(
    label: "Initial anchor",
    options: ChartAnchor.values,
    labelBuilder: (v) => v.name,
    initialOption: ChartAnchor.right,
  ),
  valueAxisPlacement: context.knobs.object.dropdown(
    label: "Value axis placement",
    options: ValueAxisPlacement.values,
    labelBuilder: (v) => v.name,
    initialOption: ValueAxisPlacement.right,
  ),
  timeAxisPlacement: context.knobs.object.dropdown(
    label: "Time axis placement",
    options: TimeAxisPlacement.values,
    labelBuilder: (v) => v.name,
    initialOption: TimeAxisPlacement.bottom,
  ),
  initialSlotExtent: context.knobs.double.slider(
    label: "Initial slot extent",
    initialValue: 8,
    min: 1,
    max: 64,
  ),
  // Below 1, zooming out merges the candles of each pixel column into one.
  minSlotExtent: context.knobs.double.slider(
    label: "Min slot extent",
    initialValue: 1,
    min: 0.05,
    max: 1,
  ),
  showVolume: context.knobs.boolean(label: "Show volume", initialValue: true),
  showMovingAverage: context.knobs.boolean(
    label: "Show MA 20",
    initialValue: true,
  ),
  showPriceTag: context.knobs.boolean(
    label: "Show price tag",
    initialValue: true,
  ),
  priceTagPrecision: context.knobs.int.slider(
    label: "Price tag precision",
    initialValue: 2,
    min: 0,
    max: 6,
  ),
  panEnabled: context.knobs.boolean(label: "Pan enabled", initialValue: true),
  verticalPanThreshold: context.knobs.double.slider(
    label: "Vertical pan threshold",
    initialValue: 16,
    min: 0,
    max: 80,
  ),
  zoomEnabled: context.knobs.boolean(label: "Zoom enabled", initialValue: true),
  crosshairEnabled: context.knobs.boolean(
    label: "Crosshair enabled",
    initialValue: true,
  ),
);

enum _SeriesType { candles, line }

class _InteractiveChartDemo extends StatefulWidget {
  const _InteractiveChartDemo({
    required this.initialAnchor,
    required this.valueAxisPlacement,
    required this.timeAxisPlacement,
    required this.initialSlotExtent,
    required this.minSlotExtent,
    required this.showVolume,
    required this.showMovingAverage,
    required this.showPriceTag,
    required this.priceTagPrecision,
    required this.panEnabled,
    required this.verticalPanThreshold,
    required this.zoomEnabled,
    required this.crosshairEnabled,
  });

  final ChartAnchor initialAnchor;
  final ValueAxisPlacement valueAxisPlacement;
  final TimeAxisPlacement timeAxisPlacement;
  final double initialSlotExtent;
  final double minSlotExtent;
  final bool showVolume;
  final bool showMovingAverage;
  final bool showPriceTag;
  final int priceTagPrecision;
  final bool panEnabled;
  final double verticalPanThreshold;
  final bool zoomEnabled;
  final bool crosshairEnabled;

  @override
  State<_InteractiveChartDemo> createState() => _InteractiveChartDemoState();
}

class _InteractiveChartDemoState extends State<_InteractiveChartDemo> {
  static const _candleSeconds = 10;
  static const _tickInterval = Duration(seconds: 1);
  static const _pageSize = 180;
  static const _loadThresholdSlots = 20;
  static const _maxPages = 50;

  final _controller = InteractiveChartController();
  final _random = math.Random(3);
  late List<Candle> _candles = _withMovingAverage(_generateHistory(count: 200));
  Timer? _timer;

  _SeriesType _series = _SeriesType.candles;

  bool _subscribed = true;
  DateTime? _lastTickAt;

  bool _isLoadingOlder = false;
  bool _exhaustedOlder = false;
  int _pagesLoaded = 0;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // --- Data generation -----------------------------------------------------

  /// Start of the candle bucket containing [t].
  static DateTime _bucketStart(DateTime t) {
    const size = _candleSeconds * 1000;
    final ms = t.millisecondsSinceEpoch;
    return DateTime.fromMillisecondsSinceEpoch(ms - ms % size);
  }

  /// [count] completed candles ending just before the current bucket.
  List<Candle> _generateHistory({required int count}) {
    final random = math.Random(7);
    final first = _bucketStart(DateTime.now())
        .subtract(Duration(seconds: _candleSeconds * count));
    var price = 100.0;
    final candles = <Candle>[];
    for (var i = 0; i < count; i++) {
      final open = price;
      final close = math.max(1.0, open + (random.nextDouble() - 0.5) * 1.2);
      price = close;
      candles.add(
        Candle(
          time: first.add(Duration(seconds: _candleSeconds * i)),
          open: open,
          high: math.max(open, close) + random.nextDouble() * 0.5,
          low: math.max(0.5, math.min(open, close) - random.nextDouble() * 0.5),
          close: close,
          volume: 100 + random.nextDouble() * 500,
        ),
      );
    }
    return candles;
  }

  /// A page of [_pageSize] candles immediately preceding [existingFirst],
  /// with its last close lined up against [existingFirst]'s open.
  List<Candle> _generateOlderPage(Candle existingFirst) {
    final random = math.Random(existingFirst.time.millisecondsSinceEpoch);
    var price = existingFirst.open;
    final page = <Candle>[];
    for (var i = 1; i <= _pageSize; i++) {
      final close = price;
      final open = math.max(1.0, close - (random.nextDouble() - 0.5) * 1.2);
      price = open;
      page.add(
        Candle(
          time: existingFirst.time.subtract(
            Duration(seconds: _candleSeconds * i),
          ),
          open: open,
          high: math.max(open, close) + random.nextDouble() * 0.5,
          low: math.max(0.5, math.min(open, close) - random.nextDouble() * 0.5),
          close: close,
          volume: 100 + random.nextDouble() * 500,
        ),
      );
    }
    return page.reversed.toList();
  }

  /// Returns [candles] with [Candle.ma20] filled in (NaN until 20 closes).
  static List<Candle> _withMovingAverage(List<Candle> candles) {
    const period = 20;
    var sum = 0.0;
    return [
      for (var i = 0; i < candles.length; i++)
        () {
          final c = candles[i];
          sum += c.close;
          if (i >= period) {
            sum -= candles[i - period].close;
          }
          return Candle(
            time: c.time,
            open: c.open,
            high: c.high,
            low: c.low,
            close: c.close,
            volume: c.volume,
            ma20: i >= period - 1 ? sum / period : double.nan,
          );
        }(),
    ];
  }

  // --- Subscription --------------------------------------------------------

  void _subscribe() {
    _onTick(); // Deliver one immediately so the forming candle shows at once.
    _timer = Timer.periodic(_tickInterval, (_) => _onTick());
  }

  void _toggleSubscription() {
    setState(() => _subscribed = !_subscribed);
    if (_subscribed) {
      _subscribe();
    } else {
      _timer?.cancel();
    }
  }

  /// Updates the forming candle in place (R-DATA-12), or appends a new one
  /// when the clock has entered a new bucket (R-DATA-9).
  void _onTick() {
    final now = DateTime.now();
    final bucket = _bucketStart(now);
    final last = _candles.last;
    final newClose = math.max(
      0.5,
      last.close + (_random.nextDouble() - 0.5) * 0.6,
    );
    final candles = List<Candle>.of(_candles);

    if (bucket.isAfter(last.time)) {
      // Fill buckets missed while paused with flat candles so the series
      // keeps a constant cadence.
      final prevClose = last.close;
      var t = last.time.add(const Duration(seconds: _candleSeconds));
      while (t.isBefore(bucket)) {
        candles.add(
          Candle(
            time: t,
            open: prevClose,
            high: prevClose,
            low: prevClose,
            close: prevClose,
            volume: 0,
          ),
        );
        t = t.add(const Duration(seconds: _candleSeconds));
      }
      candles.add(
        Candle(
          time: bucket,
          open: prevClose,
          high: math.max(prevClose, newClose),
          low: math.min(prevClose, newClose),
          close: newClose,
          volume: 100 + _random.nextDouble() * 100,
        ),
      );
    } else {
      candles[candles.length - 1] = Candle(
        time: last.time,
        open: last.open,
        high: math.max(last.high, newClose),
        low: math.min(last.low, newClose),
        close: newClose,
        volume: last.volume + _random.nextDouble() * 50,
      );
    }

    setState(() {
      _candles = _withMovingAverage(candles);
      _lastTickAt = now;
    });
  }

  // --- Pagination ----------------------------------------------------------

  /// Driven by [InteractiveChart.onVisibleRangeChanged] (R-PAGE-1/2), with an
  /// in-flight guard (R-PAGE-7) and an exhausted latch (R-PAGE-8). A
  /// `Future.delayed` stands in for a network fetch.
  ///
  /// The POC doesn't keep the view stationary across a prepend (R-DATA-10),
  /// so the chart jumps once an older page lands.
  void _onVisibleRangeChanged(int start, int end) {
    if (start > _loadThresholdSlots || _isLoadingOlder || _exhaustedOlder) {
      return;
    }
    _loadOlderPage();
  }

  Future<void> _loadOlderPage() async {
    setState(() => _isLoadingOlder = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) {
      return;
    }
    // Build from the current first candle: the live feed may have changed the
    // list while the "request" was in flight.
    final page = _generateOlderPage(_candles.first);
    _pagesLoaded++;
    setState(() {
      _candles = _withMovingAverage([...page, ..._candles]);
      _isLoadingOlder = false;
      _exhaustedOlder = _pagesLoaded >= _maxPages;
    });
  }

  // --- UI ------------------------------------------------------------------

  String _lastTickLabel() {
    final at = _lastTickAt;
    if (at == null) {
      return "Waiting for first tick…";
    }
    String two(int n) => n.toString().padLeft(2, "0");
    return "Last tick: ${two(at.hour)}:${two(at.minute)}:${two(at.second)}";
  }

  String _historyLabel() {
    if (_exhaustedOlder) {
      return "No more history";
    }
    if (_isLoadingOlder) {
      return "Loading older candles…";
    }
    return "Pan left to load history ($_pagesLoaded page(s) loaded)";
  }

  @override
  Widget build(BuildContext context) {
    final colors = ColorPalette.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<_SeriesType>(
                segments: const [
                  ButtonSegment(
                    value: _SeriesType.candles,
                    label: Text("Candles"),
                    icon: Icon(Icons.candlestick_chart),
                  ),
                  ButtonSegment(
                    value: _SeriesType.line,
                    label: Text("Line"),
                    icon: Icon(Icons.show_chart),
                  ),
                ],
                selected: {_series},
                onSelectionChanged: (s) => setState(() => _series = s.first),
              ),
              FilledButton(
                onPressed: () => _controller.jumpToLatest(
                  slotExtent: widget.initialSlotExtent,
                ),
                child: const Text("Jump to latest"),
              ),
              OutlinedButton(
                onPressed: _toggleSubscription,
                child: Text(_subscribed ? "Pause feed" : "Resume feed"),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.circle,
                    size: 10,
                    color: _subscribed ? colors.green : colors.red,
                  ),
                  const SizedBox(width: 4),
                  Text(_subscribed ? "Live" : "Paused"),
                ],
              ),
              Text(_lastTickLabel()),
              Text(_historyLabel()),
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: _controller.autoscale,
                      onChanged: (v) => _controller.setAutoscale(v ?? true),
                    ),
                    const Text("Autoscale"),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveChart<Candle>(
                    // The zoom limits are read once, so a new limit needs a
                    // new chart.
                    key: ValueKey(widget.minSlotExtent),
                    controller: _controller,
                    minSlotExtent: widget.minSlotExtent,
                    data: _candles,
                    timeOf: (c) => c.time,
                    initialAnchor: widget.initialAnchor,
                    initialSlotExtent: widget.initialSlotExtent,
                    panEnabled: widget.panEnabled,
                    verticalPanThreshold: widget.verticalPanThreshold,
                    zoomEnabled: widget.zoomEnabled,
                    crosshairEnabled: widget.crosshairEnabled,
                    onVisibleRangeChanged: _onVisibleRangeChanged,
                    valueAxis: ValueAxisConfig(
                      placement: widget.valueAxisPlacement,
                    ),
                    timeAxis: TimeAxisConfig(
                      placement: widget.timeAxisPlacement,
                      formatter: formatTimeMark,
                    ),
                    layers: [
                      const GridLayer<Candle>(),
                      if (widget.showVolume)
                        HistogramLayer<Candle>(
                          heightFraction: 0.1,
                          valueOf: (c) => c.volume,
                          color: colors.blue.withValues(alpha: 0.4),
                        ),
                      switch (_series) {
                        _SeriesType.candles => CandleLayer<Candle>(
                          openOf: (c) => c.open,
                          highOf: (c) => c.high,
                          lowOf: (c) => c.low,
                          closeOf: (c) => c.close,
                          upColor: colors.green,
                          downColor: colors.red,
                        ),
                        _SeriesType.line => LineLayer<Candle>(
                          valueOf: (c) => c.close,
                          color: colors.blue,
                          fill: true,
                          latestPointBuilder: (context, candle, index) =>
                              PulsingDot(color: colors.blue),
                        ),
                      },
                      if (widget.showMovingAverage)
                        LineLayer<Candle>(
                          valueOf: (c) => c.ma20,
                          color: colors.purple,
                        ),
                      if (widget.showPriceTag)
                        PriceTagLayer<Candle>(
                          valueOf: (c) => c.close,
                          precision: widget.priceTagPrecision,
                          lineColor: colors.blue.withValues(alpha: 0.6),
                          tagColor: colors.blue,
                        ),
                      CrosshairLayer<Candle>(
                        valueOf: (c) => c.close,
                        timeOf: (c) => c.time,
                      ),
                    ],
                  ),
                ),
                // Top-left loading indicator, pushed below the 22px time axis
                // when that axis sits at the top.
                Positioned(
                  left: 8,
                  top: widget.timeAxisPlacement == TimeAxisPlacement.top
                      ? 30
                      : 8,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _isLoadingOlder ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Color(0xFF00E676),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
