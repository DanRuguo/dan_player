import 'dart:ui' show lerpDouble;

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/side_nav_layout.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Two finite clocks shared by the continuous navigation and its resource rows.
/// Width follows the pointer; only compact-mode changes and label recovery tick.
class SidebarMotionScope extends StatefulWidget {
  const SidebarMotionScope({
    super.key,
    required this.width,
    required this.resizing,
    required this.labels,
    required this.child,
  });

  final double width;
  final bool resizing;
  final List<String> labels;
  final Widget child;

  static SidebarMotion? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SidebarMotionInherited>();

  @override
  State<SidebarMotionScope> createState() => _SidebarMotionScopeState();
}

abstract interface class SidebarMotion {
  double get width;
  bool get compact;
  double get mode;
  double get labelOpacity;
  double get iconStart;
}

class _SidebarMotionScopeState extends State<SidebarMotionScope>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final _mode = AnimationController(vsync: this);
  late final _label = AnimationController(vsync: this, value: 1);
  late final _visual = Listenable.merge([_mode, _label]);
  bool? _compact;
  double _threshold = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted && _compact != null) setState(_updateTargets);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    UiLanguageScope.watch(context);
    _measureAndUpdate();
  }

  @override
  void didUpdateWidget(covariant SidebarMotionScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.labels, widget.labels)) {
      _measureAndUpdate();
    } else {
      _updateTargets();
    }
  }

  void _measureAndUpdate() {
    _threshold = sideNavCompactThreshold(context, widget.labels);
    _updateTargets();
  }

  void _updateTargets() {
    final compact = widget.width <= _threshold;
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    final animate = AppMotion.enabled(context, MotionKind.layout) &&
        !features.disableAnimations &&
        !features.reduceMotion &&
        TickerMode.valuesOf(context).enabled;
    if (_compact == null || !animate) {
      _mode.value = compact ? 1 : 0;
    } else if (_compact != compact) {
      _mode.animateTo(compact ? 1 : 0,
          duration: AppMotion.emphasized, curve: AppMotion.standardCurve);
    }
    _compact = compact;
    final opacity = widget.resizing && !compact
        ? ((widget.width - _threshold) / 48).clamp(0.0, 1.0)
        : 1.0;
    if (widget.resizing || !animate) {
      _label.value = opacity;
    } else if (_label.value != opacity) {
      _label.animateTo(opacity,
          duration: AppMotion.standard, curve: AppMotion.standardCurve);
    }
  }

  @override
  Widget build(BuildContext context) => _SidebarMotionInherited(
      notifier: _visual,
      width: widget.width,
      compact: _compact!,
      modeAnimation: _mode,
      labelAnimation: _label,
      child: widget.child);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mode.dispose();
    _label.dispose();
    super.dispose();
  }
}

class _SidebarMotionInherited extends InheritedNotifier<Listenable>
    implements SidebarMotion {
  const _SidebarMotionInherited({
    required super.notifier,
    required this.width,
    required this.compact,
    required this.modeAnimation,
    required this.labelAnimation,
    required super.child,
  });

  @override
  final double width;
  @override
  final bool compact;
  final Animation<double> modeAnimation, labelAnimation;

  @override
  double get mode => modeAnimation.value;

  @override
  double get iconStart =>
      lerpDouble(14, (width - 44) / 2, mode)! + lerpDouble(12, 8, mode)!;

  @override
  double get labelOpacity =>
      labelAnimation.value * ((66 - iconStart - 28) / 12).clamp(0.0, 1.0);

  @override
  bool updateShouldNotify(_SidebarMotionInherited oldWidget) =>
      super.updateShouldNotify(oldWidget) ||
      width != oldWidget.width ||
      compact != oldWidget.compact;
}
