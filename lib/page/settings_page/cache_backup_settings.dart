import 'dart:io';

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
}) =>
    (gate ?? LibraryMutationGate.shared).run(() async {
      await flush();
      return service.exportBackup(
          source: await (dataDirectory ?? getAppDataDir)(),
          destination: destination);
    });

class CacheBackupSettings extends StatefulWidget {
  const CacheBackupSettings(
      {super.key, this.service = const CacheBackupService()});

  final CacheBackupService service;

  @override
  State<CacheBackupSettings> createState() => _CacheBackupSettingsState();
}

class _CacheBackupSettingsState extends State<CacheBackupSettings> {
  bool _busy = false;

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
    final proceed = await _confirm(
      title: ui('备份本地缓存？'),
      body: ui(
          '备份会保存曲库索引、歌单、歌词来源、播放统计、设置和缓存资源，不会复制音乐文件。\n\n在另一台电脑恢复前，请先准备包含尽量相同歌曲的文件夹，并先让 Dan Player 导入该文件夹；文件夹名称和位置可以不同。'),
    );
    if (!proceed || !mounted) return;

    final now = DateTime.now();
    final date = '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final picker = SaveFilePicker()
      ..title = ui('保存本地缓存备份')
      ..fileName = 'DanPlayer-cache-$date.bak'
      ..defaultExtension = 'bak'
      ..filterSpecification = {
        ui('Dan Player 备份'): '*.bak',
        ui('所有文件'): '*.*',
      };
    final output = picker.getFile();
    if (output == null) return;

    setState(() => _busy = true);
    try {
      final result = await exportLibraryCacheBackup(
        service: widget.service,
        flush: _flushPersistentState,
        destination: output,
      );
      if (!mounted) return;
      await showAppDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: AppDialogTitle(ui('备份已保存')),
          content: Text(ui(
              '已写入 {0} 个缓存文件，并记录 {1} 首歌曲的可迁移引用。备份不含音乐文件；恢复前仍需先导入尽量相同的歌曲文件夹。',
              [result.fileCount, result.songCount])),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(ui('完成')),
            ),
          ],
        ),
      );
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    var restorePrepared = false;
    final proceed = await _confirm(
      title: ui('恢复本地缓存？'),
      body: ui(
          '请先在这台电脑准备包含尽量相同歌曲的文件夹，并让 Dan Player 完成导入。恢复时会按扫描根内的相对位置、文件名和大小匹配歌曲；无法可靠匹配的信息会跳过并在完成后统计，不会保留旧电脑上失效的绝对路径。'),
    );
    if (!proceed || !mounted) return;

    final open = OpenFilePicker()
      ..title = ui('选择本地缓存备份')
      ..defaultExtension = 'bak'
      ..filterSpecification = {
        ui('Dan Player 备份'): '*.bak',
        ui('所有文件'): '*.*',
      };
    final backup = open.getFile();
    if (backup == null) return;

    final documents = await getApplicationDocumentsDirectory();
    final directoryPicker = DirectoryPicker()
      ..title = ui('选择恢复后的缓存存放位置')
      ..initialDirectory = documents.path
      ..alwaysShowInitialDirectory = true;
    final selected = directoryPicker.getDirectory();
    if (selected == null || !mounted) return;

    setState(() => _busy = true);
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

      final result = await widget.service.restoreBackup(
        backup: backup,
        destination: decision.directory,
        currentData: current,
        activateLocation: (target, staged) =>
            scheduleAppDataDirectorySwitch(target, stagedDirectory: staged),
      );
      restorePrepared = true;
      if (!mounted) return;
      final exitNow = await showAppDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              scrollable: true,
              title: AppDialogTitle(ui('缓存恢复已准备完成')),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: Text(ui(
                    '缓存将在下次启动时安全切换到：\n{0}\n\n已匹配 {1} 首歌曲；{2} 首无法可靠匹配的歌曲信息已跳过。其他可恢复的设置、歌单和统计已保留。',
                    [
                      result.destination.path,
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
    } catch (error, trace) {
      LOGGER.e('[cache restore] $error', stackTrace: trace);
      if (mounted) {
        showTextOnSnackBar(
            restorePrepared ? '恢复已准备完成；请退出并重新打开播放器' : '恢复失败，当前缓存与缓存位置均未改变',
            kind: AppNoticeKind.error,
            context: context);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsHeader(
            title: ui('本地缓存备份与恢复'),
            icon: Symbols.settings_backup_restore,
            subtitle: ui('将曲库索引、歌单、统计、设置和缓存资源保存为单个 .bak 文件；不复制音乐文件。'),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _restore,
                icon: const Icon(Symbols.settings_backup_restore),
                label: Text(ui('从备份恢复')),
              ),
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
    );
  }
}
