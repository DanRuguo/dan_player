import 'dart:async';
import 'dart:math' as math;

import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_horizontal_wheel_region.dart';
import 'package:dan_player/component/app_scrollbar.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/listening_calendar_card.dart';
import 'package:dan_player/component/statistics_bar_row.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:dan_player/statistics/statistics_display_service.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage(
      {super.key,
      this.scanner,
      this.statistics,
      this.now,
      this.displayService});

  /// Allows filesystem-free previews and deterministic widget tests.
  final LibraryStatisticsScanner? scanner;
  final PlaybackStatistics? statistics;
  final DateTime? now;
  final StatisticsDisplayService? displayService;

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  late final StatisticsDisplayService _display;
  late final bool _ownsDisplay;
  late PlaybackStatistics _displayStats;
  StatisticsDisplaySnapshot? _displaySnapshot;

  @override
  void initState() {
    super.initState();
    _ownsDisplay = widget.displayService == null &&
        (widget.statistics != null || widget.scanner != null);
    _display = widget.displayService ??
        (_ownsDisplay
            ? StatisticsDisplayService(
                statistics: widget.statistics,
                scanner: widget.scanner,
                clock: widget.now == null ? null : () => widget.now!)
            : StatisticsDisplayService.instance);
    _displayStats = PlaybackStatistics.displayCopy(null);
    _syncSnapshot();
    // Standalone previews have no application startup. The real application
    // warms its session cache once from startup, never from this page.
    if (_ownsDisplay) unawaited(_display.prewarmOnce());
  }

  void _syncSnapshot() {
    final next = _display.snapshot;
    if (identical(next, _displaySnapshot)) return;
    final previous = _displayStats;
    _displayStats = PlaybackStatistics.displayCopy(next?.playbackData,
        storageWarning: next?.storageWarning);
    _displaySnapshot = next;
    previous.dispose();
  }

  @override
  void dispose() {
    _displayStats.dispose();
    if (_ownsDisplay) _display.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ListenableBuilder(
      listenable: _display,
      builder: (context, _) {
        _syncSnapshot();
        final stats = _displayStats;
        final library = _displaySnapshot?.library;
        return ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: AppEntranceScope(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 12.0),
                  sliver: SliverToBoxAdapter(
                    child: AppEntrance(
                      identity: 'statistics-heading',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  ui("音乐统计"),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                              IconButton.filledTonal(
                                style: IconButton.styleFrom(
                                    foregroundColor: Theme.of(context)
                                        .colorScheme
                                        .onSecondaryContainer),
                                key: const ValueKey('statistics-refresh'),
                                tooltip: ui("刷新统计展示"),
                                onPressed: _display.refreshing
                                    ? null
                                    : _display.refresh,
                                icon: const Icon(Icons.refresh_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4.0),
                          Text(
                            ui("听歌习惯、曲库构成与本地文件占用。"),
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                              _displaySnapshot == null
                                  ? ui('启动时准备统计展示；后台播放记录持续保存。')
                                  : ui('展示截至 {0} · 后台持续记录，点击右上角刷新更新。', [
                                      _snapshotClock(
                                          _displaySnapshot!.capturedAt)
                                    ]),
                              key: const ValueKey('statistics-display-asof'),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                          if (stats.storageWarning != null) ...[
                            const SizedBox(height: 8),
                            Text(ui(stats.storageWarning!),
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                          ],
                          if (stats.legacyUnassignedCount > 0) ...[
                            const SizedBox(height: 8),
                            Text(ui('有 {0} 项旧版统计未明确归属；已保留总数，新的播放分别记录。',
                                [stats.legacyUnassignedCount])),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  sliver: SliverToBoxAdapter(
                    child: AppEntrance(
                      identity: 'statistics-calendar',
                      order: 1,
                      child: ListeningCalendarCard(
                          statistics: stats,
                          now: _displaySnapshot?.capturedAt ?? widget.now,
                          dailyChart:
                              _DailyListeningDistribution(statistics: stats)),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      ui("曲库概览"),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  sliver: SliverToBoxAdapter(
                    child: _LibraryOverview(snapshot: library),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24.0, 12.0, 24.0, 0.0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_display.refreshing) ...[
                          LinearProgressIndicator(
                            value: _display.total == 0
                                ? null
                                : _display.completed / _display.total,
                          ),
                          const SizedBox(height: 8),
                          Text(ui("正在核实曲库 {0} / {1}…",
                              [_display.completed, _display.total])),
                        ] else if (_display.failure != null)
                          Text(
                            ui("暂时无法完成统计，请重试。已有结果会保留。"),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          )
                        else if (library != null)
                          Text(
                            ui("统计于 {0} · 按源文件字节数统计，不含缓存或磁盘分配开销。{1}", [
                              _clock(library.scannedAt),
                              library.duplicateEntries == 0
                                  ? ''
                                  : ' 已合并 ${library.duplicateEntries} 条重复记录。'
                            ]),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 0.0),
                  sliver: SliverToBoxAdapter(
                    child: _LibraryDistributions(snapshot: library),
                  ),
                ),
                if (library != null && library.largestFiles.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 0.0),
                    sliver: SliverToBoxAdapter(
                      child: _SectionCard(
                        title: ui("占用空间最多"),
                        icon: Symbols.hard_drive,
                        child: Column(children: [
                          for (final file in library.largestFiles)
                            StatisticsBarRow(
                              label: file.title,
                              detail: file.path,
                              valueLabel: formatLibraryBytes(file.bytes),
                              valueColumnWidth: StatisticsBarRow.measureValues(
                                  context,
                                  library.largestFiles.map((file) =>
                                      formatLibraryBytes(file.bytes))),
                              value: file.bytes.toDouble(),
                              maximum: library.largestFiles.fold<double>(
                                  0,
                                  (largest, file) =>
                                      math.max(largest, file.bytes.toDouble())),
                            ),
                        ]),
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 0.0),
                  sliver: SliverToBoxAdapter(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final topPlay = stats.topPlayCount(limit: 10);
                        final topTime = stats.topListeningTime(limit: 10);
                        final cards = [
                          _RankingCard(
                            title: ui("播放最多"),
                            icon: Symbols.play_circle,
                            tracks: topPlay,
                            value: (item) => ui("{0} 次", [item.playCount]),
                            magnitude: (item) => item.playCount.toDouble(),
                          ),
                          _RankingCard(
                            title: ui("收听最久"),
                            icon: Symbols.headphones,
                            tracks: topTime,
                            value: (item) => _formatListeningDuration(
                                item.listenMilliseconds),
                            magnitude: (item) =>
                                item.listenMilliseconds.toDouble(),
                          ),
                        ]
                            .indexed
                            .map((entry) => AppEntrance(
                                  identity: ('statistics-ranking', entry.$1),
                                  order: entry.$1 + 4,
                                  child: entry.$2,
                                ))
                            .toList();
                        return constraints.maxWidth /
                                    _statisticsTextScale(context) >=
                                800
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: cards[0]),
                                  const SizedBox(width: 16.0),
                                  Expanded(child: cards[1]),
                                ],
                              )
                            : Column(
                                children: [
                                  cards[0],
                                  const SizedBox(height: 16.0),
                                  cards[1],
                                ],
                              );
                      },
                    ),
                  ),
                ),
                const SliverPadding(padding: EdgeInsets.only(bottom: 112.0)),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _snapshotClock(DateTime time) =>
      '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  static String _clock(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

String _formatListeningDuration(int milliseconds, {bool precise = false}) {
  final duration = Duration(milliseconds: math.max(0, milliseconds));
  if (duration.inHours >= 1) {
    if (precise) {
      return ui("{0} 小时 {1} 分 {2} 秒", [
        duration.inHours,
        duration.inMinutes.remainder(60),
        duration.inSeconds.remainder(60)
      ]);
    }
    return ui("{0} 小时 {1} 分{2}",
        [duration.inHours, duration.inMinutes.remainder(60), '']);
  }
  if (duration.inMinutes >= 1) {
    return precise
        ? ui("{0} 分 {1} 秒",
            [duration.inMinutes, duration.inSeconds.remainder(60)])
        : ui("{0} 分钟", [duration.inMinutes]);
  }
  if (milliseconds > 0 && duration.inSeconds == 0) return ui("不足 1 秒");
  return ui("{0} 秒", [duration.inSeconds]);
}

String _hourRange(int hour) => '${hour.toString().padLeft(2, '0')}:00–'
    '${(hour + 1).toString().padLeft(2, '0')}:00';

class _DailyListeningDistribution extends StatelessWidget {
  const _DailyListeningDistribution({required this.statistics});
  final PlaybackStatistics statistics;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('statistics-daily-distribution'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 18, runSpacing: 6, children: [
          Text(ui("完整 {0} 次", [statistics.totalCompletedCount])),
          Text(ui("提前跳过 {0} 次", [statistics.totalSkippedCount])),
        ]),
        const SizedBox(height: 24),
        _StatisticsHeading(
          title: ui("24 小时收听分布"),
          icon: Symbols.bar_chart,
        ),
        const SizedBox(height: 4),
        Text(
          ui("每根柱表示该时段累计收听时长，强调色柱为最高时段。"),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        _HourlyListeningChart(
          values: List<int>.of(statistics.hourlyMilliseconds),
          peakHours: statistics.mostActiveHours,
        ),
        const SizedBox(height: 12),
        Text(
          ui("暂停、缓冲和拖动播放进度不补算时长。休眠或采样间隔超过 2 秒时，仅计最近 2 秒，未观测的间隔不补记。"),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _HourlyListeningChart extends StatefulWidget {
  const _HourlyListeningChart({required this.values, required this.peakHours});

  final List<int> values;
  final List<int> peakHours;

  @override
  State<_HourlyListeningChart> createState() => _HourlyListeningChartState();
}

class _HourlyListeningChartState extends State<_HourlyListeningChart> {
  final ScrollController _scrollController = ScrollController();
  int? _selectedHour;

  int _value(int hour) =>
      hour < widget.values.length ? math.max(0, widget.values[hour]) : 0;

  int? get _visibleSelection => _selectedHour ?? widget.peakHours.firstOrNull;

  void _selectHour(int hour, {bool reveal = false}) {
    setState(() => _selectedHour = hour);
    if (!reveal || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final width = position.viewportDimension + position.maxScrollExtent;
    final offset = ((hour + 0.5) * width / 24 - position.viewportDimension / 2)
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();
    _scrollController.jumpTo(offset);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final maximum = widget.values.fold(0, math.max);
    final selectedHour = _visibleSelection;
    final selectedIsPeak = widget.peakHours.contains(selectedHour);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (maximum == 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              ui("还没有收听记录。开始播放后，这里会显示真实的时段分布。"),
              key: const ValueKey('listening-empty'),
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            Text(ui("收听时长"), style: Theme.of(context).textTheme.labelMedium),
            Text(
              ui("顶格 {0}", [_formatListeningDuration(maximum)]),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            const plotHeight = 168.0;
            final slotMinimum = math.max(
              30.0,
              MediaQuery.textScalerOf(context).scale(12) * 2.2 + 8,
            );
            final chartWidth = math.max(constraints.maxWidth, slotMinimum * 24);
            final scrollable = chartWidth > constraints.maxWidth;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppHorizontalWheelRegion(
                  controller: _scrollController,
                  child: AppScrollbar(
                    controller: _scrollController,
                    child: SingleChildScrollView(
                      key: const ValueKey('listening-hours-scroll'),
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(bottom: 14),
                      child: SizedBox(
                        width: chartWidth,
                        child: Stack(
                          children: [
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              height: plotHeight,
                              child: CustomPaint(
                                painter: _HourlyGridPainter(
                                  color: scheme.outlineVariant,
                                ),
                              ),
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (var hour = 0; hour < 24; hour++)
                                  Expanded(
                                    child: Semantics(
                                      key: ValueKey('listening-hour-$hour'),
                                      button: true,
                                      selected: hour == selectedHour,
                                      label: ui("{0}，收听 {1}{2}", [
                                        _hourRange(hour),
                                        _formatListeningDuration(_value(hour),
                                            precise: true),
                                        widget.peakHours.contains(hour)
                                            ? ' · ${ui("最高时段")}'
                                            : ''
                                      ]),
                                      onTap: () => _selectHour(hour),
                                      excludeSemantics: true,
                                      child: Tooltip(
                                        message: '${_hourRange(hour)} · '
                                            '${_formatListeningDuration(_value(hour), precise: true)}'
                                            '${widget.peakHours.contains(hour) ? ' · ${ui("最高时段")}' : ''}',
                                        child: InkWell(
                                          onTap: () => _selectHour(hour),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SizedBox(
                                                height: plotHeight,
                                                child: Align(
                                                  alignment:
                                                      Alignment.bottomCenter,
                                                  child: SizedBox(
                                                    width:
                                                        chartWidth / 24 * 0.58,
                                                    height: maximum == 0
                                                        ? 0
                                                        : plotHeight *
                                                            _value(hour) /
                                                            maximum,
                                                    child: DecoratedBox(
                                                      key: ValueKey(
                                                          'listening-bar-$hour'),
                                                      decoration: BoxDecoration(
                                                        color:
                                                            StatisticsMagnitudeColor
                                                                .resolve(
                                                          scheme,
                                                          maximum == 0
                                                              ? 0
                                                              : _value(hour) /
                                                                  maximum,
                                                        ),
                                                        borderRadius:
                                                            const BorderRadius
                                                                .vertical(
                                                          top: Radius.circular(
                                                              4),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Container(
                                                key: ValueKey(
                                                    'listening-hour-label-$hour'),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 3,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(5),
                                                  border: Border.all(
                                                    color: hour == selectedHour
                                                        ? scheme.primary
                                                        : Colors.transparent,
                                                  ),
                                                ),
                                                child: Text(
                                                  hour
                                                      .toString()
                                                      .padLeft(2, '0'),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelSmall
                                                      ?.copyWith(
                                                        fontSize: 12,
                                                        color: hour ==
                                                                selectedHour
                                                            ? scheme.primary
                                                            : scheme
                                                                .onSurfaceVariant,
                                                        fontWeight: hour ==
                                                                selectedHour
                                                            ? FontWeight.bold
                                                            : FontWeight.normal,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (scrollable)
                  Text(
                    ui("滚轮或横向滑动查看全部 24 个时段"),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              tooltip: ui("前一个时段"),
              onPressed: () => _selectHour(
                ((selectedHour ?? 0) + 23) % 24,
                reveal: true,
              ),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Column(
                  key: const ValueKey('listening-hour-selection'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectedHour == null
                          ? ui("选择一个时段")
                          : _hourRange(selectedHour),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      selectedHour == null
                          ? ui("点击、长按或悬停柱状条查看时长")
                          : '${_formatListeningDuration(_value(selectedHour), precise: true)}'
                              '${selectedIsPeak ? ' · ${ui("最高时段")}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: ui("后一个时段"),
              onPressed: () => _selectHour(
                ((selectedHour ?? -1) + 1) % 24,
                reveal: true,
              ),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

const _distributionColors = [
  Color(0xff168c83),
  Color(0xff4482d6),
  Color(0xff9c6ade),
  Color(0xffd68b35),
  Color(0xff89949e),
  Color(0xffc96788),
  Color(0xff668644),
  Color(0xff5c7f99),
];

Color _distributionColor(BuildContext context, int index) => Color.lerp(
      _distributionColors[index % _distributionColors.length],
      Theme.of(context).colorScheme.primary,
      .4,
    )!;

double _statisticsTextScale(BuildContext context) =>
    math.max(1, MediaQuery.textScalerOf(context).scale(14) / 14);

/// Only the bounded metric/distribution cards use intrinsic row sizing.
/// Natural text/legend height determines the row height; there is no clipping
/// or fixed-height scroll area when accessibility text sizes grow.
class _EqualHeightRows extends StatelessWidget {
  const _EqualHeightRows({
    required this.children,
    required this.columns,
    this.spacing = 16,
  });

  final List<Widget> children;
  final int columns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var start = 0; start < children.length; start += columns) ...[
          if (start != 0) SizedBox(height: spacing),
          if (columns == 1)
            children[start]
          else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var column = 0; column < columns; column++) ...[
                    if (column != 0) SizedBox(width: spacing),
                    Expanded(
                      child: start + column < children.length
                          ? children[start + column]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _LibraryOverview extends StatelessWidget {
  const _LibraryOverview({required this.snapshot});
  final LibraryStatisticsSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final library = snapshot;
        final effectiveWidth =
            constraints.maxWidth / _statisticsTextScale(context);
        return _EqualHeightRows(
          columns: effectiveWidth >= 1000 ? 4 : (effectiveWidth >= 470 ? 2 : 1),
          spacing: 12,
          children: [
            _MetricCard(
              key: const ValueKey('statistics-local-total-metric'),
              icon: Symbols.library_music,
              label: ui("总乐库"),
              value: library?.totalTracks.toString() ?? '—',
              detail: library == null
                  ? ui("正在统计")
                  : ui("本地 {0} · 联网 {1}",
                      [library.localTracks, library.onlineTracks]),
            ),
            _MetricCard(
              key: const ValueKey('statistics-local-storage-metric'),
              icon: Icons.storage_rounded,
              label: ui("本地源文件占用"),
              value: library == null
                  ? '—'
                  : formatLibraryBytes(library.totalLocalBytes),
              detail: library == null
                  ? ui("正在读取真实字节数")
                  : ui("{0} 首已核实 · 不含联网曲目", [library.measuredLocalTracks]),
            ),
            _MetricCard(
              key: const ValueKey('statistics-local-readable-metric'),
              icon: Icons.folder_off_outlined,
              label: ui("文件读取情况"),
              value: library == null
                  ? '—'
                  : ui('{0} 首未计入空间', [
                      library.missingLocalTracks +
                          library.inaccessibleLocalTracks
                    ]),
              detail: library == null
                  ? ui("只读检查，不修改源文件")
                  : ui("缺失 {0} · 无权限/不可读 {1}", [
                      library.missingLocalTracks,
                      library.inaccessibleLocalTracks
                    ]),
            ),
            _MetricCard(
              key: const ValueKey('statistics-local-folder-metric'),
              icon: Icons.folder_outlined,
              label: ui("本地文件夹"),
              value: library?.localFolderCount.toString() ?? '—',
              detail: ui("按完整路径区分直接父目录，不含联网曲目"),
            ),
          ]
              .indexed
              .map((entry) => AppEntrance(
                    identity: ('statistics-library-metric', entry.$1),
                    order: entry.$1 + 2,
                    child: entry.$2,
                  ))
              .toList(),
        );
      },
    );
  }
}

class _LibraryDistributions extends StatefulWidget {
  const _LibraryDistributions({required this.snapshot});
  final LibraryStatisticsSnapshot? snapshot;

  @override
  State<_LibraryDistributions> createState() => _LibraryDistributionsState();
}

class _LibraryDistributionsState extends State<_LibraryDistributions> {
  FolderDistributionMetric _metric = FolderDistributionMetric.songCount;
  FolderDistribution? _folders;

  @override
  void initState() {
    super.initState();
    _folders = widget.snapshot?.folderDistribution(_metric);
  }

  @override
  void didUpdateWidget(covariant _LibraryDistributions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.snapshot, widget.snapshot)) {
      _folders = widget.snapshot?.folderDistribution(_metric);
    }
  }

  void _selectMetric(FolderDistributionMetric metric) {
    if (_metric == metric) return;
    setState(() {
      _metric = metric;
      _folders = widget.snapshot?.folderDistribution(metric);
    });
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth / _statisticsTextScale(context) >= 1560
                ? 3
                : 1;
        final contentWidth =
            (constraints.maxWidth - (columns - 1) * 16) / columns - 36;
        return _EqualHeightRows(
          columns: columns,
          children: [
            AppEntrance(
              identity: 'statistics-language',
              order: 3,
              child: _LanguageCard(
                  snapshot: widget.snapshot, contentWidth: contentWidth),
            ),
            AppEntrance(
              identity: 'statistics-storage',
              order: 4,
              child: _StorageFormatCard(
                  snapshot: widget.snapshot, contentWidth: contentWidth),
            ),
            AppEntrance(
              identity: 'statistics-folders',
              order: 5,
              child: _FolderStorageCard(
                snapshot: widget.snapshot,
                distribution: _folders,
                metric: _metric,
                contentWidth: contentWidth,
                onMetricChanged: _selectMetric,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({required this.snapshot, required this.contentWidth});
  final LibraryStatisticsSnapshot? snapshot;
  final double contentWidth;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final stats = snapshot;
    return _SectionCard(
      key: const ValueKey('statistics-language-card'),
      title: ui("歌曲语言"),
      icon: Symbols.language,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stats == null
                ? ui("正在读取曲目信息…")
                : ui("标签 {0} 首 · 歌词 {1} 首 · 推断 {2} 首 · 未识别 {3} 首", [
                    stats.taggedTracks,
                    stats.lyricTracks,
                    stats.metadataInferredTracks,
                    stats.languageCounts[SongLanguage.unknown]
                  ]),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          _DistributionView(
            chartId: 'language',
            availableWidth: contentWidth,
            slices: [
              for (final language in SongLanguage.values)
                if ((stats?.languageCounts[language] ?? 0) > 0)
                  _DistributionSlice(
                    label: ui(language.label),
                    value: stats?.languageCounts[language] ?? 0,
                    amount: ui("{0} 首", [stats?.languageCounts[language] ?? 0]),
                    detail: language == SongLanguage.unknown
                        ? ui("缺乏可靠语言信息")
                        : ui("标签 {0} · 歌词 {1} · 推断 {2}", [
                            stats?.taggedLanguageCounts[language] ?? 0,
                            stats?.lyricLanguageCounts[language] ?? 0,
                            stats?.metadataInferredCount(language) ?? 0
                          ]),
                    color: _distributionColor(context, language.index),
                  ),
            ],
            centerValue: stats == null ? '—' : '${stats.totalTracks}',
            centerLabel: stats?.totalTracks == 0 ? ui("尚未添加歌曲") : ui("首曲目"),
          ),
          const SizedBox(height: 16),
          Text(
            ui("与分类页共用判定：语言标签优先，其次为本地内嵌或同名 .lrc 歌词的原文线索，最后依据歌名、作曲或参与创作艺术家和专辑名作文字推断。按常见 LRC 约定保留同时间戳首行，不混入后续译文；没有足够证据时保留未识别。歌词与文字推断均不代表已识别实际演唱语言。"),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _StorageFormatCard extends StatelessWidget {
  const _StorageFormatCard(
      {required this.snapshot, required this.contentWidth});
  final LibraryStatisticsSnapshot? snapshot;
  final double contentWidth;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final stats = snapshot;
    final formats = stats?.formats ?? const <FormatStorageUsage>[];
    final sourceFileCount =
        formats.fold(0, (sum, format) => sum + format.fileCount);
    // Keep uncommon extensions legible without an unbounded legend.
    final visible = formats.take(7).toList();
    if (formats.length > 7) {
      final remaining = formats.skip(7);
      visible.add(FormatStorageUsage(
        format: ui("其他格式"),
        fileCount: remaining.fold(0, (sum, item) => sum + item.fileCount),
        bytes: remaining.fold(0, (sum, item) => sum + item.bytes),
      ));
    }
    return _SectionCard(
      key: const ValueKey('statistics-format-card'),
      title: ui("本地空间 · 文件格式"),
      icon: Symbols.audio_file,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ui("环图与粗条按实际字节数划分，细条对照源文件数量；格式按扩展名分组。"),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          _DistributionView(
            chartId: 'format',
            availableWidth: contentWidth,
            slices: [
              for (var index = 0; index < visible.length; index++)
                _DistributionSlice(
                  label: ui(visible[index].format),
                  value: visible[index].bytes,
                  amount: formatLibraryBytes(visible[index].bytes),
                  detail: ui("{0} 个源文件", [visible[index].fileCount]),
                  comparisonValue: sourceFileCount == 0
                      ? 0
                      : visible[index].fileCount / sourceFileCount,
                  color: _distributionColor(context, index),
                ),
            ],
            centerValue:
                stats == null ? '—' : formatLibraryBytes(stats.totalLocalBytes),
            centerLabel:
                stats?.measuredLocalTracks == 0 ? ui("暂无可核实文件") : ui("已核实占用"),
          ),
          const SizedBox(height: 16),
          Text(
            stats == null
                ? ui("正在只读检查本地源文件。")
                : ui(
                    "已读取 {0} 首；缺失 {1} 首，无权限/不可读 {2} 首。联网 {3} 首不计入本地占用。文件在外部变化后可点右上角刷新。",
                    [
                        stats.measuredLocalTracks,
                        stats.missingLocalTracks,
                        stats.inaccessibleLocalTracks,
                        stats.onlineTracks
                      ]),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _FolderStorageCard extends StatelessWidget {
  const _FolderStorageCard({
    required this.snapshot,
    required this.distribution,
    required this.metric,
    required this.contentWidth,
    required this.onMetricChanged,
  });

  final LibraryStatisticsSnapshot? snapshot;
  final FolderDistribution? distribution;
  final FolderDistributionMetric metric;
  final double contentWidth;
  final ValueChanged<FolderDistributionMetric> onMetricChanged;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final stats = snapshot;
    final byCount = metric == FolderDistributionMetric.songCount;
    final entries = distribution?.entries ?? const <FolderDistributionEntry>[];
    final subdued = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return _SectionCard(
      key: const ValueKey('statistics-folder-card'),
      title: ui("本地分布 · 文件夹"),
      icon: Symbols.folder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stats == null
                ? ui("正在只读检查本地源文件…")
                : ui("{0} 个直接父目录 · 本地 {1} 首",
                    [stats.localFolderCount, stats.localTracks]),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ChoiceChip(
                key: const ValueKey('folder-metric-count'),
                label: Text(ui("歌曲数量")),
                selected: byCount,
                onSelected: (_) =>
                    onMetricChanged(FolderDistributionMetric.songCount),
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
              ChoiceChip(
                key: const ValueKey('folder-metric-bytes'),
                label: Text(ui("占用空间")),
                selected: !byCount,
                onSelected: (_) =>
                    onMetricChanged(FolderDistributionMetric.storageBytes),
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DistributionView(
            chartId: 'folders',
            availableWidth: contentWidth,
            slices: [
              for (var index = 0; index < entries.length; index++)
                _DistributionSlice(
                  label: entries[index].path ??
                      ui("其他文件夹（{0} 个）", [entries[index].folderCount]),
                  tooltip: entries[index].path,
                  value: entries[index].value(metric),
                  amount: byCount
                      ? ui("{0} 首", [entries[index].fileCount])
                      : formatLibraryBytes(entries[index].bytes),
                  detail: ui("{0} · 已核实 {1} 首{2}{3}", [
                    byCount
                        ? formatLibraryBytes(entries[index].bytes)
                        : ui("{0} 首", [entries[index].fileCount]),
                    entries[index].measuredFileCount,
                    entries[index].missingFileCount == 0
                        ? ''
                        : ui(" · 缺失 {0} 首", [entries[index].missingFileCount]),
                    entries[index].inaccessibleFileCount == 0
                        ? ''
                        : ui(" · 不可读 {0} 首",
                            [entries[index].inaccessibleFileCount])
                  ]),
                  percentage: distribution!.percentageOf(entries[index]),
                  color: _distributionColor(context, index),
                ),
            ],
            centerValue: stats == null
                ? '—'
                : byCount
                    ? '${stats.localTracks}'
                    : formatLibraryBytes(stats.totalLocalBytes),
            centerLabel: stats?.localTracks == 0
                ? ui("尚无本地文件夹")
                : byCount
                    ? ui("首本地曲目")
                    : stats?.totalLocalBytes == 0
                        ? ui("暂无可核实字节")
                        : ui("本地已核实占用"),
          ),
          const SizedBox(height: 16),
          Text(
            ui("按曲库登记路径的直接父目录分组，不递归合并子目录；完整路径不同的同名文件夹分开统计。按当前指标显示前 7 个，其余合并为“其他文件夹”。"),
            style: subdued,
          ),
          const SizedBox(height: 8),
          Text(
            ui(
                "数量包含缺失/不可读曲目；空间只计成功读取的真实字节，不含联网歌曲和缓存。{0}切换指标不重新扫描；外部文件变化后请手动刷新。",
                [
                  stats == null
                      ? ''
                      : ui(" 缺失 {0} 首，无权限/不可读 {1} 首未计入空间。", [
                          stats.missingLocalTracks,
                          stats.inaccessibleLocalTracks
                        ])
                ]),
            key: const ValueKey('statistics-folder-scope'),
            style: subdued,
          ),
        ],
      ),
    );
  }
}

class _DistributionSlice {
  const _DistributionSlice({
    required this.label,
    required this.value,
    required this.amount,
    required this.detail,
    required this.color,
    this.tooltip,
    this.percentage,
    this.comparisonValue,
  });

  final String label;
  final int value;
  final String amount;
  final String detail;
  final Color color;
  final String? tooltip;
  final double? percentage;
  final double? comparisonValue;
}

class _DistributionView extends StatelessWidget {
  const _DistributionView({
    required this.chartId,
    required this.availableWidth,
    required this.slices,
    required this.centerValue,
    required this.centerLabel,
  });

  final String chartId;
  final double availableWidth;
  final List<_DistributionSlice> slices;
  final String centerValue;
  final String centerLabel;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final total = slices.fold(0, (sum, item) => sum + item.value);
    final textScale = _statisticsTextScale(context);
    final side = math.min(
      (slices.length <= 2 ? 132.0 : 176.0) * textScale,
      math.max(1.0, availableWidth),
    );
    final horizontal = availableWidth / textScale >= 510;
    final legendWidth =
        horizontal ? availableWidth - side - 24 : availableWidth;
    final legendColumns =
        slices.length > 4 && legendWidth / textScale >= 720 ? 2 : 1;
    final rowWidth = (legendWidth - (legendColumns - 1) * 16) / legendColumns;
    final compactLegend = rowWidth / textScale < 340;
    final chart = Semantics(
      label:
          '$centerLabel $centerValue。${slices.map((item) => '${item.label} ${item.amount}').join('，')}',
      excludeSemantics: true,
      child: SizedBox.square(
        key: ValueKey('statistics-chart-$chartId'),
        dimension: side,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _DonutChartPainter(
                  slices: slices,
                  background:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(32),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: math.max(1.0, side - 64),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          centerValue,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        centerLabel,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final legend = KeyedSubtree(
      key: ValueKey('statistics-legend-$chartId'),
      child: _EqualHeightRows(
        columns: legendColumns,
        spacing: legendColumns == 1 ? 0 : 16,
        children: [
          if (slices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(ui("暂无分类数据"), textAlign: TextAlign.center),
            ),
          for (var index = 0; index < slices.length; index++)
            _DistributionComparisonRow(
              key: ValueKey('statistics-comparison-$chartId-$index'),
              slice: slices[index],
              fraction: (slices[index].percentage ??
                      (total == 0 ? 0.0 : 100 * slices[index].value / total)) /
                  100,
              compact: compactLegend,
            ),
        ],
      ),
    );
    return horizontal
        ? Row(
            children: [
              chart,
              const SizedBox(width: 24),
              Expanded(child: legend),
            ],
          )
        : Column(
            children: [
              chart,
              const SizedBox(height: 16),
              legend,
            ],
          );
  }
}

/// The ring and each comparison bar share the same denominator and colour.
/// Long folder names keep a full-path tooltip; counts and percentages have
/// their own line when text scaling leaves insufficient room beside the name.
class _DistributionComparisonRow extends StatelessWidget {
  const _DistributionComparisonRow({
    super.key,
    required this.slice,
    required this.fraction,
    required this.compact,
  });

  final _DistributionSlice slice;
  final double fraction;
  final bool compact;

  Widget _bar(BuildContext context, double value, {bool secondary = false}) =>
      ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
          height: secondary ? 5 : 8,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .09),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: value.clamp(0.0, 1.0),
                heightFactor: 1,
                child: ColoredBox(
                  color: secondary
                      ? slice.color.withValues(alpha: .58)
                      : slice.color,
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percentage = '${(fraction * 100).toStringAsFixed(1)}%';
    final label = Tooltip(
      message: slice.tooltip ?? slice.label,
      child: Text(slice.label, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
    final amount = Wrap(
      spacing: 12,
      runSpacing: 2,
      alignment: compact ? WrapAlignment.start : WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(slice.amount,
            style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
        Text(percentage, style: theme.textTheme.bodySmall),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: DecoratedBox(
                decoration:
                    BoxDecoration(color: slice.color, shape: BoxShape.circle),
                child: const SizedBox.square(dimension: 10),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(child: label),
            if (!compact) ...[
              const SizedBox(width: 16),
              Expanded(child: amount),
            ],
          ]),
          if (compact) ...[
            const SizedBox(height: 4),
            amount,
          ],
          const SizedBox(height: 7),
          Semantics(
            label: '${slice.label} ${slice.amount} $percentage',
            child: _bar(context, fraction),
          ),
          const SizedBox(height: 5),
          if (slice.comparisonValue == null)
            Text(slice.detail,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
          else
            Tooltip(
              message: ui("源文件数量"),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 2,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      Text(slice.detail, style: theme.textTheme.bodySmall),
                      Text(
                          '${(slice.comparisonValue! * 100).toStringAsFixed(1)}%',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Semantics(
                    label: '${ui("源文件数量")} ${slice.detail}',
                    child:
                        _bar(context, slice.comparisonValue!, secondary: true),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  const _DonutChartPainter({required this.slices, required this.background});
  final List<_DistributionSlice> slices;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 22.0;
    final center = size.center(Offset.zero);
    final radius = math.max(0.0, size.shortestSide / 2 - strokeWidth / 2 - 3);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = background;
    canvas.drawCircle(center, radius, paint);
    final total = slices.fold(0, (sum, item) => sum + item.value);
    if (total == 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    var start = -math.pi / 2;
    for (final slice in slices) {
      if (slice.value <= 0) continue;
      final sweep = 2 * math.pi * slice.value / total;
      canvas.drawArc(rect, start, sweep, false, paint..color = slice.color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) =>
      oldDelegate.slices != slices || oldDelegate.background != background;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return _StatisticsCard(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 112),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _StatisticsHeading(title: label, icon: icon),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared card chrome and headings keep every statistics section at one level.
class _StatisticsCard extends StatelessWidget {
  const _StatisticsCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: AppShape.controlRadius,
          side:
              BorderSide(color: scheme.outlineVariant.withValues(alpha: .55))),
      color: scheme.surfaceContainerLow,
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    );
  }
}

class _StatisticsHeading extends StatelessWidget {
  const _StatisticsHeading({required this.title, this.icon});
  final String title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[
        Icon(icon, size: 22, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
      ],
      Flexible(
          child: Text(title,
              style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600))),
    ]);
    return Semantics(header: true, child: heading);
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard(
      {super.key, required this.title, this.icon, required this.child});
  final String title;
  final IconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => _StatisticsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _StatisticsHeading(title: title, icon: icon),
          const SizedBox(height: 12),
          child,
        ]),
      );
}

class _RankingCard extends StatelessWidget {
  const _RankingCard(
      {required this.title,
      required this.icon,
      required this.tracks,
      required this.value,
      required this.magnitude});
  final String title;
  final IconData icon;
  final List<TrackPlaybackStatistics> tracks;
  final String Function(TrackPlaybackStatistics) value;
  final double Function(TrackPlaybackStatistics) magnitude;
  @override
  Widget build(BuildContext context) {
    final maximum = tracks.fold<double>(
        0, (maxValue, track) => math.max(maxValue, magnitude(track)));
    return _SectionCard(
        title: title,
        icon: icon,
        child: tracks.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Center(child: Text(ui("播放歌曲后会在这里生成排行"))))
            : Column(children: [
                for (final (index, track) in tracks.indexed)
                  StatisticsBarRow(
                      label: track.title,
                      detail:
                          '${track.artist} · ${ui(track.online ? "联网" : "本地")}'
                          '${track.legacyUnassigned ? " · ${ui('旧版未明确归属 · {0} 个候选', [
                                  track.candidateTrackIds.length
                                ])}" : ""}',
                      rank: index + 1,
                      valueColumnWidth: StatisticsBarRow.measureValues(
                          context, tracks.map(value)),
                      valueLabel: value(track),
                      value: magnitude(track),
                      maximum: maximum),
              ]));
  }
}

class _HourlyGridPainter extends CustomPainter {
  const _HourlyGridPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    for (var line = 0; line <= 3; line++) {
      final y = size.height * line / 3;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HourlyGridPainter oldDelegate) =>
      oldDelegate.color != color;
}
