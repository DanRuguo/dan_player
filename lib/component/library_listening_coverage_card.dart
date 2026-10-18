import 'package:dan_player/statistics/library_listening_coverage.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

import 'app_shape.dart';
import 'statistics_distribution_view.dart';

/// A bounded presentation of the frozen display snapshot; no live history or
/// library traversal is performed during layout, animation or language changes.
class LibraryListeningCoverageCard extends StatelessWidget {
  const LibraryListeningCoverageCard({super.key, required this.snapshot});
  final LibraryListeningCoverage? snapshot;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final coverage = snapshot;
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
                    Semantics(
                        header: true,
                        child: Row(children: [
                          Icon(Icons.library_music_outlined,
                              size: 22, color: scheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(ui('曲库播放覆盖'),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w600))),
                        ])),
                    const SizedBox(height: 12),
                    if (coverage == null)
                      Text(ui('正在读取曲目信息…'))
                    else if (coverage.totalTracks == 0)
                      Text(ui('曲库为空，添加歌曲后刷新统计即可查看播放覆盖。'))
                    else
                      StatisticsDistributionView(
                          chartId: 'listening-coverage',
                          availableWidth: constraints.maxWidth,
                          slices: [
                            for (final (index, label, count) in [
                              (0, '有明确播放记录', coverage.recordedTracks),
                              (1, '尚无明确记录', coverage.withoutRecordTracks),
                              if (coverage.uncertainTracks > 0)
                                (2, '旧版记录归属待确认', coverage.uncertainTracks),
                            ])
                              StatisticsDistributionSlice(
                                  label: ui(label),
                                  value: count,
                                  amount: count == 1
                                      ? ui('1 首')
                                      : ui('{0} 首', [count]),
                                  detail: '',
                                  percentage:
                                      count * 100 / coverage.totalTracks,
                                  color: statisticsDistributionColor(
                                      context, index)),
                          ],
                          centerValue:
                              '${(coverage.recordedFraction * 100).toStringAsFixed(1)}%',
                          centerLabel: ui('有明确记录'),
                          centerSemanticsLabel: ui('当前曲库 {0} 首，有明确播放记录 {1} 首',
                              [coverage.totalTracks, coverage.recordedTracks])),
                    const SizedBox(height: 12),
                    Text(ui('按当前曲库的歌曲身份去重，仅统计本机有明确归属的记录；尚无明确记录不代表从未听过。移出曲库的历史不计入。'),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                    if (coverage != null &&
                        coverage.legacyUnassignedRecords > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                          ui('另有 {0} 项旧版记录无法明确归属；候选歌曲单列，不推断是否听过。',
                              [coverage.legacyUnassignedRecords]),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ]);
            })));
  }
}
