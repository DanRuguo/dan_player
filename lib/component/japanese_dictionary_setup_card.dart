import 'dart:async';

import 'package:dan_player/component/app_dialog_actions.dart';
import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/app_dialog_resize.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/library/japanese_dictionary_module_install.dart';
import 'package:dan_player/library/japanese_dictionary_runtime.dart';
import 'package:dan_player/page/settings_page/settings_busy_indicator.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

typedef JapaneseDictionaryInstallerFactory = JapaneseDictionaryModuleInstaller
    Function(JapaneseDictionaryRuntime runtime);

/// The caller must still check its original lyric/request identity after a
/// successful install. Opening this prompt only reads the local destination.
Future<bool> showJapaneseDictionarySetupDialog(BuildContext context,
    {JapaneseDictionaryRuntime? runtime,
    JapaneseDictionaryInstallerFactory? installerFactory}) async {
  return await showAppDialog<bool>(
          context: context,
          builder: (_) => _DictionarySetupDialog(
              runtime: runtime ?? JapaneseDictionaryRuntime.shared,
              installerFactory: installerFactory)) ??
      false;
}

class JapaneseDictionarySetupCard extends StatefulWidget {
  const JapaneseDictionarySetupCard(
      {super.key,
      required this.onReady,
      this.runtime,
      this.installerFactory,
      this.available,
      this.visible = true,
      this.showHeading = true});

  final VoidCallback onReady;
  final JapaneseDictionaryRuntime? runtime;
  final JapaneseDictionaryInstallerFactory? installerFactory;

  /// A dialog can retire a download synchronously at the start of its reverse
  /// animation, before the child is rebuilt or disposed.
  final ValueListenable<bool>? available;
  final bool visible;
  final bool showHeading;

  @override
  State<JapaneseDictionarySetupCard> createState() =>
      _JapaneseDictionarySetupCardState();
}

class _JapaneseDictionarySetupCardState
    extends State<JapaneseDictionarySetupCard> {
  JapaneseDictionaryModuleInstaller? _installer;
  late Future<String> _directory;
  int _generation = 0;
  bool _busy = false, _failed = false, _updateQueued = false;
  double? _progress;
  String _stage = '正在校验并安装字典…';

  JapaneseDictionaryRuntime get _runtime =>
      widget.runtime ?? JapaneseDictionaryRuntime.shared;
  bool get _active =>
      mounted && widget.visible && (widget.available?.value ?? true);

  @override
  void initState() {
    super.initState();
    _directory = _runtime.installDirectory.then((value) => value.path);
    widget.available?.addListener(_availabilityChanged);
  }

  @override
  void didUpdateWidget(JapaneseDictionarySetupCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.available, widget.available)) {
      oldWidget.available?.removeListener(_availabilityChanged);
      widget.available?.addListener(_availabilityChanged);
    }
    if (!identical(oldWidget.runtime, widget.runtime) ||
        !identical(oldWidget.installerFactory, widget.installerFactory)) {
      _cancel();
      _directory = _runtime.installDirectory.then((value) => value.path);
    }
    if (!_active) _cancel();
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

  void _availabilityChanged() {
    if (!_active) _cancel();
  }

  void _cancel() {
    ++_generation;
    _installer?.cancel();
    _installer = null;
    _busy = false;
    _progress = null;
    _refresh();
  }

  Future<void> _run(bool download) async {
    if (!_active || _busy) return;
    final generation = ++_generation;
    final runtime = _runtime;
    bool current() => _active && generation == _generation;
    setState(() {
      _busy = true;
      _failed = false;
      _progress = null;
      _stage = '正在校验并安装字典…';
    });
    try {
      if (download) {
        final installer = _installer = widget.installerFactory?.call(runtime) ??
            JapaneseDictionaryModuleInstaller(runtime: runtime);
        await installer.install(progress: (value) {
          if (!current()) return;
          _progress =
              value != null && value.isFinite ? value.clamp(0.0, 1.0) : null;
          _refresh();
        }, onStage: (value) {
          if (!current()) return;
          _stage = value;
          _refresh();
        });
      }
      if (!current()) return;
      final ready = await runtime.inspect();
      if (!current()) return;
      setState(() {
        _busy = false;
        _installer = null;
        _failed = !ready;
      });
      if (ready) widget.onReady();
    } catch (_) {
      if (!current()) return;
      setState(() {
        _busy = false;
        _installer = null;
        _failed = true;
      });
    }
  }

  @override
  void dispose() {
    ++_generation;
    widget.available?.removeListener(_availabilityChanged);
    _installer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsSurface(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
          if (widget.showHeading) ...[
            SettingsHeader(
                title: ui('日语假名字典组件'), icon: Icons.menu_book_outlined),
            const SizedBox(height: 12),
          ],
          Text(ui('按需下载假名字典和许可文件；离线分析不会上传歌词。')),
          const SizedBox(height: 12),
          Text(ui('手动安装：从播放器发布页下载字典组件，解压到此目录，保留许可文件。')),
          const SizedBox(height: 6),
          FutureBuilder<String>(
              future: _directory,
              builder: (context, result) => result.hasData
                  ? SelectableText(result.data!,
                      key: const ValueKey('japanese-dictionary-directory'),
                      style: Theme.of(context).textTheme.bodySmall)
                  : const SizedBox.shrink()),
          if (_busy) ...[
            const SizedBox(height: 12),
            SettingsBusyIndicator.linear(progress: _progress),
            const SizedBox(height: 6),
            Semantics(liveRegion: true, child: Text(ui(_stage))),
          ],
          if (_failed) ...[
            const SizedBox(height: 12),
            Semantics(
                liveRegion: true,
                child: Text(ui('字典组件仍不可用。请检查下载、文件完整性和目录权限，或手动安装后重试。'),
                    key: const ValueKey('japanese-dictionary-error'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          ],
          const SizedBox(height: 14),
          AppDialogActions(children: [
            if (_installer != null)
              TextButton.icon(
                  key: const ValueKey('japanese-dictionary-cancel'),
                  onPressed: _active ? _cancel : null,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text(ui('取消下载'))),
            OutlinedButton.icon(
                key: const ValueKey('japanese-dictionary-manual'),
                onPressed: _active && !_busy ? () => _run(false) : null,
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(ui('我已安装好'))),
            FilledButton.icon(
                key: const ValueKey('japanese-dictionary-download'),
                onPressed: _active && !_busy ? () => _run(true) : null,
                icon: const Icon(Icons.download_outlined),
                label: Text(ui('从 GitHub 下载'))),
          ]),
        ]));
  }
}

class _DictionarySetupDialog extends StatefulWidget {
  const _DictionarySetupDialog(
      {required this.runtime, required this.installerFactory});
  final JapaneseDictionaryRuntime runtime;
  final JapaneseDictionaryInstallerFactory? installerFactory;

  @override
  State<_DictionarySetupDialog> createState() => _DictionarySetupDialogState();
}

class _DictionarySetupDialogState extends State<_DictionarySetupDialog> {
  final _available = ValueNotifier(true);
  Animation<double>? _animation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (!identical(animation, _animation)) {
      _animation?.removeStatusListener(_statusChanged);
      _animation = animation;
      _animation?.addStatusListener(_statusChanged);
    }
    if (_animation?.status == AnimationStatus.reverse) _available.value = false;
  }

  void _statusChanged(AnimationStatus status) {
    if (status == AnimationStatus.reverse) _available.value = false;
  }

  void _close(bool ready) {
    if (!_available.value) return;
    _available.value = false;
    final route = ModalRoute.of<bool>(context);
    final navigator = route?.navigator;
    if (navigator == null) return;
    if (route!.isCurrent) {
      navigator.pop(ready);
    } else if (route.isActive) {
      navigator.removeRoute(route, ready);
    }
  }

  @override
  void dispose() {
    _animation?.removeStatusListener(_statusChanged);
    _available.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Dialog(
        key: const ValueKey('japanese-dictionary-dialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: AppDialogContent(
            width: 560,
            maxHeight: 680,
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: AppDialogResize(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  AppDialogTitle(ui('日语假名字典组件'),
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Flexible(
                      child: SingleChildScrollView(
                          child: JapaneseDictionarySetupCard(
                              showHeading: false,
                              runtime: widget.runtime,
                              installerFactory: widget.installerFactory,
                              available: _available,
                              onReady: () => _close(true)))),
                  const SizedBox(height: 16),
                  AppDialogActions(children: [
                    TextButton.icon(
                        key: const ValueKey('japanese-dictionary-close'),
                        onPressed: () => _close(false),
                        icon: const Icon(Icons.close),
                        label: Text(ui('关闭')))
                  ]),
                ])))));
  }
}
