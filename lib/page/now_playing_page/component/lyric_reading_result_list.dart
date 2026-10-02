import 'package:dan_player/component/app_content_scrollbar.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:flutter/material.dart';

/// A clipped, naturally sized lyric row. Ink belongs to this row's Material,
/// so scrolling cannot paint selection or hover on the dialog's header.
class LyricReadingResultRow extends StatelessWidget {
  const LyricReadingResultRow(
      {super.key,
      required this.tileKey,
      required this.text,
      required this.selected,
      required this.icon,
      required this.onTap,
      this.timestamp,
      this.semanticsText});
  final String text;
  final Key tileKey;
  final String? timestamp, semanticsText;
  final bool selected;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = onTap == null
        ? theme.disabledColor
        : selected
            ? scheme.primary
            : scheme.onSurface;
    final body = theme.textTheme.bodyLarge!.copyWith(color: color);
    final timeStyle = theme.textTheme.bodySmall!.copyWith(
        color: onTap == null
            ? theme.disabledColor
            : selected
                ? scheme.primary
                : scheme.onSurfaceVariant);
    return Material(
        color: selected
            ? scheme.secondaryContainer.withValues(alpha: .45)
            : Colors.transparent,
        shape: AppShape.control,
        clipBehavior: Clip.antiAlias,
        child: ListTile(
            key: tileKey,
            onTap: onTap,
            selected: selected,
            selectedTileColor: Colors.transparent,
            minTileHeight: 48,
            minVerticalPadding: 8,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            title: LayoutBuilder(builder: (context, constraints) {
              final time = timestamp;
              var inlineTime = false;
              if (time != null) {
                final painter = TextPainter(
                    text: TextSpan(text: time, style: timeStyle),
                    textDirection: TextDirection.ltr,
                    textScaler: MediaQuery.textScalerOf(context))
                  ..layout();
                final textWidth =
                    constraints.maxWidth - 24 - 12 - painter.width - 12;
                inlineTime = textWidth >= constraints.maxWidth * .45;
                painter.dispose();
              }
              final content = Row(children: [
                Icon(icon, size: 24, color: color),
                const SizedBox(width: 12),
                Expanded(
                    child:
                        Text(text, semanticsLabel: semanticsText, style: body)),
                if (time != null && inlineTime) ...[
                  const SizedBox(width: 12),
                  Text(time,
                      style: timeStyle, textDirection: TextDirection.ltr),
                ],
              ]);
              if (time == null || inlineTime) return content;
              return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    content,
                    const SizedBox(height: 4),
                    Text(time,
                        textAlign: TextAlign.right,
                        textDirection: TextDirection.ltr,
                        style: timeStyle)
                  ]);
            })));
  }
}

/// Lazy variable-height results with exact index reveal. A distant keyboard
/// destination becomes the viewport's sliver center; no guessed height or
/// preceding paragraph measurements are needed, even in a long document.
class LyricReadingResultList extends StatefulWidget {
  const LyricReadingResultList(
      {super.key,
      required this.itemCount,
      required this.itemBuilder,
      required this.resetToken,
      this.scrollViewKey,
      this.controller});
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final Object resetToken;
  final ScrollController? controller;
  final Key? scrollViewKey;

  @override
  State<LyricReadingResultList> createState() => LyricReadingResultListState();
}

class LyricReadingResultListState extends State<LyricReadingResultList> {
  final _center = GlobalKey();
  final Map<int, GlobalKey> _rowKeys = {};
  ScrollController? _owned;
  ScrollController get _scroll =>
      widget.controller ?? (_owned ??= ScrollController());
  int _pivot = 0, _generation = 0;

  @override
  void didUpdateWidget(LyricReadingResultList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetToken != widget.resetToken ||
        oldWidget.itemCount != widget.itemCount) {
      _generation++;
      _pivot = 0;
      _rowKeys.clear();
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  void revealIndex(int index) {
    if (index < 0 || index >= widget.itemCount) return;
    final generation = ++_generation;
    if (_rowKeys[index]?.currentContext == null) {
      setState(() {
        _pivot = index;
        // Keys do not reparent between lazy slivers during layout.
        _rowKeys.clear();
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation || !_scroll.hasClients) return;
      final row = _rowKeys[index]?.currentContext?.findRenderObject();
      final viewport = context.findRenderObject();
      if (row is! RenderBox ||
          viewport is! RenderBox ||
          !row.attached ||
          !row.hasSize) {
        return;
      }
      final bounds = row.localToGlobal(Offset.zero) & row.size;
      final visible = viewport.localToGlobal(Offset.zero) & viewport.size;
      // Leave a fully visible row in place. A tall row starts at its first
      // glyph; an ordinary next/previous row moves only enough to be visible.
      if (bounds.top < visible.top || row.size.height > visible.height) {
        _scroll.position.ensureVisible(row,
            alignment: 0,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart);
      } else if (bounds.bottom > visible.bottom) {
        _scroll.position.ensureVisible(row,
            alignment: 1,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
      }
    });
  }

  Widget _row(BuildContext context, int index) => SizedBox(
      key: _rowKeys.putIfAbsent(index, GlobalKey.new),
      child: widget.itemBuilder(context, index));

  @override
  Widget build(BuildContext context) => AppContentScrollbar(
      controller: _scroll,
      builder: (context, controller) => CustomScrollView(
              key: widget.scrollViewKey,
              controller: controller,
              center: _center,
              shrinkWrap: false,
              clipBehavior: Clip.hardEdge,
              semanticChildCount: widget.itemCount,
              slivers: [
                SliverList(
                    delegate: SliverChildBuilderDelegate(
                        (context, index) => _row(context, _pivot - 1 - index),
                        childCount: _pivot,
                        semanticIndexCallback: (_, index) =>
                            _pivot - 1 - index)),
                SliverList(
                    key: _center,
                    delegate: SliverChildBuilderDelegate(
                        (context, index) => _row(context, _pivot + index),
                        childCount: widget.itemCount - _pivot,
                        semanticIndexOffset: _pivot)),
              ]));

  @override
  void dispose() {
    _generation++;
    _owned?.dispose();
    super.dispose();
  }
}
