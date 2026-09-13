import 'dart:io';
import 'dart:async';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/app_shutdown.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/data/cache_backup_service.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/collection.dart';
import 'package:dan_player/library/library_mutation_gate.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/library/track_resume_store.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/page/settings_page/backup_selection_dialog.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path_provider/path_provider.dart';

/// Hold the index mutation gate until archiving finishes, not just while
/// flushing. A scanner must not replace index.json midway through a backup.
Future<CacheBackupResult> exportLibraryCacheBackup({
  required CacheBackupService service,
  required File destination,
  required Future<void> Function() flush,
  Future<Directory> Function()? dataDirectory,
  LibraryMutationGate? gate,
  BackupSelection selection = const BackupSelection(),
  String? password,
  BackupOperation? operation,
}) =>
    (gate ?? LibraryMutationGate.shared).run(() async {
      await flush();
      return service.exportBackup(
          source: await (dataDirectory ?? getAppDataDir)(),
          destination: destination,
          selection: selection,
          password: password,
          operation: operation);
    });

class CacheBackupSettings extends StatefulWidget {
  const CacheBackupSettings(
      {super.key,
      this.service = const CacheBackupService(),
      this.restoreOnly = false,
      this.onRestorePrepared});

  final CacheBackupService service;
  final bool restoreOnly;
  final VoidCallback? onRestorePrepared;

  @override
  State<CacheBackupSettings> createState() => _CacheBackupSettingsState();
}

class _CacheBackupSettingsState extends State<CacheBackupSettings> {
  bool _busy = false;
  BackupOperation? _operation;
  BackupProgress? _progress;
  DateTime _lastProgress = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    unawaited(_operation?.cancel());
    super.dispose();
  }

  BackupOperation _beginOperation() {
    final job = BackupOperation(onProgress: (progress) {
      final now = DateTime.now();
      if (mounted && now.difference(_lastProgress).inMilliseconds >= 150) {
        _lastProgress = now;
        setState(() => _progress = progress);
      }
    });
    setState(() {
      _busy = true;
      _operation = job;
      _progress = null;
    });
    return job;
  }

  Future<bool> _confirm({
    required String title,
    required String body,
  }) async =>
      await showAppDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: AppDialogTitle(title),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(body),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(ui('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(ui('继续')),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _flushPersistentState() => Future.wait<void>([
        AudioLibrary.instance.saveIndex(),
        savePlaylists(),
        saveCustomAudioOrder(),
        saveLyricSources(),
        PlayService.flushExistingPlaybackState(),
        AppSettings.instance
            .saveSettings(captureWindowSize: false, throwOnError: true),
        AppPreference.instance.save(),
        PlaybackStatistics.instance.flush(),
        TrackResumeStore.flushIfInitialized(),
      ]);

  Future<void> _export() async {
    if (_busy) return;
    BackupContents contents;
    setState(() => _busy = true);
    try {
      contents = await LibraryMutationGate.shared.run(() async {
        await _flushPersistentState();
        return widget.service.inspectLibrary(source: await getAppDataDir());
      });
    } catch (error) {
      if (mounted)
        showTextOnSnackBar('无法读取曲库，请等待扫描完成后重试',
            kind: AppNoticeKind.error, context: context);
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    final choice = await showAppDialog<BackupDialogChoice>(
        context: context,
        builder: (context) => BackupSelectionDialog(contents: contents));
    if (choice == null || !mounted) return;

    final now = DateTime.now();
    final date = '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final picker = SaveFilePicker()
      ..title = ui('保存播放器备份')
      ..fileName = 'DanPlayer-$date.bak'
      ..defaultExtension = 'bak'
      ..filterSpecification = {
        ui('Dan Player 备份'): '*.bak',
        ui('所有文件'): '*.*',
      };
    final output = picker.getFile();
    if (output == null) return;

    final operation = _beginOperation();
    try {
      final result = await exportLibraryCacheBackup(
        service: widget.service,
        flush: _flushPersistentState,
        destination: output,
        selection: choice.selection,
        password: choice.password,
        operation: operation,
      );
      if (!mounted) return;
      await showAppDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: AppDialogTitle(ui('备份已保存')),
          content: Text(ui('已保存 {0} 个文件，包含 {1} 个音乐源文件。',
              [result.fileCount, result.musicCount])),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(ui('完成')),
            ),
          ],
        ),
      );
    } on CacheBackupEncryptionTooLarge {
      if (mounted)
        showTextOnSnackBar('加密备份的压缩后大小必须小于 64 GiB，请减少所选文件夹并分批备份。',
            kind: AppNoticeKind.error, context: context);
    } on CacheBackupCancelled {
      if (mounted) showTextOnSnackBar('操作已取消，原有文件保持不变', context: context);
    } on LibraryMutationBusy {
      if (mounted) {
        showTextOnSnackBar('曲库操作正在进行，请等待刷新或歌曲信息保存完成后重试',
            kind: AppNoticeKind.warning, context: context);
      }
    } catch (error, trace) {
      LOGGER.e('[cache backup] $error', stackTrace: trace);
      if (mounted) {
        showTextOnSnackBar('备份失败，未替换原有备份文件；请稍后重试',
            kind: AppNoticeKind.error, context: context);
      }
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
          _operation = null;
          _progress = null;
        });
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    var restorePrepared = false;
    final open = OpenFilePicker()
      ..title = ui('选择播放器备份')
      ..defaultExtension = 'bak'
      ..filterSpecification = {
        ui('Dan Player 备份'): '*.bak',
        ui('所有文件'): '*.*',
      };
    final backup = open.getFile();
    if (backup == null) return;

    String? password;
    BackupContents contents;
    var inspection = _beginOperation();
    try {
      try {
        contents = await widget.service
            .inspectBackup(backup: backup, operation: inspection);
      } on CacheBackupPasswordRequired {
        if (!mounted) return;
        password = await _requestPassword();
        if (password == null || !mounted) return;
        inspection = _beginOperation();
        contents = await widget.service.inspectBackup(
            backup: backup, password: password, operation: inspection);
      }
    } on CacheBackupCancelled {
      return;
    } catch (error) {
      if (mounted)
        showTextOnSnackBar('无法读取备份，请检查密码或文件完整性',
            kind: AppNoticeKind.error, context: context);
      return;
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
          _operation = null;
          _progress = null;
        });
    }
    if (!mounted) return;
    final choice = await showAppDialog<BackupDialogChoice>(
        context: context,
        builder: (context) => BackupSelectionDialog(
            contents: contents, restoring: true, firstUse: widget.restoreOnly));
    if (choice == null || !mounted) return;

    final documents = await getApplicationDocumentsDirectory();
    final directoryPicker = DirectoryPicker()
      ..title = ui('选择恢复内容的存放位置')
      ..initialDirectory = documents.path
      ..alwaysShowInitialDirectory = true;
    final selected = directoryPicker.getDirectory();
    if (selected == null || !mounted) return;

    final operation = _beginOperation();
    try {
      final current = await getAppDataDir();
      final decision = await CacheRestoreDestinationPolicy.decide(
        selected: selected,
        currentData: current,
      );
      if (!mounted) return;
      if (decision.requiresReplacementConfirmation) {
        final replace = await _confirm(
          title:
              decision.replacesActiveDirectory ? ui('替换当前缓存？') : ui('替换已有缓存？'),
          body: ui(
              '目标位置已识别为 Dan Player 缓存：\n{0}\n\n恢复会在下次启动前进行原子替换；若替换失败，原缓存会保留。是否继续？',
              [decision.directory.path]),
        );
        if (!replace || !mounted) return;
      }

      final result = await LibraryMutationGate.shared.run(() async {
        await _flushPersistentState();
        return widget.service.restoreBackup(
            backup: backup,
            destination: decision.directory,
            currentData: current,
            selection: choice.selection,
            password: password,
            operation: operation,
            activateLocation: (target, staged) =>
                scheduleAppDataDirectorySwitch(target,
                    stagedDirectory: staged));
      });
      restorePrepared = true;
      if (widget.restoreOnly) {
        AppSettings.instance.onboardingCompleted = true;
        await AppSettings.instance.saveSettings(captureWindowSize: false);
      }
      widget.onRestorePrepared?.call();
      if (!mounted) return;
      final exitNow = await showAppDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              scrollable: true,
              title: AppDialogTitle(ui('恢复已准备完成')),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: Text(ui(
                    '下次启动时将切换到：\n{0}\n\n已还原 {1} 个音乐源文件；已匹配 {2} 首歌曲引用，{3} 首暂不可用。未勾选的数据保持原状。',
                    [
                      result.destination.path,
                      result.musicCount,
                      result.restoredSongs,
                      result.missingSongs,
                    ])),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(ui('稍后重启')),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Symbols.power_settings_new),
                  label: Text(ui('退出播放器')),
                ),
              ],
            ),
          ) ==
          true;
      if (exitNow) {
        try {
          await shutdownAndExit(throwOnError: true);
        } catch (error, trace) {
          LOGGER.e('[cache restore exit] $error', stackTrace: trace);
          if (mounted) {
            showTextOnSnackBar('恢复已准备完成，但未能自动退出；请手动退出并重新打开播放器',
                kind: AppNoticeKind.warning, context: context);
          }
        }
      }
    } on CacheBackupCancelled {
      if (mounted) showTextOnSnackBar('操作已取消，原有文件保持不变', context: context);
    } catch (error, trace) {
      LOGGER.e('[cache restore] $error', stackTrace: trace);
      if (mounted) {
        showTextOnSnackBar(
            restorePrepared ? '恢复已准备完成；请退出并重新打开播放器' : '恢复失败，当前缓存与缓存位置均未改变',
            kind: AppNoticeKind.error,
            context: context);
      }
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
          _operation = null;
          _progress = null;
        });
    }
  }

  Future<String?> _requestPassword() async {
    final controller = TextEditingController();
    try {
      return await showAppDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
                  scrollable: true,
                  title: AppDialogTitle(ui('解锁备份')),
                  content: SizedBox(
                      width: 440,
                      child: TextField(
                          controller: controller,
                          autofocus: true,
                          obscureText: true,
                          enableSuggestions: false,
                          autocorrect: false,
                          decoration: InputDecoration(
                              labelText: ui('备份密码'),
                              helperText: ui('请原样输入密码，保留空格、大小写和符号。')),
                          onSubmitted: (value) =>
                              Navigator.pop(context, value))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(ui('取消'))),
                    FilledButton(
                        onPressed: () =>
                            Navigator.pop(context, controller.text),
                        child: Text(ui('解锁'))),
                  ]));
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return PopScope(
        canPop: !_busy,
        child: SettingsSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsHeader(
                title: ui('播放器备份与恢复'),
                icon: Symbols.settings_backup_restore,
                subtitle: ui('音乐、曲库、歌单、统计与设置，自由组合为一个压缩备份；支持密码加密和按需恢复。'),
              ),
              const SizedBox(height: 14),
              if (widget.restoreOnly) ...[
                Text(ui('首次迁移建议选择包含音乐和播放器资料的完整备份，并恢复全部内容；也可以按需选择。')),
                const SizedBox(height: 14),
              ],
              if (_busy) ...[
                LinearProgressIndicator(
                    value: (_progress?.total ?? 0) > 0
                        ? (_progress!.completed / _progress!.total).clamp(0, 1)
                        : null),
                const SizedBox(height: 8),
                Text(ui(switch (_progress?.phase) {
                  'encrypt' => '正在加密备份…',
                  'decrypt' => '正在解锁并验证备份…',
                  'compress' => '正在压缩文件…',
                  'restore' => '正在验证和恢复文件…',
                  _ => '正在准备备份文件…',
                })),
                const SizedBox(height: 8),
              ],
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (_busy)
                    TextButton(
                        onPressed: _operation?.isCancelled == true
                            ? null
                            : () {
                                unawaited(_operation?.cancel());
                                setState(() {});
                              },
                        child: Text(ui(_operation?.isCancelled == true
                            ? '正在取消…'
                            : '取消操作'))),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _restore,
                    icon: const Icon(Symbols.settings_backup_restore),
                    label: Text(ui('从备份恢复')),
                  ),
                  if (widget.restoreOnly)
                    TextButton(
                        onPressed: _busy ? null : () => Navigator.pop(context),
                        child: Text(ui('关闭'))),
                  if (!widget.restoreOnly)
                    FilledButton.icon(
                      onPressed: _busy ? null : _export,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Symbols.backup),
                      label: Text(_busy ? ui('正在处理…') : ui('备份到文件')),
                    ),
                ],
              ),
            ],
          ),
        ));
  }
}

Future<void> showOnboardingRestore(BuildContext context,
        {VoidCallback? onRestored}) =>
    showAppDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        scrollable: true,
        title: AppDialogTitle(ui('从备份恢复')),
        content: SizedBox(
            width: 640,
            child: CacheBackupSettings(
                restoreOnly: true, onRestorePrepared: onRestored)),
      ),
    );
