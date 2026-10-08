import 'dart:io';
import 'dart:math' as math;
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/component/statistics_bar_row.dart';
import 'package:dan_player/component/statistics_card_header.dart';
import 'package:dan_player/statistics/app_data_storage.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Known read-only categories reserve their real translated layout while a
/// directory is waiting. No snapshot, scan, or animation is attached to these.
@immutable
class StorageCardLayout {
  const StorageCardLayout(
      {required this.title,
      required this.categories,
      required this.description});
  final String title, description;
  final List<String> categories;
}

/// The templates participate only in this parent's legal layout reads. They
/// have no future/clock/tooltip, never paint or hit-test, and expose no semantics.
/// Keeping the active child first also preserves its element and focus.
class _StorageSlot extends MultiChildRenderObjectWidget {
  const _StorageSlot({required super.children});
  @override
  MultiChildRenderObjectElement createElement() => _StorageSlotElement(this);
  @override
  RenderObject createRenderObject(BuildContext context) => _StorageSlotBox();
}

class _StorageSlotElement extends MultiChildRenderObjectElement {
  _StorageSlotElement(super.widget);
  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) =>
      visitor(children.first);
}

class _StorageSlotParentData extends ContainerBoxParentData<RenderBox> {}

class _StorageSlotBox extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _StorageSlotParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _StorageSlotParentData) {
      child.parentData = _StorageSlotParentData();
    }
  }

  Iterable<RenderBox> get _children sync* {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      yield child;
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) => _children.fold(0.0,
      (value, child) => math.max(value, child.getMinIntrinsicWidth(height)));
  @override
  double computeMaxIntrinsicWidth(double height) => _children.fold(0.0,
      (value, child) => math.max(value, child.getMaxIntrinsicWidth(height)));
  @override
  double computeMinIntrinsicHeight(double width) => _children.fold(0.0,
      (value, child) => math.max(value, child.getMinIntrinsicHeight(width)));
  @override
  double computeMaxIntrinsicHeight(double width) => _children.fold(0.0,
      (value, child) => math.max(value, child.getMaxIntrinsicHeight(width)));
  @override
  Size computeDryLayout(BoxConstraints constraints) {
    var extent = Size.zero;
    for (final child in _children) {
      final size = child.getDryLayout(constraints.loosen());
      extent = Size(math.max(extent.width, size.width),
          math.max(extent.height, size.height));
    }
    return constraints.constrain(extent);
  }

  @override
  void performLayout() {
    var width = 0.0, height = 0.0;
    for (final child in _children) {
      child.layout(constraints.loosen(), parentUsesSize: true);
      width = math.max(width, child.size.width);
      height = math.max(height, child.size.height);
      (child.parentData! as _StorageSlotParentData).offset = Offset.zero;
    }
    size = constraints.constrain(Size(width, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      context.paintChild(firstChild!, offset);
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      firstChild!.hitTest(result, position: position);
  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) =>
      visitor(firstChild!);
}

class AppDataStorageCard extends StatefulWidget {
  const AppDataStorageCard(
      {super.key,
      this.directory,
      this.reading,
      this.title,
      this.icon = Symbols.database,
      this.scopeDescription,
      this.headerControls,
      this.readingScope,
      this.layouts,
      this.layoutIndex = 0,
      this.scanner = const AppDataStorageScanner()});
  final Directory? directory;
  final String? title;
  final IconData icon;
  final String? scopeDescription;
  final Widget? headerControls;

  /// Different roots retain separate results. Refreshing the same root keeps
  /// its previous successful result until the new reading completes.
  final Object? readingScope;

  /// Optional directory templates require a finite width and natural height,
  /// as supplied by the statistics page. Bar rows do not support IntrinsicHeight.
  final List<StorageCardLayout>? layouts;
  final int layoutIndex;

  /// The statistics page owns refreshes; standalone cards read once on entry.
  final Future<AppDataStorageSnapshot>? reading;
  final AppDataStorageScanner scanner;
  @override
  State<AppDataStorageCard> createState() => _AppDataStorageCardState();
}

class _StorageReading {
  _StorageReading(this.future, this.data);
  final Future<AppDataStorageSnapshot> future;
  AppDataStorageSnapshot? data;
  Object? error;
  bool complete = false;
}

class _AppDataStorageCardState extends State<AppDataStorageCard>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late Future<AppDataStorageSnapshot> _reading = widget.reading ?? _scan();
  final _scopes = <Object?, _StorageReading>{};
  late final _reveal =
      AnimationController(vsync: this, duration: AppMotion.standard, value: 1);
  late final _progress =
      CurvedAnimation(parent: _reveal, curve: AppMotion.standardCurve);
  ValueListenable<RenderingPreferences>? _preferences;
  bool _animate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _rememberReading();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final preferences = RenderingPreferencesScope.listenableOf(context);
    if (!identical(preferences, _preferences)) {
      _preferences?.removeListener(_motionChanged);
      _preferences = preferences..addListener(_motionChanged);
    }
    _motionChanged();
  }

  void _finishReveal() {
    _reveal.stop();
    _reveal.value = 1;
  }

  void _motionChanged() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _animate = !appToolbarReduceMotion(context) &&
        _preferences!.value.animations.allows(MotionKind.feedback) &&
        _preferences!.value.allowsVisualUpdates(
            lifecycle: lifecycle,
            treeVisible: TickerMode.valuesOf(context).enabled) &&
        lifecycle != AppLifecycleState.hidden;
    if (!_animate) _finishReveal();
  }

  @override
  void didChangeAccessibilityFeatures() => _motionChanged();
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _motionChanged();

  void _rememberReading() {
    final scope = widget.readingScope;
    final previous = _scopes[scope];
    if (identical(previous?.future, _reading)) return;
    // The combined card has two roots. Keep this cache bounded if a standalone
    // caller later reuses the same State for additional directories.
    if (previous == null && _scopes.length == 2) {
      _scopes.remove(_scopes.keys.first);
    }
    final entry = _StorageReading(_reading, previous?.data);
    _scopes[scope] = entry;
    // An inactive scope can finish while its FutureBuilder is unmounted.
    // Cache it without requesting a frame; the active builders already observe
    // their future. A replaced reading or disposed card no longer owns it.
    _reading.then<void>((data) {
      if (!mounted || !identical(_scopes[scope], entry)) return;
      entry.data = data;
      entry.complete = true;
      if (widget.layouts != null &&
          widget.readingScope == scope &&
          data.bytes > 0 &&
          _animate) {
        _reveal.forward(from: 0);
      }
    }, onError: (Object error, StackTrace stack) {
      if (!mounted || !identical(_scopes[scope], entry)) return;
      entry.data = null;
      entry.error = error;
      entry.complete = true;
      if (widget.readingScope == scope) _finishReveal();
    });
  }

  Future<AppDataStorageSnapshot> _scan() async =>
      widget.scanner.scan(widget.directory ?? await getAppDataDir());
  @override
  void didUpdateWidget(covariant AppDataStorageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.readingScope != oldWidget.readingScope ||
        !identical(widget.reading, oldWidget.reading)) {
      _finishReveal();
    }
    if (widget.reading != oldWidget.reading ||
        widget.directory != oldWidget.directory ||
        widget.scanner != oldWidget.scanner) {
      _reading = widget.reading ?? _scan();
    }
    _rememberReading();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _preferences?.removeListener(_motionChanged);
    _progress.dispose();
    _reveal.dispose();
    super.dispose();
  }

  Widget _reserved(Widget child, Iterable<Widget> templates) =>
      _StorageSlot(children: [child, ...templates]);

  // These are measurement paragraphs, not hidden copies of the visible UI.
  // Match Text's inherited style/scaling without its UI label/tooltip wrappers.
  Widget _sizingText(BuildContext context, String text, {TextStyle? style}) =>
      RichText(
          text: TextSpan(
              text: text,
              style: DefaultTextStyle.of(context).style.merge(style)),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context));

  Widget _layoutBody(BuildContext context, AppDataStorageSnapshot? data,
      _StorageReading entry) {
    final theme = Theme.of(context);
    final layouts = widget.layouts!;
    final layout = layouts[widget.layoutIndex];
    // FileStat.size is a signed 64-bit byte count. The scanner's bounded file
    // count and real formatted units reserve numeric space without a pixel
    // height estimate; waiting/zero values cannot change the row's layout mode.
    final byteBudget = formatLibraryBytes(0x7fffffffffffffff);
    final numberWidth =
        StatisticsBarRow.measureValues(context, [byteBudget, '—']);
    final totalStyle =
        theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary);
    final maximumEntries = widget.scanner.maximumEntries;
    final total = data?.bytes ?? 0;
    final parts = {
      for (final part in data?.parts ?? <AppDataStoragePart>[]) part.label: part
    };
    Widget row(String label, {AppDataStoragePart? part, bool sizing = false}) =>
        StatisticsBarRow(
            label: ui(label),
            wrapLabel: true,
            showTooltip: !sizing,
            detail: sizing
                ? ''
                : '${ui('{0} 个文件', [
                        data == null ? '—' : part?.files ?? 0
                      ])}\n${part?.paths.join('\n') ?? ''}',
            valueLabel: sizing
                ? byteBudget
                : data == null
                    ? '—'
                    : formatLibraryBytes(part?.bytes ?? 0),
            valueColumnWidth: numberWidth,
            value: sizing ? 0 : part?.bytes.toDouble() ?? 0,
            maximum: total.toDouble(),
            progress: sizing ? null : _progress);
    final summary = Text(
        data == null
            ? '— · ${ui('{0} 个文件', ['—'])}'
            : '${formatLibraryBytes(total)} · ${ui('{0} 个文件', [data.files])}',
        style: totalStyle);
    final warning = data != null &&
            (data.truncated || data.unreadable > 0 || data.skippedLinks > 0)
        ? ui('统计未包含：不可读 {0} 项、链接 {1} 项{2}', [
            data.unreadable,
            data.skippedLinks,
            data.truncated ? ui('；已达到扫描上限') : ''
          ])
        : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _reserved(
          data == null ? summary : Tooltip(message: data.path, child: summary),
          [
            _sizingText(
                context, '$byteBudget · ${ui('{0} 个文件', [maximumEntries])}',
                style: totalStyle)
          ]),
      const SizedBox(height: 8),
      for (var index = 0; index < layout.categories.length; index++)
        _reserved(
            row(layout.categories[index],
                part: parts.remove(layout.categories[index])),
            [
              for (final candidate in layouts)
                if (index < candidate.categories.length)
                  row(candidate.categories[index], sizing: true)
            ]),
      // Custom injected categories remain visible; the known templates never
      // claim that an unknown file belongs to a different category.
      for (final part in parts.values) row(part.label, part: part),
      _reserved(
          entry.error != null
              ? Text(ui('无法读取此目录的占用信息'))
              : data == null
                  ? Text(ui('正在读取占用信息…'))
                  : warning == null
                      ? const SizedBox.shrink()
                      : Text(warning),
          [
            _sizingText(context, ui('正在读取占用信息…')),
            _sizingText(context, ui('无法读取此目录的占用信息')),
            _sizingText(
                context,
                ui('统计未包含：不可读 {0} 项、链接 {1} 项{2}',
                    [maximumEntries, maximumEntries, ui('；已达到扫描上限')])),
          ]),
      const SizedBox(height: 8),
      _reserved(
          Text(layout.description,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          [
            for (final candidate in layouts)
              _sizingText(context, candidate.description,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    final title = widget.title ?? ui('缓存与播放器数据占用');
    final entry = _scopes[widget.readingScope]!;
    final heading = FutureBuilder<AppDataStorageSnapshot>(
        future: _reading,
        builder: (context, result) {
          final waiting = !entry.complete &&
              result.connectionState == ConnectionState.waiting;
          final icon = Icon(waiting ? Symbols.hourglass_empty : widget.icon,
              color: theme.colorScheme.primary);
          final iconTheme = IconTheme.of(context);
          final iconSize = iconTheme.size ?? 24.0;
          final iconExtent = iconTheme.applyTextScaling == true
              ? MediaQuery.textScalerOf(context).scale(iconSize)
              : iconSize;
          Widget headingRow(String title, {Key? key}) =>
              Row(key: key, children: [
                Tooltip(
                    message: waiting ? ui('正在读取占用信息…') : title, child: icon),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(title, style: theme.textTheme.titleMedium)),
              ]);
          final row = headingRow(title,
              key: const ValueKey('app-data-storage-heading'));
          return widget.layouts == null
              ? row
              : _reserved(row, [
                  for (final layout in widget.layouts!)
                    Row(children: [
                      SizedBox.square(dimension: iconExtent),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _sizingText(context, layout.title,
                              style: theme.textTheme.titleMedium)),
                    ])
                ]);
        });
    return Card.filled(
        shape: RoundedRectangleBorder(
            borderRadius: AppShape.controlRadius,
            side: BorderSide(
                color:
                    theme.colorScheme.outlineVariant.withValues(alpha: .55))),
        color: theme.colorScheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.headerControls == null)
                    heading
                  else ...[
                    StatisticsCardHeader(
                        title: heading, controls: widget.headerControls!),
                    const SizedBox(height: 12),
                  ],
                  FutureBuilder<AppDataStorageSnapshot>(
                      key: ValueKey(widget.readingScope),
                      future: _reading,
                      initialData: entry.data,
                      builder: (context, result) {
                        final data = entry.error == null
                            ? result.data ?? entry.data
                            : null;
                        final total = data?.bytes ?? 0;
                        if (widget.layouts != null) {
                          return _layoutBody(context, data, entry);
                        }
                        return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (data != null) ...[
                                Tooltip(
                                    message: data.path,
                                    child: Text(
                                        '${formatLibraryBytes(total)} · ${ui('{0} 个文件', [
                                              data.files
                                            ])}',
                                        style: theme.textTheme.titleLarge
                                            ?.copyWith(
                                                color: theme
                                                    .colorScheme.primary))),
                                const SizedBox(height: 8),
                                for (final part in data.parts)
                                  StatisticsBarRow(
                                      label: ui(part.label),
                                      wrapLabel: true,
                                      detail: '${ui('{0} 个文件', [
                                            part.files
                                          ])}\n${part.paths.join('\n')}',
                                      valueLabel:
                                          formatLibraryBytes(part.bytes),
                                      value: part.bytes.toDouble(),
                                      maximum: total.toDouble()),
                                if (data.truncated ||
                                    data.unreadable > 0 ||
                                    data.skippedLinks > 0)
                                  Text(ui('统计未包含：不可读 {0} 项、链接 {1} 项{2}', [
                                    data.unreadable,
                                    data.skippedLinks,
                                    data.truncated ? ui('；已达到扫描上限') : ''
                                  ])),
                              ],
                              if (entry.error != null)
                                Text(ui('无法读取此目录的占用信息'))
                              else if (data == null)
                                Text(ui('正在读取占用信息…')),
                              const SizedBox(height: 8),
                              Text(
                                  widget.scopeDescription ??
                                      ui(
                                          '实际文件字节；用户资料、自选图片与可重建缓存分别统计。链接不跟随，仅打开此页或手动刷新时读取。'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant)),
                            ]);
                      }),
                ])));
  }
}
