import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_dialog_actions.dart';
import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/app_dialog_resize.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/japanese_dictionary_setup_card.dart';
import 'package:dan_player/component/settings_section_visibility.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/library/japanese_dictionary_runtime.dart';
import 'package:dan_player/lyric/japanese_reading_analyzer.dart';
import 'package:dan_player/lyric/japanese_reading_batch.dart';
import 'package:dan_player/lyric/japanese_reading_preferences.dart';
import 'package:dan_player/page/settings_page/settings_busy_indicator.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

const _description = '仅处理播放器已缓存的日语歌词，不修改原歌词和已有注音；注音遵循“自动联网”设置，失败时回退离线。';

/// Opening settings never creates a batch or begins reading the cache. The
/// dialog owns its default task; injected tasks remain owned by their caller.
class JapaneseReadingBatchSettings extends StatefulWidget {
  const JapaneseReadingBatchSettings(
      {super.key,
      this.task,
      this.dictionaryRuntime,
      this.installerFactory,
      this.preferences,
      this.automaticallyOnline,
      this.persist});

  final JapaneseReadingBatch? task;
  final JapaneseDictionaryRuntime? dictionaryRuntime;
  final JapaneseDictionaryInstallerFactory? installerFactory;
  final ValueNotifier<JapaneseReadingPreferences>? preferences;
  final ValueListenable<bool>? automaticallyOnline;
  final Future<void> Function()? persist;

  @override
  State<JapaneseReadingBatchSettings> createState() =>
      _JapaneseReadingBatchSettingsState();
}

class _JapaneseReadingBatchSettingsState
    extends State<JapaneseReadingBatchSettings> {
  GlobalKey<_BatchDialogState>? _dialog;
  ValueNotifier<bool>? _available;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!SettingsSectionVisibility.isVisibleOf(context)) _leave();
  }

  @override
  void didUpdateWidget(JapaneseReadingBatchSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.task, oldWidget.task) ||
        !identical(widget.dictionaryRuntime, oldWidget.dictionaryRuntime) ||
        !identical(widget.installerFactory, oldWidget.installerFactory) ||
        !identical(widget.preferences, oldWidget.preferences) ||
        !identical(widget.automaticallyOnline, oldWidget.automaticallyOnline)) {
      _leave();
    }
  }

  void _leave() {
    _available?.value = false;
    final dialog = _dialog?.currentState;
    if (dialog == null) return;
    dialog.beginExit();
    final route = dialog.route;
    // Retained categories change during build. Retire native work now and
    // dismiss only this captured route after the current layout has finished.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = route?.navigator;
      if (navigator == null || !navigator.mounted) return;
      if (route!.isCurrent) {
        navigator.pop();
      } else if (route.isActive) {
        navigator.removeRoute(route);
      }
    });
  }

  Future<void> _open() async {
    if (_dialog != null || !SettingsSectionVisibility.isVisibleOf(context)) {
      return;
    }
    final key = GlobalKey<_BatchDialogState>();
    final ownsTask = widget.task == null;
    final task = widget.task ?? JapaneseReadingBatch();
    final runtime = widget.dictionaryRuntime;
    final factory = widget.installerFactory;
    final preferences =
        widget.preferences ?? AppSettings.instance.japaneseReadings;
    final automaticallyOnline = widget.automaticallyOnline ??
        AppSettings.instance.automaticOnlineLyrics;
    final persist = widget.persist ??
        () => AppSettings.instance
            .saveSettings(throwOnError: true, captureWindowSize: false);
    final available = _available = ValueNotifier(true);
    setState(() => _dialog = key);
    try {
      await showAppDialog<void>(
          context: context,
          builder: (_) => _BatchDialog(
              key: key,
              task: task,
              ownsTask: ownsTask,
              available: available,
              runtime: runtime,
              installerFactory: factory,
              preferences: preferences,
              automaticallyOnline: automaticallyOnline,
              persist: persist));
    } finally {
      available.value = false;
      available.dispose();
      if (identical(_dialog, key)) {
        _available = null;
        if (mounted) {
          setState(() => _dialog = null);
        } else {
          _dialog = null;
        }
      }
    }
  }

  @override
  void dispose() {
    _leave();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsSurface(
      child: SettingsTile(
          surface: false,
          icon: Icons.translate_outlined,
          description: ui('批量生成日语假名'),
          subtitle: ui(_description),
          action: OutlinedButton.icon(
              key: const ValueKey('japanese-reading-batch-open'),
              onPressed: _dialog == null &&
                      SettingsSectionVisibility.isVisibleOf(context)
                  ? _open
                  : null,
              icon: const Icon(Icons.translate_outlined),
              label: Text(ui('打开批量生成')))),
    );
  }
}

class _BatchDialog extends StatefulWidget {
  const _BatchDialog(
      {super.key,
      required this.task,
      required this.ownsTask,
      required this.available,
      required this.runtime,
      required this.installerFactory,
      required this.preferences,
      required this.automaticallyOnline,
      required this.persist});

  final JapaneseReadingBatch task;
  final bool ownsTask;
  final ValueNotifier<bool> available;
  final JapaneseDictionaryRuntime? runtime;
  final JapaneseDictionaryInstallerFactory? installerFactory;
  final ValueNotifier<JapaneseReadingPreferences> preferences;
  final ValueListenable<bool> automaticallyOnline;
  final Future<void> Function() persist;

  @override
  State<_BatchDialog> createState() => _BatchDialogState();
}

class _BatchDialogState extends State<_BatchDialog> {
  ModalRoute<void>? route;
  Animation<double>? _animation;
  bool _closed = false, _updateQueued = false, _dictionaryReady = false;
  _BatchView? _closingView;
  late JapaneseReadingRequestMode _manualMode;
  bool _saveFailed = false;
  int _saveRevision = 0;

  @override
  void initState() {
    super.initState();
    widget.task.addListener(_changed);
    widget.available.addListener(_availabilityChanged);
    _manualMode = widget.preferences.value.lastManualMode == 'online'
        ? JapaneseReadingRequestMode.online
        : JapaneseReadingRequestMode.offline;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    route = ModalRoute.of<void>(context);
    final animation = route?.animation;
    if (!identical(animation, _animation)) {
      _animation?.removeStatusListener(_statusChanged);
      _animation = animation;
      _animation?.addStatusListener(_statusChanged);
    }
    if (_animation?.status == AnimationStatus.reverse) beginExit();
    if (!widget.available.value) {
      beginExit();
      final captured = route;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final navigator = captured?.navigator;
        if (navigator == null || !navigator.mounted) return;
        if (captured!.isCurrent) {
          navigator.pop();
        } else if (captured.isActive) {
          navigator.removeRoute(captured);
        }
      });
    }
  }

  void _statusChanged(AnimationStatus status) {
    if (status == AnimationStatus.reverse) beginExit();
  }

  void _changed() {
    if (_closed) return;
    _refresh();
  }

  void _availabilityChanged() {
    if (!widget.available.value) beginExit();
  }

  void _refresh() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_updateQueued) return;
      _updateQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateQueued = false;
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void beginExit() {
    if (_closed) return;
    _closingView = _BatchView(widget.task);
    _closed = true;
    widget.available.value = false;
    if (widget.task.running) widget.task.cancel();
    _refresh();
  }

  void _close() {
    beginExit();
    Navigator.pop(context);
  }

  Future<void> _saveChoice() async {
    final revision = ++_saveRevision;
    try {
      await widget.persist();
    } catch (_) {
      if (mounted && !_closed && revision == _saveRevision) {
        setState(() => _saveFailed = true);
      }
    }
  }

  void _chooseMode(JapaneseReadingRequestMode value) {
    if (_closed || !widget.available.value || widget.task.running) return;
    setState(() {
      _manualMode = value;
      _saveFailed = false;
    });
    widget.preferences.value = widget.preferences.value.copyWith(
        lastManualMode:
            value == JapaneseReadingRequestMode.online ? 'online' : 'offline');
    unawaited(_saveChoice());
  }

  void _start() {
    if (_closed || !widget.available.value || widget.task.running) return;
    unawaited(widget.task.start(
        mode: widget.automaticallyOnline.value
            ? JapaneseReadingRequestMode.automatic
            : _manualMode));
  }

  @override
  void dispose() {
    widget.task.removeListener(_changed);
    widget.available.removeListener(_availabilityChanged);
    _animation?.removeStatusListener(_statusChanged);
    if (widget.task.running && !_closed) widget.task.cancel();
    if (widget.ownsTask) widget.task.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final task = _closingView ?? _BatchView(widget.task);
    final scheme = Theme.of(context).colorScheme;
    return TickerMode(
      enabled: !_closed,
      child: Dialog(
        key: const ValueKey('japanese-reading-batch-dialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: AppDialogContent(
          width: 560,
          maxHeight: 600,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: AppDialogResize(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              AppDialogTitle(ui('批量生成日语假名'),
                  style: Theme.of(context).textTheme.titleLarge,
                  sideExtent: 32,
                  leading: const Icon(Icons.translate_outlined)),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                            liveRegion: true,
                            child: Text(
                                ui(_dictionaryReady &&
                                        task.status == '需要日语假名字典组件'
                                    ? '字典组件已就绪；点击“开始生成”。'
                                    : task.status),
                                key: const ValueKey(
                                    'japanese-reading-batch-status'),
                                style: TextStyle(
                                    color: task.failed > 0 && !task.running
                                        ? scheme.error
                                        : scheme.onSurface))),
                        if (task.running) ...[
                          const SizedBox(height: 12),
                          SettingsBusyIndicator.linear(
                              progress: task.scanning || task.total == 0
                                  ? null
                                  : (task.completed / task.total)
                                      .clamp(0.0, 1.0)),
                        ],
                        const SizedBox(height: 12),
                        Text(
                            ui('已处理 {0}/{1} · 生成 {2} · 跳过 {3} · 失败 {4}', [
                              task.completed,
                              task.total,
                              task.generated,
                              task.skipped,
                              task.failed
                            ]),
                            key: const ValueKey(
                                'japanese-reading-batch-summary')),
                        ValueListenableBuilder<bool>(
                            valueListenable: widget.automaticallyOnline,
                            builder: (context, automatic, _) => automatic
                                ? const SizedBox.shrink()
                                : Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: AppSegmentedControl<
                                            JapaneseReadingRequestMode>(
                                        key: const ValueKey(
                                            'japanese-reading-batch-mode'),
                                        maxWidth: 360,
                                        wrapCompactLabel: true,
                                        semanticLabel: ui('日语假名生成方式'),
                                        value: _manualMode,
                                        options: [
                                          AppSegmentOption(
                                              value: JapaneseReadingRequestMode
                                                  .online,
                                              label: ui('联网生成'),
                                              icon: Icons.cloud_outlined,
                                              key: const ValueKey(
                                                  'japanese-reading-batch-mode-online')),
                                          AppSegmentOption(
                                              value: JapaneseReadingRequestMode
                                                  .offline,
                                              label: ui('离线生成'),
                                              icon: Icons.menu_book_outlined,
                                              key: const ValueKey(
                                                  'japanese-reading-batch-mode-offline')),
                                        ],
                                        onChanged: _closed || task.running
                                            ? null
                                            : _chooseMode))),
                        if (_saveFailed) ...[
                          const SizedBox(height: 8),
                          Text(ui('歌词设置保存失败；当前选择仍在本次会话生效。'),
                              style: TextStyle(color: scheme.error)),
                        ],
                        if (!_dictionaryReady &&
                            task.status == '需要日语假名字典组件') ...[
                          const SizedBox(height: 16),
                          JapaneseDictionarySetupCard(
                              runtime: widget.runtime,
                              installerFactory: widget.installerFactory,
                              available: widget.available,
                              visible: !_closed,
                              onReady: () {
                                if (!_closed && widget.available.value) {
                                  setState(() => _dictionaryReady = true);
                                }
                              }),
                        ],
                      ]),
                ),
              ),
              const SizedBox(height: 16),
              AppDialogActions(children: [
                TextButton.icon(
                    key: const ValueKey('japanese-reading-batch-close'),
                    onPressed: _closed ? null : _close,
                    icon: const Icon(Icons.close),
                    label: Text(ui('关闭'))),
                if (task.running)
                  TextButton.icon(
                      key: const ValueKey('japanese-reading-batch-cancel'),
                      onPressed: _closed || task.cancelling
                          ? null
                          : widget.task.cancel,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: Text(ui('取消')))
                else
                  FilledButton.icon(
                      key: const ValueKey('japanese-reading-batch-start'),
                      onPressed: _closed ? null : _start,
                      icon: const Icon(Icons.translate_outlined),
                      label: Text(ui('开始生成'))),
              ]),
            ])),
          ),
        ),
      ),
    );
  }
}

/// Keep an exiting route's last presentation immutable while its cancelled
/// task finishes. No late result can replace the closing status or counts.
class _BatchView {
  _BatchView(JapaneseReadingBatch task)
      : running = task.running,
        cancelling = task.cancelling,
        scanning = task.scanning,
        total = task.total,
        completed = task.completed,
        generated = task.generated,
        skipped = task.skipped,
        failed = task.failed,
        status = task.status;
  final bool running, cancelling, scanning;
  final int total, completed, generated, skipped, failed;
  final String status;
}
