import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/library/smart_condition.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

class SmartConditionEditor extends StatelessWidget {
  const SmartConditionEditor(
      {super.key,
      required this.value,
      required this.onChanged,
      this.depth = 0});
  final SmartCondition value;
  final ValueChanged<SmartCondition> onChanged;
  final int depth;
  static const labels = ['评分至少', '个人标签包含', '首次入库不早于', '首次入库不晚于', '属于普通歌单'];
  @override
  Widget build(BuildContext context) {
    void change(int i, SmartCondition? next) {
      final children = [...value.children];
      if (next == null) {
        children.removeAt(i);
      } else {
        children[i] = next;
      }
      onChanged(SmartCondition.group(children, any: value.any));
    }

    final scheme = Theme.of(context).colorScheme;
    InputDecoration input({String? hint}) => InputDecoration(hintText: hint);
    return Card.outlined(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: .65))),
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    AppSegmentedControl<bool>(
                        value: value.any,
                        options: [
                          AppSegmentOption(
                              value: false,
                              label: ui('全部满足'),
                              icon: Icons.done_all),
                          AppSegmentOption(
                              value: true, label: ui('任一满足'), icon: Icons.done),
                        ],
                        onChanged: (any) => onChanged(
                            SmartCondition.group(value.children, any: any))),
                    OutlinedButton.icon(
                        style: appToolbarControlStyle(context),
                        onPressed: value.leaves >= 32
                            ? null
                            : () => onChanged(SmartCondition.group([
                                  ...value.children,
                                  const SmartCondition.term(
                                      SmartField.ratingAtLeast, '4')
                                ], any: value.any)),
                        icon: const Icon(Icons.add),
                        label: Text(ui('条件'))),
                    if (depth == 0)
                      OutlinedButton.icon(
                          style: appToolbarControlStyle(context),
                          icon: const Icon(Icons.create_new_folder_outlined),
                          onPressed: value.children.length >= 32
                              ? null
                              : () => onChanged(SmartCondition.group([
                                    ...value.children,
                                    const SmartCondition.group([])
                                  ], any: value.any)),
                          label: Text(ui('条件组'))),
                  ]),
                  for (var i = 0; i < value.children.length; i++)
                    Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Column(children: [
                          Row(children: [
                            Expanded(
                                child: value.children[i].isGroup
                                    ? Text(ui('条件组'))
                                    : DropdownButtonFormField<SmartField>(
                                        borderRadius: AppShape.controlRadius,
                                        elevation: 3,
                                        dropdownColor: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerLow,
                                        decoration: input(),
                                        itemHeight: null,
                                        isExpanded: true,
                                        initialValue: value.children[i].field,
                                        items: [
                                          for (final f in SmartField.values)
                                            DropdownMenuItem(
                                                value: f,
                                                child:
                                                    Text(ui(labels[f.index])))
                                        ],
                                        onChanged: (f) => change(
                                            i,
                                            SmartCondition.term(
                                                f,
                                                f == SmartField.ratingAtLeast
                                                    ? '4'
                                                    : f ==
                                                                SmartField
                                                                    .addedAfter ||
                                                            f ==
                                                                SmartField
                                                                    .addedBefore
                                                        ? DateTime.now()
                                                            .toIso8601String()
                                                            .substring(0, 10)
                                                        : '',
                                                exclude: value
                                                    .children[i].exclude)))),
                            IconButton(
                                tooltip: ui('移除'),
                                onPressed: () => change(i, null),
                                icon: const Icon(Icons.close))
                          ]),
                          const SizedBox(height: 10),
                          if (value.children[i].isGroup)
                            SmartConditionEditor(
                                value: value.children[i],
                                depth: depth + 1,
                                onChanged: (c) => change(i, c))
                          else
                            Row(children: [
                              Expanded(
                                  child: value.children[i].field ==
                                          SmartField.playlist
                                      ? DropdownButtonFormField<String>(
                                          borderRadius: AppShape.controlRadius,
                                          elevation: 3,
                                          dropdownColor: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerLow,
                                          decoration: input(),
                                          itemHeight: null,
                                          initialValue:
                                              playlistTree.findPlaylist(value.children[i].value) ==
                                                      null
                                                  ? null
                                                  : value.children[i].value,
                                          isExpanded: true,
                                          items: [
                                            for (final p
                                                in playlistTree.allPlaylists)
                                              DropdownMenuItem(
                                                  value: p.id,
                                                  child: Text(p.name,
                                                      overflow: TextOverflow
                                                          .ellipsis))
                                          ],
                                          onChanged: (v) => change(
                                              i,
                                              SmartCondition.term(
                                                  value.children[i].field,
                                                  v ?? '',
                                                  exclude: value
                                                      .children[i].exclude)))
                                      : TextFormField(
                                          key: ValueKey('$i-${value.children[i].field}'),
                                          initialValue: value.children[i].value,
                                          decoration: input(hint: value.children[i].field == SmartField.addedAfter || value.children[i].field == SmartField.addedBefore ? 'yyyy-mm-dd' : null),
                                          onChanged: (v) => change(i, SmartCondition.term(value.children[i].field, v, exclude: value.children[i].exclude)))),
                              const SizedBox(width: 8),
                              Text(ui('排除')),
                              Checkbox(
                                  value: value.children[i].exclude,
                                  onChanged: (v) => change(
                                      i,
                                      SmartCondition.term(
                                          value.children[i].field,
                                          value.children[i].value,
                                          exclude: v!)))
                            ]),
                        ])),
                ])));
  }
}
