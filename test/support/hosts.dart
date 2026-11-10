import "dart:async";

import "package:flutter/material.dart";
import "package:interactive_chart/interactive_chart.dart";
import "package:interactive_chart/src/chart_context.dart";

import "chart_harness.dart";

/// Implements the documented paging pattern on top of the chart: the load
/// threshold, an in-flight guard and an exhausted latch, driven from
/// `onVisibleRangeChanged`. The fetch is supplied by the test, which decides
/// when (and with what) each request completes.
class PagingHost extends StatefulWidget {
  const PagingHost({
    required this.fetch,
    this.firstId = 1000,
    this.count = 400,
    this.anchor = ChartAnchor.right,
    this.thresholdSlots = 20,
    this.maxPages = 1000,
    this.valueOf,
    this.width,
    super.key,
  });

  /// Returns the older ids, ascending, ending just before `beforeId`. An
  /// empty list means there is no more history.
  final Future<List<int>> Function(int beforeId) fetch;
  final int firstId;
  final int count;
  final ChartAnchor anchor;
  final int thresholdSlots;
  final int maxPages;
  final double Function(int id)? valueOf;
  final double? width;

  @override
  State<PagingHost> createState() => PagingHostState();
}

class PagingHostState extends State<PagingHost> {
  late List<int> data = intSeries(
    widget.firstId,
    widget.firstId + widget.count,
  );
  final controller = InteractiveChartController();
  late InteractiveChartContext ctx;

  int requests = 0;
  int pagesLoaded = 0;
  bool loading = false;
  bool exhausted = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _onRange(int start, int end) {
    if (start > widget.thresholdSlots ||
        loading ||
        exhausted ||
        pagesLoaded >= widget.maxPages) {
      return;
    }
    _load();
  }

  Future<void> _load() async {
    requests++;
    setState(() => loading = true);
    final page = await widget.fetch(data.first);
    if (!mounted) {
      return; // R-PAGE-11: discard a result that arrives after dispose.
    }
    setState(() {
      loading = false;
      if (page.isEmpty) {
        exhausted = true;
      } else {
        pagesLoaded++;
        data = [...page, ...data];
      }
    });
  }

  /// [count] older bars arriving at the front, outside the load flow.
  void prepend(int count) {
    setState(
      () => data = [
        for (var i = data.first - count; i < data.first; i++) i,
        ...data,
      ],
    );
  }

  /// A live bar arriving at the newest end.
  void appendLive(int count) {
    setState(
      () =>
          data = [...data, ...intSeries(data.last + 1, data.last + 1 + count)],
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        // Fills the screen unless a width is given.
        width: widget.width ?? double.infinity,
        height: double.infinity,
        child: InteractiveChart<int>(
          controller: controller,
          data: data,
          timeOf: minuteTime,
          initialAnchor: widget.anchor,
          valueAxis: null,
          timeAxis: null,
          onVisibleRangeChanged: _onRange,
          layers: [
            LineLayer<int>(valueOf: widget.valueOf ?? (id) => 100.0 + id % 13),
            ContextProbe<int>((c) => ctx = c),
          ],
        ),
      ),
    ),
  );
}

/// One live bar: ten-second cadence, time taken from a fake clock.
class LiveBar {
  const LiveBar(this.time, this.close);
  final DateTime time;
  final double close;
}

/// A subscription feeding the chart: one tick per second updates the forming
/// bar in place, and a tick that crosses a 10-second boundary appends a new
/// bar. Time comes from a counter, never from the wall clock.
class LiveHost extends StatefulWidget {
  const LiveHost({
    this.history = 100,
    this.anchor = ChartAnchor.right,
    this.crosshair = false,
    super.key,
  });

  final int history;
  final ChartAnchor anchor;
  final bool crosshair;

  static final DateTime base = DateTime(2024, 1, 1, 12);

  @override
  State<LiveHost> createState() => LiveHostState();
}

class LiveHostState extends State<LiveHost> {
  static const barSeconds = 10;

  final controller = InteractiveChartController();
  late InteractiveChartContext ctx;
  late List<LiveBar> bars = [
    for (var i = 0; i < widget.history; i++)
      LiveBar(
        LiveHost.base.subtract(
          Duration(seconds: barSeconds * (widget.history - 1 - i)),
        ),
        100.0 + i % 9,
      ),
  ];
  int ticks = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    controller.dispose();
    super.dispose();
  }

  double closeAt(int n) => 100.0 + (n * 3) % 7;

  void tick() {
    ticks++;
    final now = LiveHost.base.add(Duration(seconds: ticks));
    final bucket = DateTime.fromMillisecondsSinceEpoch(
      now.millisecondsSinceEpoch -
          now.millisecondsSinceEpoch % (barSeconds * 1000),
    );
    final close = closeAt(ticks);
    setState(() {
      if (bucket.isAfter(bars.last.time)) {
        bars = [...bars, LiveBar(bucket, close)];
      } else {
        bars = [...bars]..[bars.length - 1] = LiveBar(bars.last.time, close);
      }
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: InteractiveChart<LiveBar>(
          controller: controller,
          data: bars,
          timeOf: (b) => b.time,
          initialAnchor: widget.anchor,
          valueAxis: null,
          timeAxis: null,
          crosshairEnabled: widget.crosshair,
          layers: [
            LineLayer<LiveBar>(valueOf: (b) => b.close),
            if (widget.crosshair)
              CrosshairLayer<LiveBar>(
                valueOf: (b) => b.close,
                timeOf: (b) => b.time,
                labelBackground: const Color(0xFF222BBB),
              ),
            ContextProbe<LiveBar>((c) => ctx = c),
          ],
        ),
      ),
    ),
  );
}
