# interactive_chart

A generic, layer-based interactive time-series chart for Flutter
(candlesticks, lines, histograms, crosshair, pan/zoom, live and paginated data).
It is a proof of concept: see [docs/poc_notes.md](docs/poc_notes.md) for what is
and isn't implemented, and [docs/requirements.md](docs/requirements.md) for the
full specification.

## Widgetbook

A separate project in [widgetbook/](widgetbook/) demonstrates the chart:

```
cd widgetbook
flutter pub get
flutter run -d chrome
```

After adding or changing use cases, regenerate with
`dart run build_runner build -d`.

## Tests

```
flutter test
```
