import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../play_service/queue_edits.dart';
import '../play_service/queue_selection.dart';
import 'app_shape.dart';
import 'app_toolbar_style.dart';

/// Real occurrence selection and batch edits, using only four local sample IDs.
/// No PlaybackService, audio files, persistent queue or background clock.
class PlayerGuideQueueToolsDemo extends StatefulWidget {
  const PlayerGuideQueueToolsDemo({super.key});
  @override
  State<PlayerGuideQueueToolsDemo> createState() =>
      _PlayerGuideQueueToolsDemoState();
}

class _PlayerGuideQueueToolsDemoState extends State<PlayerGuideQueueToolsDemo> {
  final _selection = QueueSelection()..enter();
  List<int> _items = [0, 1, 2, 3];
  int _current = 1;
  (List<int>, int)? _undo;
  static const _names = ['晨光', '午后', '晨光', '夜色'];

  void _edit(QueueBatchAction action) {
    final edit = QueueEdit.batch(
        _items,
        _current,
        [
          for (var index = 0; index < _items.length; index++)
            if (_selection.contains(_items[index])) index,
        ],
        action);
    if (edit == null) return;
    setState(() {
      _undo = (List.of(_items), _current);
      _items = edit.items;
      _current = edit.currentIndex;
      _selection.retain(_items);
    });
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final canEdit = _selection.selected.any((id) => id != _items[_current]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(ui('勾选同名的不同项，试试移动或移除，再撤销。示例中的当前曲目会保留。')),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final action in QueueBatchAction.values)
          OutlinedButton(
              key: ValueKey('guide-queue-${action.name}'),
              style: appToolbarControlStyle(context),
              onPressed: canEdit ? () => _edit(action) : null,
              child: AppToolbarLabel(
                  label: ui(switch (action) {
                    QueueBatchAction.moveNext => '移到下一首',
                    QueueBatchAction.moveLast => '移到队尾',
                    QueueBatchAction.remove => '移除所选',
                  }),
                  icon: switch (action) {
                    QueueBatchAction.moveNext => Icons.playlist_play,
                    QueueBatchAction.moveLast => Icons.vertical_align_bottom,
                    QueueBatchAction.remove => Icons.remove_circle_outline,
                  })),
        OutlinedButton.icon(
            key: const ValueKey('guide-queue-undo'),
            style: appToolbarControlStyle(context),
            onPressed: _undo == null
                ? null
                : () => setState(() {
                      _items = _undo!.$1;
                      _current = _undo!.$2;
                      _undo = null;
                      _selection.retain(_items);
                    }),
            icon: const Icon(Icons.undo, size: 20),
            label: Text(ui('撤销'))),
        TextButton.icon(
            key: const ValueKey('guide-queue-reset'),
            style: appToolbarControlStyle(context),
            onPressed: () => setState(() {
                  _items = [0, 1, 2, 3];
                  _current = 1;
                  _undo = null;
                  _selection.clear();
                }),
            icon: const Icon(Icons.restart_alt, size: 20),
            label: Text(ui('重置'))),
      ]),
      const SizedBox(height: 12),
      for (var index = 0; index < _items.length; index++)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Semantics(
              key: ValueKey('guide-queue-row-${_items[index]}'),
              label: '${ui('示例第 {0} 项：{1}', [
                    _items[index] + 1,
                    ui(_names[_items[index]])
                  ])}'
                  '${index == _current ? ' · ${ui('当前播放')}' : ''}',
              checked: _selection.contains(_items[index]),
              onTap: () =>
                  setState(() => _selection.toggle(_items[index], _items)),
              child: ExcludeSemantics(
                  child: Material(
                color: _selection.contains(_items[index])
                    ? scheme.secondaryContainer.withValues(alpha: .78)
                    : scheme.surfaceContainerLow,
                shape: AppShape.control.copyWith(
                    side: _selection.contains(_items[index])
                        ? BorderSide(
                            color: scheme.primary.withValues(alpha: .22))
                        : BorderSide.none),
                child: InkWell(
                  borderRadius: AppShape.controlRadius,
                  onTap: () => setState(() => _selection.toggle(
                      _items[index], _items,
                      extend: HardwareKeyboard.instance.isShiftPressed)),
                  child: Padding(
                      padding:
                          const EdgeInsets.only(right: 12, top: 8, bottom: 8),
                      child: Row(children: [
                        SizedBox(
                            width: 48,
                            height: 48,
                            child: ExcludeFocus(
                                child: IgnorePointer(
                                    child: Checkbox(
                                        value:
                                            _selection.contains(_items[index]),
                                        onChanged: (_) {},
                                        visualDensity: VisualDensity.standard,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize
                                                .shrinkWrap)))),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(ui(_names[_items[index]])),
                              Text(ui('示例第 {0} 项', [_items[index] + 1]),
                                  style: Theme.of(context).textTheme.bodySmall),
                              if (index == _current)
                                Text(ui('当前播放'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: scheme.primary)),
                            ])),
                      ])),
                ),
              )),
            )),
    ]);
  }
}
