import 'package:dan_player/component/app_sort_button.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/page/category_detail_page.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

Widget _host(CategoryDetailPage page, {double scale = 1}) => MaterialApp(
      theme:
          ThemeData(useMaterial3: true, visualDensity: VisualDensity.compact),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            disableAnimations: true, textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: page),
    );

Widget _track(BuildContext context, Audio audio, VoidCallback play) =>
    TextButton(
      key: ValueKey(('sort-track', audio.path)),
      onPressed: play,
      child: Text(audio.displayTitle),
    );

Future<void> _select(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(const ValueKey('category-track-sort')));
  await tester.pumpAndSettle();
  final item = find.byKey(ValueKey(key));
  await tester.ensureVisible(item);
  await tester.tap(item);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('category shares every real field and keeps album track default',
      (tester) async {
    final song = CategoryTestAudio('Example');
    final group =
        MusicCategories([song]).groups(MusicCategoryKind.album).single;
    await tester.pumpWidget(_host(CategoryDetailPage(
      kind: group.kind,
      groupId: group.id,
      audios: [song],
      trackBuilder: _track,
    )));
    await tester.pumpAndSettle();
    final button = tester.widget<AppSortButton<AudioSortField>>(
        find.byType(AppSortButton<AudioSortField>));
    expect(button.value, AudioSortField.track);
    expect(button.direction, SortDirection.ascending);
    expect(button.options.map((item) => item.value).toSet(),
        AudioSortField.values.toSet());
    expect(PlayService.isInitialized, isFalse);
  });

  testWidgets(
      'composer sorting, direction and original order leave source and selection queue intact',
      (tester) async {
    final missing = CategoryTestAudio('Missing');
    final z = CategoryTestAudio('Z', composer: 'Zebra');
    final a = CategoryTestAudio('A', composer: 'Alpha');
    final equal = CategoryTestAudio('Equal', composer: 'Alpha');
    final songs = [missing, z, a, equal];
    final group = MusicCategories(songs).groups(MusicCategoryKind.artist).first;
    List<Audio>? played;
    List<Audio>? added;
    int? start;
    await tester.pumpWidget(_host(CategoryDetailPage(
      kind: group.kind,
      groupId: group.id,
      audios: songs,
      trackBuilder: _track,
      onPlay: (index, queue) {
        start = index;
        played = queue;
      },
      onAddToPlaylist: (queue) => added = queue,
    )));
    await tester.pumpAndSettle();
    await _select(tester, 'category-sort-composer');
    await tester.tap(find.byKey(ValueKey(('sort-track', a.path))));
    expect(played, [a, equal, z, missing]);
    await tester.tap(find.byKey(ValueKey(('sort-track', z.path))));
    expect(start, 2);
    expect(played, [a, equal, z, missing]);
    await _select(tester, 'app-sort-direction-descending');
    await tester.tap(find.byKey(const ValueKey('category-add-playlist')));
    expect(added, [z, a, equal, missing]);
    await _select(tester, 'category-sort-library');
    await tester.tap(find.byKey(ValueKey(('sort-track', missing.path))));
    expect(played, songs);
    expect(songs, [missing, z, a, equal]);
    expect(PlayService.isInitialized, isFalse);
  });

  testWidgets(
      'duration handles online and local metadata without playback initialization',
      (tester) async {
    final slow = CategoryTestAudio('Slow')..duration = 300;
    final fast = CategoryTestAudio('Fast', online: true)..duration = 90;
    final unknown = CategoryTestAudio('Unknown')..duration = 0;
    final songs = [slow, unknown, fast];
    final group = MusicCategories(songs).groups(MusicCategoryKind.album).first;
    List<Audio>? queue;
    await tester.pumpWidget(_host(CategoryDetailPage(
      kind: group.kind,
      groupId: group.id,
      audios: songs,
      trackBuilder: _track,
      onPlay: (_, value) => queue = value,
    )));
    await tester.pumpAndSettle();
    await _select(tester, 'category-sort-duration');
    await tester.tap(find.byKey(ValueKey(('sort-track', fast.path))));
    expect(queue, [fast, slow, unknown]);
    await _select(tester, 'app-sort-direction-descending');
    await tester.tap(find.byKey(ValueKey(('sort-track', slow.path))));
    expect(queue, [slow, fast, unknown]);
    expect(PlayService.isInitialized, isFalse);
  });

  testWidgets('switching category while sort is open cannot apply old field',
      (tester) async {
    final first = CategoryTestAudio('First', artist: 'One');
    final second = CategoryTestAudio('Second', artist: 'Two');
    final songs = [first, second];
    final groups = MusicCategories(songs).groups(MusicCategoryKind.artist);
    CategoryDetailPage page(MusicCategoryGroup group) => CategoryDetailPage(
          kind: group.kind,
          groupId: group.id,
          audios: songs,
          trackBuilder: _track,
        );
    await tester.pumpWidget(_host(page(groups.first)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category-track-sort')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_host(page(groups.last)));
    await tester.pump();
    final item = find.byKey(const ValueKey('category-sort-composer'));
    await tester.ensureVisible(item);
    await tester.tap(item);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<AppSortButton<AudioSortField>>(
                find.byType(AppSortButton<AudioSortField>))
            .value,
        AudioSortField.original);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('all three category controls agree at 440px and $scale text',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(440, 600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final song = CategoryTestAudio('Example');
      final group =
          MusicCategories([song]).groups(MusicCategoryKind.artist).first;
      await tester.pumpWidget(_host(
          CategoryDetailPage(
            kind: group.kind,
            groupId: group.id,
            audios: [song],
            trackBuilder: _track,
          ),
          scale: scale));
      await tester.pumpAndSettle();
      final heights = [
        for (final key in [
          'playback-mode-shuffle',
          'category-add-playlist',
          'category-track-sort'
        ])
          tester.getSize(find.byKey(ValueKey(key))).height
      ];
      expect(heights, everyElement(closeTo(heights.first, .01)));
      expect(heights.first, greaterThanOrEqualTo(44));
      final playButton = tester.widget<IconButton>(
          find.byKey(const ValueKey('playback-mode-shuffle')));
      expect(
          playButton.style!.backgroundColor!.resolve({WidgetState.selected}),
          Theme.of(tester
                  .element(find.byKey(const ValueKey('playback-mode-shuffle'))))
              .colorScheme
              .primaryContainer);
      expect(tester.getSize(find.byType(ListView)).height, greaterThan(80));
      expect(tester.takeException(), isNull);
    });
  }
}
