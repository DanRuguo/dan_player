import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/library_refresh_progress.dart';
import 'package:dan_player/component/library_folders_dialog.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/library_health.dart';
import 'package:dan_player/library/library_refresh.dart';
import 'package:dan_player/library/library_mutation_gate.dart';
import 'package:dan_player/library/cover_cache.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/online/online_library.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/page/folders_page.dart' show folderDisplayName;
import 'package:dan_player/search/audio_search_index.dart';
import 'package:dan_player/utils.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:flutter/material.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

class RestoreSessionSwitch extends StatefulWidget {
  const RestoreSessionSwitch({super.key});

  @override
  State<RestoreSessionSwitch> createState() => _RestoreSessionSwitchState();
}

class _RestoreSessionSwitchState extends State<RestoreSessionSwitch> {
  final settings = AppSettings.instance;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsSwitchTile(
      title: Text(ui("恢复上次播放会话")),
      subtitle: Text(ui(settings.restoreLastSession
          ? '下次启动恢复队列与播放位置，保持暂停。'
          : '下次启动不恢复上次播放队列。')),
      icon: Symbols.history,
      value: settings.restoreLastSession,
      onChanged: (value) async {
        setState(() => settings.restoreLastSession = value);
        await settings.saveSettings();
      },
    );
  }
}

class DefaultLyricSourceControl extends StatefulWidget {
  const DefaultLyricSourceControl({super.key});

  @override
  State<DefaultLyricSourceControl> createState() =>
      _DefaultLyricSourceControlState();
}

class _DefaultLyricSourceControlState extends State<DefaultLyricSourceControl> {
  final settings = AppSettings.instance;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsTile(
      description: ui("首选歌词来源"),
      subtitle: ui('仅决定本地歌词与在线候选的优先顺序'),
      icon: Symbols.lyrics,
      action: AppSegmentedControl<bool>(
        value: settings.localLyricFirst,
        semanticLabel: ui('首选歌词来源'),
        options: [
          AppSegmentOption<bool>(
            value: true,
            icon: Symbols.cloud_off,
            label: ui("本地"),
          ),
          AppSegmentOption<bool>(
            value: false,
            icon: Symbols.cloud,
            label: ui("在线"),
          ),
        ],
        onChanged: (newSelection) async {
          if (newSelection == settings.localLyricFirst) return;

          setState(() {
            settings.localLyricFirst = newSelection;
          });
          await settings.saveSettings();
        },
      ),
    );
  }
}

class LyricApiEditor extends StatefulWidget {
  const LyricApiEditor({super.key});

  @override
  State<LyricApiEditor> createState() => _LyricApiEditorState();
}

class _LyricApiEditorState extends State<LyricApiEditor> {
  final settings = AppSettings.instance;

  Future<void> _backupCurrentApis() async {
    final currentApi = settings.lyricApiUrl?.trim();
    if (currentApi == null || currentApi.isEmpty) {
      showTextOnSnackBar("当前没有已保存的歌词API可备份");
      return;
    }

    final picker = SaveFilePicker()
      ..title = ui("备份歌词API")
      ..fileName = "dan_player_api_backup.json"
      ..defaultExtension = "json"
      ..filterSpecification = {
        ui("Dan Player API 备份"): "*.json",
        ui("所有文件"): "*.*",
      };

    final file = picker.getFile();
    if (file == null) return;

    try {
      final backup = {
        "version": 1,
        "app": AppSettings.appDisplayName,
        "createdAt": DateTime.now().toIso8601String(),
        "currentLyricApiUrl": currentApi,
        "apis": [
          {
            "type": "lyric",
            "name": ui("歌词API"),
            "url": currentApi,
          }
        ],
      };
      await file.writeAsString(
        const JsonEncoder.withIndent("  ").convert(backup),
        encoding: utf8,
      );
      showTextOnSnackBar("歌词API备份已保存");
    } catch (err, trace) {
      LOGGER.e(err, stackTrace: trace);
      showTextOnSnackBar("备份歌词API失败");
    }
  }

  Future<String?> _loadApiBackup() async {
    final picker = OpenFilePicker()
      ..title = ui("加载歌词API备份")
      ..defaultExtension = "json"
      ..filterSpecification = {
        ui("Dan Player API 备份"): "*.json",
        ui("文本文件"): "*.txt",
        ui("所有文件"): "*.*",
      };

    final file = picker.getFile();
    if (file == null) return null;

    try {
      final text = await file.readAsString(encoding: utf8);
      final url = _extractLyricApiUrlFromBackup(text);
      if (url == null || url.trim().isEmpty) {
        showTextOnSnackBar("备份文件中没有可用的歌词API");
        return null;
      }
      return url.trim();
    } catch (err, trace) {
      LOGGER.e(err, stackTrace: trace);
      showTextOnSnackBar("加载歌词API备份失败");
      return null;
    }
  }

  String? _extractLyricApiUrlFromBackup(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty) return null;

    final directUri = Uri.tryParse(text);
    if (directUri != null &&
        (directUri.scheme == "http" || directUri.scheme == "https") &&
        directUri.host.isNotEmpty) {
      return text;
    }

    final decoded = json.decode(text);
    if (decoded is! Map) return null;

    final current = decoded["currentLyricApiUrl"];
    if (current is String && current.trim().isNotEmpty) {
      return current.trim();
    }

    final apis = decoded["apis"];
    if (apis is List) {
      for (final item in apis) {
        if (item is! Map) continue;
        final type = item["type"];
        final url = item["url"];
        if (url is String &&
            url.trim().isNotEmpty &&
            (type == null || type == "lyric")) {
          return url.trim();
        }
      }
    }

    return null;
  }

  Future<void> _openEditor() async {
    final currentApi = settings.lyricApiUrl?.trim();
    final connectivityFuture = currentApi != null && currentApi.isNotEmpty
        ? testLyricApiConnectivity(currentApi)
        : null;

    String? errorText;
    final result = await showAppDialog<String?>(
      context: context,
      builder: (dialogContext) {
        return _LyricApiControllerScope(
          initialText: currentApi ?? '',
          builder: (context, controller) => StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                scrollable: true,
                title: AppDialogTitle(ui("歌词API")),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CurrentLyricApiView(
                        currentApi: currentApi,
                        connectivityFuture: connectivityFuture,
                        onDelete: () async {
                          final confirmed = await showAppDialog<bool>(
                            context: dialogContext,
                            builder: (confirmContext) => AlertDialog(
                              scrollable: true,
                              title: AppDialogTitle(ui("删除歌词API")),
                              content: Text(
                                ui("确认要删除该API吗？此操作不可恢复！"),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(confirmContext, false),
                                  child: Text(ui("取消")),
                                ),
                                FilledButton.icon(
                                  icon: const Icon(Symbols.block),
                                  onPressed: () =>
                                      Navigator.pop(confirmContext, true),
                                  label: Text(ui("确认删除")),
                                ),
                              ],
                            ),
                          );

                          if (confirmed == true && dialogContext.mounted) {
                            Navigator.pop(dialogContext, "");
                          }
                        },
                      ),
                      const SizedBox(height: 12.0),
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 8.0,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Symbols.backup),
                            label: Text(ui("备份当前API")),
                            onPressed: _backupCurrentApis,
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Symbols.file_open),
                            label: Text(ui("加载备份")),
                            onPressed: () async {
                              final loadedApi = await _loadApiBackup();
                              if (loadedApi == null) return;

                              setDialogState(() {
                                controller.text = loadedApi;
                                errorText = null;
                              });
                              showTextOnSnackBar("已读取API备份，请点击保存应用");
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16.0),
                      TextField(
                        controller: controller,
                        decoration: InputDecoration(
                          labelText: ui("接口地址"),
                          hintText: "https://example.com/lyric",
                          errorText: errorText,
                          prefixIcon: const Icon(Symbols.api),
                        ),
                      ),
                      const SizedBox(height: 12.0),
                      Text(
                        ui("请求方式：GET；参数：title、artist、album、duration、fileName、displayTitle。返回 JSON 支持 {type:\"lrc\", lyric:\"...\", translation:\"...\"}，type 可为 lrc/qrc/krc。"),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, ""),
                    child: Text(ui("恢复默认")),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(ui("取消")),
                  ),
                  FilledButton(
                    onPressed: () {
                      final value = controller.text.trim();
                      if (value.isNotEmpty) {
                        final uri = Uri.tryParse(value);
                        if (uri == null ||
                            !(uri.scheme == "http" || uri.scheme == "https") ||
                            uri.host.isEmpty) {
                          setDialogState(() {
                            errorText = ui("请输入 http 或 https 接口地址");
                          });
                          return;
                        }
                      }
                      Navigator.pop(context, value);
                    },
                    child: Text(ui("保存")),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (result == null) return;

    setState(() {
      final value = result.trim();
      settings.lyricApiUrl = value.isEmpty ? null : value;
    });
    await settings.saveSettings();
    showTextOnSnackBar(
      settings.lyricApiUrl == null ? ui("已恢复默认歌词API") : ui("歌词API已更新"),
    );
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsTile(
      description: ui("歌词API"),
      icon: Symbols.api,
      action: FilledButton.icon(
        icon: const Icon(Symbols.api),
        label: Text(settings.lyricApiUrl == null ? ui("设置接口") : ui("已自定义")),
        onPressed: _openEditor,
      ),
    );
  }
}

/// Route results arrive before reverse-transition frames finish. Keep the
/// field's controller alive until the dialog subtree actually unmounts, including
/// any notification-driven rebuilds during its exit animation.
class _LyricApiControllerScope extends StatefulWidget {
  const _LyricApiControllerScope({
    required this.initialText,
    required this.builder,
  });
  final String initialText;
  final Widget Function(BuildContext, TextEditingController) builder;

  @override
  State<_LyricApiControllerScope> createState() =>
      _LyricApiControllerScopeState();
}

class _LyricApiControllerScopeState extends State<_LyricApiControllerScope> {
  late final _controller = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return widget.builder(context, _controller);
  }
}

class _CurrentLyricApiView extends StatelessWidget {
  const _CurrentLyricApiView({
    required this.currentApi,
    required this.connectivityFuture,
    required this.onDelete,
  });

  final String? currentApi;
  final Future<LyricApiConnectivityResult>? connectivityFuture;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasCustomApi = currentApi != null && currentApi!.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.48),
        borderRadius: AppShape.surfaceRadius,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ui("当前接口"),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (hasCustomApi) ...[
                _LyricApiStatusIcon(future: connectivityFuture),
                Tooltip(
                  message: ui("删除当前歌词API"),
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Symbols.block, color: scheme.error),
                    onPressed: onDelete,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6.0),
          SelectableText(
            hasCustomApi ? currentApi! : ui("使用内置 QQ / 酷狗 / 网易歌词源"),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: hasCustomApi
                  ? scheme.onSurfaceVariant
                  : scheme.onSurfaceVariant.withValues(alpha: 0.82),
            ),
          ),
        ],
      ),
    );
  }
}

class _LyricApiStatusIcon extends StatefulWidget {
  const _LyricApiStatusIcon({required this.future});

  final Future<LyricApiConnectivityResult>? future;

  @override
  State<_LyricApiStatusIcon> createState() => _LyricApiStatusIconState();
}

class _LyricApiStatusIconState extends State<_LyricApiStatusIcon> {
  final _tooltipKey = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final future = widget.future;

    if (future == null) {
      return _StatusTooltipIcon(
        tooltipKey: _tooltipKey,
        message: ui("当前使用内置歌词源"),
        icon: Symbols.cloud_done,
        color: scheme.primary,
      );
    }

    return FutureBuilder<LyricApiConnectivityResult>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _StatusTooltipIcon(
            tooltipKey: _tooltipKey,
            message: ui("正在测试歌词API连通性"),
            icon: Symbols.sync,
            color: scheme.primary,
          );
        }

        final result = snapshot.data;
        if (result == null) {
          return _StatusTooltipIcon(
            tooltipKey: _tooltipKey,
            message: ui("测试失败：未获得结果"),
            icon: Symbols.error,
            color: scheme.error,
          );
        }

        if (result.lyricRecognized) {
          return _StatusTooltipIcon(
            tooltipKey: _tooltipKey,
            message: result.message,
            icon: Symbols.check_circle,
            color: scheme.primary,
          );
        }

        return _StatusTooltipIcon(
          tooltipKey: _tooltipKey,
          message: result.message,
          icon: result.isReachable ? Symbols.warning : Symbols.error,
          color: result.isReachable ? scheme.tertiary : scheme.error,
        );
      },
    );
  }
}

class _StatusTooltipIcon extends StatelessWidget {
  const _StatusTooltipIcon({
    required this.tooltipKey,
    required this.message,
    required this.icon,
    required this.color,
  });

  final GlobalKey<TooltipState> tooltipKey;
  final String message;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Tooltip(
      key: tooltipKey,
      message: message,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, color: color),
        onPressed: () => tooltipKey.currentState?.ensureTooltipVisible(),
      ),
    );
  }
}

class AudioLibraryEditor extends StatelessWidget {
  const AudioLibraryEditor({super.key});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsTile(
      description: ui("文件夹管理"),
      icon: Symbols.folder_managed,
      action: FilledButton.icon(
        icon: const Icon(Symbols.folder),
        label: Text(ui("文件夹管理")),
        onPressed: () {
          showAppDialog(
            context: context,
            barrierDismissible: false,
            dialogBottomInset: 0,
            builder: (context) => const AudioLibraryEditorDialog(),
          );
        },
      ),
    );
  }
}

class RefreshAudioLibraryTile extends StatefulWidget {
  const RefreshAudioLibraryTile({super.key, this.onRefresh});

  /// Injectable operation for isolated UI tests; production uses the native
  /// scanner and only reloads the library after its atomic commit.
  final Future<void> Function(bool incremental)? onRefresh;

  @override
  State<RefreshAudioLibraryTile> createState() =>
      _RefreshAudioLibraryTileState();
}

class _RefreshAudioLibraryTileState extends State<RefreshAudioLibraryTile> {
  bool _busy = false;

  Future<void> _refresh(bool incremental) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (widget.onRefresh != null) {
        await widget.onRefresh!(incremental);
        return;
      }
      final existing = LibraryRefreshTask.active.value;
      if (existing != null) {
        await _showTask(existing);
        return;
      }
      final folders = AudioLibrary.instance.scanRoots;
      if (folders.isEmpty) {
        showTextOnSnackBar("当前没有可刷新的音乐文件夹");
        return;
      }
      final before =
          LibraryRefreshSnapshot.capture(AudioLibrary.instance.audioCollection);
      final indexPath = await getAppDataDir();
      if (!mounted) return;
      final task = LibraryRefreshTask.native(
        incremental: incremental,
        folders: folders,
        indexPath: indexPath,
        commit: () => _reloadScannedLibrary(
            incremental: incremental, before: before, indexPath: indexPath),
      );
      await _showTask(task);
    } catch (_) {
      if (mounted) showTextOnSnackBar("刷新未完成，原曲库仍保留，请检查文件夹访问权限后重试");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showTask(LibraryRefreshTask task) async {
    var dialogOpen = true;
    unawaited(task.completed.then((_) {
      if (!dialogOpen) _reportRefreshOutcome(task);
    }));
    await showAppDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _RefreshAudioLibraryDialog(task: task));
    dialogOpen = false;
    if (task.isTerminal) _reportRefreshOutcome(task);
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsTile(
      description: ui("刷新音乐库"),
      subtitle: ui("增量刷新只读取新增或改动歌曲；完整刷新重新读取全部歌曲信息"),
      icon: Symbols.sync,
      action: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: ValueListenableBuilder<LibraryRefreshTask?>(
          valueListenable: LibraryRefreshTask.active,
          builder: (context, task, _) => task != null
              ? FilledButton.tonalIcon(
                  icon: const Icon(Symbols.progress_activity),
                  label: Text(ui('查看扫描进度')),
                  onPressed: _busy ? null : () => _refresh(task.incremental))
              : Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      key: const ValueKey('library-refresh-incremental'),
                      icon: const Icon(Symbols.sync),
                      label: Text(ui("增量刷新")),
                      onPressed: _busy ? null : () => _refresh(true),
                    ),
                    FilledButton.tonalIcon(
                      key: const ValueKey('library-refresh-full'),
                      icon: const Icon(Symbols.refresh),
                      label: Text(ui("完整刷新")),
                      onPressed: _busy ? null : () => _refresh(false),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _RefreshSyncFailure implements Exception {}

void _reportRefreshOutcome(LibraryRefreshTask task) {
  if (!task.takeCompletionNotice()) return;
  if (task.phase == LibraryRefreshPhase.cancelled) {
    showTextOnSnackBar('扫描已取消，原曲库未改变');
  } else if (task.error != null) {
    showTextOnSnackBar(task.error is LibraryMutationBusy
        ? '曲库操作正在进行，请等待刷新或歌曲信息保存完成后重试'
        : task.error is _RefreshSyncFailure
            ? '索引已更新，但界面同步未完成，请重新打开应用'
            : '刷新未完成，原曲库仍保留，请检查文件夹访问权限后重试');
  } else if (task.pendingMetadata == 0) {
    showTextOnSnackBar('音乐库已刷新');
  } else {
    showTextOnSnackBar('音乐库已刷新，{0}首暂时保留原信息或文件名，下次刷新会重试',
        arguments: [task.pendingMetadata]);
  }
}

Future<int> _reloadScannedLibrary({
  bool incremental = false,
  LibraryRefreshSnapshot? before,
  Directory? indexPath,
}) async {
  final previous = before ??
      LibraryRefreshSnapshot.capture(AudioLibrary.instance.audioCollection);
  final directory = indexPath ?? await getAppDataDir();
  try {
    final count = await completeLibraryRefresh(
      incremental: incremental,
      before: previous,
      readCommitted: () =>
          LibraryRefreshSnapshot.read(File('${directory.path}/index.json')),
      invalidateCover: CoverCache.instance.invalidate,
      clearCovers: CoverCache.instance.clear,
      reload: () async {
        await AudioLibrary.initFromIndex();
        AudioLibrary.instance
            .replaceOnlineAudios(OnlineLibrary.instance.audios);
        // The progress dialog can be closed while scanning. Rebind live
        // objects so a late reload cannot replace playlist or lyric edits
        // that the user made while the native task was running.
        playlistTree.refreshAudioReferences(AudioLibrary.instance.audioByPath);
        if (PlayService.isInitialized) {
          PlayService.instance.playbackService.refreshAudioReferences(
            AudioLibrary.instance.audioByPath,
          );
        }
        await AudioSearchIndex.instance.ensureBuilt();
      },
    );
    try {
      await LibraryHealthService(directory)
          .recordScan(AudioLibrary.instance.scanRoots);
    } catch (error) {
      LOGGER.w('[library health] $error');
    }
    return count;
  } catch (_) {
    throw _RefreshSyncFailure();
  }
}

class _RefreshAudioLibraryDialog extends StatelessWidget {
  const _RefreshAudioLibraryDialog({
    required this.task,
  });

  final LibraryRefreshTask task;

  Future<void> _finish(BuildContext context) async {
    if (context.mounted) Navigator.pop(context);
    _reportRefreshOutcome(task);
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return PopScope(
      canPop: true,
      child: AlertDialog(
        scrollable: true,
        title: AppDialogTitle(ui(task.incremental ? "增量刷新" : "完整刷新"),
            leading: const Icon(Symbols.sync)),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(ui("按路径、大小和修改时间检查；旧索引首次可能需要补读，内容变化但大小和时间均未变时请使用完整刷新")),
            const SizedBox(height: 16),
            LibraryRefreshProgress(
              task: task,
              onSettled: (_) => _finish(context),
              onBackground: () => Navigator.pop(context),
            ),
          ]),
        ),
      ),
    );
  }
}

class AudioLibraryEditorDialog extends StatefulWidget {
  const AudioLibraryEditorDialog(
      {super.key, this.loadIndexPath = getAppDataDir});

  final Future<Directory> Function() loadIndexPath;

  @override
  State<AudioLibraryEditorDialog> createState() =>
      _AudioLibraryEditorDialogState();
}

class _AudioLibraryEditorDialogState extends State<AudioLibraryEditorDialog> {
  final folders = List<String>.from(AudioLibrary.instance.scanRoots);

  Directory? _indexPath;
  LibraryRefreshTask? _task;
  bool editing = true;

  Future<void> _confirm() async {
    if (!editing) return;
    setState(() {
      editing = false;
      _indexPath = null;
    });
    try {
      final directory = await widget.loadIndexPath();
      if (!mounted) return;
      final task = LibraryRefreshTask.native(
          folders: folders,
          indexPath: directory,
          incremental: false,
          commit: () => _reloadScannedLibrary(indexPath: directory));
      unawaited(task.completed.then((_) {
        if (!mounted) _reportRefreshOutcome(task);
      }));
      setState(() {
        _indexPath = directory;
        _task = task;
      });
    } catch (error, trace) {
      LOGGER.e('[library folder] index directory unavailable',
          error: error, stackTrace: trace);
      if (!mounted) return;
      setState(() => editing = true);
      showTextOnSnackBar("刷新未完成，原曲库仍保留，请检查文件夹访问权限后重试", context: context);
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);

    return PopScope(
      canPop: true,
      child: LibraryFoldersDialog(
        folders: folders,
        folderName: folderDisplayName,
        editing: editing,
        onAdd: () {
          final dirPicker = DirectoryPicker()..title = ui('选择文件夹');
          final dir = dirPicker.getDirectory();
          if (dir == null || !mounted) return;
          setState(() => folders.add(dir.path));
        },
        onRemove: (index) {
          if (editing) setState(() => folders.removeAt(index));
        },
        onCancel: () => Navigator.pop(context),
        onConfirm: _confirm,
        progress: _indexPath == null || _task == null
            ? null
            : LibraryRefreshProgress(
                key: ObjectKey(_task),
                task: _task!,
                onBackground: () => Navigator.pop(context),
                onSettled: (task) {
                  if (!mounted) return;
                  _reportRefreshOutcome(task);
                  if (task.phase == LibraryRefreshPhase.completed) {
                    Navigator.pop(context);
                  } else {
                    setState(() {
                      editing = true;
                      _task = null;
                    });
                  }
                },
              ),
      ),
    );
  }
}

String preventSleepStatusText(bool enabled, String nativeStatus) {
  if (!enabled) return ui('已关闭 · 使用系统休眠设置');
  if (nativeStatus == '已生效') return ui('已开启 · 播放中，防休眠已生效');
  if (nativeStatus.startsWith('电源请求失败')) return ui('未生效 · 请重新切换开关');
  return ui('已开启 · 等待播放');
}

class PreventSleepSwitch extends StatelessWidget {
  const PreventSleepSwitch({super.key});
  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ValueListenableBuilder(
      valueListenable: AppSettings.instance.experience,
      builder: (context, pref, _) => ValueListenableBuilder(
        valueListenable: DesktopIntegration.instance.powerRequestStatus,
        builder: (context, status, _) => SettingsSwitchTile(
          icon: Symbols.bedtime,
          title: Text(ui('播放时防止自动休眠')),
          subtitle:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ui('播放时保持电脑唤醒；暂停后恢复自动休眠。屏幕仍可熄灭。')),
            const SizedBox(height: 4),
            Text(
                preventSleepStatusText(pref.preventSleepDuringPlayback, status),
                style: TextStyle(
                    color: status.startsWith('电源请求失败') &&
                            pref.preventSleepDuringPlayback
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary)),
          ]),
          value: pref.preventSleepDuringPlayback,
          onChanged: (v) async {
            AppSettings.instance.experience.value =
                pref.copyWith(preventSleepDuringPlayback: v);
            try {
              await AppSettings.instance.saveSettings(throwOnError: true);
            } catch (_) {
              if (context.mounted)
                showPresentationNotice(ui('设置保存失败，本次会话仍保留当前选择'),
                    context: context, kind: AppNoticeKind.error);
            }
          },
        ),
      ),
    );
  }
}
