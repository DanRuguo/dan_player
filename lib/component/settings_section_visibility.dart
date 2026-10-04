import 'package:flutter/widgets.dart';

/// Whether this retained settings section is the current category.
/// This is independent of preferences which keep hidden visual effects active.
class SettingsSectionVisibility extends InheritedWidget {
  const SettingsSectionVisibility({
    super.key,
    required this.visible,
    required super.child,
  });

  final bool visible;

  /// Standalone settings widgets remain visible without a section host.
  static bool isVisibleOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SettingsSectionVisibility>()
          ?.visible ??
      true;

  @override
  bool updateShouldNotify(SettingsSectionVisibility oldWidget) =>
      visible != oldWidget.visible;
}
