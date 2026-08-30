import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/playlist_name_dialog.dart';
import 'package:dan_player/component/playlist_ui_actions.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

/// Distinguishes selecting the root (playlist == null) from cancelling a dialog.
class PlaylistDestination {
  const PlaylistDestination(this.playlist);
  final Playlist? playlist;
}

Future<PlaylistDestination?> showPlaylistDestinationDialog(
  BuildContext context, {
  PlaylistTree? tree,
  String title = '选择目标歌单',
  String confirmLabel = '移动',
  bool allowRoot = false,
  String? Function(Playlist?)? disabledReason,
  bool allowCreate = false,
  Future<void> Function()? persist,
}) =>
    showAppDialog<PlaylistDestination>(
      context: context,
      builder: (_) => PlaylistDestinationDialog(
        tree: tree ?? playlistTree,
        title: title,
        confirmLabel: confirmLabel,
        allowRoot: allowRoot,
        disabledReason: disabledReason,
        allowCreate: allowCreate,
        persist: persist,
      ),
    );

class PlaylistDestinationDialog extends StatefulWidget {
  const PlaylistDestinationDialog({
    super.key,
    required this.tree,
    required this.title,
    required this.confirmLabel,
    this.allowRoot = false,
    this.disabledReason,
    this.allowCreate = false,
    this.persist,
  });

  final PlaylistTree tree;
  final String title;
  final String confirmLabel;
  final bool allowRoot;
  final String? Function(Playlist?)? disabledReason;
  final bool allowCreate;
  final Future<void> Function()? persist;

  @override
  State<PlaylistDestinationDialog> createState() =>
      _PlaylistDestinationDialogState();
}

class _PlaylistDestinationDialogState extends State<PlaylistDestinationDialog> {
  PlaylistDestination? _selected;
  String? _createError;
  bool _creating = false;
  bool get _readBlocked =>
      identical(widget.tree.roots, PLAYLISTS) && playlistsReadBlocked;

  Future<void> _create() async {
    if (_readBlocked) return;
    final parent = _selected?.playlist;
    final name = await showPlaylistNameDialog(
      context,
      title: parent == null ? ui("新建歌单") : ui("在“{0}”下新建子歌单", [parent.name]),
    );
    if (name == null || !mounted) return;
    setState(() => _creating = true);
    var createdInMemory = false;
    try {
      final created = widget.tree.createPlaylist(name, parent: parent);
      createdInMemory = true;
      setState(() {
        _selected = PlaylistDestination(created);
        _createError = null;
      });
      await savePlaylistUiChanges(persist: widget.persist);
    } catch (error) {
      if (mounted) {
        setState(() => _createError = createdInMemory
            ? ui("新歌单尚未保存：{0}", [error])
            : ui("无法创建歌单：{0}", [error]));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _confirm() {
    final selection = _selected;
    if (selection == null ||
        _readBlocked ||
        widget.disabledReason?.call(selection.playlist) != null) {
      return;
    }
    Navigator.of(context).pop(selection);
  }

  Widget _destinationRow(Playlist? playlist) {
    final reason = widget.disabledReason?.call(playlist);
    final selected =
        _selected != null && _selected!.playlist?.id == playlist?.id;
    final path = playlist?.pathFromRoot.map((item) => item.name).join(' / ');
    final name = playlist?.name ?? ui("全部歌单（顶层）");
    final depth = playlist == null ? 0 : playlist.pathFromRoot.length - 1;
    return Tooltip(
      message: reason ?? path ?? name,
      child: Semantics(
        selected: selected,
        child: ListTile(
          key: ValueKey('playlist-destination-${playlist?.id ?? 'root'}'),
          enabled: reason == null && !_creating && !_readBlocked,
          selected: selected,
          contentPadding: EdgeInsets.only(
            left: 12.0 + depth.clamp(0, 4) * 12.0,
            right: 12.0,
          ),
          leading: Icon(
              playlist == null ? Icons.home_outlined : Icons.folder_outlined),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: reason != null || depth > 1
              ? Text(reason ?? path!,
                  maxLines: 2, overflow: TextOverflow.ellipsis)
              : null,
          trailing: Icon(selected
              ? Icons.radio_button_checked
              : Icons.radio_button_unchecked),
          onTap: reason != null || _creating || _readBlocked
              ? null
              : () => setState(() => _selected = PlaylistDestination(playlist)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return AlertDialog(
      title: AppDialogTitle(widget.title),
      content: SizedBox(
        width: 480,
        height: MediaQuery.sizeOf(context).height.clamp(300, 800) * 0.45,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_readBlocked)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(ui("歌单数据读取失败，已保护原文件。请到歌单页面修复后重新读取。")),
              ),
            if (_createError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _createError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: widget.tree.allPlaylists.isEmpty && !widget.allowRoot
                  ? Center(child: Text(ui("还没有歌单，请先新建一个。")))
                  : ListView(
                      children: [
                        if (widget.allowRoot) _destinationRow(null),
                        for (final playlist in widget.tree.allPlaylists)
                          _destinationRow(playlist),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.allowCreate)
          TextButton.icon(
            onPressed: _creating || _readBlocked ? null : _create,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: Text(_selected?.playlist == null ? ui("新建歌单") : ui("新建子歌单")),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(ui("取消")),
        ),
        FilledButton(
          onPressed:
              _selected == null || _creating || _readBlocked ? null : _confirm,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Shared by local/online song menus and multi-select; only tree descriptors
/// are copied. Remote streams are not downloaded and source files are untouched.
Future<void> showAddAudiosToPlaylistDialog(
  BuildContext context,
  Iterable<Audio> audios, {
  PlaylistTree? tree,
  Future<void> Function()? persist,
}) async {
  final tracks = audios.toList(growable: false);
  if (tracks.isEmpty) return;
  final targetTree = tree ?? playlistTree;
  if (identical(targetTree.roots, PLAYLISTS) && playlistsReadBlocked) {
    showAppNotice(
      ui("歌单数据尚未完整读取，无法添加歌曲；请到歌单页面重新读取。"),
      context: context,
      kind: AppNoticeKind.warning,
    );
    return;
  }
  final destination = await showPlaylistDestinationDialog(
    context,
    tree: targetTree,
    title:
        tracks.length == 1 ? ui("加入歌单") : ui("将 {0} 首歌曲加入歌单", [tracks.length]),
    confirmLabel: ui("添加"),
    allowCreate: true,
    persist: persist,
  );
  final playlist = destination?.playlist;
  if (playlist == null || !context.mounted) return;
  var mutated = false;
  try {
    final added = targetTree.addAudios(playlist, tracks).length;
    mutated = true;
    await savePlaylistUiChanges(persist: persist);
    if (!context.mounted) return;
    showAppNotice(
      added == 0
          ? ui("所选歌曲已在“{0}”中", [playlist.name])
          : ui("已将 {0} 首歌曲加入“{1}”", [added, playlist.name]),
      context: context,
      kind: AppNoticeKind.success,
    );
  } catch (error) {
    if (!context.mounted) return;
    showAppNotice(
      mutated ? ui("更改已保留在当前会话，但保存失败：{0}", [error]) : ui("加入歌单失败：{0}", [error]),
      context: context,
      kind: AppNoticeKind.error,
    );
  }
}
