import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_action_icon.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/audio_artwork.dart';
import 'package:dan_player/component/audio_columns.dart';
import 'package:dan_player/component/audio_delete_action.dart';
import 'package:dan_player/statistics/library_statistics.dart'
    show classifySongComposer;
import 'package:dan_player/component/audio_metadata_dialog.dart';
import 'package:dan_player/component/lyric_editor_dialog.dart';
import 'package:dan_player/component/music_grid.dart';
import 'package:dan_player/component/next_play_animation.dart';
import 'package:dan_player/component/online_source_display.dart';
import 'package:dan_player/component/playlist_destination_dialog.dart';
import 'package:dan_player/component/readable_ellipsis_text.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/component/cover_repair_dialog.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/online/online_library.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:flutter/services.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

/// A playlist can contain the same Audio more than once. Its selection belongs
/// to a relationship ID, not to the shared song object used by library views.
class AudioTileSelection {
  const AudioTileSelection({
    required this.enabled,
    required this.selected,
    required this.onToggle,
    required this.onStart,
  });

  final bool enabled;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onStart;
}

/// 由[playlist]和[audioIndex]确定audio，而不是直接传入audio，
/// 这是为了实现点击列表项播放乐曲时指定该列表为播放列表。
/// 同时，播放乐曲时也是需要index和playlist来定位audio和设置播放列表。
class AudioTile extends StatefulWidget {
  const AudioTile({
    super.key,
    required this.audioIndex,
    required this.playlist,
    this.focus = false,
    this.leading,
    this.action,
    this.multiSelectController,
    this.additionalMenuItems = const [],
    this.selection,
    this.columns = false,
    this.showSourceLabel = false,
  });

  final int audioIndex;
  final List<Audio> playlist;
  final bool focus;
  final Widget? leading;
  final Widget? action;
  final MultiSelectController? multiSelectController;

  /// Relationship actions supplied by a playlist view. Source-specific music
  /// actions remain available for both local and online songs.
  final List<Widget> additionalMenuItems;
  final AudioTileSelection? selection;

  /// Keep the layout on the row when a reorder proxy moves to the root overlay.
  final bool columns;

  /// Makes the provider visible in mixed-source result lists. The default
  /// library views keep their existing compact metadata line.
  final bool showSourceLabel;

  @override
  State<AudioTile> createState() => _AudioTileState();
}

class _AudioTileState extends State<AudioTile> {
  BuildContext? _artworkContext;

  /// Opens the shared song menu at the visible trailing action instead of the
  /// leading edge of the full-width row/card owned by [MenuAnchor].
  ///
  /// Right-click already supplies a pointer-local position. Keyboard/touch
  /// activation of the three-dot button has no pointer position, so a bare
  /// `open()` falls back to the anchor's start edge (the far left on LTR
  /// pages). Converting the action's bottom centre back into the anchor's
  /// coordinate space keeps both entry points on one accessible menu without
  /// duplicating actions or overlays.
  void _toggleMenuFromAction(
    MenuController controller,
    BuildContext anchorContext,
    BuildContext actionContext,
  ) {
    if (controller.isOpen) {
      controller.close();
      return;
    }

    final anchorBox = anchorContext.findRenderObject() as RenderBox?;
    final actionBox = actionContext.findRenderObject() as RenderBox?;
    if (anchorBox == null ||
        actionBox == null ||
        !anchorBox.attached ||
        !actionBox.attached ||
        !anchorBox.hasSize ||
        !actionBox.hasSize) {
      // Defensive fallback for the unlikely frame in which the action has
      // just changed view and its render box is not available yet.
      controller.open();
      return;
    }

    final actionBottomCenter = actionBox.localToGlobal(
      Offset(actionBox.size.width / 2, actionBox.size.height),
    );
    controller.open(position: anchorBox.globalToLocal(actionBottomCenter));
  }

  Widget _artwork(Audio audio, Widget placeholder) => Builder(
        builder: (context) {
          _artworkContext = context;
          return ClipRRect(
            borderRadius: AppShape.smallRadius,
            child: AudioArtwork(
              audio: audio,
              size: 48,
              placeholder: placeholder,
            ),
          );
        },
      );

  Widget _metadataMenuLabel(String label) => ReadableEllipsisText(label);

  Future<void> _toggleOnlineLibrary(Audio audio) async {
    try {
      final library = OnlineLibrary.instance;
      if (library.contains(audio)) {
        await library.remove(audio);
        showTextOnSnackBar("已从总乐库移除");
      } else {
        await library.add(audio);
        showTextOnSnackBar("已加入总乐库");
      }
      if (mounted) setState(() {});
    } catch (error, trace) {
      LOGGER.e("[online library] $error", stackTrace: trace);
      showTextOnSnackBar("更新总乐库失败：{0}", arguments: [error]);
    }
  }

  Future<void> _downloadOnlineAudio(Audio audio) async {
    final service = OnlineMusicService.instance;
    if (!service.canDownload(audio)) {
      showTextOnSnackBar(
          service.downloadUnavailableReason(audio) ?? "当前来源不支持下载");
      return;
    }
    final picker = SaveFilePicker()
      ..title = ui("下载联网音乐")
      ..fileName = OnlineMusicService.suggestedFileName(audio)
      ..defaultExtension = "mp3"
      ..filterSpecification = {
        ui("音频文件"): "*.mp3;*.m4a;*.flac;*.ogg",
        ui("所有文件"): "*.*",
      };
    final file = picker.getFile();
    if (file == null) return;

    showTextOnSnackBar("正在下载 {0}…", arguments: [audio.title]);
    try {
      await OnlineMusicService.instance.download(audio, file);
      showTextOnSnackBar("下载完成：{0}", arguments: [file.path]);
    } on OnlineMusicException catch (error) {
      showTextOnSnackBar(error.message);
    } catch (error, trace) {
      LOGGER.e("[online download] $error", stackTrace: trace);
      showTextOnSnackBar("下载失败：{0}", arguments: [error]);
    }
  }

  List<Widget> _buildMenuItems(BuildContext context, Audio audio) {
    final sourceLabel = onlineSourceDisplayLabel(
      provider: audio.onlineProvider,
      fallback: audio.sourceLabel,
    );
    final common = <Widget>[
      MenuItemButton(
        onPressed: () => showCoverRepairDialog(context, [audio]),
        leadingIcon: const Icon(Symbols.image_search),
        child: Text(ui('重新读取封面')),
      ),
      MenuItemButton(
        onPressed: () {
          PlayService.instance.playbackService.addToNext(audio);
          NextPlayAnimation.fly(
            context: context,
            sourceContext: _artworkContext ?? context,
            audio: audio,
          );
        },
        leadingIcon: const Icon(Symbols.plus_one),
        child: Text(ui("下一首播放")),
      ),
      MenuItemButton(
        onPressed: () => showAddAudiosToPlaylistDialog(context, [audio]),
        leadingIcon: const Icon(Symbols.playlist_add),
        child: Text(ui("加入歌单…")),
      ),
      if (widget.multiSelectController != null || widget.selection != null)
        MenuItemButton(
          onPressed: () {
            if (widget.selection != null) {
              widget.selection!.onStart();
              return;
            }
            widget.multiSelectController!.useMultiSelectView(true);
            widget.multiSelectController!.select(audio);
          },
          leadingIcon: const Icon(Symbols.select),
          child: Text(ui("多选")),
        ),
      if (widget.additionalMenuItems.isNotEmpty) const Divider(),
      ...widget.additionalMenuItems,
    ];

    if (audio.isOnline) {
      final inLibrary = OnlineLibrary.instance.contains(audio);
      final canDownload = OnlineMusicService.instance.canDownload(audio);
      final downloadReason =
          OnlineMusicService.instance.downloadUnavailableReason(audio);
      return [
        MenuItemButton(
          onPressed: null,
          leadingIcon: const Icon(Symbols.cloud),
          child: Text(ui("来源：{0}", [sourceLabel])),
        ),
        ...common,
        MenuItemButton(
          onPressed: () => _toggleOnlineLibrary(audio),
          leadingIcon: Icon(
            inLibrary ? Symbols.library_add_check : Symbols.library_add,
          ),
          child: Text(inLibrary ? ui("从总乐库移除") : ui("加入总乐库")),
        ),
        MenuItemButton(
          onPressed: canDownload ? () => _downloadOnlineAudio(audio) : null,
          leadingIcon: const Icon(Symbols.download),
          child: Text(
            canDownload
                ? ui("下载")
                : ui("下载不可用：{0}", [ui(downloadReason ?? '来源未授权')]),
          ),
        ),
        MenuItemButton(
          onPressed: () {
            context.push(app_paths.AUDIO_DETAIL_PAGE, extra: audio);
          },
          leadingIcon: const Icon(Symbols.info),
          child: Text(ui("联网歌曲详情")),
        ),
      ];
    }

    return [
      for (final artistName in audio.splitedArtists)
        MenuItemButton(
          onPressed: () {
            final artist = AudioLibrary.instance.artistCollection[artistName];
            if (artist != null) {
              context.push(app_paths.ARTIST_DETAIL_PAGE, extra: artist);
            }
          },
          leadingIcon: const Icon(Symbols.artist),
          child: _metadataMenuLabel(artistName),
        ),
      MenuItemButton(
        onPressed: () {
          final album = MusicCategories.albumGroupFor(
              audio, AudioLibrary.instance.audioCollection);
          context.push(album.location, extra: album);
        },
        leadingIcon: const Icon(Symbols.album),
        child: _metadataMenuLabel(audio.album),
      ),
      ...common,
      if (audio.canEditLocalFile)
        MenuItemButton(
          onPressed: () async {
            final updated = await showEditAudioMetadataDialog(context, audio);
            if (updated && mounted) setState(() {});
          },
          leadingIcon: const Icon(Symbols.edit_note),
          child: Text(ui("编辑歌曲信息")),
        ),
      if (audio.canEditLocalFile)
        MenuItemButton(
          onPressed: () => showLyricEditorDialog(context, audio),
          leadingIcon: const Icon(Symbols.lyrics),
          child: Text(ui("编辑歌词")),
        ),
      MenuItemButton(
        onPressed: () {
          context.push(app_paths.AUDIO_DETAIL_PAGE, extra: audio);
        },
        leadingIcon: const Icon(Symbols.info),
        child: Text(ui("详细信息")),
      ),
      if (audio.canEditLocalFile) ...[
        const Divider(),
        DeleteAudioMenuItem(audio: audio, hostContext: context),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final audio = widget.playlist[widget.audioIndex];
    final compactGrid = MusicGridScope.of(context);

    return AppEntrance(
      key: ValueKey(audio.path),
      identity: ('audio', audio.path),
      order: widget.audioIndex,
      child: MenuAnchor(
        // Song pages live in a nested Navigator below the persistent mini
        // player. The root Overlay keeps the mini player from painting over
        // editing/actions; this inset also makes a long menu scroll above the
        // player's full footprint instead of hiding its final actions.
        useRootOverlay: true,
        // MenuAnchor otherwise measures its horizontal "natural" width before
        // applying maximumSize. A long metadata/additional item is then clipped
        // as one oversized rectangle, which hides both TextOverflow.ellipsis
        // and the menu surface's rounded corners. Keep the panel constrained by
        // the overlay from the start so every item receives the real width.
        crossAxisUnconstrained: false,
        alignmentOffset: const Offset(8, 0),
        reservedPadding: const EdgeInsets.fromLTRB(8, 8, 8, 116),
        consumeOutsideTap: true,
        style: const MenuStyle(
          maximumSize: WidgetStatePropertyAll(
            Size(420, double.infinity),
          ),
        ),
        menuChildren: _buildMenuItems(context, audio),
        builder: (anchorContext, controller, _) {
          final selected = widget.selection?.selected ??
              (widget.multiSelectController?.selected.contains(audio) == true);
          final selecting = widget.selection?.enabled ??
              (widget.multiSelectController?.enableMultiSelectView == true);
          final textColor = widget.focus ? scheme.primary : scheme.onSurface;
          final metadataColor =
              widget.focus ? scheme.primary : scheme.onSurfaceVariant;
          final tileColor = selected
              ? scheme.secondaryContainer.withValues(alpha: 0.78)
              : widget.focus
                  ? scheme.primaryContainer.withValues(alpha: 0.30)
                  : Colors.transparent;
          final outlineColor = selected || widget.focus
              ? scheme.primary.withValues(alpha: selected ? 0.22 : 0.18)
              : Colors.transparent;
          final placeholder = Icon(
            Symbols.broken_image,
            size: 48.0,
            color: scheme.onSurfaceVariant,
          );
          final durationText =
              Duration(seconds: audio.duration).toStringHMMSS();
          final sourceLabel = audio.isOnline
              ? onlineSourceDisplayLabel(
                  provider: audio.onlineProvider,
                  fallback: audio.sourceLabel,
                )
              : null;
          final durationLabel = Text(
            durationText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: metadataColor),
          );
          final sourceStatus = !audio.isOnline
              ? null
              : !PlayService.isInitialized
                  ? Tooltip(
                      message: ui("联网音乐 · {0}", [sourceLabel]),
                      child:
                          Icon(Symbols.cloud, size: 18.0, color: metadataColor),
                    )
                  : ValueListenableBuilder<String?>(
                      valueListenable: PlayService
                          .instance.playbackService.resolvingAudioPath,
                      builder: (context, resolvingPath, _) => Tooltip(
                        message: resolvingPath == audio.path
                            ? ui("正在获取播放地址")
                            : ui("联网音乐 · {0}", [sourceLabel]),
                        child: resolvingPath == audio.path
                            ? const SizedBox.square(
                                dimension: 18.0,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(Symbols.cloud,
                                size: 18.0, color: metadataColor),
                      ),
                    );

          return TweenAnimationBuilder<Color?>(
            tween: ColorTween(begin: Colors.transparent, end: tileColor),
            duration: AppMotion.quick,
            curve: AppMotion.standardCurve,
            builder: (context, color, child) => ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Ink(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: AppShape.controlRadius,
                  border: Border.all(color: outlineColor),
                ),
                child: child,
              ),
            ),
            child: InkWell(
              focusColor: Colors.transparent,
              borderRadius: AppShape.controlRadius,
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return scheme.primary.withValues(alpha: 0.12);
                }
                if (states.contains(WidgetState.hovered)) {
                  return scheme.primary.withValues(alpha: 0.06);
                }
                if (states.contains(WidgetState.focused)) {
                  return scheme.primary.withValues(alpha: 0.08);
                }
                return null;
              }),
              onTap: () {
                if (controller.isOpen) {
                  controller.close();
                  return;
                }

                if (!selecting) {
                  if (PlayService
                          .instance.playbackService.resolvingAudioPath.value ==
                      audio.path) {
                    return;
                  }
                  PlayService.instance.playbackService
                      .play(widget.audioIndex, widget.playlist);
                } else {
                  if (widget.selection != null) {
                    widget.selection!.onToggle();
                    return;
                  }
                  if (widget.multiSelectController!.selected.contains(audio)) {
                    widget.multiSelectController!.unselect(audio);
                  } else {
                    widget.multiSelectController!.select(audio);
                  }
                }
              },
              onLongPress: () {
                if (selecting) {
                  return;
                }
                HapticFeedback.mediumImpact();
                controller.open();
              },
              onSecondaryTapDown: (details) {
                if (selecting) {
                  return;
                }

                controller.open(position: details.localPosition);
              },
              child: compactGrid
                  ? MusicGridTileBody(
                      key: const ValueKey('audio-grid-content'),
                      title: widget.showSourceLabel && sourceLabel != null
                          ? '${audio.displayTitle}\n${ui("来源：{0}", [
                                  sourceLabel
                                ])}'
                          : audio.displayTitle,
                      tooltip: '${audio.displayTitle}\n'
                          '${audio.isOnline ? ui("联网音乐 · {0}", [
                                  sourceLabel
                                ]) : ui("本地音乐")}',
                      color: textColor,
                      leading: widget.leading,
                      // Ink's 1px border is part of its layout padding.
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 7),
                      artwork: _artwork(audio, placeholder),
                      contentWrapper: (child) => MusicGridReorderScope.wrap(
                        context,
                        item: audio,
                        label: audio.displayTitle,
                        child: child,
                      ),
                      action: widget.action ??
                          Builder(
                            builder: (actionContext) => AppIconActionButton(
                              key: ValueKey('audio-grid-menu-${audio.path}'),
                              tooltip: ui("歌曲操作"),
                              onPressed: selecting
                                  ? null
                                  : () => _toggleMenuFromAction(
                                        controller,
                                        anchorContext,
                                        actionContext,
                                      ),
                              selected: controller.isOpen,
                              glyph: AppActionGlyph.moreVertical,
                            ),
                          ),
                    )
                  : Padding(
                      // Ink adds its 1px border to the padding: 48 + 2*(7+1) = 64.
                      // Larger accessibility text can grow the real row instead of
                      // overflowing a fixed-height box or being silently scaled down.
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 7),
                      child: LayoutBuilder(builder: (context, constraints) {
                        if (widget.columns) {
                          final composer = classifySongComposer(
                              composerTag: audio.composer,
                              artist: audio.artist);
                          return Row(
                            key: const ValueKey('audio-columns-row'),
                            children: [
                              if (widget.leading != null) widget.leading!,
                              _artwork(audio, placeholder),
                              const SizedBox(width: 16),
                              Expanded(
                                  child: AudioColumnFields(
                                      title: audio.displayTitle,
                                      composer: composer.value ?? ui("未知作曲家"),
                                      album: audio.album,
                                      titleColor: textColor,
                                      metadataColor: metadataColor)),
                              const SizedBox(width: 8),
                              SizedBox(
                                  width: 64,
                                  child: Tooltip(
                                      message: audio.isOnline
                                          ? ui("{0} · 联网音乐 · {1}",
                                              [durationText, sourceLabel])
                                          : durationText,
                                      child: Align(
                                          alignment:
                                              AlignmentDirectional.centerEnd,
                                          child: durationLabel))),
                              const SizedBox(width: 8),
                              widget.action ??
                                  Builder(
                                      builder: (actionContext) =>
                                          AppIconActionButton(
                                              key: ValueKey(
                                                  'audio-columns-menu-${audio.path}'),
                                              tooltip: ui("歌曲操作"),
                                              onPressed: selecting
                                                  ? null
                                                  : () => _toggleMenuFromAction(
                                                        controller,
                                                        anchorContext,
                                                        actionContext,
                                                      ),
                                              selected: controller.isOpen,
                                              glyph:
                                                  AppActionGlyph.moreVertical)),
                            ],
                          );
                        }
                        // Measure only the short, static duration, not every title.
                        // The colour tween reuses this child; no playback/frame-time
                        // text measurement or extra artwork request is introduced.
                        final durationMetrics = TextPainter(
                          text: TextSpan(
                            text: durationText,
                            style: DefaultTextStyle.of(context)
                                .style
                                .merge(TextStyle(color: metadataColor)),
                          ),
                          textDirection: Directionality.of(context),
                          textScaler: MediaQuery.textScalerOf(context),
                          maxLines: 1,
                        )..layout();
                        final trailingWidth = durationMetrics.width +
                            (sourceStatus == null ? 0 : 26);
                        durationMetrics.dispose();
                        final needsSeparateDetails = constraints.maxWidth <
                            48 +
                                16 +
                                64 +
                                8 +
                                trailingWidth +
                                (widget.action == null ? 0 : 56) +
                                (widget.leading == null ? 0 : 64);
                        // Old fixed-extent hosts still own their row height. Do not
                        // add another line inside a host that cannot grow at all.
                        final separateDetails = needsSeparateDetails &&
                            (!constraints.hasBoundedHeight ||
                                constraints.maxHeight > 64);
                        return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                  key: const ValueKey('audio-tile-main-row'),
                                  children: [
                                    if (widget.leading != null)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(right: 16.0),
                                        child: widget.leading!,
                                      ),

                                    /// cover
                                    _artwork(audio, placeholder),
                                    const SizedBox(width: 16.0),

                                    /// title, artist and album
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            audio.displayTitle,
                                            style: TextStyle(
                                                color: textColor, fontSize: 16),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(width: 4.0),
                                          Text(
                                            widget.showSourceLabel &&
                                                    sourceLabel != null
                                                ? '${ui("来源：{0}", [
                                                        sourceLabel
                                                      ])} · ${audio.artist} - ${audio.album}'
                                                : "${audio.artist} - ${audio.album}",
                                            style:
                                                TextStyle(color: metadataColor),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8.0),
                                    if (!separateDetails) ...[
                                      if (sourceStatus != null) ...[
                                        sourceStatus,
                                        const SizedBox(width: 8),
                                      ],
                                      if (needsSeparateDetails)
                                        Flexible(
                                          child: Tooltip(
                                              message: durationText,
                                              child: durationLabel),
                                        )
                                      else
                                        durationLabel,
                                    ],
                                    if (widget.action != null)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(left: 8.0),
                                        child: widget.action!,
                                      ),
                                  ]),
                              if (separateDetails)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    key: const ValueKey(
                                        'audio-tile-secondary-row'),
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (sourceStatus != null) ...[
                                        sourceStatus,
                                        const SizedBox(width: 8),
                                      ],
                                      Flexible(
                                        child: Tooltip(
                                            message: durationText,
                                            child: durationLabel),
                                      ),
                                    ],
                                  ),
                                ),
                            ]);
                      }),
                    ),
            ),
          );
        },
      ),
    );
  }
}
