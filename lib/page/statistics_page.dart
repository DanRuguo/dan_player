import 'dart:math' as math;

import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_scrollbar.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/statistics_bar_row.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key, this.scanner, this.statistics});

  /// Allows filesystem-free previews and deterministic widget tests.
  final LibraryStatisticsScanner? scanner;
  final PlaybackStatistics? statistics;

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  late final LibraryStatisticsScanner _scanner;
  LibraryStatisticsSnapshot? _librarySnapshot;
  int _requestedRevision = -1;
  int _generation = 0;
  int _scanned = 0;
  int _scanTotal = 0;
  bool _scanning = false;
  bool _refreshScheduled = false;
  String? _scanError;

  @override
  void initState() {
    super.initState();
    _scanner = widget.scanner ?? LibraryStatisticsScanner();
    AudioLibrary.changes.addListener(_libraryChanged);
    _refreshLibrary(notify: false);
  }

  void _libraryChanged() => _refreshIfLibraryChanged();

  Future<void> _refreshLibrary({bool notify = true}) async {
    final generation = ++_generation;
    _requestedRevision = AudioLibrary.revision;
    final audios = List<Audio>.of(AudioLibrary.instance.audioCollection);
    void begin() {
      _scanning = true;
      _scanned = 0;
      _scanTotal = audios.length;
      _scanError = null;
    }

    if (notify) {
      setState(begin);
    } else {
      begin();
    }
    try {
      final snapshot = await _scanner.scan(
        audios,
        isCancelled: () => !mounted || generation != _generation,
        onProgress: (completed, total) {
          if (!mounted || generation != _generation) return;
          setState(() {
            _scanned = completed;
            _scanTotal = total;
          });
        },
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _librarySnapshot = snapshot;
        _scanning = false;
      });
    } on LibraryScanCancelled {
      // A newer library revision owns the next result, or the page is gone.
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _scanning = false;
        _scanError = ui("暂时无法完成统计，请重试。已有结果会保留。");
      });
    }
  }

  void _refreshIfLibraryChanged() {
    // PlaybackStatistics notifies every few seconds. Only a changed library
    // revision can schedule disk work; ordinary playback rebuilds reuse data.
    if (_requestedRevision == AudioLibrary.revision || _refreshScheduled) {
      return;
    }
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (mounted && _requestedRevision != AudioLibrary.revision) {
        _refreshLibrary();
      }
    });
    // Library notifications can arrive while playback and the UI are idle.
    // Coalesce them into one upcoming frame rather than waiting for playback.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _generation++;
    AudioLibrary.changes.removeListener(_libraryChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ListenableBuilder(
      listenable: widget.statistics ?? PlaybackStatistics.instance,
      builder: (context, _) {
        _refreshIfLibraryChanged();
        final stats = widget.statistics ?? PlaybackStatistics.instance;
        final library = _librarySnapshot;
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
                                tooltip: ui("重新核实文件大小与语言"),
                                onPressed: _scanning ? null : _refreshLibrary,
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
                      identity: 'statistics-listening-behavior',
                      order: 1,
                      child: _ListeningBehavior(statistics: stats),
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
                        if (_scanning) ...[
                          LinearProgressIndicator(
                            value:
                                _scanTotal == 0 ? null : _scanned / _scanTotal,
                          ),
                          const SizedBox(height: 8),
                          Text(ui("正在核实曲库 {0} / {1}…", [_scanned, _scanTotal])),
                        ] else if (_scanError != null)
                          Text(
                            _scanError!,
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
                            tracks: topPlay,
                            value: (item) => ui("{0} 次", [item.playCount]),
                            magnitude: (item) => item.playCount.toDouble(),
                          ),
                          _RankingCard(
                            title: ui("收听最久"),
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

class _ListeningBehavior extends StatelessWidget {
  const _ListeningBehavior({required this.statistics});

  final PlaybackStatistics statistics;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final peaks = statistics.mostActiveHours;
    final peakDuration =
        peaks.isEmpty ? 0 : statistics.hourlyMilliseconds[peaks.first];
    final peakDescription = peaks.isEmpty
        ? ui("播放后显示高峰时段")
        : peaks.length == 1
            ? ui("{0} · 按本机时间", [_formatListeningDuration(peakDuration)])
            : ui("{0} 个并列时段 · 每段 {1}",
                [peaks.length, _formatListeningDuration(peakDuration)]);
    final metrics = [
      _BehaviorMetric(
        icon: Symbols.headphones,
        label: ui("听歌时长"),
        value: _formatListeningDuration(statistics.totalListenMilliseconds),
        detail: ui("仅累计实际播放采样时间"),
      ),
      _BehaviorMetric(
        icon: Symbols.play_circle,
        label: ui("播放次数"),
        value: ui('{0} 次', [statistics.totalPlayCount]),
        detail: ui("{0} 首有记录 · 恢复播放不重复计次", [statistics.tracks.length]),
      ),
      _BehaviorMetric(
        icon: Symbols.schedule,
        label: ui("最活跃时段"),
        value: peaks.isEmpty ? '—' : _hourRange(peaks.first),
        detail: peakDescription,
        tooltip: peaks.isEmpty ? null : peaks.map(_hourRange).join('、'),
      ),
    ];
    return Card.filled(
      key: const ValueKey('listening-behavior'),
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
          borderRadius: AppShape.controlRadius,
          side:
              BorderSide(color: scheme.outlineVariant.withValues(alpha: .55))),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  ui("听歌行为"),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Tooltip(
                  message: ui("包含所有已保存记录。历史小时分布没有日期维度，不作为近7天或近30天数据展示。"),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: AppShape.smallRadius,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      child: Text(
                        ui("全部记录"),
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: scheme.onSecondaryContainer,
                                ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              ui("本地与联网歌曲一并统计，发现你一天中的听歌习惯。"),
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final textScale =
                    MediaQuery.textScalerOf(context).scale(14) / 14;
                final effectiveWidth =
                    constraints.maxWidth / math.max(1, textScale);
                final columns = effectiveWidth >= 720
                    ? 3
                    : effectiveWidth >= 460
                        ? 2
                        : 1;
                final width =
                    (constraints.maxWidth - (columns - 1) * 12) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final metric in metrics)
                      SizedBox(width: width, child: metric),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                Text(ui("完整 {0} 次", [statistics.totalCompletedCount])),
                Text(ui("提前跳过 {0} 次", [statistics.totalSkippedCount])),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              ui("24 小时收听分布"),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
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
              peakHours: peaks,
            ),
            const SizedBox(height: 12),
            Text(
              ui("暂停、缓冲和拖动播放进度不补算时长。休眠或采样间隔超过 2 秒时，仅计最近 2 秒，未观测的间隔不补记。"),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BehaviorMetric extends StatelessWidget {
  const _BehaviorMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final metric = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: AppShape.controlRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: scheme.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              ],
            ),
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
            Text(detail, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
    return tooltip == null ? metric : Tooltip(message: tooltip!, child: metric);
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
                AppScrollbar(
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
                                        borderRadius: BorderRadius.circular(6),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              height: plotHeight,
                                              child: Align(
                                                alignment:
                                                    Alignment.bottomCenter,
                                                child: SizedBox(
                                                  width: chartWidth / 24 * 0.58,
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
                                                        top: Radius.circular(4),
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
                                                hour.toString().padLeft(2, '0'),
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
                if (scrollable)
                  Text(
                    ui("横向滑动查看全部 24 个时段"),
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

double _statisticsTextScale(BuildContext context) =>
    math.max(1, MediaQuery.textScalerOf(context).scale(14) / 14);

/// Only the bounded overview/distribution cards use intrinsic row sizing.
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
              icon: Symbols.library_music,
              label: ui("总乐库"),
              value: library?.totalTracks.toString() ?? '—',
              detail: library == null
                  ? ui("正在统计")
                  : ui("本地 {0} · 联网 {1}",
                      [library.localTracks, library.onlineTracks]),
            ),
            _MetricCard(
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
              icon: Icons.folder_off_outlined,
              label: ui("文件读取情况"),
              value: library == null
                  ? '—'
                  : '${library.missingLocalTracks + library.inaccessibleLocalTracks} 首未计入空间',
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
            constraints.maxWidth / _statisticsTextScale(context) >= 1080
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
                  color: _distributionColors[language.index],
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ui("扇区按实际字节数划分；格式按文件扩展名分组。"),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          _DistributionView(
            chartId: 'format',
            availableWidth: contentWidth,
            slices: [
              for (var index = 0; index < visible.length; index++)
                _DistributionSlice(
                  label: visible[index].format,
                  value: visible[index].bytes,
                  amount: formatLibraryBytes(visible[index].bytes),
                  detail: ui("{0} 个源文件", [visible[index].fileCount]),
                  color:
                      _distributionColors[index % _distributionColors.length],
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
                        : '${entries[index].fileCount} 首',
                    entries[index].measuredFileCount,
                    entries[index].missingFileCount == 0
                        ? ''
                        : ' · 缺失 ${entries[index].missingFileCount} 首',
                    entries[index].inaccessibleFileCount == 0
                        ? ''
                        : ' · 不可读 ${entries[index].inaccessibleFileCount} 首'
                  ]),
                  percentage: distribution!.percentageOf(entries[index]),
                  color:
                      _distributionColors[index % _distributionColors.length],
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
                      : ' 缺失 ${stats.missingLocalTracks} 首，无权限/不可读 ${stats.inaccessibleLocalTracks} 首未计入空间。'
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
  });

  final String label;
  final int value;
  final String amount;
  final String detail;
  final Color color;
  final String? tooltip;
  final double? percentage;
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
      196.0 * textScale,
      math.max(1.0, availableWidth),
    );
    final horizontal = availableWidth / textScale >= 510;
    final legendWidth =
        horizontal ? availableWidth - side - 24 : availableWidth;
    final compactLegend = legendWidth / textScale < 280;
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
              padding: const EdgeInsets.all(40),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: math.max(1.0, side - 80),
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
    final legend = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (slices.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(ui("没有可用于分布统计的本地文件"), textAlign: TextAlign.center),
          ),
        for (final slice in slices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: slice.color,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox.square(dimension: 10),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (slice.tooltip == null)
                        Text(slice.label)
                      else
                        Tooltip(
                            message: slice.tooltip!, child: Text(slice.label)),
                      Text(slice.detail,
                          style: Theme.of(context).textTheme.bodySmall),
                      if (compactLegend) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            Text(slice.amount),
                            Text(
                              '${(slice.percentage ?? (total == 0 ? 0.0 : 100 * slice.value / total)).toStringAsFixed(1)}%',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (!compactLegend) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(slice.amount, textAlign: TextAlign.right),
                        Text(
                          '${(slice.percentage ?? (total == 0 ? 0.0 : 100 * slice.value / total)).toStringAsFixed(1)}%',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
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
    final scheme = Theme.of(context).colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      shape: AppShape.surface,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 144),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, color: scheme.primary),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
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
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Card.filled(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: AppShape.controlRadius,
          side: BorderSide(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: .55))),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12.0),
            child,
          ],
        ),
      ),
    );
  }
}

class _RankingCard extends StatelessWidget {
  const _RankingCard(
      {required this.title,
      required this.tracks,
      required this.value,
      required this.magnitude});
  final String title;
  final List<TrackPlaybackStatistics> tracks;
  final String Function(TrackPlaybackStatistics) value;
  final double Function(TrackPlaybackStatistics) magnitude;
  @override
  Widget build(BuildContext context) {
    final maximum = tracks.fold<double>(
        0, (maxValue, track) => math.max(maxValue, magnitude(track)));
    return _SectionCard(
        title: title,
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
