import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:desktop_lyric/ui_language.dart';

enum AppNoticeKind { info, success, warning, error }

/// Owns feedback above the navigator (including every dialog barrier), while
/// content regions provide the actual rounded-panel bounds, not window width.
class AppPresentationHost extends StatefulWidget {
  const AppPresentationHost({super.key, required this.child});
  final Widget child;

  static AppPresentationHostState? _current;
  static AppPresentationHostState? maybeOf(BuildContext? context) =>
      context?.dependOnInheritedWidgetOfExactType<_PresentationScope>()?.host ??
      _current;

  @override
  State<AppPresentationHost> createState() => AppPresentationHostState();
}

class AppPresentationHostState extends State<AppPresentationHost> {
  final _changes = ValueNotifier<int>(0);
  final _regions = <_ContentRegionHandle>[];
  final _hostKey = GlobalKey();
  _Notice? _notice;
  Timer? _expiry;
  Timer? _removal;
  int _revision = 0;
  bool _closing = false;
  bool _regionUpdateQueued = false;

  _ContentRegionHandle? get _activeRegion {
    for (final region in _regions.reversed) {
      if (region.active && region.rect != null) return region;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    AppPresentationHost._current = this;
  }

  @override
  void dispose() {
    _expiry?.cancel();
    _removal?.cancel();
    if (identical(AppPresentationHost._current, this)) {
      AppPresentationHost._current = null;
    }
    _changes.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _changes.value++;
  }

  void _regionChanged() {
    if (_regionUpdateQueued) return;
    _regionUpdateQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _regionUpdateQueued = false;
      _changed();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void showNotice(
    String text, {
    AppNoticeKind kind = AppNoticeKind.info,
    Duration duration = const Duration(seconds: 4),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (text.trim().isEmpty) return;
    _expiry?.cancel();
    _removal?.cancel();
    final revision = ++_revision;
    void present() {
      if (!mounted || revision != _revision) return;
      _closing = false;
      _notice = _Notice(text, kind, revision, actionLabel, onAction);
      _changed();
      _expiry = Timer(duration, dismissNotice);
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => present());
    } else {
      present();
    }
  }

  void dismissNotice() {
    _expiry?.cancel();
    _removal?.cancel();
    if (_notice == null || !mounted) return;
    final revision = _revision;
    _closing = true;
    _changed();
    _removal = Timer(const Duration(milliseconds: 140), () {
      if (!mounted || revision != _revision) return;
      _notice = null;
      _changed();
    });
  }

  Rect _bounds(Size viewport, Offset origin, [_ContentRegionHandle? source]) {
    // A responsive shell can replace its region while a modal stays open.
    // Never keep centering against that disposed/offstage region's old rect.
    final sourceRect =
        source != null && _regions.contains(source) && source.active
            ? source.rect
            : null;
    final frame = sourceRect ?? _activeRegion?.rect;
    final viewportRect = Offset.zero & viewport;
    if (frame == null) return viewportRect;
    final clipped = frame.shift(-origin).intersect(viewportRect);
    return clipped.width > 0 && clipped.height > 0 ? clipped : viewportRect;
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return _PresentationScope(
      host: this,
      child: LayoutBuilder(builder: (context, constraints) {
        final notice = _notice;
        final box = _hostKey.currentContext?.findRenderObject() as RenderBox?;
        final origin = box?.hasSize == true
            ? box!.localToGlobal(Offset.zero)
            : Offset.zero;
        final bounds = _bounds(constraints.biggest, origin);
        final layout = notice == null
            ? null
            : _NoticeLayout.measure(context, notice, bounds.size);
        return Stack(
          key: _hostKey,
          fit: StackFit.expand,
          children: [
            widget.child,
            if (notice != null && layout != null)
              Positioned(
                left: bounds.center.dx - layout.width / 2,
                top: math.max(bounds.top + 4,
                    bounds.bottom - layout.height - layout.bottomInset),
                width: layout.width,
                height: layout.height,
                child: _NoticeBubble(
                  key: ValueKey(notice.revision),
                  notice: notice,
                  layout: layout,
                  closing: _closing,
                  onClose: dismissNotice,
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _PresentationScope extends InheritedWidget {
  const _PresentationScope({required this.host, required super.child});
  final AppPresentationHostState host;
  @override
  bool updateShouldNotify(_PresentationScope oldWidget) =>
      host != oldWidget.host;
}

class _ContentRegionHandle {
  Rect? rect;
  bool active = true;
}

/// Place directly around the clipped content panel, or around the mini player.
/// TickerMode excludes the preserved, offstage normal window in mini mode.
class AppContentRegion extends StatefulWidget {
  const AppContentRegion({super.key, required this.child});
  final Widget child;
  @override
  State<AppContentRegion> createState() => _AppContentRegionState();
}

class _AppContentRegionState extends State<AppContentRegion> {
  final _handle = _ContentRegionHandle();
  AppPresentationHostState? _host;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final host =
        context.dependOnInheritedWidgetOfExactType<_PresentationScope>()?.host;
    if (host != _host) {
      _host?._regions.remove(_handle);
      _host?._regionChanged();
      _host = host;
      _host?._regions.add(_handle);
    }
    _handle.active = TickerMode.valuesOf(context).enabled;
    _host?._regionChanged();
  }

  @override
  void dispose() {
    _host?._regions.remove(_handle);
    _host?._regionChanged();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return _DialogRegionScope(
      region: _handle,
      child: _RegionProbe(
        onRect: (rect) {
          if (rect == _handle.rect) return;
          _handle.rect = rect;
          _host?._regionChanged();
        },
        child: widget.child,
      ),
    );
  }
}

class _RegionProbe extends SingleChildRenderObjectWidget {
  const _RegionProbe({required this.onRect, required super.child});
  final ValueChanged<Rect> onRect;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRegion(onRect);
  @override
  void updateRenderObject(BuildContext context, _RenderRegion renderObject) =>
      renderObject.onRect = onRect;
}

class _RenderRegion extends RenderProxyBox {
  _RenderRegion(this.onRect);
  ValueChanged<Rect> onRect;
  @override
  void paint(PaintingContext context, Offset offset) {
    onRect(localToGlobal(Offset.zero) & size);
    super.paint(context, offset);
  }
}

class _DialogRegionScope extends InheritedWidget {
  const _DialogRegionScope({required this.region, required super.child});
  final _ContentRegionHandle? region;
  @override
  bool updateShouldNotify(_DialogRegionScope oldWidget) =>
      region != oldWidget.region;
}

/// Retains normal Material route/barrier, focus, back and result semantics.
/// Nested editors inherit the originating content region, not the whole window.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
}) {
  final host = AppPresentationHost.maybeOf(context);
  final region = context
          .dependOnInheritedWidgetOfExactType<_DialogRegionScope>()
          ?.region ??
      host?._activeRegion;
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  return navigator.push<T>(_CompletingDialogRoute<T>(
    context: context,
    useSafeArea: host == null,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor ??
        DialogTheme.of(context).barrierColor ??
        Theme.of(context).dialogTheme.barrierColor ??
        Colors.black54,
    barrierLabel: barrierLabel,
    settings: routeSettings,
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    builder: (dialogContext) => host == null
        ? builder(dialogContext)
        : _DialogRegionScope(
            region: region,
            child:
                _AppDialogFrame(host: host, region: region, builder: builder),
          ),
  ));
}

/// Navigator teardown does not necessarily pop its routes. A mini-mode dialog
/// can disappear this way, leaving its caller's await and busy guard stuck.
/// Complete only that abandoned result; normal pops retain their actual value.
class _CompletingDialogRoute<T> extends DialogRoute<T> {
  _CompletingDialogRoute({
    required super.context,
    required super.builder,
    super.themes,
    super.barrierDismissible,
    super.barrierColor,
    super.barrierLabel,
    super.useSafeArea,
    super.settings,
    super.traversalEdgeBehavior,
  });

  bool _completed = false;

  @override
  void didComplete(T? result) {
    _completed = true;
    super.didComplete(result);
  }

  @override
  void dispose() {
    if (!_completed) didComplete(null);
    super.dispose();
  }
}

class _AppDialogFrame extends StatelessWidget {
  const _AppDialogFrame(
      {required this.host, required this.region, required this.builder});
  final AppPresentationHostState host;
  final _ContentRegionHandle? region;
  final WidgetBuilder builder;
  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return AnimatedBuilder(
      animation: host._changes,
      // A notice or panel resize should relayout, not recreate the editor's
      // widget subtree. Inherited theme/media updates still reach this child.
      child: Builder(builder: builder),
      builder: (context, dialogChild) =>
          LayoutBuilder(builder: (context, constraints) {
        final navigatorBox =
            Navigator.of(context).context.findRenderObject() as RenderBox?;
        final origin = navigatorBox?.hasSize == true
            ? navigatorBox!.localToGlobal(Offset.zero)
            : Offset.zero;
        final rect = host._bounds(constraints.biggest, origin, region);
        final notice = host._notice;
        final reserve = notice == null
            ? 0.0
            : _NoticeLayout.measure(context, notice, rect.size).reservedHeight;
        final media = MediaQuery.of(context);
        final theme = Theme.of(context);
        return Stack(children: [
          Positioned.fromRect(
            rect: rect,
            // Reserve space in the same frame as the notice. Animating this
            // inset lets a newly shown bubble cover the old action position.
            // Dialog entry and the notice itself still animate normally.
            child: Padding(
              key: const ValueKey('app-dialog-available-region'),
              padding: EdgeInsets.only(bottom: reserve),
              child: MediaQuery(
                data: media.copyWith(size: rect.size, padding: EdgeInsets.zero),
                child: Theme(
                  data: theme.copyWith(
                      dialogTheme: theme.dialogTheme.copyWith(
                    alignment: Alignment.center,
                    insetPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  )),
                  child: dialogChild!,
                ),
              ),
            ),
          ),
        ]);
      }),
    );
  }
}

class _Notice {
  const _Notice(
      this.text, this.kind, this.revision, this.actionLabel, this.onAction);
  final String text;
  final AppNoticeKind kind;
  final int revision;
  final String? actionLabel;
  final VoidCallback? onAction;
}

class _NoticeLayout {
  const _NoticeLayout(this.width, this.height, this.maxLines, this.bottomInset,
      this.showIcon, this.actionWidth);
  final double width, height, bottomInset, actionWidth;
  final int maxLines;
  final bool showIcon;
  double get reservedHeight => height + bottomInset + 8;

  static _NoticeLayout measure(
      BuildContext context, _Notice notice, Size region) {
    final maxWidth = math.max(1.0, region.width * .6);
    final showIcon = maxWidth >= 240;
    final scale = MediaQuery.textScalerOf(context);
    final style =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final painter = TextPainter(
        text: TextSpan(text: notice.text, style: style),
        textDirection: Directionality.of(context),
        textScaler: scale);
    final hasAction = notice.actionLabel != null && notice.onAction != null;
    final actionPainter = TextPainter(
        text: TextSpan(text: notice.actionLabel ?? '', style: style),
        textDirection: Directionality.of(context),
        textScaler: scale)
      ..layout();
    final actionWidth =
        hasAction ? math.min(maxWidth * .26, actionPainter.width + 16) : 0.0;
    final fixedWidth = 24 + 32 + 8 + (showIcon ? 28 : 0) + actionWidth;
    painter.layout();
    final width = math.min(maxWidth,
        math.max(math.min(144.0, maxWidth), painter.width + fixedWidth));
    final textWidth = math.max(1.0, width - fixedWidth);
    final maxHeight = math.min(132.0, math.max(44.0, region.height * .26));
    final lineHeight = painter.preferredLineHeight;
    final lines = ((maxHeight - 20) / lineHeight).floor().clamp(1, 3);
    painter.text = TextSpan(text: notice.text, style: style);
    painter.maxLines = lines;
    painter.ellipsis = '…';
    painter.layout(maxWidth: textWidth);
    final height = math.min(region.height, math.max(44.0, painter.height + 20));
    painter.dispose();
    actionPainter.dispose();
    return _NoticeLayout(width, height, lines, region.height >= 120 ? 12 : 0,
        showIcon, actionWidth);
  }
}

class _NoticeBubble extends StatelessWidget {
  const _NoticeBubble(
      {super.key,
      required this.notice,
      required this.layout,
      required this.closing,
      required this.onClose});
  final _Notice notice;
  final _NoticeLayout layout;
  final bool closing;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground, icon, label) = switch (notice.kind) {
      AppNoticeKind.info => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
          Icons.info_outline,
          ui("提示")
        ),
      AppNoticeKind.success => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
          Icons.check_circle_outline,
          ui("成功")
        ),
      AppNoticeKind.warning => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
          Icons.warning_amber_rounded,
          ui("注意")
        ),
      AppNoticeKind.error => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          Icons.error_outline,
          ui("错误")
        ),
    };
    final reduced = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduced ? 1 : 0, end: 1),
      duration: reduced ? Duration.zero : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
              offset: Offset(0, (1 - value) * 6), child: child)),
      child: AnimatedOpacity(
        opacity: closing ? 0 : 1,
        duration: reduced ? Duration.zero : const Duration(milliseconds: 140),
        child: Material(
          key: const ValueKey('app-notice-bubble'),
          color: background,
          elevation: 6,
          shadowColor: scheme.shadow.withValues(alpha: .22),
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(children: [
              if (layout.showIcon) ...[
                Icon(icon, size: 20, color: foreground),
                const SizedBox(width: 8)
              ],
              Expanded(
                  child: Semantics(
                liveRegion: true,
                label: '$label：${notice.text}',
                excludeSemantics: true,
                child: Text(notice.text,
                    maxLines: layout.maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: foreground)),
              )),
              if (layout.actionWidth > 0)
                SizedBox(
                    width: layout.actionWidth,
                    child: TextButton(
                      style: TextButton.styleFrom(
                          foregroundColor: foreground,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: Size.zero),
                      onPressed: () {
                        onClose();
                        notice.onAction?.call();
                      },
                      child: Text(notice.actionLabel!,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    )),
              const SizedBox(width: 8),
              SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    key: const ValueKey('app-notice-close'),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints.tightFor(width: 32, height: 32),
                    icon: Icon(Icons.close_rounded,
                        semanticLabel: ui("关闭通知"), color: foreground, size: 20),
                    onPressed: onClose,
                  )),
            ]),
          ),
        ),
      ),
    );
  }
}
