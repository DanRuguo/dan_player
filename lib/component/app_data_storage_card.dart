import 'dart:io';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/statistics_bar_row.dart';
import 'package:dan_player/component/statistics_card_header.dart';
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
      this.title,
      this.icon = Symbols.database,
      this.scopeDescription,
      this.headerControls,
      this.readingScope,
      this.scanner = const AppDataStorageScanner()});
  final Directory? directory;
  final String? title;
  final IconData icon;
  final String? scopeDescription;
  final Widget? headerControls;

  /// Different roots retain separate results. Refreshing the same root keeps
  /// its previous successful result until the new reading completes.
  final Object? readingScope;

  /// The statistics page owns refreshes; standalone cards read once on entry.
  final Future<AppDataStorageSnapshot>? reading;
  final AppDataStorageScanner scanner;
  @override
  State<AppDataStorageCard> createState() => _AppDataStorageCardState();
}

class _StorageReading {
  _StorageReading(this.future, this.data);
  final Future<AppDataStorageSnapshot> future;
  AppDataStorageSnapshot? data;
  Object? error;
  bool complete = false;
}

class _AppDataStorageCardState extends State<AppDataStorageCard> {
  late Future<AppDataStorageSnapshot> _reading = widget.reading ?? _scan();
  final _scopes = <Object?, _StorageReading>{};

  @override
  void initState() {
    super.initState();
    _rememberReading();
  }

  void _rememberReading() {
    final scope = widget.readingScope;
    final previous = _scopes[scope];
    if (identical(previous?.future, _reading)) return;
    // The combined card has two roots. Keep this cache bounded if a standalone
    // caller later reuses the same State for additional directories.
    if (previous == null && _scopes.length == 2) {
      _scopes.remove(_scopes.keys.first);
    }
    final entry = _StorageReading(_reading, previous?.data);
    _scopes[scope] = entry;
    // An inactive scope can finish while its FutureBuilder is unmounted.
    // Cache it without requesting a frame; the active builders already observe
    // their future. A replaced reading or disposed card no longer owns it.
    _reading.then<void>((data) {
      if (!mounted || !identical(_scopes[scope], entry)) return;
      entry.data = data;
      entry.complete = true;
    }, onError: (Object error, StackTrace stack) {
      if (!mounted || !identical(_scopes[scope], entry)) return;
      entry.data = null;
      entry.error = error;
      entry.complete = true;
    });
  }

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
    _rememberReading();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    final title = widget.title ?? ui('缓存与播放器数据占用');
    final entry = _scopes[widget.readingScope]!;
    final heading = FutureBuilder<AppDataStorageSnapshot>(
        future: _reading,
        builder: (context, result) {
          final waiting = !entry.complete &&
              result.connectionState == ConnectionState.waiting;
          return Row(
              key: const ValueKey('app-data-storage-heading'),
              children: [
                Tooltip(
                    message: waiting ? ui('正在读取占用信息…') : title,
                    child: Icon(waiting ? Symbols.hourglass_empty : widget.icon,
                        color: theme.colorScheme.primary)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(title, style: theme.textTheme.titleMedium)),
              ]);
        });
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
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.headerControls == null)
                    heading
                  else ...[
                    StatisticsCardHeader(
                        title: heading, controls: widget.headerControls!),
                    const SizedBox(height: 12),
                  ],
                  FutureBuilder<AppDataStorageSnapshot>(
                      key: ValueKey(widget.readingScope),
                      future: _reading,
                      initialData: entry.data,
                      builder: (context, result) {
                        final data = entry.error == null
                            ? result.data ?? entry.data
                            : null;
                        final total = data?.bytes ?? 0;
                        return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (data != null) ...[
                                Tooltip(
                                    message: data.path,
                                    child: Text(
                                        '${formatLibraryBytes(total)} · ${ui('{0} 个文件', [
                                              data.files
                                            ])}',
                                        style: theme.textTheme.titleLarge
                                            ?.copyWith(
                                                color: theme
                                                    .colorScheme.primary))),
                                const SizedBox(height: 8),
                                for (final part in data.parts)
                                  StatisticsBarRow(
                                      label: ui(part.label),
                                      wrapLabel: true,
                                      detail: '${ui('{0} 个文件', [
                                            part.files
                                          ])}\n${part.paths.join('\n')}',
                                      valueLabel:
                                          formatLibraryBytes(part.bytes),
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
                              ],
                              if (entry.error != null)
                                Text(ui('无法读取此目录的占用信息'))
                              else if (data == null)
                                Text(ui('正在读取占用信息…')),
                              const SizedBox(height: 8),
                              Text(
                                  widget.scopeDescription ??
                                      ui(
                                          '实际文件字节；用户资料、自选图片与可重建缓存分别统计。链接不跟随，仅打开此页或手动刷新时读取。'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant)),
                            ]);
                      }),
                ])));
  }
}
