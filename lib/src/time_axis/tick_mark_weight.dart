/// How important a time-axis mark is: the coarsest calendar or clock
/// boundary it crosses relative to the previous slot. The tiers and values
/// follow TradingView's weight ladder.
///
/// The weight decides which marks survive when labels would collide (heavier
/// marks win) and how a mark is formatted and styled.
///
/// [value] is the numeric rank.
enum TickMarkWeight implements Comparable<TickMarkWeight> {
  /// The second changed (or nothing coarser did).
  second(10),

  /// The minute changed.
  minute1(20),

  /// A 5-minute boundary was crossed.
  minute5(21),

  /// A 30-minute boundary was crossed.
  minute30(22),

  /// The hour changed.
  hour1(30),

  /// A 3-hour boundary was crossed.
  hour3(31),

  /// A 6-hour boundary was crossed.
  hour6(32),

  /// A 12-hour boundary (midnight or noon) was crossed.
  hour12(33),

  /// The day changed.
  day(50),

  /// The month changed.
  month(60),

  /// The year changed.
  year(70);

  const TickMarkWeight(this.value);

  /// Numeric rank; a larger value is a coarser boundary.
  final double value;

  @override
  int compareTo(TickMarkWeight other) => value.compareTo(other.value);

  /// Whether this weight is coarser than [other].
  bool operator >(TickMarkWeight other) => value > other.value;

  /// Whether this weight is at least as coarse as [other].
  bool operator >=(TickMarkWeight other) => value >= other.value;

  /// Whether this weight is finer than [other].
  bool operator <(TickMarkWeight other) => value < other.value;

  /// Whether this weight is at most as coarse as [other].
  bool operator <=(TickMarkWeight other) => value <= other.value;
}
