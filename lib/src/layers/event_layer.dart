import "package:equatable/equatable.dart";
import "package:flutter/widgets.dart";
import "package:interactive_chart/src/chart_context.dart";
import "package:interactive_chart/src/layer.dart";

/// Something that happened on a day and is worth marking on the chart: a
/// dividend, an earnings report, a revenue release and so on.
///
/// The event belongs to the *day* of [time] (its time of day is ignored) and
/// is drawn at the first datum of that day.
class ChartEvent extends Equatable {
  const ChartEvent({
    required this.time,
    required this.title,
    required this.description,
    required this.icon,
    this.color = const Color(0xFF3B82F6),
  });

  /// The day the event happened on.
  final DateTime time;

  /// Short heading, shown in the details overlay.
  final String title;

  /// The details shown below the title in the overlay.
  final String description;

  /// The glyph drawn in the marker.
  final IconData icon;

  /// Background of the marker.
  final Color color;

  @override
  List<Object?> get props => [time, title, description, icon, color];
}

/// Look of the details card [EventLayer] shows when a marker is tapped.
/// For full control use [EventLayer.overlayBuilder] instead.
class EventOverlayConfig {
  const EventOverlayConfig({
    this.backgroundColor = const Color(0xFFFFFFFF),
    this.barrierColor = const Color(0x33000000),
    this.dismissOnBarrierTap = true,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.padding = const EdgeInsets.all(12),
    this.maxWidth = 280,
    this.boxShadow = const [
      BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4)),
    ],
    this.titleStyle = const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: Color(0xFF111111),
      decoration: TextDecoration.none,
    ),
    this.descriptionStyle = const TextStyle(
      fontSize: 12,
      color: Color(0xFF444444),
      decoration: TextDecoration.none,
    ),
    this.closeButton,
  });

  /// Fill of the card.
  final Color backgroundColor;

  /// Dimming drawn over the chart behind the card.
  final Color barrierColor;

  /// Whether a tap on the dimmed area outside the card closes the overlay.
  final bool dismissOnBarrierTap;

  /// Corner rounding of the card.
  final BorderRadius borderRadius;

  /// Space between the card's edge and its content.
  final EdgeInsets padding;

  /// The card is as wide as its text needs, up to this.
  final double maxWidth;

  /// Shadow under the card.
  final List<BoxShadow> boxShadow;

  /// Style of the title.
  final TextStyle titleStyle;

  /// Style of the description.
  final TextStyle descriptionStyle;

  /// Content of the close button, e.g. an `Icon`. Null draws a small cross.
  /// It is wrapped in the tappable button, so it needs no gesture handling.
  final Widget? closeButton;
}

/// Marks financial events on the chart with small icons, one per event, at
/// the day they happened on. Tapping an icon opens a card in the middle of
/// the chart with the event's title and description and a close button.
///
/// Icons rest on the bottom of the viewport, [bottomInsetFraction] of its
/// height up, so they can sit just above a bottom strip such as a
/// `HistogramLayer`'s (pass its `heightFraction`). Several events on the same
/// day stack upwards. When the chart is zoomed out so far that the icons of
/// neighbouring days would overlap, those icons are hidden until it is zoomed
/// back in. Put the layer after the other layers, so its icons and
/// card are drawn on top of them.
///
/// A day with no datum (a weekend, say) gets no marker, and events outside
/// the visible range are not built. Purely additive: it does not take part in
/// autoscale. The open card is remembered by the event, so it survives pans,
/// zooms and new data, and closes if its event is removed from [events].
class EventLayer<T> extends ChartLayer<T> {
  const EventLayer({
    required this.events,
    required this.timeOf,
    this.bottomInsetFraction = 0,
    this.iconSize = 14,
    this.iconColor = const Color(0xFFFFFFFF),
    this.overlay = const EventOverlayConfig(),
    this.overlayBuilder,
    this.onEventTap,
  }) : assert(
         bottomInsetFraction >= 0 && bottomInsetFraction < 1,
         "bottomInsetFraction must be in [0, 1)",
       );

  /// Key of the card (default or custom) while it is open.
  static const overlayKey = ValueKey("chart-event-overlay");

  /// Key of the default card's close button.
  static const closeButtonKey = ValueKey("chart-event-close");

  /// The events to mark, in any order.
  final List<ChartEvent> events;

  /// The time of a datum, to find the datum of an event's day.
  final DateTime Function(T datum) timeOf;

  /// How far above the bottom of the viewport the lowest icon rests, as a
  /// fraction of the viewport height.
  final double bottomInsetFraction;

  /// Size of the glyph inside the marker. The marker is a little larger.
  final double iconSize;

  /// Colour of the glyph.
  final Color iconColor;

  /// Look of the default details card.
  final EventOverlayConfig overlay;

  /// Builds the card in place of the default one, for full control. Call
  /// `close` to dismiss it. The dimmed barrier is still drawn around it.
  final Widget Function(
    BuildContext context,
    ChartEvent event,
    VoidCallback close,
  )?
  overlayBuilder;

  /// Called when a marker is tapped, before the card opens.
  final void Function(ChartEvent event)? onEventTap;

  @override
  Widget build(Size size, InteractiveChartContext ctx, List<T> data) =>
      _EventLayerView<T>(layer: this, size: size, ctx: ctx, data: data);

  /// Index of the first datum on the same calendar day as [day], or null.
  int? _slotOfDay(List<T> data, DateTime day) {
    int key(DateTime t) => t.year * 10000 + t.month * 100 + t.day;
    final target = key(day);
    var lo = 0;
    var hi = data.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (key(timeOf(data[mid])) < target) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo < data.length && key(timeOf(data[lo])) == target ? lo : null;
  }
}

class _EventLayerView<T> extends StatefulWidget {
  const _EventLayerView({
    required this.layer,
    required this.size,
    required this.ctx,
    required this.data,
  });

  final EventLayer<T> layer;
  final Size size;
  final InteractiveChartContext ctx;
  final List<T> data;

  @override
  State<_EventLayerView<T>> createState() => _EventLayerViewState<T>();
}

class _EventLayerViewState<T> extends State<_EventLayerView<T>> {
  ChartEvent? _selected;

  void _open(ChartEvent event) {
    widget.layer.onEventTap?.call(event);
    setState(() => _selected = event);
  }

  void _close() => setState(() => _selected = null);

  @override
  Widget build(BuildContext context) {
    final layer = widget.layer;
    final ctx = widget.ctx;
    final size = widget.size;

    final markerSize = layer.iconSize + 8;
    const gap = 2.0;
    final baseline = size.height * (1 - layer.bottomInsetFraction);

    // Events by slot, in the order given, so same-day events stack stably.
    final bySlot = <int, List<ChartEvent>>{};
    for (final event in layer.events) {
      final slot = layer._slotOfDay(widget.data, event.time);
      if (slot != null) {
        (bySlot[slot] ??= []).add(event);
      }
    }

    // Zoomed out far enough, neighbouring days' icons would overlap. Those
    // are left out (all the icons that touch, not just some of them), so the
    // result depends only on the zoom, never on where the chart is panned.
    final slots = bySlot.keys.toList()..sort();
    final crowded = <int>{};
    for (var i = 1; i < slots.length; i++) {
      if ((slots[i] - slots[i - 1]) * ctx.slotExtent < markerSize) {
        crowded
          ..add(slots[i - 1])
          ..add(slots[i]);
      }
    }

    final markers = <Widget>[];
    for (final MapEntry(key: slot, value: stack) in bySlot.entries) {
      if (crowded.contains(slot) ||
          slot < ctx.visibleStart - 1 ||
          slot > ctx.visibleEnd) {
        continue;
      }
      final x = ctx.xOf(slot);
      for (var k = 0; k < stack.length; k++) {
        final event = stack[k];
        markers.add(
          Positioned(
            key: ValueKey(event),
            left: x - markerSize / 2,
            top: baseline - (k + 1) * markerSize - k * gap,
            width: markerSize,
            height: markerSize,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _open(event),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: event.color,
                ),
                child: Center(
                  child: Icon(
                    event.icon,
                    size: layer.iconSize,
                    color: layer.iconColor,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    final selected = _selected;
    return Stack(
      children: [
        ...markers,
        if (selected != null && layer.events.contains(selected))
          Positioned.fill(child: _buildOverlay(context, selected)),
      ],
    );
  }

  Widget _buildOverlay(BuildContext context, ChartEvent event) {
    final layer = widget.layer;
    final config = layer.overlay;
    final card =
        layer.overlayBuilder?.call(context, event, _close) ??
        _EventCard(event: event, config: config, onClose: _close);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: config.dismissOnBarrierTap ? _close : null,
            child: ColoredBox(color: config.barrierColor),
          ),
        ),
        Center(
          // Swallows taps on the card, so they do not reach the barrier.
          child: GestureDetector(
            key: EventLayer.overlayKey,
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: card,
          ),
        ),
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.config,
    required this.onClose,
  });

  final ChartEvent event;
  final EventOverlayConfig config;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: config.maxWidth),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: config.backgroundColor,
        borderRadius: config.borderRadius,
        boxShadow: config.boxShadow,
      ),
      child: Padding(
        padding: config.padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(event.title, style: config.titleStyle)),
                const SizedBox(width: 8),
                GestureDetector(
                  key: EventLayer.closeButtonKey,
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: Semantics(
                    button: true,
                    label: "Close",
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child:
                          config.closeButton ??
                          _CloseGlyph(color: config.titleStyle.color),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(event.description, style: config.descriptionStyle),
          ],
        ),
      ),
    ),
  );
}

/// A small cross drawn with paths, so the card needs no icon font.
class _CloseGlyph extends StatelessWidget {
  const _CloseGlyph({required this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(14),
    painter: _CloseGlyphPainter(color ?? const Color(0xFF111111)),
  );
}

class _CloseGlyphPainter extends CustomPainter {
  const _CloseGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(Offset.zero, Offset(size.width, size.height), paint)
      ..drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(_CloseGlyphPainter old) => old.color != color;
}
