import 'package:dan_player/component/audio_artwork.dart';
import 'package:dan_player/library/category_cover_store.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

/// A generated category uses its managed custom cover first and the first
/// current song only as a fallback. Missing/corrupt copies never hide a group.
class CategoryCover extends StatelessWidget {
  const CategoryCover({
    super.key,
    required this.group,
    required this.store,
    required this.size,
    required this.placeholder,
  });

  final MusicCategoryGroup group;
  final CategoryCoverStore store;
  final double size;
  final Widget placeholder;

  Widget _songArtwork() => group.coverAudio == null
      ? placeholder
      : AudioArtwork(
          audio: group.coverAudio!,
          size: size,
          placeholder: placeholder,
        );

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final id = store.coverIdFor(group);
    return Semantics(
      image: true,
      label: ui("{0}的歌单封面", [group.title]),
      child: SizedBox.square(
        dimension: size,
        child: id == null
            ? _songArtwork()
            : FutureBuilder<ImageProvider?>(
                key: ValueKey(('category-custom-cover', group.persistenceKey)),
                future: store.imageFor(group),
                builder: (context, snapshot) {
                  final image = snapshot.data;
                  if (image == null) return _songArtwork();
                  return ArtworkImage(
                    image: image,
                    size: size,
                    revision: (id, store.revision),
                    errorBuilder: (_, __, ___) => _songArtwork(),
                  );
                },
              ),
      ),
    );
  }
}
