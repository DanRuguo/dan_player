import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/audio_artwork.dart';
import 'package:dan_player/component/playlist_create_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/library/playlist_cover_snapshot.dart';
import 'package:dan_player/library/cover_image_import.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

Future<String?> showPlaylistCoverPicker(BuildContext context,
        {required Playlist playlist, PlaylistImagePicker? pickImage}) =>
    showAppDialog<String>(
      context: context,
      builder: (_) => PlaylistCoverPicker(
          songs: playlist.flattenAudios(), pickImage: pickImage),
    );

class PlaylistCoverPicker extends StatefulWidget {
  const PlaylistCoverPicker({
    super.key,
    required this.songs,
    this.pickImage,
    this.saveSongCover = savePlaylistSongCover,
    this.saveFileCover = importPlaylistCoverFile,
  });

  final List<Audio> songs;
  final PlaylistImagePicker? pickImage;
  final Future<String> Function(Audio) saveSongCover;
  final Future<String> Function(String) saveFileCover;

  @override
  State<PlaylistCoverPicker> createState() => _PlaylistCoverPickerState();
}

class _PlaylistCoverPickerState extends State<PlaylistCoverPicker> {
  late final _songs = {
    for (final song in widget.songs) song.path: song,
  }.values.toList(growable: false);
  Audio? _selected;
  String _query = '';
  String? _error;
  bool _busy = false;

  Future<void> _choose({bool file = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var result = file
          ? await (widget.pickImage ?? pickPlaylistImage)()
          : await widget.saveSongCover(_selected!);
      if (file && result != null) {
        result = await widget.saveFileCover(result);
      }
      if (mounted && result != null) Navigator.pop(context, result);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is CoverImageException
            ? error.toString()
            : ui('无法读取封面，请重试或选择其他图片。'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final matches = _songs
        .where((song) => '${song.displayTitle}\n${song.artist}\n${song.album}'
            .toLowerCase()
            .contains(_query))
        .toList(growable: false);
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        child: AppDialogContent(
          width: 580,
          maxHeight: MediaQuery.sizeOf(context).height * .8,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                  child: CustomScrollView(shrinkWrap: true, slivers: [
                SliverToBoxAdapter(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      AppDialogTitle(ui('选择歌单封面')),
                      const SizedBox(height: 12),
                      Text(ui('选择歌单中的歌曲封面，或从文件选择图片。所选歌曲封面会独立保存。'),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Text(ui('封面会保存为独立副本，长边最多 1600 像素、体积最多 2 MiB；不修改原图。'),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                          key: const ValueKey('playlist-cover-file'),
                          onPressed: _busy ? null : () => _choose(file: true),
                          icon: const Icon(Icons.folder_open),
                          label: Text(ui('从文件选择图片'))),
                      const SizedBox(height: 12),
                      if (_songs.isNotEmpty)
                        TextField(
                            key: const ValueKey('playlist-cover-search'),
                            enabled: !_busy,
                            decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search),
                                hintText: ui('搜索歌曲')),
                            onChanged: (value) => setState(
                                () => _query = value.trim().toLowerCase())),
                      const SizedBox(height: 8),
                      if (_error != null)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(_error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error))),
                      if (matches.isEmpty)
                        Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                                ui(_songs.isEmpty
                                    ? '歌单中没有歌曲，可从文件选择图片。'
                                    : '没有匹配的歌曲。'),
                                textAlign: TextAlign.center)),
                    ])),
                SliverList.builder(
                    itemCount: matches.length,
                    itemBuilder: (context, index) {
                      final audio = matches[index];
                      return ListTile(
                        key: ValueKey(('playlist-cover-song', audio.path)),
                        enabled: !_busy,
                        selected: _selected?.path == audio.path,
                        leading: AudioArtwork(
                            audio: audio,
                            size: 48,
                            placeholder:
                                const Icon(Icons.album_outlined, size: 40)),
                        title: Text(audio.displayTitle,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(audio.artist,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Icon(_selected?.path == audio.path
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off),
                        onTap: () => setState(() => _selected = audio),
                      );
                    }),
              ])),
              const SizedBox(height: 16),
              Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                        onPressed: _busy ? null : () => Navigator.pop(context),
                        child: Text(ui('取消'))),
                    FilledButton.icon(
                        key: const ValueKey('playlist-cover-apply'),
                        onPressed: _busy || _selected == null ? null : _choose,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.check),
                        label: Text(ui('使用此封面'))),
                  ]),
            ]),
          ),
        ),
      ),
    );
  }
}
