import "dart:math" as math;

/// How many decimals value labels need so adjacent ticks read differently:
/// enough to show the tick step exactly, and never fewer than two. Tiny
/// ranges (1e-8) would otherwise all print as `0.00`.
int valueDecimals(List<double> ticks) {
  if (ticks.length < 2) {
    return 2;
  }
  final step = (ticks[1] - ticks[0]).abs();
  if (!step.isFinite || step == 0) {
    return 2;
  }
  // The smallest number of decimals at which the step is a whole number of
  // units in the last place (within rounding error). Relative, so a tiny step
  // is not mistaken for zero.
  bool whole(double scaled) {
    final nearest = scaled.round();
    return nearest != 0 && (scaled - nearest).abs() <= 1e-6 * nearest;
  }

  var decimals = 0;
  var scaled = step;
  while (decimals < 12 && !whole(scaled)) {
    decimals++;
    scaled *= 10;
  }
  return math.max(2, decimals);
}

/// "Nice" step value-axis ticks (R-AXIS-8: 1/2/2.5/5/10 progression).
List<double> niceValueTicks(double min, double max, {int targetCount = 5}) {
  final lo = min == max ? min - 1 : min;
  final hi = min == max ? max + 1 : max;
  final range = hi - lo;
  final rawStep = range / targetCount;
  final magnitude = math
      .pow(10, (math.log(rawStep) / math.ln10).floor())
      .toDouble();
  final residual = rawStep / magnitude;
  // 1/2/2.5/5/10 progression (R-AXIS-8): round the raw step up to the next.
  double niceResidual;
  if (residual > 5) {
    niceResidual = 10;
  } else if (residual > 2.5) {
    niceResidual = 5;
  } else if (residual > 2) {
    niceResidual = 2.5;
  } else if (residual > 1) {
    niceResidual = 2;
  } else {
    niceResidual = 1;
  }
  final step = niceResidual * magnitude;
  final start = (lo / step).ceil() * step;

  final ticks = <double>[];
  for (var v = start; v <= hi + step * 1e-6; v += step) {
    ticks.add(v);
  }
  return ticks;
}
