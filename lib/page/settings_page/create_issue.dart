import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_content_scrollbar.dart';
import 'package:dan_player/component/app_dialog_actions.dart';
import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/data/folder_explorer.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/library/ffmpeg_runtime.dart';
import 'package:dan_player/library/japanese_dictionary_runtime.dart';
import 'package:dan_player/log/app_log_service.dart';
import 'package:dan_player/src/rust/api/utils.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

enum IssueCategory {
  bug('[Bug]', '功能异常', Symbols.bug_report),
  playback('[Playback]', '播放与音频', Symbols.graphic_eq),
  lyrics('[Lyrics]', '歌词与联网', Symbols.lyrics),
  ui('[UI]', '界面与动画', Symbols.palette),
  feature('[Feature]', '功能建议', Symbols.lightbulb);

  const IssueCategory(this.tag, this.labelKey, this.icon);
  final String tag;
  final String labelKey;
  final IconData icon;
}

Future<void> showReportIssueDialog(
  BuildContext context, {
  AppLogService? logService,
  Future<bool> Function(String uri)? launchUrl,
  Future<void> Function(Directory dir)? browseFolder,
}) {
  return showAppDialog<void>(
    context: context,
    builder: (dialogContext) => ReportIssueDialog(
      logService: logService,
      launchUrl: launchUrl,
      browseFolder: browseFolder,
    ),
  );
}

class CreateIssueTile extends StatelessWidget {
  const CreateIssueTile({super.key, this.logService});

  final AppLogService? logService;

  Future<void> _openLogsDirectory(BuildContext context, AppLogService logs) async {
    try {
      var dir = logs.logsDirectory;
      if (dir == null) {
        final dataDir = await getAppDataDir();
        await logs.initialize(dataDir, appVersion: AppSettings.version);
        dir = logs.logsDirectory;
      }
      if (dir == null) return;
      await dir.create(recursive: true);
      await browseFolderInExplorer(dir);
    } catch (_) {
      if (!context.mounted) return;
      showAppNotice(ui('无法打开此文件夹'), context: context, kind: AppNoticeKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final logs = logService ?? AppLogService.instance;
    final scheme = Theme.of(context).colorScheme;
    return AppEntrance(
      identity: const ('setting', 'create-issue-card'),
      child: ValueListenableBuilder<int>(
        valueListenable: logs.revision,
        builder: (context, _, __) {
          final totalCount = logs.countFor(AppLogFilter.recent15Days);
          final warnCount = logs.warningOrErrorCount;
          return SettingsSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SettingsHeader(
                  title: ui('报告问题'),
                  icon: Symbols.bug_report,
                  subtitle: ui('汇总环境摘要与带时间戳的运行日志；日志文件保留 15 天后自动清理。'),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _StatusBadge(
                          icon: Symbols.schedule,
                          label: ui('近 15 天日志：{0} 条', [totalCount]),
                          background: scheme.secondaryContainer.withValues(alpha: .55),
                          foreground: scheme.onSecondaryContainer,
                        ),
                        if (warnCount > 0)
                          _StatusBadge(
                            icon: Symbols.warning_amber_rounded,
                            label: ui('警告/错误：{0}', [warnCount]),
                            background: scheme.tertiaryContainer.withValues(alpha: .65),
                            foreground: scheme.onTertiaryContainer,
                          ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: const ValueKey('open-logs-folder-button'),
                          onPressed: () => _openLogsDirectory(context, logs),
                          icon: const Icon(Symbols.folder_open, size: 18),
                          label: Text(ui('日志目录')),
                        ),
                        FilledButton.icon(
                          key: const ValueKey('open-report-issue-dialog'),
                          onPressed: () => showReportIssueDialog(
                            context,
                            logService: logs,
                          ),
                          icon: const Icon(Symbols.bug_report, size: 18),
                          label: Text(ui('创建问题')),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Legacy compatibility widget if mounted directly; presents the same rich body.
class SettingsIssuePage extends StatelessWidget {
  const SettingsIssuePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: ReportIssueDialog(embedded: true),
      ),
    );
  }
}

class ReportIssueDialog extends StatefulWidget {
  const ReportIssueDialog({
    super.key,
    this.logService,
    this.launchUrl,
    this.browseFolder,
    this.embedded = false,
  });

  final AppLogService? logService;
  final Future<bool> Function(String uri)? launchUrl;
  final Future<void> Function(Directory dir)? browseFolder;
  final bool embedded;

  @override
  State<ReportIssueDialog> createState() => _ReportIssueDialogState();
}

class _ReportIssueDialogState extends State<ReportIssueDialog> {
  static const int _maxSafeIssueUrlLength = 6200;

  late final AppLogService _logs = widget.logService ?? AppLogService.instance;
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _logController = TextEditingController();
  final _titleFocus = FocusNode();

  IssueCategory _category = IssueCategory.bug;
  AppLogFilter _filter = AppLogFilter.recent15Days;
  bool _redactPaths = true;
  bool _includeLogs = true;
  bool _userEditedLogs = false;
  bool _syncingLogField = false;
  bool _submitting = false;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    _logs.revision.addListener(_onLogsChanged);
    _syncLogsToField();
    unawaited(_refreshAndPruneLogs());
  }

  @override
  void dispose() {
    _logs.revision.removeListener(_onLogsChanged);
    _titleController.dispose();
    _descController.dispose();
    _logController.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  Future<void> _refreshAndPruneLogs() async {
    if (!_logs.isInitialized) {
      try {
        final dataDir = await getAppDataDir();
        await _logs.initialize(dataDir, appVersion: AppSettings.version);
      } catch (_) {}
    } else {
      await _logs.pruneExpiredLogs();
    }
    if (!mounted) return;
    if (!_userEditedLogs) {
      _syncLogsToField();
    }
    setState(() {});
  }

  void _onLogsChanged() {
    if (!mounted) return;
    if (!_userEditedLogs) {
      _syncLogsToField();
    }
    setState(() {});
  }

  void _syncLogsToField() {
    _syncingLogField = true;
    _logController.text = _logs.formatEntries(
      filter: _filter,
      redactPaths: _redactPaths,
    );
    _syncingLogField = false;
  }

  String _environmentSummary() {
    final themeLabel = switch (AppSettings.instance.themeMode) {
      ThemeMode.system => 'system',
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
    };
    final ffmpegReady =
        FfmpegRuntime.shared.ready ? 'ready' : 'not-probed-or-missing';
    final jpReady = JapaneseDictionaryRuntime.shared.ready
        ? 'ready'
        : 'not-probed-or-missing';
    return '- Dan Player: `${AppSettings.version}`\n'
        '- OS: `${Platform.operatingSystem} (${Platform.operatingSystemVersion})`\n'
        '- UI Language: `${uiLanguage.value.code}` · Theme: `$themeLabel`\n'
        '- Optional Tools: `FFmpeg=$ffmpegReady`, `JapaneseReadings=$jpReady`';
  }

  String _resolvedIssueTitle() {
    final raw = _titleController.text.trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('[')) return raw;
    return '${_category.tag} $raw';
  }

  String _reportText(String value) => _redactPaths
      ? AppLogService.redactSensitivePaths(value.trim(), extraRoots: [
          if (_logs.dataDirectory != null) _logs.dataDirectory!.path,
        ])
      : value.trim();

  String _buildIssueBody({String? logOverride, bool truncatedNote = false}) {
    final descText = _reportText(_descController.text);
    final effectiveLogs = _reportText(logOverride ?? _logController.text);
    final buf = StringBuffer()
      ..writeln('## ${ui("问题描述")}')
      ..writeln(descText.isEmpty ? ui('（未填写补充说明）') : descText)
      ..writeln()
      ..writeln('## ${ui("运行环境")}')
      ..writeln(_environmentSummary());

    if (_includeLogs) {
      buf
        ..writeln()
        ..writeln('## ${ui("运行日志")}')
        ..writeln('```text')
        ..writeln(effectiveLogs.isEmpty ? ui('（暂无日志记录）') : effectiveLogs)
        ..writeln('```');
      if (truncatedNote) {
        buf.writeln(
            '> ${ui("注：因浏览器链接长度限制，此处仅附带最新日志片段；完整报告已自动复制到剪贴板。")}');
      }
    }
    return buf.toString();
  }

  Uri _buildGithubUri(String title, String body) {
    return Uri.https(
      'github.com',
      '/${AppSettings.githubOwner}/${AppSettings.githubRepository}/issues/new',
      <String, String>{
        'title': title,
        'body': body,
      },
    );
  }

  String _clipboardReport(String title, String body) =>
      title.isEmpty ? body : '# $title\n\n$body';

  Future<void> _copyFullReport() async {
    final report = _clipboardReport(_reportText(_resolvedIssueTitle()), _buildIssueBody());
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    showAppNotice(
      ui('已复制完整诊断报告'),
      context: context,
      kind: AppNoticeKind.success,
    );
  }

  Future<void> _copyLogsOnly() async {
    final text = _reportText(_logController.text);
    if (text.isEmpty) {
      showAppNotice(ui('当前没有可复制的日志'), context: context);
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showAppNotice(
      ui('已复制运行日志'),
      context: context,
      kind: AppNoticeKind.success,
    );
  }

  Future<void> _openLogsFolder() async {
    try {
      var dir = _logs.logsDirectory;
      if (dir == null) {
        final dataDir = await getAppDataDir();
        await _logs.initialize(dataDir, appVersion: AppSettings.version);
        dir = _logs.logsDirectory;
      }
      if (dir == null) return;
      await dir.create(recursive: true);
      if (widget.browseFolder != null) {
        await widget.browseFolder!(dir);
      } else {
        await browseFolderInExplorer(dir);
      }
    } catch (_) {
      if (!mounted) return;
      showAppNotice(ui('无法打开此文件夹'), context: context, kind: AppNoticeKind.error);
    }
  }

  Future<void> _clearAllLogs() async {
    await _logs.clearLogs();
    if (!mounted) return;
    setState(() {
      _userEditedLogs = false;
      _syncLogsToField();
    });
    showAppNotice(
      ui('运行日志已清空'),
      context: context,
      kind: AppNoticeKind.success,
    );
  }

  Future<void> _submitToGithub() async {
    if (_submitting) return;
    final title = _reportText(_resolvedIssueTitle());
    if (title.isEmpty) {
      setState(() => _titleError = ui('请先填写问题标题'));
      _titleFocus.requestFocus();
      return;
    }
    setState(() {
      _titleError = null;
      _submitting = true;
    });

    try {
      final fullBody = _buildIssueBody();
      var targetUri = _buildGithubUri(title, fullBody);
      var copiedFallback = false;

      if (targetUri.toString().length > _maxSafeIssueUrlLength) {
        await Clipboard.setData(ClipboardData(text: _clipboardReport(title, fullBody)));
        copiedFallback = true;
        final lines = _logController.text.trim().split('\n');
        var tailCount = _includeLogs ? math.min(lines.length, 32) : 0;
        while (tailCount > 0) {
          final tail = lines.sublist(lines.length - tailCount).join('\n');
          final candidate = _buildGithubUri(
            title,
            _buildIssueBody(logOverride: tail, truncatedNote: true),
          );
          if (candidate.toString().length <= _maxSafeIssueUrlLength) {
            targetUri = candidate;
            break;
          }
          tailCount ~/= 2;
        }
        if (targetUri.toString().length > _maxSafeIssueUrlLength) {
          // Long descriptions and multi-byte titles can exceed the URL limit
          // even after omitting the log. The complete report is on the clipboard.
          final shortTitle = String.fromCharCodes(title.runes.take(180));
          targetUri = _buildGithubUri(shortTitle, ui('请在此粘贴已复制的完整诊断报告。'));
        }
      }

      final opener = widget.launchUrl ?? (String url) => launchInBrowser(uri: url);
      var launched = false;
      try {
        launched = await opener(targetUri.toString());
      } catch (error, stack) {
        LOGGER.w('[report issue] browser launch failed', error: error, stackTrace: stack);
      }
      if (!mounted) return;
      if (!launched) {
        await Clipboard.setData(ClipboardData(text: _clipboardReport(title, fullBody)));
        if (!mounted) return;
        showAppNotice(
          ui('未能打开浏览器，完整诊断报告已复制到剪贴板'),
          context: context,
          kind: AppNoticeKind.warning,
        );
        return;
      }
      showAppNotice(
        copiedFallback
            ? ui('已打开 GitHub 问题页，完整日志报告已复制到剪贴板')
            : ui('已打开 GitHub 问题页面'),
        context: context,
        kind: AppNoticeKind.success,
      );
      if (!widget.embedded && mounted) {
        Navigator.of(context).pop();
      }
    } catch (err, trace) {
      LOGGER.e('[report issue] $err', stackTrace: trace);
      if (mounted) {
        showAppNotice(err.toString(), context: context, kind: AppNoticeKind.error);
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final screen = MediaQuery.sizeOf(context);
    final compact = screen.width < 560;
    final filteredCount = _logs.countFor(_filter);
    final motionDuration = AppMotion.duration(
      context,
      MotionKind.feedback,
      AppMotion.quick,
    );

    final bodyContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Issue category expressive pill selector
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in IssueCategory.values)
              ChoiceChip(
                key: ValueKey('issue-category-${item.name}'),
                selected: _category == item,
                showCheckmark: false,
                avatar: Icon(
                  item.icon,
                  size: 17,
                  color: _category == item
                      ? scheme.onPrimaryContainer
                      : scheme.primary,
                ),
                label: Text(ui(item.labelKey)),
                onSelected: (_) => setState(() => _category = item),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // 2. Environment & Privacy pill bar
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: AppShape.surfaceRadius,
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: isDark ? .36 : .44),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _StatusBadge(
                      icon: Symbols.verified,
                      label: 'v${AppSettings.version}',
                      background: scheme.primaryContainer.withValues(alpha: .65),
                      foreground: scheme.onPrimaryContainer,
                    ),
                    _StatusBadge(
                      icon: Symbols.computer,
                      label: Platform.operatingSystem.toUpperCase(),
                      background:
                          scheme.secondaryContainer.withValues(alpha: .55),
                      foreground: scheme.onSecondaryContainer,
                    ),
                    _StatusBadge(
                      icon: Symbols.translate,
                      label: uiLanguage.value.code.toUpperCase(),
                      background:
                          scheme.surfaceContainerHighest.withValues(alpha: .72),
                      foreground: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilterChip(
                      key: const ValueKey('issue-redact-paths-chip'),
                      selected: _redactPaths,
                      onSelected: (value) {
                        setState(() {
                          _redactPaths = value;
                          if (!_userEditedLogs) _syncLogsToField();
                        });
                      },
                      label: Text(ui('隐藏个人路径')),
                    ),
                    FilterChip(
                      key: const ValueKey('issue-include-logs-chip'),
                      selected: _includeLogs,
                      onSelected: (value) =>
                          setState(() => _includeLogs = value),
                      label: Text(ui('附带运行日志')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 3. Title & Description inputs
        Focus(
          onFocusChange: HotkeysHelper.onFocusChanges,
          child: TextField(
            key: const ValueKey('issue-title-input'),
            controller: _titleController,
            focusNode: _titleFocus,
            autofocus: !widget.embedded,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (_titleError != null) setState(() => _titleError = null);
            },
            decoration: InputDecoration(
              labelText: ui('问题标题'),
              hintText: ui('简要概括遇到的问题或建议'),
              prefixIcon: Icon(_category.icon, size: 20),
              errorText: _titleError,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Focus(
          onFocusChange: HotkeysHelper.onFocusChanges,
          child: TextField(
            key: const ValueKey('issue-description-input'),
            controller: _descController,
            minLines: 3,
            maxLines: 5,
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              alignLabelWithHint: true,
              labelText: ui('复现步骤与补充说明'),
              hintText: ui('可填写触发步骤、预期表现与实际现象（选填）'),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 4. Timestamped 15-day Diagnostic Log Card
        AnimatedOpacity(
          duration: motionDuration,
          opacity: _includeLogs ? 1.0 : 0.62,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: AppShape.cardRadius,
              border: Border.all(
                color:
                    scheme.outlineVariant.withValues(alpha: isDark ? .38 : .46),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Symbols.terminal, size: 19, color: scheme.primary),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  ui('运行日志'),
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          _StatusBadge(
                            icon: Symbols.auto_delete,
                            label: ui('15 天自动删除 · {0} 条', [filteredCount]),
                            background: scheme.secondaryContainer
                                .withValues(alpha: .52),
                            foreground: scheme.onSecondaryContainer,
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (_userEditedLogs)
                            ActionChip(
                              key: const ValueKey('issue-restore-logs-chip'),
                              avatar: const Icon(Symbols.sync, size: 16),
                              label: Text(ui('恢复自动同步')),
                              onPressed: () {
                                setState(() {
                                  _userEditedLogs = false;
                                  _syncLogsToField();
                                });
                              },
                            ),
                          IconButton(
                            key: const ValueKey('issue-refresh-logs-button'),
                            tooltip: ui('刷新并清理过期日志'),
                            visualDensity: VisualDensity.compact,
                            onPressed: _refreshAndPruneLogs,
                            icon: const Icon(Symbols.refresh, size: 19),
                          ),
                          IconButton(
                            key: const ValueKey('issue-copy-logs-button'),
                            tooltip: ui('复制日志'),
                            visualDensity: VisualDensity.compact,
                            onPressed: _copyLogsOnly,
                            icon: const Icon(Symbols.content_copy, size: 18),
                          ),
                          IconButton(
                            key: const ValueKey('issue-open-log-dir-button'),
                            tooltip: ui('打开日志目录'),
                            visualDensity: VisualDensity.compact,
                            onPressed: _openLogsFolder,
                            icon: const Icon(Symbols.folder_open, size: 19),
                          ),
                          IconButton(
                            key: const ValueKey('issue-clear-logs-button'),
                            tooltip: ui('清空日志'),
                            visualDensity: VisualDensity.compact,
                            onPressed: _clearAllLogs,
                            icon: const Icon(Symbols.delete_sweep, size: 19),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  AppSegmentedControl<AppLogFilter>(
                    value: _filter,
                    semanticLabel: ui('日志筛选'),
                    options: [
                      AppSegmentOption(
                        value: AppLogFilter.recent15Days,
                        label: ui('近 15 天'),
                        icon: Symbols.history,
                      ),
                      AppSegmentOption(
                        value: AppLogFilter.currentSession,
                        label: ui('本次启动'),
                        icon: Symbols.play_circle,
                      ),
                      AppSegmentOption(
                        value: AppLogFilter.warningsAndErrors,
                        label: ui('警告与错误'),
                        icon: Symbols.error_outline,
                      ),
                    ],
                    onChanged: (next) {
                      setState(() {
                        _filter = next;
                        _userEditedLogs = false;
                        _syncLogsToField();
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 188,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest
                            .withValues(alpha: isDark ? .46 : .52),
                        borderRadius: AppShape.controlRadius,
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: .42),
                        ),
                      ),
                      child: _logController.text.trim().isEmpty &&
                              !_userEditedLogs
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  _filter == AppLogFilter.warningsAndErrors
                                      ? ui('近 15 天未记录到警告或错误日志')
                                      : ui('当前暂无运行日志记录'),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            )
                          : Focus(
                              onFocusChange: HotkeysHelper.onFocusChanges,
                              child: TextField(
                                key: const ValueKey('issue-log-editor'),
                                controller: _logController,
                                expands: true,
                                maxLines: null,
                                textAlignVertical: TextAlignVertical.top,
                                onChanged: (_) {
                                  if (!_syncingLogField && !_userEditedLogs) {
                                    setState(() => _userEditedLogs = true);
                                  }
                                },
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: 'Consolas',
                                  fontSize: 12.2,
                                  height: 1.42,
                                  color: scheme.onSurface,
                                ),
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  filled: false,
                                  hintText: ui('你可以随意审阅或删减日志内容。'),
                                  contentPadding: const EdgeInsets.all(12),
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    ui('每条日志均记录本地时间戳，提交前可直接编辑；超过 15 天的历史日志文件会自动删除。'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );

    if (widget.embedded) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 740),
        child: SettingsSurface(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppDialogTitle(
                ui('报告问题'),
                leading: const Icon(Symbols.bug_report),
              ),
              const SizedBox(height: 16),
              bodyContent,
              const SizedBox(height: 16),
              AppDialogActions(
                children: [
                  FilledButton.tonalIcon(
                    key: const ValueKey('issue-copy-report-button'),
                    onPressed: _copyFullReport,
                    icon: const Icon(Symbols.content_copy, size: 18),
                    label: Text(ui('复制完整报告')),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('issue-submit-github-button'),
                    onPressed: _submitting ? null : _submitToGithub,
                    icon: const Icon(Symbols.open_in_new, size: 18),
                    label: Text(ui('前往 GitHub 提交')),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 20,
        vertical: 14,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 16 : 24,
          compact ? 16 : 20,
          compact ? 16 : 24,
          compact ? 14 : 18,
        ),
        child: AppDialogContent(
          width: 720,
          maxHeight: math.max(360, screen.height - 56),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppDialogTitle(
                ui('报告问题'),
                leading: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: .72),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SizedBox.square(
                    dimension: 36,
                    child: Icon(
                      Symbols.bug_report,
                      size: 20,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                subtitle: Text(
                  ui('生成环境摘要与近 15 天时间戳运行日志，提交前可审阅或脱敏'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                trailing: IconButton(
                  tooltip: ui('关闭'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: AppContentScrollbar(
                  builder: (context, scrollController) => SingleChildScrollView(
                    key: const ValueKey('issue-dialog-scroll'),
                    controller: scrollController,
                    padding: const EdgeInsets.only(right: 6),
                    child: bodyContent,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              AppDialogActions(
                children: [
                  TextButton(
                    key: const ValueKey('issue-cancel-button'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(ui('取消')),
                  ),
                  FilledButton.tonalIcon(
                    key: const ValueKey('issue-copy-report-button'),
                    onPressed: _copyFullReport,
                    icon: const Icon(Symbols.content_copy, size: 18),
                    label: Text(ui('复制完整报告')),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('issue-submit-github-button'),
                    onPressed: _submitting ? null : _submitToGithub,
                    icon: const Icon(Symbols.open_in_new, size: 18),
                    label: Text(ui('前往 GitHub 提交')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppShape.pillRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
