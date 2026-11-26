import 'dart:async';

import 'package:dan_player/component/app_dialog_actions.dart';
import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/app_dialog_resize.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/settings_section_visibility.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/lyric/english_phonetic_batch.dart';
import 'package:dan_player/page/settings_page/settings_busy_indicator.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

const _description = '仅处理播放器已缓存的歌词，完全离线匹配英语单词音标，不修改原歌词和已有注音。';

/// Opening settings never creates a batch or begins reading the cache. The
/// dialog owns its default task; injected tasks remain owned by their caller.
class EnglishPhoneticBatchSettings extends StatefulWidget {
  const EnglishPhoneticBatchSettings({super.key, this.task, this.surface = true});

  final EnglishPhoneticBatch? task;
  final bool surface;

  @override
  State<EnglishPhoneticBatchSettings> createState() =>
      _EnglishPhoneticBatchSettingsState();
}

class _EnglishPhoneticBatchSettingsState
    extends State<EnglishPhoneticBatchSettings> {
  GlobalKey<_EnglishBatchDialogState>? _dialog;
  ValueNotifier<bool>? _available;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!SettingsSectionVisibility.isVisibleOf(context)) _leave();
  }

  @override
  void didUpdateWidget(EnglishPhoneticBatchSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.task, oldWidget.task)) {
      _leave();
    }
  }

  void _leave() {
    _available?.value = false;
    final dialog = _dialog?.currentState;
    if (dialog == null) return;
    dialog.beginExit();
    final route = dialog.route;
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
    final key = GlobalKey<_EnglishBatchDialogState>();
    final ownsTask = widget.task == null;
    final task = widget.task ?? EnglishPhoneticBatch();
    final available = _available = ValueNotifier(true);
    setState(() => _dialog = key);
    try {
      await showAppDialog<void>(
        context: context,
        builder: (_) => _EnglishBatchDialog(
          key: key,
          task: task,
          ownsTask: ownsTask,
          available: available,
        ),
      );
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
    final tile = SettingsTile(
      surface: false,
      icon: Icons.spellcheck_outlined,
      description: ui('批量生成英语音标'),
      subtitle: ui(_description),
      action: OutlinedButton.icon(
        key: const ValueKey('english-phonetic-batch-open'),
        onPressed: _dialog == null &&
                SettingsSectionVisibility.isVisibleOf(context)
            ? _open
            : null,
        icon: const Icon(Icons.spellcheck_outlined),
        label: Text(ui('打开批量生成')),
      ),
    );
    return widget.surface ? SettingsSurface(child: tile) : tile;
  }
}

class _EnglishBatchDialog extends StatefulWidget {
  const _EnglishBatchDialog({
    super.key,
    required this.task,
    required this.ownsTask,
    required this.available,
  });

  final EnglishPhoneticBatch task;
  final bool ownsTask;
  final ValueNotifier<bool> available;

  @override
  State<_EnglishBatchDialog> createState() => _EnglishBatchDialogState();
}

class _EnglishBatchDialogState extends State<_EnglishBatchDialog> {
  ModalRoute<void>? route;
  Animation<double>? _animation;
  bool _closed = false, _updateQueued = false;
  _EnglishBatchView? _closingView;

  @override
  void initState() {
    super.initState();
    widget.task.addListener(_changed);
    widget.available.addListener(_availabilityChanged);
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
    _closingView = _EnglishBatchView(widget.task);
    _closed = true;
    widget.available.value = false;
    if (widget.task.running) widget.task.cancel();
    _refresh();
  }

  void _close() {
    beginExit();
    Navigator.pop(context);
  }

  void _start() {
    if (_closed || !widget.available.value || widget.task.running) return;
    unawaited(widget.task.start());
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
    final task = _closingView ?? _EnglishBatchView(widget.task);
    final scheme = Theme.of(context).colorScheme;
    return TickerMode(
      enabled: !_closed,
      child: Dialog(
        key: const ValueKey('english-phonetic-batch-dialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: AppDialogContent(
          width: 560,
          maxHeight: 520,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: AppDialogResize(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppDialogTitle(
                    ui('批量生成英语音标'),
                    style: Theme.of(context).textTheme.titleLarge,
                    sideExtent: 32,
                    leading: const Icon(Icons.spellcheck_outlined),
                  ),
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
                              ui(task.status),
                              key: const ValueKey(
                                  'english-phonetic-batch-status'),
                              style: TextStyle(
                                color: task.failed > 0 && !task.running
                                    ? scheme.error
                                    : scheme.onSurface,
                              ),
                            ),
                          ),
                          AnimatedSize(
                            duration: !_closed &&
                                    AppMotion.enabled(
                                      context,
                                      MotionKind.transitions,
                                    )
                                ? AppMotion.quick
                                : Duration.zero,
                            curve: AppMotion.standardCurve,
                            alignment: Alignment.topCenter,
                            child: task.running
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: SettingsBusyIndicator.linear(
                                      progress: task.scanning || task.total == 0
                                          ? null
                                          : (task.completed / task.total)
                                              .clamp(0.0, 1.0),
                                    ),
                                  )
                                : const SizedBox(width: double.infinity),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            ui('已处理 {0}/{1} · 生成 {2} · 跳过 {3} · 失败 {4}', [
                              task.completed,
                              task.total,
                              task.generated,
                              task.skipped,
                              task.failed,
                            ]),
                            key: const ValueKey(
                                'english-phonetic-batch-summary'),
                            style: const TextStyle(
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppDialogActions(
                    children: [
                      TextButton.icon(
                        key: const ValueKey('english-phonetic-batch-close'),
                        onPressed: _closed ? null : _close,
                        icon: const Icon(Icons.close),
                        label: Text(ui('关闭')),
                      ),
                      if (task.running)
                        TextButton.icon(
                          key: const ValueKey('english-phonetic-batch-cancel'),
                          onPressed: _closed || task.cancelling
                              ? null
                              : widget.task.cancel,
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: Text(ui('取消')),
                        )
                      else
                        FilledButton.icon(
                          key: const ValueKey('english-phonetic-batch-start'),
                          onPressed: _closed ? null : _start,
                          icon: const Icon(Icons.spellcheck_outlined),
                          label: Text(ui('开始生成')),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EnglishBatchView {
  _EnglishBatchView(EnglishPhoneticBatch task)
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
