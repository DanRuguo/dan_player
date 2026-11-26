import 'package:dan_player/component/app_scrollbar.dart';
import 'package:dan_player/component/app_content_transition.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/settings_section_visibility.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

class SettingsSection {
  const SettingsSection({
    required this.id,
    required this.title,
    required this.icon,
    required this.children,
  });
  final String id;
  final String title;
  final IconData icon;
  final List<Widget> children;
}

/// Visual sub-category divider inside a [SettingsSection] to organize dense
/// preference lists without splitting top-level navigation tabs.
class SettingsSubgroupHeader extends StatelessWidget {
  const SettingsSubgroupHeader({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
  });

  final String title;
  final IconData icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: scheme.primary),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Divider(
                height: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Propagates the active search-target setting ID so nested items inside a
/// consolidated card can scroll into view and highlight just like top-level
/// settings cards.
class SettingsTargetScope extends InheritedWidget {
  const SettingsTargetScope({
    super.key,
    required this.targetId,
    required this.targetKey,
    required super.child,
  });

  final String? targetId;
  final GlobalKey targetKey;

  static SettingsTargetScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsTargetScope>();

  @override
  bool updateShouldNotify(SettingsTargetScope oldWidget) =>
      oldWidget.targetId != targetId || oldWidget.targetKey != targetKey;
}

class SettingsTargetAnchor extends StatelessWidget {
  const SettingsTargetAnchor({
    super.key,
    required this.settingId,
    required this.child,
  });

  final String settingId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = SettingsTargetScope.maybeOf(context);
    final matched = scope != null && scope.targetId == settingId;
    if (!matched) return child;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: scope.targetKey,
      color: scheme.primary.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: AppShape.controlRadius,
        side: BorderSide(color: scheme.primary, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: child,
      ),
    );
  }
}

/// Sections mount on first visit, then remain alive. Small bounded settings
/// groups use a scroll view + Column so offscreen editors keep uncommitted text.
/// Inactive sections cannot accept focus or expose duplicate semantics. Their
/// ticker gate follows the visual-update preference; unvisited sections stay lazy.
class GroupedSettings extends StatefulWidget {
  const GroupedSettings(
      {super.key,
      required this.sections,
      this.initialSection,
      this.initialSetting});
  final String? initialSection, initialSetting;
  final List<SettingsSection> sections;

  @override
  State<GroupedSettings> createState() => _GroupedSettingsState();
}

class _GroupedSettingsState extends State<GroupedSettings> {
  late String _selected;
  final Set<String> _visited = {};

  @override
  void initState() {
    super.initState();
    assert(widget.sections.isNotEmpty);
    assert(widget.sections.map((section) => section.id).toSet().length ==
        widget.sections.length);
    _selected = widget.sections.any((s) => s.id == widget.initialSection)
        ? widget.initialSection!
        : widget.sections.first.id;
    _visited.add(_selected);
  }

  @override
  void didUpdateWidget(covariant GroupedSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = widget.sections.map((section) => section.id).toSet();
    if (oldWidget.initialSection != widget.initialSection &&
        ids.contains(widget.initialSection)) {
      _selected = widget.initialSection!;
    }
    _visited.removeWhere((id) => !ids.contains(id));
    if (!ids.contains(_selected)) _selected = widget.sections.first.id;
    _visited.add(_selected);
  }

  void _select(String id) {
    if (id == _selected) return;
    // Do not leave keyboard input attached to an offstage editor.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _selected = id;
      _visited.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720 ||
            MediaQuery.textScalerOf(context).scale(14) > 20;
        return Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppEntrance(
                identity: 'settings-category-navigation',
                child: compact
                    ? InputDecorator(
                        decoration: InputDecoration(
                          labelText: ui("设置分类"),
                          border: AppShape.inputBorder,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            dropdownColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerLow,
                            elevation: 3,
                            key: const ValueKey('settings-category-picker'),
                            value: _selected,
                            isExpanded: true,
                            itemHeight: null,
                            menuMaxHeight:
                                MediaQuery.sizeOf(context).height * .65,
                            borderRadius: AppShape.controlRadius,
                            onChanged: (id) {
                              if (id != null) _select(id);
                            },
                            selectedItemBuilder: (context) => [
                              for (final section in widget.sections)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(section.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            items: [
                              for (final section in widget.sections)
                                DropdownMenuItem(
                                  key: ValueKey(
                                      'settings-category-${section.id}'),
                                  value: section.id,
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    child: Row(children: [
                                      Icon(section.icon, size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(child: Text(section.title)),
                                    ]),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      )
                    : Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final section in widget.sections)
                          _SettingsCategoryTab(
                            key: ValueKey('settings-category-${section.id}'),
                            icon: section.icon,
                            label: section.title,
                            selected: _selected == section.id,
                            onTap: () => _select(section.id),
                          ),
                      ]),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: AppContentTransition(
                  identity: _selected,
                  child: IndexedStack(
                    index: widget.sections
                        .indexWhere((section) => section.id == _selected),
                    sizing: StackFit.expand,
                    children: [
                      for (final section in widget.sections)
                        if (_visited.contains(section.id))
                          TickerMode(
                            key: ValueKey('settings-section-${section.id}'),
                            enabled: _selected == section.id ||
                                !RenderingPreferencesScope.of(context)
                                    .pauseWhenHidden,
                            child: SettingsSectionVisibility(
                              visible: _selected == section.id,
                              child: ExcludeFocus(
                                excluding: _selected != section.id,
                                child: _SectionContent(
                                    section: section,
                                    target: section.id == widget.initialSection
                                        ? widget.initialSetting
                                        : null),
                              ),
                            ),
                          )
                        else
                          SizedBox.shrink(
                              key: ValueKey('settings-section-${section.id}')),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SettingsCategoryTab extends StatefulWidget {
  const _SettingsCategoryTab({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SettingsCategoryTab> createState() => _SettingsCategoryTabState();
}

class _SettingsCategoryTabState extends State<_SettingsCategoryTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final duration = AppMotion.duration(
      context,
      MotionKind.feedback,
      AppMotion.quick,
    );
    final Color bgColor;
    final Color borderColor;
    final Color fgColor;
    final Color iconColor;
    if (widget.selected) {
      bgColor = scheme.primaryContainer;
      borderColor = scheme.primary.withValues(alpha: 0.36);
      fgColor = scheme.onPrimaryContainer;
      iconColor = scheme.onPrimaryContainer;
    } else if (_hovered) {
      bgColor =
          scheme.secondaryContainer.withValues(alpha: isDark ? 0.42 : 0.55);
      borderColor = scheme.primary.withValues(alpha: 0.32);
      fgColor = scheme.onSurface;
      iconColor = scheme.primary;
    } else {
      bgColor = scheme.surfaceContainerLow;
      borderColor =
          scheme.outlineVariant.withValues(alpha: isDark ? 0.38 : 0.46);
      fgColor = scheme.onSurface;
      iconColor = scheme.primary;
    }
    return Semantics(
      button: true,
      selected: widget.selected,
      child: AnimatedContainer(
        duration: duration,
        curve: AppMotion.standardCurve,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: AppShape.pillRadius,
          border: Border.all(color: borderColor),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            onHover: (hovering) {
              if (_hovered != hovering) {
                setState(() => _hovered = hovering);
              }
            },
            borderRadius: AppShape.pillRadius,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: iconColor),
                  const SizedBox(width: 8),
                  Text(
                    widget.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: fgColor,
                      fontWeight:
                          widget.selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData get icon => widget.icon;
}

class _SectionContent extends StatefulWidget {
  const _SectionContent({required this.section, this.target});
  final String? target;
  final SettingsSection section;

  @override
  State<_SectionContent> createState() => _SectionContentState();
}

class _SectionContentState extends State<_SectionContent> {
  final _scroll = ScrollController();
  final _target = GlobalKey();
  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(covariant _SectionContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.target != oldWidget.target) _reveal();
  }

  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _target.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(target,
          alignment: 0,
          duration: AppMotion.duration(
              context, MotionKind.transitions, AppMotion.standard));
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final topLevelMatched = widget.target != null &&
        widget.section.children
            .any((child) => child.key == ValueKey('setting-${widget.target}'));
    return SettingsTargetScope(
      targetId: topLevelMatched ? null : widget.target,
      targetKey: _target,
      child: AppScrollbar(
        controller: _scroll,
        child: SingleChildScrollView(
          key: PageStorageKey('settings-scroll-${widget.section.id}'),
          controller: _scroll,
          primary: false,
          padding: const EdgeInsets.fromLTRB(0, 0, 12, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in widget.section.children.indexed) ...[
                if (entry.$1 != 0)
                  SizedBox(
                    height: entry.$2 is SettingsSubgroupHeader
                        ? 22
                        : (widget.section.children[entry.$1 - 1]
                                is SettingsSubgroupHeader
                            ? 10
                            : 16),
                  ),
                Container(
                  key: entry.$2.key == ValueKey('setting-${widget.target}')
                      ? _target
                      : null,
                  decoration:
                      entry.$2.key == ValueKey('setting-${widget.target}')
                          ? BoxDecoration(
                              borderRadius: AppShape.surfaceRadius,
                              border: Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2))
                          : null,
                  child: AppEntrance(
                    identity: (
                      'settings-row',
                      widget.section.id,
                      entry.$2.runtimeType,
                      entry.$1
                    ),
                    order: entry.$1,
                    child: entry.$2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
