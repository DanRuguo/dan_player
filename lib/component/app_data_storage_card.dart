import 'dart:io';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/statistics_bar_row.dart';
import 'package:dan_player/statistics/app_data_storage.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class AppDataStorageCard extends StatefulWidget {
  const AppDataStorageCard(
      {super.key,
      this.directory,
      this.reading,
      this.scanner = const AppDataStorageScanner()});
  final Directory? directory;

  /// The statistics page owns refreshes; standalone cards read once on entry.
  final Future<AppDataStorageSnapshot>? reading;
  final AppDataStorageScanner scanner;
  @override
  State<AppDataStorageCard> createState() => _AppDataStorageCardState();
}

class _AppDataStorageCardState extends State<AppDataStorageCard> {
  late Future<AppDataStorageSnapshot> _reading = widget.reading ?? _scan();
  Future<AppDataStorageSnapshot> _scan() async =>
      widget.scanner.scan(widget.directory ?? await getAppDataDir());
  @override
  void didUpdateWidget(covariant AppDataStorageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reading != oldWidget.reading ||
        widget.directory != oldWidget.directory ||
        widget.scanner != oldWidget.scanner) {
      _reading = widget.reading ?? _scan();
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    return Card.filled(
        shape: RoundedRectangleBorder(
            borderRadius: AppShape.controlRadius,
            side: BorderSide(
                color:
                    theme.colorScheme.outlineVariant.withValues(alpha: .55))),
        color: theme.colorScheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        child: Padding(
            padding: const EdgeInsets.all(18),
            child: FutureBuilder<AppDataStorageSnapshot>(
                future: _reading,
                builder: (context, result) {
                  final data = result.data;
                  final total = data?.bytes ?? 0;
                  final waiting =
                      result.connectionState == ConnectionState.waiting;
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Tooltip(
                              message:
                                  waiting ? ui('正在读取占用信息…') : ui('缓存与播放器数据占用'),
                              child: Icon(
                                  waiting
                                      ? Symbols.hourglass_empty
                                      : Symbols.database,
                                  color: theme.colorScheme.primary)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(ui('缓存与播放器数据占用'),
                                  style: theme.textTheme.titleMedium)),
                        ]),
                        if (data != null) ...[
                          Tooltip(
                              message: data.path,
                              child: Text(
                                  '${formatLibraryBytes(total)} · ${ui('{0} 个文件', [
                                        data.files
                                      ])}',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                      color: theme.colorScheme.primary))),
                          const SizedBox(height: 8),
                          for (final part in data.parts)
                            StatisticsBarRow(
                                label: ui(part.label),
                                wrapLabel: true,
                                detail: '${ui('{0} 个文件', [
                                      part.files
                                    ])}\n${part.paths.join('\n')}',
                                valueLabel: formatLibraryBytes(part.bytes),
                                value: part.bytes.toDouble(),
                                maximum: total.toDouble()),
                          if (data.truncated ||
                              data.unreadable > 0 ||
                              data.skippedLinks > 0)
                            Text(ui('统计未包含：不可读 {0} 项、链接 {1} 项{2}', [
                              data.unreadable,
                              data.skippedLinks,
                              data.truncated ? ui('；已达到扫描上限') : ''
                            ])),
                        ] else if (result.hasError)
                          Text(ui('无法读取此目录的占用信息'))
                        else
                          Text(ui('正在读取占用信息…')),
                        const SizedBox(height: 8),
                        Text(ui('实际文件字节；用户资料、自选图片与可重建缓存分别统计。链接不跟随，仅打开此页或手动刷新时读取。'),
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ]);
                })));
  }
}
