import 'dart:math' as math;

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/search/search_history.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Shared measuring for persistence's normal-window budget and visible rows.
/// Only whole newest rows are shown; hidden older entries keep their identity.
class SearchHistoryLayout {
  SearchHistoryLayout({
    required List<String> queries,
    required double width,
    required double height,
    required TextStyle style,
    required TextScaler scaler,
    required TextDirection direction,
  }) {
    final measure =
        TextPainter(textDirection: direction, textScaler: scaler, maxLines: 1);
    try {
      measure.text = TextSpan(text: 'Ag国', style: style);
      measure.layout();
      rowHeight = math.max(40, measure.height + 16);
      double used = 0;
      int row = 0;
      for (final query in queries) {
        measure.text = TextSpan(text: query, style: style);
        measure.layout();
        final itemWidth = math.min(width, math.max(48.0, measure.width + 32));
        if (used > 0 && used + gap + itemWidth > width + .01) {
          row++;
          used = 0;
        }
        if (width < 48 || (row + 1) * rowHeight + row * gap > height) break;
        widths.add(itemWidth);
        used += (used == 0 ? 0 : gap) + itemWidth;
      }
    } finally {
      measure.dispose();
    }
  }

  static const gap = 8.0;
  static const normalWidth = 560.0;
  static const normalHeight = 184.0;
  late final double rowHeight;
  final widths = <double>[];
}

TextStyle _historyStyle(BuildContext context) =>
    (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
        .copyWith(fontSize: 14);

Future<void> rememberSearch(
    BuildContext context, SearchHistoryStore history, String query) async {
  final style = _historyStyle(context);
  final direction = Directionality.of(context);
  try {
    await history.record(query,
        capacity: (queries) => SearchHistoryLayout(
              queries: queries,
              width: SearchHistoryLayout.normalWidth,
              height: SearchHistoryLayout.normalHeight,
              style: style,
              scaler: TextScaler.noScaling,
              direction: direction,
            ).widths.length);
  } catch (error, trace) {
    LOGGER.w('[search history] $error', stackTrace: trace);
    if (context.mounted) {
      showAppNotice(ui('搜索历史保存失败'),
          context: context, kind: AppNoticeKind.error);
    }
  }
}

class SearchHistoryCapsules extends StatefulWidget {
  const SearchHistoryCapsules(
      {super.key, required this.history, required this.onSearch});

  final SearchHistoryStore history;
  final ValueChanged<String> onSearch;

  @override
  State<SearchHistoryCapsules> createState() => _SearchHistoryCapsulesState();
}

class _SearchHistoryCapsulesState extends State<SearchHistoryCapsules> {
  String? _armed;
  String? _deleting;

  Future<void> _activate(String query) async {
    if (_deleting != null) return;
    if (_armed != query) {
      setState(() => _armed = null);
      widget.onSearch(query);
      return;
    }
    setState(() => _deleting = query);
    try {
      await widget.history.remove(query);
      if (mounted) setState(() => _armed = null);
    } catch (error, trace) {
      LOGGER.w('[delete search history] $error', stackTrace: trace);
      if (mounted) {
        showAppNotice(ui('搜索历史删除失败'),
            context: context, kind: AppNoticeKind.error);
      }
    } finally {
      if (mounted) setState(() => _deleting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final style = _historyStyle(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          setState(() => _armed = null);
        }
      },
      child: ValueListenableBuilder<List<String>>(
        valueListenable: widget.history,
        builder: (context, queries, _) => LayoutBuilder(
          builder: (context, constraints) {
            final layout = SearchHistoryLayout(
                queries: queries,
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                style: style,
                scaler: MediaQuery.textScalerOf(context),
                direction: Directionality.of(context));
            return Align(
              alignment: Alignment.topCenter,
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: SearchHistoryLayout.gap,
                runSpacing: SearchHistoryLayout.gap,
                children: [
                  for (var index = 0; index < layout.widths.length; index++)
                    SizedBox(
                      key: ValueKey(('search-history', queries[index])),
                      width: layout.widths[index],
                      height: layout.rowHeight,
                      child: Builder(builder: (context) {
                        final query = queries[index];
                        final armed = _armed == query;
                        void arm() =>
                            setState(() => _armed = armed ? null : query);
                        return Semantics(
                          button: true,
                          label: armed ? ui('删除搜索历史：{0}', [query]) : query,
                          hint: ui('右键点击或长按以删除'),
                          child: Tooltip(
                            message: armed ? ui('再次点击删除') : query,
                            child: GestureDetector(
                              onSecondaryTap: arm,
                              child: TextButton(
                                onPressed: _deleting == null
                                    ? () => _activate(query)
                                    : null,
                                onLongPress: arm,
                                style: TextButton.styleFrom(
                                  shape: const StadiumBorder(),
                                  padding: armed
                                      ? EdgeInsets.zero
                                      : const EdgeInsets.symmetric(
                                          horizontal: 16),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  foregroundColor: armed
                                      ? scheme.onPrimary
                                      : scheme.onSurfaceVariant,
                                  backgroundColor: armed
                                      ? scheme.primary
                                      : scheme.surfaceContainerHighest,
                                  textStyle: style,
                                  animationDuration: AppMotion.duration(context,
                                      MotionKind.feedback, AppMotion.quick),
                                ),
                                child: ExcludeSemantics(
                                  child: armed
                                      ? const Icon(Symbols.close,
                                          size: 22, weight: 700)
                                      : Text(query,
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
