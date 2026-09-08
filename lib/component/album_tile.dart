import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/audio_artwork.dart';
import 'package:dan_player/component/category_cover.dart';
import 'package:dan_player/library/category_cover_store.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:flutter/material.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:dan_player/app_paths.dart' as app_paths;

class AlbumTile extends StatelessWidget {
  const AlbumTile({
    super.key,
    required this.album,
  });

  final Album album;

  @override
  Widget build(BuildContext context) {
    CategoryCoverStore.shared.load();
    final scheme = Theme.of(context).colorScheme;
    final groups = MusicCategories(album.works).groups(MusicCategoryKind.album);
    final group = groups.length == 1 ? groups.single : null;
    final placeholder = Icon(
      Symbols.broken_image,
      size: 48,
      color: scheme.onSurface,
    );
    return AppEntrance(
      key: ValueKey(album.groupId ?? album.name),
      identity: ('album', album.groupId ?? album.name),
      child: Tooltip(
        message: [album.name, if (album.albumArtist != null) album.albumArtist!]
            .join(' · '),
        child: InkWell(
          onTap: () => group == null
              ? context.push(app_paths.ALBUM_DETAIL_PAGE, extra: album)
              : context.push(group.location, extra: group),
          borderRadius: AppShape.controlRadius,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: AppShape.smallRadius,
                  child: album.works.isEmpty
                      ? placeholder
                      : group != null
                          ? ListenableBuilder(
                              listenable: CategoryCoverStore.shared,
                              builder: (context, _) => CategoryCover(
                                group: group,
                                store: CategoryCoverStore.shared,
                                size: 48,
                                placeholder: placeholder,
                              ),
                            )
                          : AudioArtwork(
                              audio: album.works.first,
                              placeholder: placeholder,
                            ),
                ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(album.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: scheme.onSurface)),
                        if (album.albumArtist != null)
                          Text(album.albumArtist!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
