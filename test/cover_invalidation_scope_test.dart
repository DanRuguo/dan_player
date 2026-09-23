import 'dart:io';

import 'package:dan_player/category_presentation.dart';
import 'package:dan_player/component/category_tile_grid.dart';
import 'package:dan_player/component/playlist_rectangle_tile.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/category_cover_store.dart';
import 'package:dan_player/library/cover_cache.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

class _CountedCategoryAudio extends CategoryTestAudio {
  _CountedCategoryAudio(super.id);
  int reads = 0;

  @override
  Future<ImageProvider?> artworkForSize(ArtworkSize size) async {
    reads++;
    return null;
  }
}

void main() {
  testWidgets('unrelated cover invalidation does not rebuild a playlist tile',
      (tester) async {
    final audio = Audio('A', 'Artist', 'Album', 0, 60, null, null,
        'C:/isolated/song.mp3', 1, 1, null);
    var builds = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 160,
          height: 160,
          child: PlaylistRectangleTile(
            title: audio.title,
            audio: audio,
            loadArtwork: false,
            onTap: () {},
            onSecondaryTapDown: (_) {},
            onLongPress: () {},
            contentWrapper: (child) {
              builds++;
              return child;
            },
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final before = builds;

    // CoverCache's shared notification also fires for every other song.
    // This tile's own generation remains unchanged.
    CoverCache.instance.changes.value++;
    await tester.pump();
    expect(builds, before);
  });

  testWidgets('unrelated cover invalidation does not reload category artwork',
      (tester) async {
    final fixture = (await tester.runAsync(() => Directory(
            '${Directory.current.parent.path}/tool/qa-local/cover-invalidation')
        .create(recursive: true)))!;
    final covers = CategoryCoverStore(dataDirectory: () async => fixture);
    addTearDown(covers.dispose);
    final audio = _CountedCategoryAudio('counted');
    final group =
        MusicCategories([audio]).groups(MusicCategoryKind.album).single;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomScrollView(slivers: [
          CategoryTileGrid(
            groups: [group],
            presentation:
                const CategoryPresentation(shape: CategoryCoverShape.rounded),
            covers: covers,
            changing: const {},
            icon: Icons.album,
            onChanged: (_) {},
            onOpen: (_) {},
            onChangeCover: (_) {},
            onRemoveCover: (_) {},
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    final before = audio.reads;
    expect(before, greaterThan(0));

    CoverCache.instance.changes.value++;
    await tester.pumpAndSettle();
    expect(audio.reads, before);
  });
}
