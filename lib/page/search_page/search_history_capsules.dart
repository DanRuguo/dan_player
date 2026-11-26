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
  bool _clearing = false;

  Future<void> _activate(String query) async {
    if (_deleting != null || _clearing) return;
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

  Future<void> _clearAll() async {
    if (_clearing || _deleting != null) return;
    setState(() {
      _clearing = true;
      _armed = null;
    });
    try {
      await widget.history.clear();
    } catch (error, trace) {
      LOGGER.w('[clear search history] $error', stackTrace: trace);
      if (mounted) {
        showAppNotice(ui('搜索历史删除失败'),
            context: context, kind: AppNoticeKind.error);
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
            final showHeader =
                queries.isNotEmpty &&
                constraints.maxWidth >= 180 &&
                constraints.maxHeight >= 84;
            final headerHeight = showHeader ? 34.0 : 0.0;
            final layout = SearchHistoryLayout(
                queries: queries,
                width: constraints.maxWidth,
                height: math.max(0.0, constraints.maxHeight - headerHeight),
                style: style,
                scaler: MediaQuery.textScalerOf(context),
                direction: Directionality.of(context));
            if (layout.widths.isEmpty) {
              return const SizedBox.shrink();
            }
            return Align(
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showHeader)
                    SizedBox(
                      height: headerHeight,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Symbols.history,
                            size: 15,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              ui('最近搜索'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          TextButton.icon(
                            key: const ValueKey('search-history-clear-all'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 2),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: _clearing ? null : _clearAll,
                            icon: const Icon(Symbols.delete_sweep, size: 15),
                            label: Text(ui('清空')),
                          ),
                        ],
                      ),
                    ),
                  Wrap(
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
                              label:
                                  armed ? ui('删除搜索历史：{0}', [query]) : query,
                              hint: ui('右键点击或长按以删除'),
                              child: Tooltip(
                                message: armed ? ui('再次点击删除') : query,
                                child: GestureDetector(
                                  onSecondaryTap: arm,
                                  child: TextButton(
                                    onPressed: _deleting == null && !_clearing
                                        ? () => _activate(query)
                                        : null,
                                    onLongPress: arm,
                                    style: ButtonStyle(
                                      shape: const WidgetStatePropertyAll(
                                          StadiumBorder()),
                                      padding: WidgetStatePropertyAll(armed
                                          ? EdgeInsets.zero
                                          : const EdgeInsets.symmetric(
                                              horizontal: 15)),
                                      minimumSize: const WidgetStatePropertyAll(
                                          Size.zero),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      side: WidgetStateProperty.resolveWith(
                                          (states) {
                                        if (armed) return BorderSide.none;
                                        if (states
                                            .contains(WidgetState.hovered)) {
                                          return BorderSide(
                                            color: scheme.primary
                                                .withValues(alpha: .36),
                                          );
                                        }
                                        return BorderSide(
                                          color: scheme.outlineVariant
                                              .withValues(alpha: .44),
                                        );
                                      }),
                                      foregroundColor: WidgetStatePropertyAll(
                                          armed
                                              ? scheme.onPrimary
                                              : scheme.onSurfaceVariant),
                                      backgroundColor: WidgetStateProperty
                                          .resolveWith((states) {
                                        if (armed) return scheme.primary;
                                        if (states
                                            .contains(WidgetState.hovered)) {
                                          return scheme.secondaryContainer
                                              .withValues(alpha: .56);
                                        }
                                        return scheme.surfaceContainerLow;
                                      }),
                                      textStyle: WidgetStatePropertyAll(style),
                                      animationDuration: AppMotion.duration(
                                          context,
                                          MotionKind.feedback,
                                          AppMotion.quick),
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
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
