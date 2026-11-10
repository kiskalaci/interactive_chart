// dart format width=80
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_import, prefer_relative_imports, directives_ordering

// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AppGenerator
// **************************************************************************

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:interactive_chart_widgetbook/widgets/interactive_chart_widgetbook.dart'
    as _interactive_chart_widgetbook_widgets_interactive_chart_widgetbook;
import 'package:interactive_chart_widgetbook/widgets/time_marks_widgetbook.dart'
    as _interactive_chart_widgetbook_widgets_time_marks_widgetbook;
import 'package:widgetbook/widgetbook.dart' as _widgetbook;

final directories = <_widgetbook.WidgetbookNode>[
  _widgetbook.WidgetbookComponent(
    name: 'InteractiveChart',
    useCases: [
      _widgetbook.WidgetbookUseCase(
        name: 'Interactive chart',
        builder:
            _interactive_chart_widgetbook_widgets_interactive_chart_widgetbook
                .interactiveChartUseCase,
      ),
      _widgetbook.WidgetbookUseCase(
        name: 'Time mark weights',
        builder: _interactive_chart_widgetbook_widgets_time_marks_widgetbook
            .timeMarkWeightsUseCase,
      ),
    ],
  ),
];
