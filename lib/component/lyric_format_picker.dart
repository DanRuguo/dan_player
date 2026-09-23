import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/lyric/lyric_edit_codec.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

Future<LyricEditFormat?> chooseLyricEditFormat(BuildContext context,
        {LyricEditFormat? current}) =>
    showAppDialog<LyricEditFormat>(
        context: context,
        builder: (context) => AlertDialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              title: AppDialogTitle(ui('选择歌词编辑格式'),
                  leading: const Icon(Symbols.lyrics)),
              content: SizedBox(
                  width: 620,
                  child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * .62),
                      child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: LyricEditFormat.values.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final format = LyricEditFormat.values[index];
                            final scheme = Theme.of(context).colorScheme;
                            return Material(
                                color: current == format
                                    ? scheme.secondaryContainer
                                    : scheme.surfaceContainerLow,
                                shape: AppShape.control,
                                clipBehavior: Clip.antiAlias,
                                child: ListTile(
                                    key:
                                        ValueKey('lyric-format-${format.name}'),
                                    leading: Icon(
                                        format.timedWords
                                            ? Symbols.av_timer
                                            : Symbols.notes,
                                        color: scheme.primary),
                                    title: Text(ui(format.label)),
                                    subtitle: Text(ui(switch (format) {
                                      LyricEditFormat.plain =>
                                        '不含时间轴，适合只编写歌词文字。',
                                      LyricEditFormat.lrc => '逐句时间轴；翻译和注音分别编辑。',
                                      LyricEditFormat.lossless =>
                                        '保留全部逐字时间、翻译和注音，适合无损保存与交换。',
                                      _ => '逐字时间轴；支持原文、翻译和注音。',
                                    })),
                                    trailing: Icon(
                                        current == format
                                            ? Symbols.check_circle
                                            : Symbols.chevron_right,
                                        color: scheme.primary),
                                    onTap: () =>
                                        Navigator.pop(context, format)));
                          }))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(ui('取消')))
              ],
            ));
