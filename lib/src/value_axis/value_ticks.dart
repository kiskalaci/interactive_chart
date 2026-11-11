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

/// [value] written with exactly [decimals] digits after the decimal point,
/// cropped toward zero instead of rounded: `1.239` at 2 decimals is `1.23`,
/// and `-1.239` is `-1.23`. Missing digits are padded with zeros (`5` is
/// `5.00`).
///
/// Works on the shortest decimal text that round-trips the double, so a value
/// the caller wrote as `0.29` stays `0.29` rather than becoming `0.28` through
/// binary representation error. Non-finite values return `value.toString()`.
String truncateToDecimals(double value, int decimals) {
  assert(decimals >= 0, "decimals must not be negative");
  if (!value.isFinite) {
    return value.toString();
  }
  final text = value.abs().toString();
  final exponentAt = text.indexOf("e");
  final mantissa = exponentAt == -1 ? text : text.substring(0, exponentAt);
  final exponent = exponentAt == -1
      ? 0
      : int.parse(text.substring(exponentAt + 1));
  final pointAt = mantissa.indexOf(".");
  final whole = pointAt == -1 ? mantissa : mantissa.substring(0, pointAt);
  final fraction = pointAt == -1 ? "" : mantissa.substring(pointAt + 1);

  // Every digit with the decimal point after the first `pointPosition` of them.
  final digits = whole + fraction;
  final pointPosition = whole.length + exponent;
  String integerPart;
  String fractionPart;
  if (pointPosition <= 0) {
    integerPart = "0";
    fractionPart = "${"0" * -pointPosition}$digits";
  } else if (pointPosition >= digits.length) {
    integerPart = digits + "0" * (pointPosition - digits.length);
    fractionPart = "";
  } else {
    integerPart = digits.substring(0, pointPosition);
    fractionPart = digits.substring(pointPosition);
  }
  // `0.5e1` style leading zeros do not occur in `toString()`, but keep the
  // integer part canonical anyway.
  integerPart = integerPart.replaceFirst(RegExp(r"^0+(?=\d)"), "");

  fractionPart = fractionPart.length >= decimals
      ? fractionPart.substring(0, decimals)
      : fractionPart.padRight(decimals, "0");
  final body = decimals == 0 ? integerPart : "$integerPart.$fractionPart";
  final isZero = !body.contains(RegExp("[1-9]"));
  return value < 0 && !isZero ? "-$body" : body;
}
