import "dart:math" as math;

/// Demo-only OHLCV datum. Not part of the library's public API — the whole
/// point of R-DATA-1 is that callers bring their own type.
class Candle {
  const Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    this.ma20 = double.nan,
  });

  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;
  final double ma20;
}

/// Generates a synthetic daily OHLCV series (weekends skipped) with a
/// trailing 20-period moving average, for the widgetbook use case.
List<Candle> generateDemoCandles({
  int count = 500,
  DateTime? start,
  int seed = 7,
}) {
  final random = math.Random(seed);
  var t =
      start ?? DateTime.now().subtract(Duration(days: (count * 7 / 5).ceil()));
  var price = 100.0;
  final closes = <double>[];
  final candles = <Candle>[];

  while (candles.length < count) {
    if (t.weekday == DateTime.saturday) {
      t = t.add(const Duration(days: 2));
      continue;
    }
    if (t.weekday == DateTime.sunday) {
      t = t.add(const Duration(days: 1));
      continue;
    }

    final open = price;
    final drift = (random.nextDouble() - 0.48) * 4;
    final close = math.max<double>(1, open + drift);
    final high = math.max(open, close) + random.nextDouble() * 2;
    final low = math.max(0.5, math.min(open, close) - random.nextDouble() * 2);
    final volume = 1000 + random.nextDouble() * 5000;

    closes.add(close);
    final ma = closes.length >= 20
        ? closes.sublist(closes.length - 20).reduce((a, b) => a + b) / 20
        : double.nan;

    candles.add(
      Candle(
        time: t,
        open: open,
        high: high,
        low: low,
        close: close,
        volume: volume,
        ma20: ma,
      ),
    );
    price = close;
    t = t.add(const Duration(days: 1));
  }

  return candles;
}

/// Generates a page of `count` candles chronologically preceding
/// [existingFirst], for the pagination demo's "load older history" callback.
/// Weekends are skipped, and the page's last (most recent) close lines up
/// with [existingFirst]'s open so the series reads as continuous.
List<Candle> generateOlderCandlesPage(
  Candle existingFirst, {
  int count = 100,
  int seed = 11,
}) {
  final random = math.Random(seed ^ existingFirst.time.millisecondsSinceEpoch);
  var t = existingFirst.time;
  var price = existingFirst.open;
  final page = <Candle>[];

  while (page.length < count) {
    t = t.subtract(const Duration(days: 1));
    if (t.weekday == DateTime.saturday || t.weekday == DateTime.sunday) {
      continue;
    }

    final close = price;
    final drift = (random.nextDouble() - 0.48) * 4;
    final open = math.max<double>(1, close - drift);
    final high = math.max(open, close) + random.nextDouble() * 2;
    final low = math.max(0.5, math.min(open, close) - random.nextDouble() * 2);
    final volume = 1000 + random.nextDouble() * 5000;

    page.add(
      Candle(
        time: t,
        open: open,
        high: high,
        low: low,
        close: close,
        volume: volume,
      ),
    );
    price = open;
  }

  return page.reversed.toList();
}

/// Advances a live feed by one tick, for the subscription demo. Most ticks
/// update the last candle in place (R-DATA-12: a still-forming bar); every
/// [ticksPerBar]th tick rolls over into a brand-new candle instead
/// (R-DATA-9: appending must not disturb pan/zoom). Returns the updated
/// list and the (possibly reset) tick count.
(List<Candle> candles, int ticksInBar) tickLiveCandles(
  List<Candle> candles, {
  required int ticksInBar,
  required int ticksPerBar,
  required math.Random random,
}) {
  final last = candles.last;
  final drift = (random.nextDouble() - 0.5) * 0.6;
  final newClose = math.max(0.5, last.close + drift);
  final nextTicksInBar = ticksInBar + 1;

  if (nextTicksInBar >= ticksPerBar) {
    var nextTime = last.time.add(const Duration(days: 1));
    while (nextTime.weekday == DateTime.saturday ||
        nextTime.weekday == DateTime.sunday) {
      nextTime = nextTime.add(const Duration(days: 1));
    }
    candles.add(
      Candle(
        time: nextTime,
        open: newClose,
        high: newClose,
        low: newClose,
        close: newClose,
        volume: 1000 + random.nextDouble() * 1000,
      ),
    );
    return (candles, 0);
  }

  candles[candles.length - 1] = Candle(
    time: last.time,
    open: last.open,
    high: math.max(last.high, newClose),
    low: math.min(last.low, newClose),
    close: newClose,
    volume: last.volume + random.nextDouble() * 200,
  );
  return (candles, nextTicksInBar);
}
