import 'package:dan_player/library/personal_library.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'app_shape.dart';
import 'statistics_card_header.dart';
import 'statistics_distribution_view.dart';

/// A detached personal snapshot, displayed without reading files or observing
/// the live library. Only a different snapshot rebuilds the bounded tag ranking.
class PersonalAnnotationsCard extends StatefulWidget {
  const PersonalAnnotationsCard({super.key, required this.snapshot});
  final PersonalOrganizationSummary? snapshot;

  @override
  State<PersonalAnnotationsCard> createState() =>
      _PersonalAnnotationsCardState();
}

class _PersonalAnnotationsCardState extends State<PersonalAnnotationsCard> {
  var _group = 'ratings';
  List<MapEntry<String, int>> _topTags = const [];
  int _otherTags = 0, _otherAnnotations = 0;

  @override
  void initState() {
    super.initState();
    _captureTags();
  }

  @override
  void didUpdateWidget(PersonalAnnotationsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.snapshot, widget.snapshot)) _captureTags();
  }

  void _captureTags() {
    final snapshot = widget.snapshot;
    final top = <MapEntry<String, int>>[];
    var tagCount = 0;
    for (final entry
        in snapshot?.tagCounts.entries ?? const <MapEntry<String, int>>[]) {
      if (entry.value <= 0) continue;
      tagCount++;
      var index = 0;
      while (index < top.length &&
          (top[index].value > entry.value ||
              (top[index].value == entry.value &&
                  top[index].key.compareTo(entry.key) < 0))) {
        index++;
      }
      if (index >= 5) continue;
      if (top.length == 5) top.removeLast();
      top.insert(index, entry);
    }
    _topTags = List.unmodifiable(top);
    _otherTags = tagCount - top.length;
    _otherAnnotations = (snapshot?.tagAnnotations ?? 0) -
        top.fold(0, (sum, entry) => sum + entry.value);
  }

  List<StatisticsDistributionSlice> _slices(
      BuildContext context, PersonalOrganizationSummary snapshot) {
    if (_group == 'ratings') {
      return [
        for (var rating = 1; rating <= 5; rating++)
          if ((snapshot.ratingCounts[rating] ?? 0) > 0)
            StatisticsDistributionSlice(
                label: ui('{0} 星', [rating]),
                value: snapshot.ratingCounts[rating]!,
                amount: snapshot.ratingCounts[rating] == 1
                    ? ui('1 首')
                    : ui('{0} 首', [snapshot.ratingCounts[rating]]),
                detail: ui('已评级歌曲'),
                percentage: snapshot.ratedTracks == 0
                    ? 0
                    : snapshot.ratingCounts[rating]! *
                        100 /
                        snapshot.ratedTracks,
                color: statisticsDistributionColor(context, rating - 1)),
      ];
    }
    return [
      for (final (index, tag) in _topTags.indexed)
        StatisticsDistributionSlice(
            label: tag.key,
            value: tag.value,
            amount: tag.value == 1 ? ui('1 次标注') : ui('{0} 次标注', [tag.value]),
            detail: ui('标签附着次数'),
            percentage: snapshot.tagAnnotations == 0
                ? 0
                : tag.value * 100 / snapshot.tagAnnotations,
            color: statisticsDistributionColor(context, index)),
      if (_otherTags > 0)
        StatisticsDistributionSlice(
            label: ui('其他标签'),
            value: _otherAnnotations,
            amount: _otherAnnotations == 1
                ? ui('1 次标注')
                : ui('{0} 次标注', [_otherAnnotations]),
            detail: ui('其他 {0} 个标签', [_otherTags]),
            percentage: snapshot.tagAnnotations == 0
                ? 0
                : _otherAnnotations * 100 / snapshot.tagAnnotations,
            color: statisticsDistributionColor(context, 5)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final snapshot = widget.snapshot;
    final ratings = _group == 'ratings';
    return Card.filled(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
            borderRadius: AppShape.controlRadius,
            side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: .55))),
        color: scheme.surfaceContainerLow,
        child: Padding(
            padding: const EdgeInsets.all(18),
            child: LayoutBuilder(builder: (context, constraints) {
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StatisticsCardHeader(
                      title: Semantics(
                          header: true,
                          child: Row(children: [
                            Icon(Symbols.loyalty,
                                size: 22, color: scheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(ui('个人标注'),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                            color: scheme.primary,
                                            fontWeight: FontWeight.w600))),
                          ])),
                      controls: Semantics(
                          label: ui('标注分组'),
                          child: Wrap(
                              key: const ValueKey(
                                  'personal-annotations-selector'),
                              alignment: WrapAlignment.end,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final option in [
                                  ('ratings', '评级'),
                                  ('tags', '标签')
                                ])
                                  ChoiceChip(
                                      key: ValueKey(
                                          'personal-annotations-${option.$1}'),
                                      label: Text(ui(option.$2)),
                                      selected: _group == option.$1,
                                      onSelected: (selected) {
                                        if (selected) {
                                          setState(() => _group = option.$1);
                                        }
                                      }),
                              ])),
                    ),
                    const SizedBox(height: 12),
                    if (snapshot == null)
                      Text(ui('个人标注统计尚未就绪'))
                    else ...[
                      StatisticsDistributionView(
                          chartId: _group,
                          availableWidth: constraints.maxWidth,
                          slices: _slices(context, snapshot),
                          centerValue:
                              '${ratings ? snapshot.ratedTracks : snapshot.tagAnnotations}',
                          centerLabel: ratings
                              ? ui(snapshot.ratedTracks == 0 ? '暂无评级' : '已评级歌曲')
                              : ui(snapshot.tagAnnotations == 0
                                  ? '暂无标签'
                                  : '标签附着次数')),
                      const SizedBox(height: 16),
                      Text(
                          ratings
                              ? ui('按已评级歌曲计算比例；未评级歌曲不参与。')
                              : '${ui('按逐歌标签附着次数计算；一首歌可有多个标签，次数不等于歌曲总数。')} ${ui('显示前 5 个标签，其余合并为“其他标签”。')}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ]);
            })));
  }
}
