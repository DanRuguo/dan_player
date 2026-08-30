import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/audio_artwork.dart';
import 'package:flutter/material.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:dan_player/app_paths.dart' as app_paths;

class ArtistTile extends StatelessWidget {
  const ArtistTile({
    super.key,
    required this.artist,
  });

  final Artist artist;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Icon(
      Symbols.broken_image,
      color: scheme.onSurface,
      size: 48,
    );
    return AppEntrance(
      key: ValueKey(artist.name),
      identity: ('artist', artist.name),
      child: Tooltip(
        message: artist.name,
        child: InkWell(
          onTap: () =>
              context.push(app_paths.ARTIST_DETAIL_PAGE, extra: artist),
          borderRadius: AppShape.controlRadius,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                ClipOval(
                  child: artist.works.isEmpty
                      ? placeholder
                      : AudioArtwork(
                          audio: artist.works.first,
                          placeholder: placeholder,
                        ),
                ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Text(
                      artist.name,
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
