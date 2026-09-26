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
      this.depth = 0,
      this.leafBudget = 32});
  final SmartCondition value;
  final ValueChanged<SmartCondition> onChanged;
  final int depth;
  final int leafBudget;
  static const labels = {
    SmartField.ratingAtLeast: '评分至少',
    SmartField.personalTag: '个人标签包含',
    SmartField.addedAfter: '首次入库不早于',
    SmartField.addedBefore: '首次入库不晚于',
    SmartField.playlist: '属于普通歌单',
    SmartField.titleContains: '标题包含',
    SmartField.artistContains: '歌手包含',
    SmartField.albumContains: '专辑包含',
    SmartField.folderWithin: '位于文件夹（含子目录）',
    SmartField.formatIs: '文件格式为',
    SmartField.durationAtLeast: '时长至少（秒）',
    SmartField.durationAtMost: '时长至多（秒）',
    SmartField.ratingAtMost: '评分至多',
    SmartField.unrated: '尚未评分',
    SmartField.playCountAtLeast: '播放次数至少',
    SmartField.playCountAtMost: '播放次数至多',
    SmartField.bitrateAtLeast: '码率至少（kbps）',
    SmartField.sampleRateAtLeast: '采样率至少（Hz）',
    SmartField.composerContains: '作曲家包含',
    SmartField.albumArtistContains: '专辑艺术家包含',
    SmartField.languageIs: '语言标签为',
    SmartField.fileNameContains: '文件名包含',
    SmartField.fileSizeAtLeast: '文件大小至少（字节）',
    SmartField.fileSizeAtMost: '文件大小至多（字节）',
    SmartField.bitrateAtMost: '码率至多（kbps）',
    SmartField.sampleRateAtMost: '采样率至多（Hz）',
    SmartField.trackAtLeast: '音轨号至少',
    SmartField.trackAtMost: '音轨号至多',
    SmartField.missingComposer: '缺少作曲家标签',
    SmartField.missingAlbumArtist: '缺少专辑艺术家标签',
    SmartField.missingLanguage: '缺少语言标签',
    SmartField.missingAlbum: '缺少专辑标签',
    SmartField.missingArtist: '缺少艺术家标签',
    SmartField.untagged: '没有个人标签',
    SmartField.cueTrack: '是 CUE 分轨',
    SmartField.metadataPending: '元数据等待补读',
  };
  static String initialValue(SmartField? field) =>
      smartBooleanFields.contains(field)
          ? 'true'
          : switch (field) {
              SmartField.ratingAtLeast || SmartField.ratingAtMost => '4',
              SmartField.unrated => 'true',
              SmartField.durationAtLeast => '60',
              SmartField.durationAtMost => '300',
              SmartField.playCountAtLeast => '1',
              SmartField.playCountAtMost => '0',
              SmartField.bitrateAtLeast => '320',
              SmartField.sampleRateAtLeast => '48000',
              SmartField.sampleRateAtMost => '48000',
              SmartField.bitrateAtMost => '320',
              SmartField.trackAtLeast => '1',
              SmartField.trackAtMost => '10',
              SmartField.fileSizeAtLeast => '10485760',
              SmartField.fileSizeAtMost => '104857600',
              SmartField.addedAfter ||
              SmartField.addedBefore =>
                DateTime.now().toIso8601String().substring(0, 10),
              _ => '',
            };
  static String? hint(SmartField? field) => switch (field) {
        SmartField.ratingAtLeast || SmartField.ratingAtMost => '1–5',
        SmartField.durationAtLeast || SmartField.durationAtMost => '0–86400',
        SmartField.playCountAtLeast ||
        SmartField.playCountAtMost =>
          '0–1000000000',
        SmartField.bitrateAtLeast || SmartField.bitrateAtMost => '0–100000',
        SmartField.sampleRateAtLeast ||
        SmartField.sampleRateAtMost =>
          '0–10000000',
        SmartField.trackAtLeast || SmartField.trackAtMost => '0–100000',
        SmartField.fileSizeAtLeast ||
        SmartField.fileSizeAtMost =>
          '0–1000000000000000',
        SmartField.folderWithin => '例如 C:\\Music',
        SmartField.formatIs => '例如 flac 或 mp3（单一格式）',
        SmartField.addedAfter || SmartField.addedBefore => 'yyyy-mm-dd',
        _ => null,
      };
  static bool numeric(SmartField? field) => {
        SmartField.ratingAtLeast,
        SmartField.ratingAtMost,
        SmartField.durationAtLeast,
        SmartField.durationAtMost,
        SmartField.playCountAtLeast,
        SmartField.playCountAtMost,
        SmartField.bitrateAtLeast,
        SmartField.sampleRateAtLeast,
        SmartField.bitrateAtMost,
        SmartField.sampleRateAtMost,
        SmartField.trackAtLeast,
        SmartField.trackAtMost,
        SmartField.fileSizeAtLeast,
        SmartField.fileSizeAtMost,
      }.contains(field);
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
    InputDecoration input({String? hint}) => InputDecoration(
        hintText: hint == null ? null : ui(hint), border: AppShape.inputBorder);
    Widget termValue(int i) {
      final term = value.children[i];
      if (term.field == SmartField.playlist) {
        return DropdownButtonFormField<String>(
            borderRadius: AppShape.controlRadius,
            elevation: 3,
            dropdownColor: scheme.surfaceContainerLow,
            decoration: input(),
            itemHeight: null,
            initialValue: playlistTree.findPlaylist(term.value) == null
                ? null
                : term.value,
            isExpanded: true,
            items: [
              for (final playlist in playlistTree.allPlaylists)
                DropdownMenuItem(
                    value: playlist.id,
                    child: Text(playlist.name, overflow: TextOverflow.ellipsis))
            ],
            onChanged: (v) => change(
                i,
                SmartCondition.term(term.field, v ?? '',
                    exclude: term.exclude)));
      }
      return TextFormField(
          key: ValueKey('$i-${term.field}'),
          initialValue: term.value,
          maxLength: 160,
          keyboardType:
              numeric(term.field) ? TextInputType.number : TextInputType.text,
          decoration: input(hint: hint(term.field)).copyWith(counterText: ''),
          onChanged: (v) => change(
              i, SmartCondition.term(term.field, v, exclude: term.exclude)));
    }

    Widget exclusion(int i) => Row(mainAxisSize: MainAxisSize.min, children: [
          Text(ui('排除')),
          Checkbox(
              value: value.children[i].exclude,
              onChanged: (v) => change(
                  i,
                  SmartCondition.term(
                      value.children[i].field, value.children[i].value,
                      exclude: v!))),
        ]);
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
                        onPressed: value.leaves >= leafBudget ||
                                value.children.length >= 32
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
                                    : LayoutBuilder(
                                        builder: (context, constraints) =>
                                            DropdownButtonFormField<SmartField>(
                                                borderRadius:
                                                    AppShape.controlRadius,
                                                elevation: 3,
                                                dropdownColor: Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerLow,
                                                decoration: input(),
                                                itemHeight: null,
                                                isExpanded: true,
                                                isDense: false,
                                                initialValue:
                                                    value.children[i].field,
                                                selectedItemBuilder: (_) => [
                                                      for (final f
                                                          in SmartField.values)
                                                        f ==
                                                                value
                                                                    .children[i]
                                                                    .field
                                                            ? SizedBox(
                                                                width: (constraints
                                                                            .maxWidth -
                                                                        48)
                                                                    .clamp(
                                                                        1,
                                                                        double
                                                                            .infinity),
                                                                child: Text(
                                                                    ui(labels[
                                                                        f]!),
                                                                    maxLines: 6,
                                                                    softWrap:
                                                                        true))
                                                            : const SizedBox
                                                                .shrink(),
                                                    ],
                                                items: [
                                                  for (final f
                                                      in SmartField.values)
                                                    DropdownMenuItem(
                                                        value: f,
                                                        child: SizedBox(
                                                            width: (constraints
                                                                        .maxWidth -
                                                                    48)
                                                                .clamp(
                                                                    1,
                                                                    double
                                                                        .infinity),
                                                            child: Text(
                                                                ui(labels[f]!),
                                                                maxLines: 6,
                                                                softWrap:
                                                                    true)))
                                                ],
                                                onChanged: (f) => change(
                                                    i,
                                                    SmartCondition.term(
                                                        f, initialValue(f),
                                                        exclude: value
                                                            .children[i]
                                                            .exclude))))),
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
                                leafBudget: leafBudget -
                                    value.leaves +
                                    value.children[i].leaves,
                                onChanged: (c) => change(i, c))
                          else if (smartBooleanFields
                              .contains(value.children[i].field))
                            Align(
                                alignment: Alignment.centerRight,
                                child: exclusion(i))
                          else
                            LayoutBuilder(
                                builder: (context, constraints) =>
                                    constraints.maxWidth < 320
                                        ? Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                                termValue(i),
                                                Align(
                                                    alignment:
                                                        Alignment.centerRight,
                                                    child: exclusion(i))
                                              ])
                                        : Row(children: [
                                            Expanded(child: termValue(i)),
                                            const SizedBox(width: 8),
                                            exclusion(i)
                                          ])),
                        ])),
                ])));
  }
}
