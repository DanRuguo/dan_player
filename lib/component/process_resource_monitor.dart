import 'dart:async';
import 'dart:math' as math;

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_dialog_resize.dart';
import 'package:dan_player/component/app_menu_anchor.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/process_resource_chart.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/component/settings_section_visibility.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/process_resource_preferences.dart';
import 'package:dan_player/process_resource_coordinator.dart';
import 'package:dan_player/process_resource_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The settings page embeds this as its last surface. Visibility, rather than
/// animation preferences, owns sampling. Charts are static between samples.
class ProcessResourceMonitor extends StatefulWidget {
  const ProcessResourceMonitor(
      {super.key,
      this.preferences,
      this.onPreferencesChanged,
      this.controller,
      this.coordinator,
      this.isHidden});
  final ValueListenable<ProcessResourcePreferences>? preferences;
  final Future<void> Function(ProcessResourcePreferences)? onPreferencesChanged;
  final ProcessResourceService? controller;
  final ProcessResourceCoordinator? coordinator;
  final ValueListenable<bool>? isHidden;
  @override
  State<ProcessResourceMonitor> createState() => _ProcessResourceMonitorState();
}

class _ProcessResourceMonitorState extends State<ProcessResourceMonitor>
    with WidgetsBindingObserver {
  final _surface = GlobalKey();
  late ProcessResourceService _controller;
  ProcessResourceLease? _lease;
  late ValueListenable<ProcessResourcePreferences> _preferences;
  late ValueListenable<bool> _hidden;
  ScrollPosition? _scroll;
  bool _queued = false,
      _treeVisible = true,
      _lifecycleVisible = true,
      _inViewport = false,
      _layoutVisible = false;
  bool _saveFailed = false;
  int _saveGeneration = 0;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _lifecycleVisible = lifecycle == null ||
        lifecycle == AppLifecycleState.resumed ||
        lifecycle == AppLifecycleState.inactive;
    WidgetsBinding.instance.addObserver(this);
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _lease =
          (widget.coordinator ?? ProcessResourceCoordinator.instance).acquire();
      _controller = _lease!.service;
    }
    _preferences = widget.preferences ?? AppSettings.instance.processResources;
    _hidden = widget.isHidden ?? DesktopIntegration.instance.isHidden;
    _preferences.addListener(_changed);
    _hidden.addListener(_visibilityChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _treeVisible = TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        SettingsSectionVisibility.isVisibleOf(context);
    if (!_treeVisible) _visibilityChanged();
    final position = Scrollable.maybeOf(context)?.position;
    if (_scroll != position) {
      _scroll?.removeListener(_scheduleVisibility);
      _scroll = position;
      _scroll?.addListener(_scheduleVisibility);
    }
    _scheduleVisibility();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleVisible = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    _visibilityChanged();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _visibilityChanged();
  }

  void _visibilityChanged() {
    final visible =
        _treeVisible && _lifecycleVisible && _inViewport && !_hidden.value;
    if (mounted && visible != _layoutVisible) {
      setState(() => _layoutVisible = visible);
    }
    // Sampling ownership changes immediately; the finite surface resize is
    // purely visual and never keeps the worker alive while closing.
    final active = _preferences.value.enabled && visible;
    unawaited(_lease?.setActive(active,
            intervalSeconds: _preferences.value.intervalSeconds) ??
        _controller.setActive(active,
            intervalSeconds: _preferences.value.intervalSeconds));
  }

  void _scheduleVisibility() {
    if (_queued || !mounted) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!mounted) return;
      final render = _surface.currentContext?.findRenderObject();
      var visible = false;
      if (render is RenderBox && render.attached && render.hasSize) {
        final rect = render.localToGlobal(Offset.zero) & render.size;
        Rect viewport = Offset.zero & MediaQuery.sizeOf(context);
        final scrollRender =
            Scrollable.maybeOf(context)?.context.findRenderObject();
        if (scrollRender is RenderBox &&
            scrollRender.attached &&
            scrollRender.hasSize) {
          viewport = viewport.intersect(
              scrollRender.localToGlobal(Offset.zero) & scrollRender.size);
        }
        visible = !rect.isEmpty && rect.overlaps(viewport);
      }
      _inViewport = visible;
      _visibilityChanged();
    });
  }

  Future<void> _change(ProcessResourcePreferences value) async {
    final generation = ++_saveGeneration;
    setState(() => _saveFailed = false);
    try {
      if (widget.onPreferencesChanged != null) {
        await widget.onPreferencesChanged!(value);
      } else {
        AppSettings.instance.processResources.value = value;
        await AppSettings.instance
            .saveSettings(throwOnError: true, captureWindowSize: false);
      }
    } catch (_) {
      if (mounted && generation == _saveGeneration) {
        setState(() => _saveFailed = true);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _preferences.removeListener(_changed);
    _hidden.removeListener(_visibilityChanged);
    _scroll?.removeListener(_scheduleVisibility);
    if (_lease != null) {
      _lease!.dispose();
    } else {
      unawaited(_controller.setActive(false));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    _scheduleVisibility(); // Layout/resize callbacks, never a polling loop.
    return _ResourceVisibilityProbe(
        onPaint: _scheduleVisibility,
        child: SettingsSurface(
            key: _surface,
            child: TickerMode(
                enabled: _layoutVisible,
                child: AppDialogResize(
                    key: const ValueKey('resource-monitor-size'),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SettingsHeader(
                              title: ui('播放器资源监控'),
                              icon: Icons.monitor_heart_outlined,
                              subtitle:
                                  ui('仅统计当前播放器进程；只在已开启的显示位置可见时采样，隐藏窗口后停止。')),
                          SettingsSwitchTile(
                              surface: false,
                              controlKey: const ValueKey('resource-enabled'),
                              contentPadding:
                                  SettingsSurface.embeddedRowPadding,
                              icon: Icons.power_settings_new,
                              title: Text(ui('启用资源监控')),
                              value: _preferences.value.enabled,
                              onChanged: (value) => unawaited(_change(
                                  _preferences.value
                                      .copyWith(enabled: value)))),
                          if (_preferences.value.enabled) ...[
                            SettingsSwitchTile(
                                surface: false,
                                controlKey: const ValueKey('resource-sidebar'),
                                contentPadding:
                                    SettingsSurface.embeddedRowPadding,
                                icon: Icons.view_sidebar_outlined,
                                title: Text(ui('在侧栏下方显示')),
                                value: _preferences.value.showInSidebar,
                                onChanged: (value) => unawaited(_change(
                                    _preferences.value
                                        .copyWith(showInSidebar: value)))),
                            SettingsSwitchTile(
                                surface: false,
                                controlKey: const ValueKey('resource-lyrics'),
                                contentPadding:
                                    SettingsSurface.embeddedRowPadding,
                                icon: Icons.lyrics_outlined,
                                title: Text(ui('在歌词页左上角显示')),
                                value: _preferences.value.showInLyrics,
                                onChanged: (value) => unawaited(_change(
                                    _preferences.value
                                        .copyWith(showInLyrics: value)))),
                            const SizedBox(height: 4),
                            Text(
                                ui('各处共用显示方式与刷新间隔；侧栏和歌词页的 RAM 百分比为播放器工作集占物理内存的比例。'),
                                style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 16),
                            LayoutBuilder(builder: (context, constraints) {
                              final controls = [
                                _ResourceChoice<int>(
                                    controlKey: 'resource-interval',
                                    title: ui('刷新间隔'),
                                    value: _preferences.value.intervalSeconds,
                                    values:
                                        ProcessResourcePreferences.intervals,
                                    label: (value) => ui('每 {0} 秒', [value]),
                                    onChanged: (value) => unawaited(_change(
                                        _preferences.value.copyWith(
                                            intervalSeconds: value)))),
                                _ResourceChoice<ProcessResourceDisplay>(
                                    controlKey: 'resource-display',
                                    title: ui('显示方式'),
                                    value: _preferences.value.display,
                                    values: ProcessResourceDisplay.values,
                                    label: (value) => ui(switch (value) {
                                          ProcessResourceDisplay.numbers =>
                                            '数字',
                                          ProcessResourceDisplay.line => '折线',
                                          ProcessResourceDisplay.bar => '条形'
                                        }),
                                    onChanged: (value) => unawaited(_change(
                                        _preferences.value
                                            .copyWith(display: value)))),
                              ];
                              final scale =
                                  MediaQuery.textScalerOf(context).scale(14) /
                                      14;
                              return constraints.maxWidth / scale >= 430
                                  ? Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                          Expanded(child: controls[0]),
                                          const SizedBox(width: 16),
                                          Expanded(child: controls[1])
                                        ])
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                          controls[0],
                                          const SizedBox(height: 12),
                                          controls[1]
                                        ]);
                            }),
                            const SizedBox(height: 16),
                            ListenableBuilder(
                                // A peer view can keep the shared worker alive;
                                // this hidden surface must release its rebuild
                                // listener independently of sampling ownership.
                                listenable: _layoutVisible
                                    ? _controller
                                    : const AlwaysStoppedAnimation<double>(0),
                                builder: (context, _) {
                                  final samples = _controller.history;
                                  final latest = _controller.latest;
                                  final mode = _preferences.value.display;
                                  return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        LayoutBuilder(
                                            builder: (context, constraints) {
                                          final scale =
                                              MediaQuery.textScalerOf(context)
                                                      .scale(14) /
                                                  14;
                                          final tiles = [
                                            _ResourceMetric(
                                                title: ui('CPU'),
                                                value: latest?.cpuPercent,
                                                unavailable:
                                                    _controller.unavailable ||
                                                        latest?.cpuStatus ==
                                                            'unavailable',
                                                history: samples
                                                    .map((e) => e.cpuPercent)
                                                    .toList(),
                                                maximum: 100,
                                                mode: mode),
                                            _ResourceMetric(
                                                title: ui('GPU'),
                                                value: latest?.gpuPercent,
                                                unavailable:
                                                    _controller.unavailable ||
                                                        latest?.gpuStatus ==
                                                            'unavailable',
                                                history: samples
                                                    .map((e) => e.gpuPercent)
                                                    .toList(),
                                                maximum: 100,
                                                mode: mode),
                                            _ResourceMetric(
                                                title: ui('内存'),
                                                value: latest?.workingSetBytes
                                                    ?.toDouble(),
                                                unavailable: _controller
                                                        .unavailable ||
                                                    latest != null &&
                                                        latest.workingSetBytes ==
                                                            null,
                                                history: samples
                                                    .map((e) => e
                                                        .workingSetBytes
                                                        ?.toDouble())
                                                    .toList(),
                                                maximum: math.max(
                                                    1,
                                                    samples.fold<double>(
                                                        0,
                                                        (v, e) => math.max(
                                                            v,
                                                            e.workingSetBytes
                                                                    ?.toDouble() ??
                                                                0))),
                                                memory: true,
                                                mode: mode),
                                          ];
                                          return constraints.maxWidth / scale >=
                                                  520
                                              ? Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                      for (var index = 0;
                                                          index < tiles.length;
                                                          index++) ...[
                                                        if (index > 0)
                                                          const SizedBox(
                                                              width: 12),
                                                        Expanded(
                                                            child: tiles[index])
                                                      ]
                                                    ])
                                              : Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                      for (var index = 0;
                                                          index < tiles.length;
                                                          index++) ...[
                                                        if (index > 0)
                                                          const SizedBox(
                                                              height: 12),
                                                        tiles[index]
                                                      ]
                                                    ]);
                                        }),
                                        const SizedBox(height: 12),
                                        if (mode !=
                                            ProcessResourceDisplay.numbers)
                                          Text(ui(
                                              '近 {0} 次采样', [samples.length])),
                                        if (mode ==
                                            ProcessResourceDisplay.bar) ...[
                                          const SizedBox(height: 4),
                                          Text(ui(
                                              '内存条形以最近采样的最大工作集为参照，不代表系统内存用量。'))
                                        ],
                                      ]);
                                }),
                            const SizedBox(height: 8),
                            Text(
                                ui('CPU 为全部逻辑核心的占用比例；GPU 为本进程最忙引擎；内存为工作集，包含共享页。'),
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                          if (_saveFailed)
                            SettingsSaveFeedback(
                                onRetry: () =>
                                    unawaited(_change(_preferences.value))),
                        ])))));
  }
}

// A preceding settings section can grow without rebuilding this const widget.
// Read its final global rect after layout/paint, including those position-only
// changes; no frame is requested and no periodic visibility timer is needed.
class _ResourceVisibilityProbe extends SingleChildRenderObjectWidget {
  const _ResourceVisibilityProbe({required this.onPaint, required super.child});
  final VoidCallback onPaint;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ResourceVisibilityRender(onPaint);
  @override
  void updateRenderObject(BuildContext context,
          covariant _ResourceVisibilityRender renderObject) =>
      renderObject.onPaint = onPaint;
}

class _ResourceVisibilityRender extends RenderProxyBox {
  _ResourceVisibilityRender(this.onPaint);
  VoidCallback onPaint;
  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    onPaint();
  }
}

class _ResourceChoice<T> extends StatelessWidget {
  const _ResourceChoice(
      {required this.controlKey,
      required this.title,
      required this.value,
      required this.values,
      required this.label,
      required this.onChanged});
  final String controlKey, title;
  final T value;
  final List<T> values;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title),
        const SizedBox(height: 6),
        AppMenuAnchor(
            style: const MenuStyle(
                shape: WidgetStatePropertyAll(AppShape.control)),
            menuChildren: [
              for (final option in values)
                MenuItemButton(
                    key: ValueKey(
                        '$controlKey-${option is Enum ? option.name : option}'),
                    onPressed: () => onChanged(option),
                    leadingIcon: SizedBox.square(
                        dimension: 20,
                        child: option == value
                            ? const Icon(Icons.check, size: 20)
                            : null),
                    child: Text(label(option)))
            ],
            builder: (context, menu, _) => OutlinedButton(
                key: ValueKey(controlKey),
                style: OutlinedButton.styleFrom(
                    shape: AppShape.control,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12)),
                onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                child: Row(children: [
                  Expanded(child: Text(label(value))),
                  const SizedBox(width: 8),
                  const Icon(Icons.expand_more, size: 20)
                ])))
      ]);
}

class _ResourceMetric extends StatelessWidget {
  const _ResourceMetric(
      {required this.title,
      required this.value,
      required this.unavailable,
      required this.history,
      required this.maximum,
      required this.mode,
      this.memory = false});
  final String title;
  final double? value;
  final bool unavailable, memory;
  final List<double?> history;
  final double maximum;
  final ProcessResourceDisplay mode;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = value == null
        ? ui(unavailable ? '不可用' : '等待采样')
        : memory
            ? '${(value! / (1024 * 1024)).toStringAsFixed(1)} MiB'
            : '${value!.toStringAsFixed(1)}%';
    return Semantics(
        label: '$title: $text',
        child: ExcludeSemantics(
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color:
                        scheme.surfaceContainerHighest.withValues(alpha: .45),
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(title,
                              style: Theme.of(context).textTheme.labelLarge),
                          const SizedBox(height: 6),
                          Text(text,
                              key: ValueKey('resource-value-$title'),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                      color: value == null
                                          ? scheme.onSurfaceVariant
                                          : scheme.primary)),
                          if (mode != ProcessResourceDisplay.numbers) ...[
                            const SizedBox(height: 10),
                            ProcessResourceChart(
                                height: mode == ProcessResourceDisplay.line
                                    ? 72
                                    : 20,
                                history: history,
                                value: value,
                                maximum: maximum,
                                mode: mode,
                                color: scheme.primary,
                                track: scheme.outlineVariant
                                    .withValues(alpha: .35))
                          ],
                        ])))));
  }
}
