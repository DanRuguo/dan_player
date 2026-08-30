import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/audio_artwork.dart';
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
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Icon(
      Symbols.broken_image,
      size: 48,
      color: scheme.onSurface,
    );
    return AppEntrance(
      key: ValueKey(album.name),
      identity: ('album', album.name),
      child: Tooltip(
        message: album.name,
        child: InkWell(
          onTap: () => context.push(app_paths.ALBUM_DETAIL_PAGE, extra: album),
          borderRadius: AppShape.controlRadius,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: AppShape.smallRadius,
                  child: album.works.isEmpty
                      ? placeholder
                      : AudioArtwork(
                          audio: album.works.first,
                          placeholder: placeholder,
                        ),
                ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Text(
                      album.name,
                      softWrap: false,
                      maxLines: 2,
                      style: TextStyle(color: scheme.onSurface),
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
