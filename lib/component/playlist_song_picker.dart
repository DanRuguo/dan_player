import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

Future<List<Audio>?> showPlaylistSongPicker(
  BuildContext context, {
  required Set<String> existingPaths,
  List<Audio>? library,
  List<Audio> selectedAudios = const [],
  bool replaceSelection = false,
}) =>
    showAppDialog<List<Audio>>(
      context: context,
      builder: (_) => PlaylistSongPicker(
        library: library ?? AudioLibrary.instance.audioCollection,
        existingPaths: existingPaths,
        selectedAudios: selectedAudios,
        replaceSelection: replaceSelection,
      ),
    );

/// A descriptor-only picker: opening it never reads covers or opens playback.
class PlaylistSongPicker extends StatefulWidget {
  const PlaylistSongPicker({
    super.key,
    required this.library,
    required this.existingPaths,
    this.selectedAudios = const [],
    this.replaceSelection = false,
  });

  final List<Audio> library;
  final Set<String> existingPaths;
  final List<Audio> selectedAudios;
  final bool replaceSelection;

  @override
  State<PlaylistSongPicker> createState() => _PlaylistSongPickerState();
}

class _PlaylistSongPickerState extends State<PlaylistSongPicker> {
  late final Set<String> _selected =
      widget.selectedAudios.map((audio) => audio.path).toSet();
  // Start with the previous selection so a missing library entry is visible,
  // retained by default, and cannot disappear merely by opening this editor.
  late final List<Audio> _library = {
    for (final audio in widget.selectedAudios) audio.path: audio,
    for (final audio in widget.library) audio.path: audio,
  }.values.toList(growable: false);
  late final Set<String> _knownPaths =
      widget.library.map((audio) => audio.path).toSet();
  String _query = '';

  List<Audio> get _matches => _library.where((audio) {
        return _query.isEmpty ||
            '${audio.displayTitle}\n${audio.artist}\n${audio.album}'
                .toLowerCase()
                .contains(_query);
      }).toList(growable: false);

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final matches = _matches;
    return Dialog(
      child: SizedBox(
        width: 588,
        height: (MediaQuery.sizeOf(context).height * .7).clamp(240, 700),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // One lazy viewport lets even the title and search controls move
              // out of the way in a short window; only the actions stay fixed.
              Expanded(
                  child: CustomScrollView(
                key: const ValueKey('playlist-song-picker-scroll'),
                slivers: [
                  SliverToBoxAdapter(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppDialogTitle(
                          widget.replaceSelection
                              ? ui("更改所选歌曲")
                              : ui("从总乐库添加歌曲"),
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 16),
                      Focus(
                        onFocusChange: HotkeysHelper.onFocusChanges,
                        child: TextField(
                          key: const ValueKey('playlist-song-search'),
                          autofocus: true,
                          onChanged: (query) => setState(
                              () => _query = query.trim().toLowerCase()),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: ui("搜索标题、歌手或专辑"),
                            border: AppShape.inputBorder,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: matches.isEmpty
                              ? null
                              : () => setState(() {
                                    _selected.addAll(matches
                                        .where((audio) =>
                                            widget.replaceSelection ||
                                            !widget.existingPaths
                                                .contains(audio.path))
                                        .map((audio) => audio.path));
                                  }),
                          child: Text(ui("选择当前搜索结果")),
                        ),
                      ),
                      if (widget.replaceSelection)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(ui("仅编辑本层歌曲；子歌单及仍选歌曲的混排位置会保留。")),
                        ),
                    ],
                  )),
                  if (matches.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(_library.isEmpty
                            ? ui("总乐库为空；先添加本地音乐或收藏联网搜索结果。")
                            : ui("没有匹配歌曲")),
                      ),
                    )
                  else
                    SliverList.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final audio = matches[index];
                        final exists = !widget.replaceSelection &&
                            widget.existingPaths.contains(audio.path);
                        return CheckboxListTile(
                          key: ValueKey('playlist-pick-${audio.path}'),
                          value: exists || _selected.contains(audio.path),
                          secondary: Icon(audio.isOnline
                              ? Icons.cloud_outlined
                              : Icons.music_note_outlined),
                          title: Text(audio.displayTitle,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            exists
                                ? ui("已在当前歌单中")
                                : !_knownPaths.contains(audio.path)
                                    ? ui("总乐库暂未收录，保留歌曲引用")
                                    : '${audio.artist} · ${audio.album}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onChanged: exists
                              ? null
                              : (checked) => setState(() {
                                    checked == true
                                        ? _selected.add(audio.path)
                                        : _selected.remove(audio.path);
                                  }),
                        );
                      },
                    ),
                ],
              )),
              const SizedBox(height: 12),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                overflowAlignment: OverflowBarAlignment.end,
                spacing: 8,
                overflowSpacing: 4,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(ui("取消")),
                  ),
                  FilledButton(
                    onPressed: _selected.isEmpty && !widget.replaceSelection
                        ? null
                        : () => Navigator.of(context).pop(_library
                            .where((audio) => _selected.contains(audio.path))
                            .toList(growable: false)),
                    child: Text(widget.replaceSelection
                        ? ui("保存选择（{0} 首）", [_selected.length])
                        : ui("添加 {0} 首", [_selected.length])),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
