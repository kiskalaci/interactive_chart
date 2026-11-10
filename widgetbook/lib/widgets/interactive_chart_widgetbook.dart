import "dart:async";
import "dart:math" as math;

import "package:flutter/material.dart";
import "package:interactive_chart_widgetbook/color_palette.dart";
import "package:interactive_chart/candle.dart";
import "package:interactive_chart/interactive_chart.dart";
import "package:widgetbook/widgetbook.dart";
import "package:widgetbook_annotation/widgetbook_annotation.dart" as widgetbook;

@widgetbook.UseCase(name: "Candles + volume + MA", type: InteractiveChart)
Widget defaultUseCase(BuildContext context) => _InteractiveChartDemo(
  initialAnchor: context.knobs.object.dropdown(
    label: "Initial anchor",
    options: ChartAnchor.values,
    labelBuilder: (v) => v.name,
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
  panEnabled: context.knobs.boolean(label: "Pan enabled", initialValue: true),
  zoomEnabled: context.knobs.boolean(label: "Zoom enabled", initialValue: true),
  crosshairEnabled: context.knobs.boolean(
    label: "Crosshair enabled",
    initialValue: true,
  ),
);

class _InteractiveChartDemo extends StatefulWidget {
  const _InteractiveChartDemo({
    required this.initialAnchor,
    required this.valueAxisPlacement,
    required this.timeAxisPlacement,
    required this.initialSlotExtent,
    required this.panEnabled,
    required this.zoomEnabled,
    required this.crosshairEnabled,
  });

  final ChartAnchor initialAnchor;
  final ValueAxisPlacement valueAxisPlacement;
  final TimeAxisPlacement timeAxisPlacement;
  final double initialSlotExtent;
  final bool panEnabled;
  final bool zoomEnabled;
  final bool crosshairEnabled;

  @override
  State<_InteractiveChartDemo> createState() => _InteractiveChartDemoState();
}

class _InteractiveChartDemoState extends State<_InteractiveChartDemo> {
  late final List<Candle> _candles = generateDemoCandles();
  final _controller = InteractiveChartController();
  int? _tappedIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ColorPalette.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              FilledButton(
                onPressed: _controller.jumpToLatest,
                child: const Text("Jump to latest"),
              ),
              const SizedBox(width: 8),
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
              const SizedBox(width: 16),
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final (start, end) = _controller.visibleRange;
                  return Text(
                    "visible: [$start, $end) · slotExtent=${_controller.slotExtent.toStringAsFixed(1)}",
                  );
                },
              ),
              const SizedBox(width: 16),
              Text(
                _tappedIndex == null
                    ? "Tap a candle"
                    : "Tapped candle: $_tappedIndex",
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: InteractiveChart<Candle>(
              controller: _controller,
              data: _candles,
              timeOf: (c) => c.time,
              initialAnchor: widget.initialAnchor,
              initialSlotExtent: widget.initialSlotExtent,
              panEnabled: widget.panEnabled,
              zoomEnabled: widget.zoomEnabled,
              crosshairEnabled: widget.crosshairEnabled,
              valueAxis: ValueAxisConfig(placement: widget.valueAxisPlacement),
              timeAxis: TimeAxisConfig(placement: widget.timeAxisPlacement),
              layers: [
                const GridLayer<Candle>(),
                HistogramLayer<Candle>(
                  heightFraction: 0.1,
                  valueOf: (c) => c.volume,
                  color: colors.blue.withValues(alpha: 0.4),
                ),
                CandleLayer<Candle>(
                  openOf: (c) => c.open,
                  highOf: (c) => c.high,
                  lowOf: (c) => c.low,
                  closeOf: (c) => c.close,
                  upColor: colors.green,
                  downColor: colors.red,
                  onTap: (index) => setState(() => _tappedIndex = index),
                ),
                LineLayer<Candle>(valueOf: (c) => c.ma20, color: colors.purple),
                CrosshairLayer<Candle>(
                  valueOf: (c) => c.close,
                  timeOf: (c) => c.time,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Loads older history as the user scrolls back in time, driven by
/// [InteractiveChart.onVisibleRangeChanged] (R-PAGE-1/2). Mirrors the shape
/// of the fuller `R-PAGE-*` contract in `docs/requirements.md` §4.4 — an
/// in-flight guard (R-PAGE-7) and an exhausted latch (R-PAGE-8) — using a
/// `Future.delayed` in place of a real network fetch.
///
/// The POC doesn't implement R-DATA-10 (keeping the view visually stationary
/// across a prepend — see `docs/poc_notes.md`), so panning past the load
/// threshold does cause a visible jump once the older page lands; a
/// production data source would want that compensation added to the widget
/// itself rather than worked around here.
@widgetbook.UseCase(name: "Candle pagination", type: InteractiveChart)
Widget paginationUseCase(BuildContext context) => const _PaginationDemo();

class _PaginationDemo extends StatefulWidget {
  const _PaginationDemo();

  @override
  State<_PaginationDemo> createState() => _PaginationDemoState();
}

class _PaginationDemoState extends State<_PaginationDemo> {
  static const _loadThresholdSlots = 20;
  static const _maxPages = 4;

  final _controller = InteractiveChartController();
  late List<Candle> _candles = generateDemoCandles(count: 150);
  bool _isLoadingOlder = false;
  bool _exhaustedOlder = false;
  int _pagesLoaded = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onVisibleRangeChanged(int start, int end) {
    if (start > _loadThresholdSlots || _isLoadingOlder || _exhaustedOlder) {
      return;
    }
    _loadOlderPage();
  }

  Future<void> _loadOlderPage() async {
    setState(() => _isLoadingOlder = true);

    // Simulates a network round-trip; a real caller would fetch here instead.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) {
      return;
    }

    final page = generateOlderCandlesPage(_candles.first);
    _pagesLoaded++;
    setState(() {
      _candles = [...page, ..._candles];
      _isLoadingOlder = false;
      _exhaustedOlder = _pagesLoaded >= _maxPages;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = ColorPalette.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              FilledButton(
                onPressed: _controller.jumpToLatest,
                child: const Text("Jump to latest"),
              ),
              const SizedBox(width: 16),
              Text(
                _exhaustedOlder
                    ? "No more history"
                    : _isLoadingOlder
                    ? "Loading older candles…"
                    : "Pan left to load history ($_pagesLoaded page(s) loaded)",
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: InteractiveChart<Candle>(
              controller: _controller,
              data: _candles,
              timeOf: (c) => c.time,
              onVisibleRangeChanged: _onVisibleRangeChanged,
              valueAxis: const ValueAxisConfig(),
              timeAxis: const TimeAxisConfig(),
              layers: [
                const GridLayer<Candle>(),
                HistogramLayer<Candle>(
                  heightFraction: 0.1,
                  valueOf: (c) => c.volume,
                  color: colors.blue.withValues(alpha: 0.4),
                ),
                CandleLayer<Candle>(
                  openOf: (c) => c.open,
                  highOf: (c) => c.high,
                  lowOf: (c) => c.low,
                  closeOf: (c) => c.close,
                  upColor: colors.green,
                  downColor: colors.red,
                ),
                CrosshairLayer<Candle>(
                  valueOf: (c) => c.close,
                  timeOf: (c) => c.time,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Simulates a live candle subscription. Most ticks update the last candle
/// in place (R-DATA-12); every few ticks it rolls over into a brand-new bar
/// instead (append), demonstrating that appending must not disturb the
/// user's current pan/zoom (R-DATA-9) — panning away from the latest candle
/// and letting the feed keep ticking leaves the viewport exactly where the
/// user left it.
@widgetbook.UseCase(name: "Candle subscription", type: InteractiveChart)
Widget subscriptionUseCase(BuildContext context) => const _SubscriptionDemo();

class _SubscriptionDemo extends StatefulWidget {
  const _SubscriptionDemo();

  @override
  State<_SubscriptionDemo> createState() => _SubscriptionDemoState();
}

class _SubscriptionDemoState extends State<_SubscriptionDemo> {
  static const _ticksPerBar = 6;

  final _controller = InteractiveChartController();
  final _random = math.Random(3);
  late List<Candle> _candles = generateDemoCandles(count: 300);
  Timer? _timer;
  int _ticksInBar = 0;
  bool _subscribed = true;
  DateTime? _lastTickAt;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    _timer = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => _onTick(),
    );
  }

  void _onTick() {
    final (candles, ticksInBar) = tickLiveCandles(
      _candles,
      ticksInBar: _ticksInBar,
      ticksPerBar: _ticksPerBar,
      random: _random,
    );
    setState(() {
      _candles = candles;
      _ticksInBar = ticksInBar;
      _lastTickAt = DateTime.now();
    });
  }

  void _toggleSubscription() {
    setState(() => _subscribed = !_subscribed);
    if (_subscribed) {
      _subscribe();
    } else {
      _timer?.cancel();
    }
  }

  String _lastTickLabel() {
    final at = _lastTickAt;
    if (at == null) {
      return "Waiting for first tick…";
    }
    String two(int n) => n.toString().padLeft(2, "0");
    return "Last tick: ${two(at.hour)}:${two(at.minute)}:${two(at.second)}";
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ColorPalette.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              FilledButton(
                onPressed: _controller.jumpToLatest,
                child: const Text("Jump to latest"),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _toggleSubscription,
                child: Text(_subscribed ? "Pause feed" : "Resume feed"),
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.circle,
                size: 10,
                color: _subscribed ? colors.green : colors.red,
              ),
              const SizedBox(width: 4),
              Text(_subscribed ? "Live" : "Paused"),
              const SizedBox(width: 16),
              Text(_lastTickLabel()),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: InteractiveChart<Candle>(
              controller: _controller,
              data: _candles,
              timeOf: (c) => c.time,
              valueAxis: const ValueAxisConfig(),
              timeAxis: const TimeAxisConfig(),
              layers: [
                const GridLayer<Candle>(),
                HistogramLayer<Candle>(
                  heightFraction: 0.1,
                  valueOf: (c) => c.volume,
                  color: colors.blue.withValues(alpha: 0.4),
                ),
                CandleLayer<Candle>(
                  openOf: (c) => c.open,
                  highOf: (c) => c.high,
                  lowOf: (c) => c.low,
                  closeOf: (c) => c.close,
                  upColor: colors.green,
                  downColor: colors.red,
                ),
                CrosshairLayer<Candle>(
                  valueOf: (c) => c.close,
                  timeOf: (c) => c.time,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
