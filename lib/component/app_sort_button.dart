import 'dart:math' as math;

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/sorting/sort_direction.dart';
import 'package:flutter/material.dart';

export 'package:dan_player/sorting/sort_direction.dart';
import 'package:desktop_lyric/ui_language.dart';

class AppSortOption<T> {
  const AppSortOption({
    required this.value,
    required this.label,
    required this.icon,
    this.key,
    this.group,
    this.enabled = true,
  });

  final T value;
  final String label;
  final IconData icon;
  final Key? key;
  final String? group;
  final bool enabled;
}

sealed class _SortChoice<T> {
  const _SortChoice();
}

class _MethodChoice<T> extends _SortChoice<T> {
  const _MethodChoice(this.value);
  final T value;
}

class _DirectionChoice<T> extends _SortChoice<T> {
  const _DirectionChoice(this.value);
  final SortDirection value;
}

/// A shared, bounded 44px sorting capsule with one keyboard/touch menu for the
/// method and its direction. It owns no data, preferences, or playback state.
class AppSortButton<T> extends StatefulWidget {
  const AppSortButton({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.direction,
    this.onDirectionChanged,
    this.enabled = true,
    this.maxWidth,
    this.scopeId,
    this.isCurrent,
    this.helpText,
  });

  final T value;
  final List<AppSortOption<T>> options;
  final ValueChanged<T> onChanged;
  final SortDirection? direction;
  final ValueChanged<SortDirection>? onDirectionChanged;
  final bool enabled;
  final double? maxWidth;

  /// Use a stable page/group identity, not a list rebuilt on each playback tick.
  /// An old overlay cannot apply its action to a newly opened group.
  final Object? scopeId;
  final bool Function()? isCurrent;
  final String? helpText;

  @override
  State<AppSortButton<T>> createState() => _AppSortButtonState<T>();
}

class _AppSortButtonState<T> extends State<AppSortButton<T>>
    with WidgetsBindingObserver {
  final _anchor = GlobalKey();
  RelativeRect? _lastPosition;
  bool _open = false;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(AppSortButton<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scopeId != widget.scopeId ||
        oldWidget.value != widget.value ||
        (oldWidget.enabled && !widget.enabled)) {
      _epoch++;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool get _enabled => widget.enabled && widget.options.isNotEmpty;
  bool get _current => widget.isCurrent?.call() ?? true;

  String _localizedHelpText(String text) {
    final complete = ui(text);
    if (complete != text || !text.contains('\n')) return complete;
    // Callers compose the footer from independently catalogued notes. Looking
    // up the joined string would otherwise fall back to Chinese in non-Chinese
    // interfaces even though every individual line has a translation.
    return text.split('\n').map(ui).join('\n');
  }

  bool get _needsScrollHint {
    final rowCount = widget.options.length +
        widget.options
            .map((option) => option.group)
            .whereType<String>()
            .toSet()
            .length +
        (widget.direction == null ? 0 : 2) +
        (widget.helpText == null ? 0 : 1);
    return rowCount * 48 >
        math.min(480, MediaQuery.sizeOf(context).height - 48);
  }

  RelativeRect _position(BuildContext _, BoxConstraints constraints) {
    if (!mounted) return _lastPosition ?? RelativeRect.fill;
    final button = _anchor.currentContext?.findRenderObject();
    final overlay = Navigator.of(context).overlay?.context.findRenderObject();
    if (button is! RenderBox ||
        overlay is! RenderBox ||
        !button.attached ||
        !overlay.attached) {
      return _lastPosition ?? RelativeRect.fill;
    }
    final bottomLeft = button.localToGlobal(Offset(0, button.size.height + 6),
        ancestor: overlay);
    return _lastPosition = RelativeRect.fromRect(
      Rect.fromLTWH(bottomLeft.dx, bottomLeft.dy, button.size.width, 0),
      Offset.zero & overlay.size,
    );
  }

  PopupMenuItem<_SortChoice<T>> _menuItem({
    required _SortChoice<T> value,
    required String label,
    required IconData icon,
    required bool checked,
    Key? key,
    bool enabled = true,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuItem<_SortChoice<T>>(
      key: key,
      value: value,
      enabled: enabled,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(icon,
              size: 20,
              color: enabled
                  ? scheme.onSurfaceVariant
                  : scheme.onSurface.withValues(alpha: .38)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(ui(label),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                semanticsLabel: ui(label)),
          ),
          if (checked) ...[
            const SizedBox(width: 8),
            Icon(Icons.check, size: 18, color: scheme.primary),
          ],
        ],
      ),
    );
  }

  List<PopupMenuEntry<_SortChoice<T>>> _menuItems() {
    final items = <PopupMenuEntry<_SortChoice<T>>>[];
    if (_needsScrollHint) {
      items.add(PopupMenuItem<_SortChoice<T>>(
        key: const ValueKey('app-sort-scroll-hint'),
        enabled: false,
        height: 48,
        child: Row(children: [
          const Icon(Icons.unfold_more, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(ui("滚动或滑动查看更多排序项"),
                  style: Theme.of(context).textTheme.bodySmall)),
        ]),
      ));
    }
    if (widget.direction != null && widget.onDirectionChanged != null) {
      for (final direction in SortDirection.values) {
        items.add(_menuItem(
          key: ValueKey('app-sort-direction-${direction.name}'),
          value: _DirectionChoice(direction),
          label: direction.label,
          icon: direction == SortDirection.ascending
              ? Icons.arrow_upward
              : Icons.arrow_downward,
          checked: direction == widget.direction,
        ));
      }
      items.add(const PopupMenuDivider(height: 10));
    }
    // Group the menu without changing option indexes/values used by the legacy
    // page preferences. showMenu supplies a bounded, keyboard-scrollable list.
    final groups = <String?, List<AppSortOption<T>>>{};
    for (final option in widget.options) {
      (groups[option.group] ??= []).add(option);
    }
    var firstGroup = true;
    for (final entry in groups.entries) {
      if (!firstGroup) items.add(const PopupMenuDivider(height: 10));
      firstGroup = false;
      if (entry.key != null) {
        items.add(PopupMenuItem<_SortChoice<T>>(
          enabled: false,
          height: 48,
          child: Text(ui(entry.key!),
              style: Theme.of(context).textTheme.labelMedium),
        ));
      }
      for (final option in entry.value) {
        items.add(_menuItem(
          key: option.key,
          value: _MethodChoice(option.value),
          label: option.label,
          icon: option.icon,
          checked: option.value == widget.value,
          enabled: option.enabled,
        ));
      }
    }
    if (widget.helpText case final String text when text.isNotEmpty) {
      items.add(const PopupMenuDivider(height: 10));
      items.add(PopupMenuItem<_SortChoice<T>>(
        enabled: false,
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(_localizedHelpText(text),
            style: Theme.of(context).textTheme.bodySmall),
      ));
    }
    return items;
  }

  Future<void> _show() async {
    if (_open || !_enabled || !_current) return;
    final epoch = _epoch;
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final reduced = appToolbarReduceMotion(context);
    setState(() => _open = true);
    _SortChoice<T>? result;
    try {
      result = await showMenu<_SortChoice<T>>(
        context: _anchor.currentContext ?? context,
        semanticLabel: _needsScrollHint ? ui("排序方式，可滚动查看更多字段") : ui("排序方式"),
        positionBuilder: _position,
        shape: AppShape.control,
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shadowColor: scheme.shadow.withValues(alpha: .18),
        elevation: 4,
        requestFocus: true,
        constraints: BoxConstraints(
          maxWidth: math.max(44, math.min(360, size.width - 32)),
          maxHeight: math.max(48, math.min(480, size.height - 48)),
        ),
        menuPadding: const EdgeInsets.symmetric(vertical: 6),
        popUpAnimationStyle: reduced
            ? AnimationStyle.noAnimation
            : const AnimationStyle(
                duration: AppMotion.quick,
                reverseDuration: AppMotion.quick,
                curve: AppMotion.standardCurve,
                reverseCurve: Curves.easeInCubic,
              ),
        items: _menuItems(),
      );
    } finally {
      if (mounted) setState(() => _open = false);
    }
    if (!mounted) return;
    if (result == null || epoch != _epoch || !_enabled || !_current) return;
    switch (result) {
      case _MethodChoice<T>():
        // Validate against live options instead of invoking an opening snapshot.
        for (final option in widget.options) {
          if (option.value == result.value && option.enabled) {
            widget.onChanged(option.value);
            break;
          }
        }
      case _DirectionChoice<T>():
        if (widget.direction != null) {
          widget.onDirectionChanged?.call(result.value);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final option = widget.options.where((item) => item.value == widget.value);
    final method = option.isEmpty ? ui("排序") : ui(option.first.label);
    final label = widget.direction == null
        ? method
        : '$method · ${ui(widget.direction!.label)}';
    final reduced = appToolbarReduceMotion(context);
    final maxWidth = widget.maxWidth ??
        math.max(44.0, math.min(320.0, MediaQuery.sizeOf(context).width - 32));
    const arrow = Icon(Icons.expand_more, size: 18);
    // showMenu captures this inherited theme from the anchor context. Windows'
    // standard scroll behavior supplies an independent controller per popup;
    // the app's scrollbar reveals the bounded menu's scroll extent on input.
    return ScrollbarTheme(
      data: ScrollbarTheme.of(context).copyWith(
        interactive: true,
      ),
      child: ConstrainedBox(
        key: _anchor,
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Tooltip(
          message: ui("排序：{0}", [label]),
          triggerMode: TooltipTriggerMode.manual,
          excludeFromSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onSecondaryTap: _enabled ? _show : null,
            onLongPress: _enabled ? _show : null,
            child: OutlinedButton(
              onPressed: _enabled ? _show : null,
              style: appToolbarControlStyle(context, reduced: reduced),
              child: AppToolbarLabel(
                label: label,
                semanticsLabel: ui("排序：{0}", [label]),
                icon: widget.direction == null
                    ? Icons.sort
                    : widget.direction == SortDirection.ascending
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                trailing: reduced
                    ? arrow
                    : AnimatedRotation(
                        turns: _open ? .5 : 0,
                        duration: AppMotion.quick,
                        curve: AppMotion.standardCurve,
                        child: arrow,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
