import 'package:dan_player/component/app_scrollbar.dart';
import 'package:dan_player/component/app_content_transition.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_shape.dart';
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

/// Sections mount on first visit, then remain alive. Small bounded settings
/// groups use a scroll view + Column so offscreen editors keep uncommitted text.
/// Inactive sections cannot accept focus or expose duplicate semantics. Their
/// ticker gate follows the visual-update preference; unvisited sections stay lazy.
class GroupedSettings extends StatefulWidget {
  const GroupedSettings({super.key, required this.sections});
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
    _selected = widget.sections.first.id;
    _visited.add(_selected);
  }

  @override
  void didUpdateWidget(covariant GroupedSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = widget.sections.map((section) => section.id).toSet();
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
              if (compact)
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: ui("设置分类"),
                    border: AppShape.inputBorder,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      dropdownColor:
                          Theme.of(context).colorScheme.surfaceContainerLow,
                      elevation: 3,
                      key: const ValueKey('settings-category-picker'),
                      value: _selected,
                      isExpanded: true,
                      itemHeight: null,
                      menuMaxHeight: MediaQuery.sizeOf(context).height * .65,
                      borderRadius: AppShape.controlRadius,
                      onChanged: (id) {
                        if (id != null) _select(id);
                      },
                      selectedItemBuilder: (context) => [
                        for (final section in widget.sections)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(section.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      items: [
                        for (final section in widget.sections)
                          DropdownMenuItem(
                            key: ValueKey('settings-category-${section.id}'),
                            value: section.id,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
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
              else
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final section in widget.sections)
                    ChoiceChip(
                      key: ValueKey('settings-category-${section.id}'),
                      avatar: Icon(section.icon, size: 18),
                      showCheckmark: false,
                      label: Text(section.title),
                      selected: _selected == section.id,
                      onSelected: (_) => _select(section.id),
                    ),
                ]),
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
                            child: ExcludeFocus(
                              excluding: _selected != section.id,
                              child: _SectionContent(section: section),
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

class _SectionContent extends StatefulWidget {
  const _SectionContent({required this.section});
  final SettingsSection section;

  @override
  State<_SectionContent> createState() => _SectionContentState();
}

class _SectionContentState extends State<_SectionContent> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return AppScrollbar(
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
              if (entry.$1 != 0) const SizedBox(height: 16),
              AppEntrance(
                identity: (
                  'settings-row',
                  widget.section.id,
                  entry.$2.runtimeType,
                  entry.$1
                ),
                order: entry.$1,
                child: entry.$2,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
