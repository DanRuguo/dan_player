import 'package:dan_player/component/app_dialog_content.dart';
import 'dart:async';

import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_content_scrollbar.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/playlist_name_dialog.dart';
import 'package:dan_player/component/playlist_ui_actions.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
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
      // Keep normal barrier/Escape cancellation while idle. The dialog's
      // PopScope vetoes those route pops only during the asynchronous save.
      barrierDismissible: true,
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
  static const _slowSaveDismissDelay = Duration(seconds: 12);

  PlaylistDestination? _selected;
  String? _createError;
  bool _creating = false;
  bool _slowSaveCanDismiss = false;
  bool _closing = false;
  Timer? _slowSaveTimer;
  bool get _readBlocked =>
      identical(widget.tree.roots, PLAYLISTS) && playlistsReadBlocked;

  Future<void> _create() async {
    if (_readBlocked || _creating || _closing) return;
    final parent = _selected?.playlist;
    final name = await showPlaylistNameDialog(
      context,
      title: parent == null ? ui("新建歌单") : ui("在“{0}”下新建子歌单", [parent.name]),
    );
    if (name == null || !mounted || _closing) return;
    setState(() {
      _creating = true;
      _slowSaveCanDismiss = false;
      _createError = null;
    });
    _slowSaveTimer?.cancel();
    _slowSaveTimer = Timer(_slowSaveDismissDelay, () {
      if (!mounted || !_creating || _closing) return;
      setState(() => _slowSaveCanDismiss = true);
    });
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
      _slowSaveTimer?.cancel();
      if (mounted) {
        setState(() {
          _creating = false;
          _slowSaveCanDismiss = false;
        });
      }
    }
  }

  void _confirm() {
    final selection = _selected;
    if (_closing ||
        _creating ||
        selection == null ||
        _readBlocked ||
        widget.disabledReason?.call(selection.playlist) != null) {
      return;
    }
    _closeWithResult(selection);
  }

  void _dismiss() {
    if (_closing || (_creating && !_slowSaveCanDismiss)) return;
    _closeWithResult(null);
  }

  void _closeWithResult(PlaylistDestination? result) {
    if (_closing) return;
    setState(() => _closing = true);
    // PopScope owns every exit path, including barrier and Escape. Rebuild it
    // into the one-shot allowed state before issuing the actual route pop.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  @override
  void dispose() {
    _slowSaveTimer?.cancel();
    super.dispose();
  }

  Widget _destinationRow(Playlist? playlist) {
    final scheme = Theme.of(context).colorScheme;
    final reason = widget.disabledReason?.call(playlist);
    final selected =
        _selected != null && _selected!.playlist?.id == playlist?.id;
    final path = playlist?.pathFromRoot.map((item) => item.name).join(' / ');
    final name = playlist?.name ?? ui("全部歌单（顶层）");
    final depth = playlist == null ? 0 : playlist.pathFromRoot.length - 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Tooltip(
        message: reason ?? path ?? name,
        child: Semantics(
          selected: selected,
          child: Material(
            color: selected ? scheme.secondaryContainer : Colors.transparent,
            shape: AppShape.control,
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              key: ValueKey('playlist-destination-${playlist?.id ?? 'root'}'),
              enabled:
                  reason == null && !_creating && !_closing && !_readBlocked,
              selected: selected,
              selectedColor: scheme.onSecondaryContainer,
              contentPadding: EdgeInsetsDirectional.only(
                start: 12.0 + depth.clamp(0, 5) * 18.0,
                end: 12.0,
              ),
              leading: Icon(
                playlist == null
                    ? Symbols.home
                    : selected
                        ? Symbols.folder_open
                        : Symbols.folder,
              ),
              title: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: selected
                    ? const TextStyle(fontWeight: FontWeight.w600)
                    : null,
              ),
              subtitle: reason != null || depth > 0
                  ? Text(
                      reason ?? path!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: reason == null
                          ? null
                          : TextStyle(color: scheme.error),
                    )
                  : null,
              trailing: Icon(
                selected ? Symbols.check_circle : Symbols.chevron_right,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              onTap: reason != null || _creating || _closing || _readBlocked
                  ? null
                  : () =>
                      setState(() => _selected = PlaylistDestination(playlist)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _destinationList(List<Playlist> playlists, ColorScheme scheme) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: AppShape.surfaceRadius,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: playlists.isEmpty && !widget.allowRoot
            ? _EmptyPlaylistDestination(
                onCreate: widget.allowCreate &&
                        !_creating &&
                        !_closing &&
                        !_readBlocked
                    ? _create
                    : null,
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
                child: AppContentScrollbar(
                  builder: (context, controller) => ListView.builder(
                    shrinkWrap: true,
                    key: const ValueKey('playlist-destination-list'),
                    controller: controller,
                    padding: const EdgeInsetsDirectional.only(end: 4),
                    itemCount: playlists.length + (widget.allowRoot ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (widget.allowRoot && index == 0) {
                        return _destinationRow(null);
                      }
                      final playlistIndex = index - (widget.allowRoot ? 1 : 0);
                      return _destinationRow(playlists[playlistIndex]);
                    },
                  ),
                ),
              ),
      );

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final playlists = widget.tree.allPlaylists;
    final selectedPlaylist = _selected?.playlist;
    final selectionPath = selectedPlaylist == null
        ? (_selected == null ? null : ui("全部歌单（顶层）"))
        : selectedPlaylist.pathFromRoot.map((item) => item.name).join(' / ');
    final dialogHeight =
        (MediaQuery.sizeOf(context).height - 64).clamp(360, 680).toDouble();
    return PopScope<PlaylistDestination>(
      canPop: _closing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _dismiss();
      },
      child: Dialog(
        child: AppDialogContent(
          width: 560,
          maxHeight: dialogHeight,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final textScale =
                    MediaQuery.textScalerOf(context).scale(14) / 14;
                final compact = constraints.maxHeight < 480 || textScale > 1.7;
                final destinationList = _destinationList(playlists, scheme);
                final column = Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppDialogTitle(
                      widget.title,
                      style: theme.textTheme.titleLarge,
                      leading:
                          Icon(Symbols.playlist_add, color: scheme.primary),
                      trailing: IconButton(
                        key: const ValueKey('playlist-destination-close'),
                        tooltip: ui("取消"),
                        onPressed:
                            _closing || (_creating && !_slowSaveCanDismiss)
                                ? null
                                : _dismiss,
                        icon: const Icon(Symbols.close),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      key: const ValueKey(
                          'playlist-destination-selection-summary'),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: AppShape.controlRadius,
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selectionPath == null
                                ? Symbols.touch_app
                                : Symbols.drive_file_move,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selectionPath == null
                                      ? ui("请选择一个目标歌单")
                                      : ui("已选择目标歌单"),
                                  style: theme.textTheme.labelLarge,
                                ),
                                if (selectionPath != null)
                                  Text(
                                    selectionPath,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              ui("{0} 个歌单", [playlists.length]),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_readBlocked)
                      _DestinationMessage(
                        message: ui("歌单数据读取失败，已保护原文件。请到歌单页面修复后重新读取。"),
                        error: true,
                      ),
                    if (_createError != null)
                      _DestinationMessage(message: _createError!, error: true),
                    if (_slowSaveCanDismiss)
                      _DestinationMessage(
                        message: ui("保存时间较长，操作仍在后台继续。你可以取消并稍后查看结果。"),
                      ),
                    const SizedBox(height: 10),
                    if (compact)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                            maxHeight:
                                (constraints.maxHeight * .62).clamp(0, 340)),
                        child: destinationList,
                      )
                    else
                      Flexible(child: destinationList),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.only(top: 12),
                      decoration: BoxDecoration(
                        border: Border(
                            top: BorderSide(color: scheme.outlineVariant)),
                      ),
                      child: OverflowBar(
                        alignment: MainAxisAlignment.end,
                        overflowAlignment: OverflowBarAlignment.end,
                        spacing: 8,
                        overflowSpacing: 8,
                        children: [
                          if (widget.allowCreate)
                            OutlinedButton.icon(
                              key:
                                  const ValueKey('playlist-destination-create'),
                              onPressed: _creating || _closing || _readBlocked
                                  ? null
                                  : _create,
                              icon: _creating
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Symbols.create_new_folder),
                              label: Text(_selected?.playlist == null
                                  ? ui("新建歌单")
                                  : ui("新建子歌单")),
                            ),
                          TextButton.icon(
                            onPressed:
                                _closing || (_creating && !_slowSaveCanDismiss)
                                    ? null
                                    : _dismiss,
                            icon: const Icon(Symbols.close),
                            label: Text(ui("取消")),
                          ),
                          FilledButton.icon(
                            key: const ValueKey('playlist-destination-confirm'),
                            onPressed: _selected == null ||
                                    _creating ||
                                    _closing ||
                                    _readBlocked ||
                                    widget.disabledReason
                                            ?.call(_selected?.playlist) !=
                                        null
                                ? null
                                : _confirm,
                            icon: const Icon(Symbols.check),
                            label: Text(widget.confirmLabel),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                if (!compact) return column;
                return SingleChildScrollView(
                  key: const ValueKey('playlist-destination-compact-scroll'),
                  child: column,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DestinationMessage extends StatelessWidget {
  const _DestinationMessage({required this.message, this.error = false});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = error ? scheme.errorContainer : scheme.surfaceContainer;
    final foreground = error ? scheme.onErrorContainer : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppShape.controlRadius,
        ),
        child: Row(
          children: [
            Icon(error ? Symbols.error : Symbols.info, color: foreground),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: TextStyle(color: foreground))),
          ],
        ),
      ),
    );
  }
}

class _EmptyPlaylistDestination extends StatelessWidget {
  const _EmptyPlaylistDestination({this.onCreate});

  final Future<void> Function()? onCreate;

  @override
  Widget build(BuildContext context) => Center(
        heightFactor: 1,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Symbols.queue_music,
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 10),
              Text(ui("还没有歌单，请先新建一个。"), textAlign: TextAlign.center),
              if (onCreate != null) ...[
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: onCreate,
                  icon: const Icon(Symbols.create_new_folder),
                  label: Text(ui("新建歌单")),
                ),
              ],
            ],
          ),
        ),
      );
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
    if (added == 0) {
      showAppNotice(
        ui("所选歌曲已在“{0}”中", [playlist.name]),
        context: context,
        kind: AppNoticeKind.success,
      );
      return;
    }
    mutated = true;
    await savePlaylistUiChanges(persist: persist);
    if (!context.mounted) return;
    showAppNotice(
      ui("已将 {0} 首歌曲加入“{1}”", [added, playlist.name]),
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
