import 'dart:async';
import 'dart:math' as math;

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/process_resource_chart.dart';
import 'package:dan_player/component/window_chrome_theme.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/process_resource_coordinator.dart';
import 'package:dan_player/process_resource_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:material_symbols_icons/symbols.dart';

enum ProcessResourceSurface { sidebar, lyrics }

/// Small, sample-driven views of the same process worker used in settings.
/// The sampling lease follows actual visibility, independently of animation
/// preferences; an inactive surface never stops another visible consumer.
class CompactProcessResourceMonitor extends StatefulWidget {
  const CompactProcessResourceMonitor({
    super.key,
    required this.surface,
    this.compactSidebar = false,
    this.columnSpacing = 8,
    this.preferences,
    this.coordinator,
    this.isHidden,
  });

  final ProcessResourceSurface surface;
  final bool compactSidebar;
  final double columnSpacing;
  final ValueListenable<ProcessResourcePreferences>? preferences;
  final ProcessResourceCoordinator? coordinator;
  final ValueListenable<bool>? isHidden;

  @override
  State<CompactProcessResourceMonitor> createState() =>
      _CompactProcessResourceMonitorState();
}

class _CompactProcessResourceMonitorState
    extends State<CompactProcessResourceMonitor> with WidgetsBindingObserver {
  final _surface = GlobalKey();
  late ProcessResourceLease _lease;
  late ValueListenable<ProcessResourcePreferences> _preferences;
  late ValueListenable<bool> _hidden;
  ScrollPosition? _scroll;
  bool _queued = false, _treeVisible = false, _inViewport = false;
  bool _lifecycleVisible = true;
  bool _surfaceActive = false;

  bool get _enabled =>
      _preferences.value.enabled &&
      (widget.surface == ProcessResourceSurface.sidebar
          ? _preferences.value.showInSidebar
          : _preferences.value.showInLyrics);

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _lifecycleVisible = lifecycle == null ||
        lifecycle == AppLifecycleState.resumed ||
        lifecycle == AppLifecycleState.inactive;
    WidgetsBinding.instance.addObserver(this);
    _attach();
  }

  void _attach() {
    _lease =
        (widget.coordinator ?? ProcessResourceCoordinator.instance).acquire();
    _preferences = widget.preferences ?? AppSettings.instance.processResources;
    _hidden = widget.isHidden ?? DesktopIntegration.instance.isHidden;
    _preferences.addListener(_changed);
    _hidden.addListener(_syncVisibility);
  }

  @override
  void didUpdateWidget(covariant CompactProcessResourceMonitor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferences != widget.preferences ||
        oldWidget.coordinator != widget.coordinator ||
        oldWidget.isHidden != widget.isHidden) {
      _preferences.removeListener(_changed);
      _hidden.removeListener(_syncVisibility);
      _lease.dispose();
      _attach();
    }
    _syncVisibility();
    _scheduleVisibility();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final drawer = DrawerController.maybeOf(context);
    _treeVisible = TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        (drawer == null || drawer.isDrawerOpen);
    final position = Scrollable.maybeOf(context)?.position;
    if (_scroll != position) {
      _scroll?.removeListener(_scheduleVisibility);
      _scroll = position;
      _scroll?.addListener(_scheduleVisibility);
    }
    _syncVisibility();
    _scheduleVisibility();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleVisible = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    _syncVisibility();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _syncVisibility();
    _scheduleVisibility();
  }

  void _syncVisibility() {
    final active = _enabled &&
        _treeVisible &&
        _lifecycleVisible &&
        _inViewport &&
        !_hidden.value;
    if (mounted && _surfaceActive != active) {
      setState(() => _surfaceActive = active);
    }
    unawaited(_lease.setActive(active,
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
        var viewport = Offset.zero & MediaQuery.sizeOf(context);
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
      _syncVisibility();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _preferences.removeListener(_changed);
    _hidden.removeListener(_syncVisibility);
    _scroll?.removeListener(_scheduleVisibility);
    _lease.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    _scheduleVisibility();
    if (!_enabled) return const SizedBox.shrink();
    final color = WindowChromeTheme.foregroundOf(context);
    final track = color.withValues(alpha: .16);
    final inline = widget.surface == ProcessResourceSurface.lyrics;
    return _CompactVisibilityProbe(
      onPaint: _scheduleVisibility,
      child: RepaintBoundary(
        key: _surface,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.4,
          child: ListenableBuilder(
            listenable: _surfaceActive
                ? _lease.service
                : const AlwaysStoppedAnimation<double>(0),
            builder: (context, _) {
              final service = _lease.service;
              final current = service.latest;
              final metrics = [
                _MetricData('CPU', Symbols.memory, current?.cpuPercent,
                    service.history.map((s) => s.cpuPercent).toList(),
                    unavailable: service.unavailable ||
                        current?.cpuStatus == 'unavailable'),
                _MetricData('GPU', Symbols.monitor, current?.gpuPercent,
                    service.history.map((s) => s.gpuPercent).toList(),
                    unavailable: service.unavailable ||
                        current?.gpuStatus == 'unavailable'),
                _MetricData('RAM', Symbols.memory_alt, current?.ramPercent,
                    service.history.map((s) => s.ramPercent).toList(),
                    unavailable: service.unavailable ||
                        (current != null && current.ramPercent == null),
                    bytes: current?.workingSetBytes),
              ];
              Widget metric(_MetricData data) => _CompactMetric(
                  key: ValueKey(
                      'compact-resource-${widget.surface.name}-${data.name}'),
                  data: data,
                  mode: _preferences.value.display,
                  color: color,
                  track: track,
                  inline: inline,
                  compactSidebar: widget.compactSidebar);
              if (inline) {
                return SizedBox(
                    height: 40,
                    child: Row(children: [
                      for (var index = 0; index < metrics.length; index++) ...[
                        if (index > 0) SizedBox(width: widget.columnSpacing),
                        Expanded(child: metric(metrics[index])),
                      ]
                    ]));
              }
              return Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                      widget.compactSidebar ? 0 : 26,
                      4,
                      widget.compactSidebar ? 0 : 26,
                      12),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    for (var index = 0; index < metrics.length; index++) ...[
                      metric(metrics[index]),
                    ]
                  ]));
            },
          ),
        ),
      ),
    );
  }
}

class _MetricData {
  const _MetricData(this.name, this.icon, this.value, this.history,
      {required this.unavailable, this.bytes});
  final String name;
  final IconData icon;
  final double? value;
  final List<double?> history;
  final bool unavailable;
  final int? bytes;
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric(
      {super.key,
      required this.data,
      required this.mode,
      required this.color,
      required this.track,
      required this.inline,
      required this.compactSidebar});
  final _MetricData data;
  final ProcessResourceDisplay mode;
  final Color color, track;
  final bool inline, compactSidebar;

  @override
  Widget build(BuildContext context) {
    final value = data.value;
    final percent = value == null
        ? ui(data.unavailable ? '不可用' : '等待采样')
        : '${value.toStringAsFixed(1)}%';
    final details = data.bytes == null
        ? percent
        : '$percent · ${(data.bytes! / (1024 * 1024)).toStringAsFixed(1)} MiB';
    final label = '${ui(data.name == 'RAM' ? '内存' : data.name)}: $details';
    final number = value == null ? '—' : '${value.toStringAsFixed(1)}%';
    final icon = Icon(data.icon, size: inline ? 24 : 28, color: color);
    final indicator = value == null && !inline
        ? Text('—',
            style:
                Theme.of(context).textTheme.labelSmall?.copyWith(color: color))
        : mode == ProcessResourceDisplay.numbers
            ? FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(number,
                    maxLines: 1,
                    softWrap: false,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: color,
                        fontSize: inline ? 10 : 12,
                        fontFeatures: const [FontFeature.tabularFigures()])))
            : SizedBox(
                width: double.infinity,
                child: ProcessResourceChart(
                    history: data.history,
                    value: value,
                    maximum: 100,
                    mode: mode,
                    color: color,
                    track: track,
                    height: mode == ProcessResourceDisplay.line ? 12 : 4));
    final content =
        ExcludeSemantics(child: LayoutBuilder(builder: (context, constraints) {
      if (compactSidebar && !inline) {
        return SizedBox(height: 34, child: Center(child: icon));
      }
      if (inline) {
        return Column(mainAxisSize: MainAxisSize.min, children: [
          icon,
          const SizedBox(height: 2),
          SizedBox(
              width: math.min(constraints.maxWidth,
                  mode == ProcessResourceDisplay.numbers ? 64 : 24),
              height: mode == ProcessResourceDisplay.numbers ? 14 : 12,
              child: Align(alignment: Alignment.center, child: indicator)),
        ]);
      }
      return SizedBox(
          height: 32,
          child: Row(children: [
            icon,
            const SizedBox(width: 12),
            if (mode == ProcessResourceDisplay.numbers || value == null)
              Flexible(child: indicator)
            else
              Expanded(child: indicator)
          ]));
    }));
    return Semantics(
        label: label,
        child: inline || compactSidebar
            ? Tooltip(
                message: label, excludeFromSemantics: true, child: content)
            : content);
  }
}

// Position-only changes can occur without rebuilding the resource slot. Its
// existing layout/paint is the visibility trigger; there is no polling timer.
class _CompactVisibilityProbe extends SingleChildRenderObjectWidget {
  const _CompactVisibilityProbe({required this.onPaint, required super.child});
  final VoidCallback onPaint;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _CompactVisibilityRender(onPaint);
  @override
  void updateRenderObject(BuildContext context,
          covariant _CompactVisibilityRender renderObject) =>
      renderObject.onPaint = onPaint;
}

class _CompactVisibilityRender extends RenderProxyBox {
  _CompactVisibilityRender(this.onPaint);
  VoidCallback onPaint;
  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    onPaint();
  }
}
