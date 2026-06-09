import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/audio_metadata_dialog.dart';
import 'package:dan_player/component/scroll_aware_future_builder.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

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
  });

  final int audioIndex;
  final List<Audio> playlist;
  final bool focus;
  final Widget? leading;
  final Widget? action;
  final MultiSelectController? multiSelectController;

  @override
  State<AudioTile> createState() => _AudioTileState();
}

class _AudioTileState extends State<AudioTile> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final audio = widget.playlist[widget.audioIndex];

    return MenuAnchor(
      consumeOutsideTap: true,
      menuChildren: [
        /// artists
        SubmenuButton(
          menuChildren: List.generate(
            audio.splitedArtists.length,
            (i) => MenuItemButton(
              onPressed: () {
                final Artist artist = AudioLibrary
                    .instance.artistCollection[audio.splitedArtists[i]]!;
                context.push(
                  app_paths.ARTIST_DETAIL_PAGE,
                  extra: artist,
                );
              },
              leadingIcon: const Icon(Symbols.artist),
              child: Text(audio.splitedArtists[i]),
            ),
          ),
          child: const Text("艺术家"),
        ),

        /// album
        MenuItemButton(
          onPressed: () {
            final Album album =
                AudioLibrary.instance.albumCollection[audio.album]!;
            context.push(app_paths.ALBUM_DETAIL_PAGE, extra: album);
          },
          leadingIcon: const Icon(Symbols.album),
          child: Text(audio.album),
        ),

        /// 下一首播放
        MenuItemButton(
          onPressed: () {
            PlayService.instance.playbackService.addToNext(audio);
          },
          leadingIcon: const Icon(Symbols.plus_one),
          child: const Text("下一首播放"),
        ),

        /// 多选
        if (widget.multiSelectController != null)
          MenuItemButton(
            onPressed: () {
              widget.multiSelectController!.useMultiSelectView(true);
              widget.multiSelectController!.select(audio);
            },
            leadingIcon: const Icon(Symbols.select),
            child: const Text("多选"),
          ),

        MenuItemButton(
          onPressed: () async {
            final updated = await showEditAudioMetadataDialog(context, audio);
            if (updated && mounted) {
              setState(() {});
            }
          },
          leadingIcon: const Icon(Symbols.edit_note),
          child: const Text("编辑歌曲信息"),
        ),

        /// to detail page
        MenuItemButton(
          onPressed: () {
            context.push(app_paths.AUDIO_DETAIL_PAGE, extra: audio);
          },
          leadingIcon: const Icon(Symbols.info),
          child: const Text("详细信息"),
        ),
      ],
      builder: (context, controller, _) {
        final selected =
            widget.multiSelectController?.selected.contains(audio) == true;
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

        return TweenAnimationBuilder<Color?>(
          tween: ColorTween(begin: Colors.transparent, end: tileColor),
          duration: AppMotion.quick,
          curve: AppMotion.standardCurve,
          builder: (context, color, child) => Ink(
            height: 64.0,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10.0),
              border: Border.all(color: outlineColor),
            ),
            child: child,
          ),
          child: InkWell(
            focusColor: Colors.transparent,
            borderRadius: BorderRadius.circular(10.0),
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

              if (widget.multiSelectController == null ||
                  !widget.multiSelectController!.enableMultiSelectView) {
                PlayService.instance.playbackService
                    .play(widget.audioIndex, widget.playlist);
              } else {
                if (widget.multiSelectController!.selected.contains(audio)) {
                  widget.multiSelectController!.unselect(audio);
                } else {
                  widget.multiSelectController!.select(audio);
                }
              }
            },
            onSecondaryTapDown: (details) {
              if (widget.multiSelectController?.enableMultiSelectView == true) {
                return;
              }

              controller.open(
                  position: details.localPosition.translate(0, -240));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(children: [
                if (widget.leading != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: widget.leading!,
                  ),

                /// cover
                ScrollAwareFutureBuilder(
                  future: () => audio.cover,
                  builder: (context, snapshot) {
                    if (snapshot.data == null) {
                      return placeholder;
                    }

                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8.0),
                      child: Image(
                        image: snapshot.data!,
                        width: 48.0,
                        height: 48.0,
                        errorBuilder: (_, __, ___) => placeholder,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 16.0),

                /// title, artist and album
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        audio.displayTitle,
                        style: TextStyle(color: textColor, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(width: 4.0),
                      Text(
                        "${audio.artist} - ${audio.album}",
                        style: TextStyle(color: metadataColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8.0),
                Text(
                  Duration(seconds: audio.duration).toStringHMMSS(),
                  style: TextStyle(
                    color: metadataColor,
                  ),
                ),
                if (widget.action != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: widget.action!,
                  ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
