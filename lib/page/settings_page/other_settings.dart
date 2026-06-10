import 'dart:convert';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/build_index_state_view.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/collection.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/utils.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

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
    return SettingsTile(
      description: "首选歌词来源",
      icon: Symbols.lyrics,
      action: SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment<bool>(
            value: true,
            icon: Icon(Symbols.cloud_off),
            label: Text("本地"),
          ),
          ButtonSegment<bool>(
            value: false,
            icon: Icon(Symbols.cloud),
            label: Text("在线"),
          ),
        ],
        selected: {settings.localLyricFirst},
        onSelectionChanged: (newSelection) async {
          if (newSelection.first == settings.localLyricFirst) return;

          setState(() {
            settings.localLyricFirst = newSelection.first;
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
      ..title = "备份歌词API"
      ..fileName = "dan_player_api_backup.json"
      ..defaultExtension = "json"
      ..filterSpecification = const {
        "Dan Player API 备份": "*.json",
        "所有文件": "*.*",
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
            "name": "歌词API",
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
      ..title = "加载歌词API备份"
      ..defaultExtension = "json"
      ..filterSpecification = const {
        "Dan Player API 备份": "*.json",
        "文本文件": "*.txt",
        "所有文件": "*.*",
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
    final controller = TextEditingController(text: settings.lyricApiUrl ?? "");
    final currentApi = settings.lyricApiUrl?.trim();
    final connectivityFuture = currentApi != null && currentApi.isNotEmpty
        ? testLyricApiConnectivity(currentApi)
        : null;

    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        String? errorText;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("歌词API"),
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
                        final confirmed = await showDialog<bool>(
                          context: dialogContext,
                          builder: (confirmContext) => AlertDialog(
                            title: const Text("删除歌词API"),
                            content: const Text(
                              "确认要删除该API吗？此操作不可恢复！",
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(confirmContext, false),
                                child: const Text("取消"),
                              ),
                              FilledButton.icon(
                                icon: const Icon(Symbols.block),
                                onPressed: () =>
                                    Navigator.pop(confirmContext, true),
                                label: const Text("确认删除"),
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
                          label: const Text("备份当前API"),
                          onPressed: _backupCurrentApis,
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Symbols.file_open),
                          label: const Text("加载备份"),
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
                        labelText: "接口地址",
                        hintText: "https://example.com/lyric",
                        errorText: errorText,
                        prefixIcon: const Icon(Symbols.api),
                      ),
                    ),
                    const SizedBox(height: 12.0),
                    Text(
                      "请求方式：GET；参数：title、artist、album、duration、fileName、displayTitle。返回 JSON 支持 "
                      "{type:\"lrc\", lyric:\"...\", translation:\"...\"}，type 可为 lrc/qrc/krc。",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, ""),
                  child: const Text("恢复默认"),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("取消"),
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
                          errorText = "请输入 http 或 https 接口地址";
                        });
                        return;
                      }
                    }
                    Navigator.pop(context, value);
                  },
                  child: const Text("保存"),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    if (result == null) return;

    setState(() {
      final value = result.trim();
      settings.lyricApiUrl = value.isEmpty ? null : value;
    });
    await settings.saveSettings();
    showTextOnSnackBar(
      settings.lyricApiUrl == null ? "已恢复默认歌词API" : "歌词API已更新",
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      description: "歌词API",
      icon: Symbols.api,
      action: FilledButton.icon(
        icon: const Icon(Symbols.api),
        label: Text(settings.lyricApiUrl == null ? "设置接口" : "已自定义"),
        onPressed: _openEditor,
      ),
    );
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasCustomApi = currentApi != null && currentApi!.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(10.0),
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
                  "当前接口",
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (hasCustomApi) ...[
                _LyricApiStatusIcon(future: connectivityFuture),
                Tooltip(
                  message: "删除当前歌词API",
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
            hasCustomApi ? currentApi! : "使用内置 QQ / 酷狗 / 网易歌词源",
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
    final scheme = Theme.of(context).colorScheme;
    final future = widget.future;

    if (future == null) {
      return _StatusTooltipIcon(
        tooltipKey: _tooltipKey,
        message: "当前使用内置歌词源",
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
            message: "正在测试歌词API连通性",
            icon: Symbols.sync,
            color: scheme.primary,
          );
        }

        final result = snapshot.data;
        if (result == null) {
          return _StatusTooltipIcon(
            tooltipKey: _tooltipKey,
            message: "测试失败：未获得结果",
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
    return SettingsTile(
      description: "文件夹管理",
      icon: Symbols.folder_managed,
      action: FilledButton.icon(
        icon: const Icon(Symbols.folder),
        label: const Text("文件夹管理"),
        onPressed: () {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const AudioLibraryEditorDialog(),
          );
        },
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
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
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
                child: Text(
                  "管理文件夹",
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
                              tooltip: "移除",
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
                                  await AudioLibrary.initFromIndex();
                                  await Future.wait([
                                    readCustomAudioOrder(),
                                    readCollections(),
                                    readPlaylists(),
                                    readLyricSources(),
                                  ]);
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                  }
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
                      dirPicker.title = "选择文件夹";

                      final dir = dirPicker.getDirectory();
                      if (dir == null) return;

                      setState(() {
                        folders.add(dir.path);
                      });
                    },
                    child: const Text("添加"),
                  ),
                  const SizedBox(width: 8.0),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("取消"),
                  ),
                  const SizedBox(width: 8.0),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        editing = false;
                      });
                    },
                    child: const Text("确定"),
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
