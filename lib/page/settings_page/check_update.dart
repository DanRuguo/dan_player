import 'package:dan_player/component/app_presentation.dart';
import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/src/rust/api/utils.dart';
import 'package:dan_player/update/update_service.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

Future<void> checkForUpdateAndPresent(
  BuildContext context, {
  bool silent = false,
}) async {
  try {
    final update = await UpdateService.instance.checkLatest(
      includeIgnored: !silent,
    );
    await UpdateService.instance.recordSuccessfulCheck();
    if (!context.mounted) return;
    if (update == null) {
      if (!silent) showTextOnSnackBar("当前已是最新稳定版");
      return;
    }
    if (silent) {
      showAppNotice(
        ui("发现稳定版 {0}", [update.version]),
        context: context,
        duration: const Duration(seconds: 12),
        kind: AppNoticeKind.info,
        actionLabel: ui("查看"),
        onAction: () {
          if (context.mounted) {
            unawaited(_showUpdateDialog(context, update));
          }
        },
      );
      return;
    }
    await _showUpdateDialog(context, update);
  } on UpdateException catch (error, stackTrace) {
    LOGGER.e(error.cause ?? error, stackTrace: stackTrace);
    if (!silent && context.mounted) showTextOnSnackBar(error.message);
  } catch (error, stackTrace) {
    LOGGER.e(error, stackTrace: stackTrace);
    if (!silent && context.mounted) showTextOnSnackBar("检查更新失败，请稍后重试");
  }
}

Future<void> _showUpdateDialog(
    BuildContext context, AvailableUpdate update) async {
  await showAppDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => NewestUpdateView(update: update),
  );
}

Future<void> _openSafeLink(String raw, {bool githubOnly = false}) async {
  final uri = Uri.tryParse(raw);
  final allowedScheme =
      uri?.scheme == 'https' || (!githubOnly && uri?.scheme == 'http');
  final allowedHost = !githubOnly || uri?.host.toLowerCase() == 'github.com';
  if (uri == null || !allowedScheme || !allowedHost || uri.host.isEmpty) {
    showTextOnSnackBar("已阻止不安全的外部链接");
    return;
  }
  if (!await launchInBrowser(uri: uri.toString())) {
    showTextOnSnackBar("无法打开链接");
  }
}

/// Schedules one unobtrusive update check after the library screen is ready.
class AutomaticUpdateCheck extends StatefulWidget {
  const AutomaticUpdateCheck({super.key, required this.child});

  final Widget child;

  @override
  State<AutomaticUpdateCheck> createState() => _AutomaticUpdateCheckState();
}

class _AutomaticUpdateCheckState extends State<AutomaticUpdateCheck> {
  static bool _scheduledForThisProcess = false;

  @override
  void initState() {
    super.initState();
    if (!_scheduledForThisProcess &&
        UpdateService.instance.shouldCheckAutomatically) {
      _scheduledForThisProcess = true;
      Future<void>.delayed(const Duration(seconds: 8), () async {
        if (mounted) await checkForUpdateAndPresent(context, silent: true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return widget.child;
  }
}

class CheckForUpdate extends StatefulWidget {
  const CheckForUpdate({super.key});

  @override
  State<CheckForUpdate> createState() => _CheckForUpdateState();
}

class _CheckForUpdateState extends State<CheckForUpdate> {
  bool _isChecking = false;

  Future<void> _check() async {
    setState(() => _isChecking = true);
    await checkForUpdateAndPresent(context);
    if (mounted) setState(() => _isChecking = false);
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final settings = AppSettings.instance;
    final lastCheck = settings.lastUpdateCheckAt;
    return SettingsSurface(
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSwitchTile(
          surface: false,
          contentPadding: SettingsSurface.embeddedRowPadding,
          title: Text(ui("自动检查稳定版更新（每天最多一次）")),
          icon: Symbols.system_update_alt,
          value: settings.autoCheckUpdates,
          onChanged: (value) async {
            setState(() => settings.autoCheckUpdates = value);
            await settings.saveSettings();
          },
        ),
        const SizedBox(height: 10.0),
        Wrap(
          spacing: 12.0,
          runSpacing: 8.0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              icon: const Icon(Symbols.update),
              label: Text(ui("立即检查")),
              onPressed: _isChecking ? null : _check,
            ),
            Text(ui("当前版本：{0}", [AppSettings.version])),
            if (lastCheck != null)
              Text(
                ui("上次检查：{0}", [_formatDateTime(lastCheck)]),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            if (_isChecking)
              const SizedBox.square(
                dimension: 18.0,
                child: CircularProgressIndicator(strokeWidth: 2.0),
              ),
          ],
        ),
      ],
    ));
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }
}

class NewestUpdateView extends StatefulWidget {
  const NewestUpdateView({super.key, required this.update});

  final AvailableUpdate update;

  @override
  State<NewestUpdateView> createState() => _NewestUpdateViewState();
}

class _NewestUpdateViewState extends State<NewestUpdateView> {
  final _detailsScroll = ScrollController();
  final _actionsScroll = ScrollController();
  bool _downloading = false;
  UpdateDownloadProgress? _progress;
  UpdateDownloadResult? _result;
  UpdateDownloadCancellation? _cancellation;
  String? _error;

  Future<void> _download() async {
    if (_downloading) return;
    final releaseUrl = widget.update.release.htmlUrl;
    if (widget.update.asset == null) {
      if (releaseUrl != null) await _openSafeLink(releaseUrl, githubOnly: true);
      return;
    }

    setState(() {
      _downloading = true;
      _error = null;
      _progress = null;
      _result = null;
    });
    final cancellation = UpdateDownloadCancellation();
    _cancellation = cancellation;
    try {
      final result = await UpdateService.instance.download(
        widget.update,
        onProgress: (progress) {
          if (mounted &&
              !cancellation.isCancelled &&
              identical(_cancellation, cancellation)) {
            setState(() => _progress = progress);
          }
        },
        cancellation: cancellation,
      );
      if (mounted &&
          !cancellation.isCancelled &&
          identical(_cancellation, cancellation)) {
        setState(() => _result = result);
      }
    } on UpdateException catch (error, stackTrace) {
      LOGGER.e(error.cause ?? error, stackTrace: stackTrace);
      if (mounted && !cancellation.isCancelled) {
        setState(() => _error = error.message);
      }
    } catch (error, stackTrace) {
      LOGGER.e(error, stackTrace: stackTrace);
      if (mounted && !cancellation.isCancelled) {
        setState(() => _error = ui("更新包下载失败，请稍后重试"));
      }
    } finally {
      if (identical(_cancellation, cancellation)) _cancellation = null;
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _cancelDownload() {
    _cancellation?.cancel();
  }

  Future<void> _showDownloadedFile() async {
    final result = _result;
    if (result == null) return;
    final opened = await showInExplorer(path: result.file.path);
    if (!opened) showTextOnSnackBar("无法打开资源管理器");
  }

  Future<void> _ignore() async {
    await UpdateService.instance.ignoreVersion(widget.update.version);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    _detailsScroll.dispose();
    _actionsScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final release = widget.update.release;
    final scheme = Theme.of(context).colorScheme;
    final maxHeight =
        (MediaQuery.sizeOf(context).height - 64.0).clamp(0.0, 720.0);
    final result = _result;
    final progress = _progress;

    return Dialog(
      child: SizedBox(
        width: 720.0,
        height: maxHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Scrollbar(
                  controller: _detailsScroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    key: const ValueKey('update-details-scroll'),
                    controller: _detailsScroll,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppDialogTitle(
                          release.name ?? 'Dan Player ${widget.update.version}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                          subtitle: Text(
                            ui("稳定版 {0}{1}", [
                              widget.update.version,
                              release.publishedAt == null
                                  ? ''
                                  : ' · ${release.publishedAt!.toLocal().toString().split('.').first}'
                            ]),
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                          leading: Icon(Symbols.new_releases,
                              color: scheme.primary, size: 30.0),
                        ),
                        const SizedBox(height: 16.0),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLow,
                            borderRadius: AppShape.surfaceRadius,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: MarkdownBody(
                              data: release.body?.trim().isNotEmpty == true
                                  ? release.body!
                                  : ui("此版本没有提供更新说明。"),
                              selectable: true,
                              onTapLink: (_, href, __) {
                                if (href != null) {
                                  unawaited(_openSafeLink(href));
                                }
                              },
                              styleSheet: MarkdownStyleSheet.fromTheme(
                                  Theme.of(context)),
                            ),
                          ),
                        ),
                        if (_downloading || progress != null) ...[
                          const SizedBox(height: 14.0),
                          LinearProgressIndicator(value: progress?.fraction),
                          const SizedBox(height: 6.0),
                          Text(
                            progress == null
                                ? ui("正在准备下载…")
                                : ui("已下载 {0}{1}", [
                                    _formatBytes(progress.receivedBytes),
                                    progress.totalBytes == null
                                        ? ''
                                        : ' / ${_formatBytes(progress.totalBytes!)}'
                                  ]),
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12.0),
                          Text(_error!, style: TextStyle(color: scheme.error)),
                        ],
                        if (result != null) ...[
                          const SizedBox(height: 12.0),
                          Row(
                            children: [
                              Icon(
                                result.checksumVerified
                                    ? Symbols.verified_user
                                    : Symbols.download_done,
                                color: result.checksumVerified
                                    ? Colors.green
                                    : scheme.primary,
                              ),
                              const SizedBox(width: 8.0),
                              Expanded(
                                child: Text(
                                  result.checksumVerified
                                      ? ui("下载完成，SHA-256 校验通过。请从资源管理器启动安装包。")
                                      : ui(
                                          "下载完成；发布者未提供校验文件。为安全起见不会自动执行，请在资源管理器中确认后安装。"),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12.0),
              Row(
                children: [
                  Expanded(
                    child: Scrollbar(
                      controller: _actionsScroll,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        key: const ValueKey('update-actions-scroll'),
                        controller: _actionsScroll,
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!_downloading) ...[
                              TextButton(
                                onPressed: _ignore,
                                child: Text(ui("忽略此版本")),
                              ),
                              const SizedBox(width: 10),
                            ],
                            if (result != null)
                              FilledButton.icon(
                                onPressed: _showDownloadedFile,
                                icon: const Icon(Symbols.folder_open),
                                label: Text(ui("显示安装包")),
                              )
                            else
                              FilledButton.icon(
                                onPressed: _downloading ? null : _download,
                                icon: Icon(widget.update.asset == null
                                    ? Symbols.open_in_new
                                    : Symbols.download),
                                label: Text(widget.update.asset == null
                                    ? ui("打开发布页")
                                    : ui("下载更新")),
                              ),
                            if (release.htmlUrl != null)
                              IconButton(
                                tooltip: ui("在 GitHub 查看"),
                                onPressed: () => _openSafeLink(release.htmlUrl!,
                                    githubOnly: true),
                                icon: const Icon(Symbols.open_in_new),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Keep one exit/recovery action outside the horizontally
                  // scrollable command group, even with large text.
                  if (_downloading)
                    TextButton.icon(
                      onPressed: _cancelDownload,
                      icon: const Icon(Symbols.cancel),
                      label: Text(ui("取消下载")),
                    )
                  else
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(result == null ? ui("稍后") : ui("完成")),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
