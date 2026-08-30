import 'package:dan_player/component/app_presentation.dart';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/build_index_state_view.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/collection.dart';
import 'package:dan_player/library/cover_cache.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/online/online_library.dart';
import 'package:dan_player/play_service/play_service.dart';
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
            builder: (context) => const AudioLibraryEditorDialog(),
          );
        },
      ),
    );
  }
}

class RefreshAudioLibraryTile extends StatelessWidget {
  const RefreshAudioLibraryTile({super.key});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsTile(
      description: ui("刷新音乐库"),
      icon: Symbols.sync,
      action: FilledButton.tonalIcon(
        icon: const Icon(Symbols.refresh),
        label: Text(ui("完整刷新")),
        onPressed: () async {
          final folders = AudioLibrary.instance.folders
              .map((folder) => folder.path)
              .toSet()
              .toList();
          if (folders.isEmpty) {
            showTextOnSnackBar("当前没有可刷新的音乐文件夹");
            return;
          }
          final indexPath = await getAppDataDir();
          if (!context.mounted) return;

          await showAppDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (context) => _RefreshAudioLibraryDialog(
              folders: folders,
              indexPath: indexPath,
            ),
          );
        },
      ),
    );
  }
}

Future<void> _reloadScannedLibrary() async {
  await AudioLibrary.initFromIndex();
  AudioLibrary.instance.replaceOnlineAudios(OnlineLibrary.instance.audios);
  await Future.wait([
    readCustomAudioOrder(),
    readPlaylists(),
    readLyricSources(),
  ]);
  if (PlayService.isInitialized) {
    PlayService.instance.playbackService.refreshAudioReferences(
      AudioLibrary.instance.audioByPath,
    );
  }
  await CoverCache.instance.clear();
  await AudioSearchIndex.instance.ensureBuilt();
}

class _RefreshAudioLibraryDialog extends StatelessWidget {
  const _RefreshAudioLibraryDialog({
    required this.folders,
    required this.indexPath,
  });

  final List<String> folders;
  final Directory indexPath;

  Future<void> _finish(BuildContext context) async {
    await _reloadScannedLibrary();

    if (context.mounted) Navigator.pop(context);
    showTextOnSnackBar("音乐库已刷新");
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return AlertDialog(
      title: AppDialogTitle(ui("刷新音乐库"), leading: const Icon(Symbols.sync)),
      content: SizedBox(
        width: 440.0,
        height: 110.0,
        child: Center(
          child: BuildIndexStateView(
            indexPath: indexPath,
            folders: folders,
            whenIndexBuilt: () => _finish(context),
            whenIndexFailed: (error, _) {
              if (context.mounted) Navigator.pop(context);
              showTextOnSnackBar("刷新音乐库失败：{0}", arguments: [error]);
            },
          ),
        ),
      ),
    );
  }
}

class AudioLibraryEditorDialog extends StatefulWidget {
  const AudioLibraryEditorDialog({super.key});

  @override
  State<AudioLibraryEditorDialog> createState() =>
      _AudioLibraryEditorDialogState();
}

class _AudioLibraryEditorDialogState extends State<AudioLibraryEditorDialog> {
  final folders = List.generate(
    AudioLibrary.instance.folders.length,
    (i) => AudioLibrary.instance.folders[i].path,
  );

  final applicationSupportDirectory = getAppDataDir();

  bool editing = true;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: EdgeInsets.zero,
      child: SizedBox(
        height: 450.0,
        width: 450.0,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: AppDialogTitle(
                  ui("管理文件夹"),
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: editing
                      ? ListView.builder(
                          itemCount: folders.length,
                          itemBuilder: (context, i) => ListTile(
                            title: Text(folders[i], maxLines: 1),
                            trailing: IconButton(
                              tooltip: ui("移除"),
                              color: scheme.error,
                              onPressed: () {
                                setState(() {
                                  folders.removeAt(i);
                                });
                              },
                              icon: const Icon(Symbols.delete),
                            ),
                          ),
                        )
                      : FutureBuilder(
                          future: applicationSupportDirectory,
                          builder: (context, snapshot) {
                            if (snapshot.data == null) {
                              return const Center(
                                child: Text("Fail to get app data dir."),
                              );
                            }

                            return Center(
                              child: BuildIndexStateView(
                                indexPath: snapshot.data!,
                                folders: folders,
                                whenIndexBuilt: () async {
                                  await _reloadScannedLibrary();
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                  }
                                },
                                whenIndexFailed: (error, _) {
                                  if (!mounted) return;
                                  setState(() {
                                    editing = true;
                                  });
                                  showTextOnSnackBar("更新音乐文件夹失败：{0}",
                                      arguments: [error]);
                                },
                              ),
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(height: 16.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () async {
                      final dirPicker = DirectoryPicker();
                      dirPicker.title = ui("选择文件夹");

                      final dir = dirPicker.getDirectory();
                      if (dir == null) return;

                      setState(() {
                        folders.add(dir.path);
                      });
                    },
                    child: Text(ui("添加")),
                  ),
                  const SizedBox(width: 8.0),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(ui("取消")),
                  ),
                  const SizedBox(width: 8.0),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        editing = false;
                      });
                    },
                    child: Text(ui("确定")),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
