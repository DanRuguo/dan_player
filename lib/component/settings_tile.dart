import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:flutter/material.dart';

/// One settings surface and one set of row metrics, independent of persistence.
/// Embedded rows opt out of a second card while retaining identical controls.
class SettingsSurface extends StatelessWidget {
  const SettingsSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  static const rowPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);
  static const embeddedRowPadding = EdgeInsets.symmetric(vertical: 12);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: AppShape.surface.copyWith(
        side: BorderSide(
            color: MediaQuery.maybeHighContrastOf(context) == true
                ? scheme.outline
                : scheme.outlineVariant.withValues(alpha: .45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTileTheme(
        data: ListTileTheme.of(context).copyWith(
          contentPadding: rowPadding,
          horizontalTitleGap: 12,
          minLeadingWidth: 24,
          iconColor: scheme.primary,
          textColor: scheme.onSurface,
          titleTextStyle:
              theme.textTheme.titleMedium?.copyWith(color: scheme.onSurface),
          subtitleTextStyle: theme.textTheme.bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class SettingsHeader extends StatelessWidget {
  const SettingsHeader(
      {super.key, required this.title, required this.icon, this.subtitle});
  final String title;
  final IconData icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox.square(
          dimension: 24,
          child: Icon(icon, size: 22, color: theme.colorScheme.primary)),
      const SizedBox(width: 12),
      Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
            Text(title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.onSurface)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ])),
    ]);
  }
}

/// Keeps Material's merged toggle semantics, full-row hit target and keyboard
/// handling. [controlKey] belongs to the real SwitchListTile, not this wrapper.
class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile(
      {super.key,
      this.controlKey,
      required this.icon,
      required this.title,
      this.subtitle,
      required this.value,
      required this.onChanged,
      this.surface = true,
      this.contentPadding = SettingsSurface.rowPadding});
  final Key? controlKey;
  final IconData icon;
  final Widget title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool surface;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final row = SwitchListTile(
      key: controlKey,
      title: title,
      subtitle: subtitle,
      secondary: SizedBox.square(
          dimension: 24,
          child: Icon(icon,
              size: 22,
              color: onChanged == null
                  ? Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: .38)
                  : Theme.of(context).colorScheme.primary)),
      contentPadding: contentPadding,
      value: value,
      onChanged: onChanged,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
    return surface
        ? SettingsSurface(padding: EdgeInsets.zero, child: row)
        : row;
  }
}

class SettingsTile extends StatefulWidget {
  const SettingsTile(
      {super.key,
      required this.description,
      required this.action,
      this.icon,
      this.subtitle,
      this.surface = true});

  final String description;
  final Widget action;
  final IconData? icon;
  final String? subtitle;
  final bool surface;

  @override
  State<SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<SettingsTile> {
  // Unique to this control and stable when its displayed language changes.
  late final _entranceIdentity = ('setting', widget.description);

  @override
  Widget build(BuildContext context) {
    final description = widget.description;
    final action = widget.action;
    final icon = widget.icon;
    final content = LayoutBuilder(builder: (context, constraints) {
      final label = icon != null
          ? SettingsHeader(
              title: description, icon: icon, subtitle: widget.subtitle)
          : Text(description, style: Theme.of(context).textTheme.titleMedium);
      if (constraints.maxWidth < 560 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.4) {
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              label,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: action)
            ]);
      }
      return Row(children: [
        Expanded(child: label),
        const SizedBox(width: 16),
        action
      ]);
    });
    return AppEntrance(
      // Translated text must not restart this entrance animation.
      identity: _entranceIdentity,
      child: widget.surface ? SettingsSurface(child: content) : content,
    );
  }
}
