import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_action_list_tile.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/playlist_ui_actions.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

Future<void> showPlaylistTrash(BuildContext context) => showAppDialog<void>(
    context: context, builder: (_) => const PlaylistTrashDialog());

class PlaylistTrashDialog extends StatefulWidget {
  const PlaylistTrashDialog({super.key});
  @override
  State<PlaylistTrashDialog> createState() => _PlaylistTrashDialogState();
}

class _PlaylistTrashDialogState extends State<PlaylistTrashDialog> {
  String? _error;
  bool _busy = false;
  Future<void> _change(Map<String, dynamic> record, bool restore) async {
    final node = Playlist.fromMap(record['playlist'] as Map);
    final destination = record['parent'] == null
        ? null
        : playlistTree.findPlaylist(record['parent'] as String);
    final approved = await showAppDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
                title: Text(ui(restore ? '恢复歌单' : '永久移除回收记录'),
                    textAlign: TextAlign.center),
                content: Text(restore
                    ? '${node.name}\n${ui("共 {0} 首歌曲", [
                            node.flattenAudios().length
                          ])}\n${destination?.name ?? ui("恢复到根级")}\n${ui("同名歌单保留并更名，不覆盖现有歌单。")}'
                    : ui('仅删除这份歌单恢复记录，不删除音乐文件。')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(ui('取消'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(ui('确认')))
                ]));
    if (approved != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (restore) {
        restorePlaylistTrash(record['id'] as String);
      } else {
        playlistTrash.remove(record);
      }
      await savePlaylistUiChanges();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: AppDialogTitle(ui('歌单回收站'),
              leading: const Icon(Icons.delete_outline)),
          content: AppDialogContent(
              width: 540,
              maxHeight: 460,
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Text(ui('仅恢复播放器内的歌单，不恢复已删除的音乐文件。'),
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                    const SizedBox(height: 12),
                    if (_error != null)
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    if (playlistTrash.isEmpty)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Column(children: [
                            Icon(Icons.delete_outline,
                                size: 32,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(height: 12),
                            Text(ui('回收站为空'), textAlign: TextAlign.center),
                          ]))
                    else
                      for (final r in playlistTrash)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SettingsSurface(
                                padding: EdgeInsets.zero,
                                child: AppActionListTile(
                                    leading: Material(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer,
                                        shape: AppShape.control,
                                        child: Padding(
                                            padding: const EdgeInsets.all(10),
                                            child: Icon(Icons.queue_music,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onPrimaryContainer))),
                                    title: (r['playlist'] as Map)['name']
                                        as String,
                                    subtitle: MaterialLocalizations.of(context)
                                        .formatCompactDate(
                                            DateTime.fromMillisecondsSinceEpoch(
                                                    r['deletedAt'] as int,
                                                    isUtc: true)
                                                .toLocal()),
                                    actions: [
                                      IconButton(
                                          tooltip: ui('恢复'),
                                          onPressed: _busy
                                              ? null
                                              : () => _change(r, true),
                                          icon: const Icon(Icons.restore)),
                                      IconButton(
                                          tooltip: ui('永久移除'),
                                          onPressed: _busy
                                              ? null
                                              : () => _change(r, false),
                                          icon:
                                              const Icon(Icons.delete_outline))
                                    ])))
                  ]))),
          actions: [
            if (playlistsHaveUnsavedChanges)
              TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          try {
                            await savePlaylistUiChanges();
                            if (mounted) setState(() => _error = null);
                          } catch (e) {
                            if (mounted) setState(() => _error = '$e');
                          }
                        },
                  child: Text(ui('重试保存'))),
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: Text(ui('关闭')))
          ]);
}

Future<void> showPlaylistPresentation(
        BuildContext context, Playlist playlist) =>
    showAppDialog<void>(
        context: context,
        builder: (_) => PlaylistPresentationDialog(playlist: playlist));

class PlaylistPresentationDialog extends StatefulWidget {
  const PlaylistPresentationDialog({super.key, required this.playlist});
  final Playlist playlist;
  @override
  State<PlaylistPresentationDialog> createState() =>
      _PlaylistPresentationDialogState();
}

class _PlaylistPresentationDialogState
    extends State<PlaylistPresentationDialog> {
  late final _columns = <String>{
    ...(widget.playlist.presentation['columns'] is List
        ? (widget.playlist.presentation['columns'] as List).whereType<String>()
        : <String>['artist', 'album'])
  };
  late final _widths = <String, double>{
    if (widget.playlist.presentation['widths'] is Map)
      for (final e in (widget.playlist.presentation['widths'] as Map).entries)
        if (e.key is String && e.value is num && (e.value as num).isFinite)
          e.key as String: (e.value as num).toDouble().clamp(80, 320),
  };
  bool _busy = false;
  String? _error;
  Future<void> _save(bool reset) async {
    setState(() => _busy = true);
    try {
      widget.playlist.presentation = reset
          ? {}
          : {
              ...widget.playlist.presentation,
              'columns': _columns.toList(),
              'widths': _widths
            };
      await savePlaylistUiChanges();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: AppDialogTitle(ui('歌单视图'),
          leading: const Icon(Icons.view_column_outlined)),
      content: AppDialogContent(
          width: 500,
          child: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.playlist.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: theme.colorScheme.primary)),
              const SizedBox(height: 8),
              Text(ui('仅影响此歌单。窄窗口自动使用紧凑布局。'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 20),
              Text(ui('显示的列'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final entry in const {
                'artist': ('艺术家', Icons.person_outline),
                'album': ('专辑', Icons.album_outlined),
                'track': ('轨号', Icons.numbers),
                'tags': ('个人标签', Icons.label_outline),
                'rating': ('个人评分', Icons.star_outline),
              }.entries)
                Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SettingsSurface(
                        padding: EdgeInsets.zero,
                        child: Column(children: [
                          CheckboxListTile(
                            key: ValueKey('playlist-column-${entry.key}'),
                            secondary: Icon(entry.value.$2,
                                size: 22, color: theme.colorScheme.primary),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            title: Text(ui(entry.value.$1)),
                            value: _columns.contains(entry.key),
                            onChanged: _busy
                                ? null
                                : (selected) => setState(() {
                                      if (selected == true) {
                                        _columns.add(entry.key);
                                      } else {
                                        _columns.remove(entry.key);
                                      }
                                    }),
                          ),
                          if (_columns.contains(entry.key))
                            Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                child: Column(children: [
                                  Row(children: [
                                    Expanded(
                                        child: Text(ui('列宽'),
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                    color: theme.colorScheme
                                                        .onSurfaceVariant))),
                                    Text(
                                        '${(_widths[entry.key] ?? 160).round()}',
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                                color:
                                                    theme.colorScheme.primary)),
                                  ]),
                                  Slider(
                                      min: 80,
                                      max: 320,
                                      divisions: 12,
                                      label:
                                          '${(_widths[entry.key] ?? 160).round()}',
                                      value: (_widths[entry.key] ?? 160)
                                          .clamp(80, 320),
                                      onChanged: _busy
                                          ? null
                                          : (width) => setState(() =>
                                              _widths[entry.key] = width)),
                                ])),
                        ]))),
              if (_error != null)
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ))),
      actions: [
        TextButton.icon(
            onPressed: _busy ? null : () => _save(true),
            icon: const Icon(Icons.restore, size: 18),
            label: Text(ui('恢复全局设置'))),
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(ui('取消'))),
        FilledButton.icon(
            onPressed: _busy ? null : () => _save(false),
            icon: const Icon(Icons.check, size: 18),
            label: Text(ui('保存'))),
      ],
    );
  }
}
