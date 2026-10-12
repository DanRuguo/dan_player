import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/audio_artwork.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/folder_tree_pane.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/library/folder_tree.dart';
import 'package:dan_player/page/folders_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/page/uni_page_components.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as path;

import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

class _CountedAudio extends CategoryTestAudio {
  _CountedAudio(super.id, this.onTitleRead, {required super.path});
  final VoidCallback onTitleRead;
  @override
  String get displayTitle {
    onTitleRead();
    return super.displayTitle;
  }
}

class _CountedSongs extends ListBase<Audio> {
  _CountedSongs(this.values);
  final List<Audio> values;
  var reads = 0;
  @override
  int get length => values.length;
  @override
  set length(int value) => throw UnsupportedError('Read-only fixture');
  @override
  Audio operator [](int index) {
    reads++;
    return values[index];
  }

  @override
  void operator []=(int index, Audio value) =>
      throw UnsupportedError('Read-only fixture');
}

class _ControlledImage extends ImageProvider<_ControlledImage> {
  final frame = Completer<ImageInfo>();
  var loads = 0;
  @override
  Future<_ControlledImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
      _ControlledImage key, ImageDecoderCallback decode) {
    loads++;
    return OneFrameImageStreamCompleter(
        frame.future.then((value) => value.clone()));
  }

  void complete(raster.Image image) {
    final info = ImageInfo(image: image.clone());
    addTearDown(info.dispose);
    frame.complete(info);
  }
}

class _Playback extends PlaylistFeaturePlayback {
  _Playback() : super([]);
  List<Audio>? played;
  @override
  void play(int audioIndex, List<Audio> playlist) {
    played = playlist;
  }
}

class _SortRequest {
  _SortRequest(this.songs, this.field, this.direction);
  final List<Audio> songs;
  final AudioSortField field;
  final SortDirection direction;
  final result = Completer<List<Audio>>();
  void complete() =>
      result.complete(sortedAudios(songs, field, direction: direction));
}

class _ControlledSorter {
  final requests = <_SortRequest>[];
  Future<List<Audio>> sort(
      List<Audio> songs, AudioSortField field, SortDirection direction) {
    final request = _SortRequest(songs, field, direction);
    requests.add(request);
    return request.result.future;
  }
}

double _opacity(WidgetTester tester, Finder child) {
  var result = 1.0;
  for (final widget in tester.widgetList<Opacity>(
      find.ancestor(of: child, matching: find.byType(Opacity)))) {
    result *= widget.opacity;
  }
  for (final widget in tester.widgetList<FadeTransition>(
      find.ancestor(of: child, matching: find.byType(FadeTransition)))) {
    result *= widget.opacity.value;
  }
  return result;
}

void main({bool onlyRender = false, String? onlyCase}) {
  const renderCases = {
    'first song expansion has a finite entrance instead of a pop',
    'cold song cover uses loading paint without a false music icon',
    'late decoded first cover fades in after expansion has settled',
  };
  void widgetCase(String name, Future<void> Function(WidgetTester) callback) {
    if (onlyRender && !renderCases.contains(name)) return;
    if (onlyCase != null && onlyCase.isNotEmpty && !name.contains(onlyCase)) {
      return;
    }
    testWidgets(name, callback);
  }

  TestWidgetsFlutterBinding.ensureInitialized();
  final qa = path.join(Directory.current.parent.path, 'tool', 'qa-local',
      'kana-layout-feedback-oct11', 'folders');
  final data = Directory(path.join(qa, 'data'));
  final music = path.join(qa, 'Music');
  late List<AudioFolder> previousFolders;
  late PagePreference previousFolderPreference, previousSongPreference;
  late UiLanguage previousLanguage;

  setUpAll(loadPlaylistFeatureFonts);
  setUp(() {
    previousFolders = AudioLibrary.instance.folders;
    previousFolderPreference = AppPreference.instance.foldersPagePref;
    previousSongPreference = AppPreference.instance.folderDetailPagePref;
    previousLanguage = uiLanguage.value;
    uiLanguage.value = UiLanguage.zh;
    AppPreference.instance.foldersPagePref =
        PagePreference(0, SortOrder.ascending, ContentView.table);
    AppPreference.instance.folderDetailPagePref =
        PagePreference(0, SortOrder.ascending, ContentView.table);
  });
  tearDown(() {
    AudioLibrary.instance.folders = previousFolders;
    AppPreference.instance.foldersPagePref = previousFolderPreference;
    AppPreference.instance.folderDetailPagePref = previousSongPreference;
    uiLanguage.value = previousLanguage;
  });

  Audio song(int index) =>
      CategoryTestAudio('Track ${index.toString().padLeft(5, '0')}',
          path: path.join(music, '$index.mp3'));
  Audio orderedSong(int index) => CategoryTestAudio(
      'Track ${index.toString().padLeft(5, '0')}',
      path: path.join(music, 'Track ${index.toString().padLeft(5, '0')}.mp3'));
  Finder folder() => find.byKey(ValueKey('folder-open-$music'));
  Finder cover(Audio audio) =>
      find.byKey(ValueKey('folder-tree-cover-${audio.path}'));
  Widget host(Widget child,
          {bool visible = true,
          bool reduced = false,
          MotionPreferences preferences = const MotionPreferences()}) =>
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows, useMaterial3: true),
        home: MediaQuery(
            data: MediaQueryData(
                size: const Size(760, 720), disableAnimations: reduced),
            child: MotionPreferencesScope(
                preferences: preferences,
                child: TickerMode(
                    enabled: visible,
                    child: AppEntranceScope(child: Scaffold(body: child))))),
      );
  Future<void> mount(WidgetTester tester,
      {AudioArtworkLoader? loadArtwork,
      FolderTreeSongSorter? sortLargeFolder,
      PlaybackService? playbackService}) async {
    sizePlaylistFeature(tester, width: 760, height: 720);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    await tester.pumpWidget(host(FoldersPage(
        dataDirectory: data,
        sortLargeFolder: sortLargeFolder,
        playbackService: playbackService,
        loadArtwork: loadArtwork ?? (_, __) async => null)));
    await tester.pumpAndSettle();
  }

  Future<void> expand(WidgetTester tester) async {
    await tester.tapAt(tester.getTopLeft(folder()) + const Offset(70, 35));
    await tester.pump();
  }

  widgetCase('collapsed folders do not synchronously sort the entire library',
      (tester) async {
    var titleReads = 0;
    AudioLibrary.instance.folders = [
      for (var folder = 0; folder < 40; folder++)
        AudioFolder([
          for (var index = 0; index < 200; index++)
            _CountedAudio('$index', () => titleReads++,
                path: path.join(music, '$folder', '$index.mp3')),
        ], path.join(music, '$folder'), 1, 1),
    ];
    await mount(tester);
    expect(titleReads, 0,
        reason: 'No song is visible; opening the folder page must not sort '
            'all 8000 titles on its UI frame.');
    expect(find.byType(AudioArtwork), findsNothing);
    expect(tester.takeException(), isNull);
  });

  widgetCase('first large expansion reads only the viewport song rows',
      (tester) async {
    final songs = _CountedSongs([for (var i = 0; i < 20000; i++) song(i)]);
    final tree = FolderTree.project(
        folders: [AudioFolder(songs, music, 1, 1)], scanRoots: []);
    var expanded = <String>{};
    late StateSetter change;
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var builds = 0;
    sizePlaylistFeature(tester, width: 760, height: 720);
    await tester.pumpWidget(host(StatefulBuilder(builder: (context, setState) {
      change = setState;
      return FolderTreePane(
          tree: tree,
          expanded: expanded,
          songsByFolder: {tree.roots.single.id: songs},
          controller: controller,
          footer: const SizedBox.shrink(),
          folderBuilder: (_, __) => const SizedBox(height: 72),
          songBuilder: (_, __, audio, index, coverSize) {
            builds++;
            return ColoredBox(key: ValueKey(audio.path), color: Colors.red);
          });
    })));
    await tester.pumpAndSettle();
    songs.reads = 0;
    change(() => expanded = {tree.roots.single.id});
    await tester.pumpAndSettle();
    expect(builds, inInclusiveRange(1, 200));
    expect(songs.reads, lessThan(400),
        reason: 'Indexing every offscreen row defeats the lazy viewport.');
    final afterExpand = songs.reads;
    change(() {});
    await tester.pump();
    expect(songs.reads - afterExpand, lessThan(400),
        reason: 'A selection/theme rebuild must retain the projected rows.');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  widgetCase('first song expansion has a finite entrance instead of a pop',
      (tester) async {
    final audio = song(0);
    AudioLibrary.instance.folders = [
      AudioFolder([audio], music, 1, 1)
    ];
    await mount(tester);
    await expand(tester);
    final first = tester.getTopLeft(cover(audio));
    expect(_opacity(tester, cover(audio)), lessThan(.99));
    await tester.pump(const Duration(milliseconds: 90));
    final middle = tester.getTopLeft(cover(audio));
    final opacity = _opacity(tester, cover(audio));
    expect(opacity, inExclusiveRange(0.0, 1.0));
    await tester.pumpAndSettle();
    final last = tester.getTopLeft(cover(audio));
    expect((first - last).distance, greaterThan(1));
    expect((middle - last).distance, lessThan((first - last).distance));
    expect(_opacity(tester, cover(audio)), 1);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  widgetCase(
      'large folder completes its real worker before exposing sorted playback',
      (tester) async {
    final songs = [for (var i = 0; i < 1600; i++) orderedSong(i)];
    final original = songs.reversed.toList();
    AudioLibrary.instance.folders = [AudioFolder(original, music, 1, 1)];
    final playback = _Playback();
    addTearDown(playback.dispose);
    await mount(tester, playbackService: playback);
    await expand(tester);
    final loading =
        find.byKey(ValueKey('folder-tree-sorting-${folderTreePathId(music)}'));
    expect(loading, findsOneWidget);
    expect(find.byType(AudioTile), findsNothing,
        reason: 'Unsorted first rows must not be exposed and then jump.');
    for (var i = 0; i < 300 && loading.evaluate().isNotEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(loading, findsNothing, reason: 'The actual isolate must finish.');
    final pane = tester.widget<FolderTreePane>(find.byType(FolderTreePane));
    final sorted = pane.songsByFolder[folderTreePathId(music)]!;
    expect(sorted, orderedEquals(songs));
    for (var i = 0; i < sorted.length; i++) {
      expect(sorted[i], same(songs[i]));
    }
    expect(find.byType(AudioTile).evaluate().length, inInclusiveRange(1, 120));
    await tester.tap(cover(songs.first));
    await tester.pumpAndSettle();
    expect(playback.played, same(sorted));
    expect(AudioLibrary.instance.folders.single.audios, same(original));
    expect(original, orderedEquals(songs.reversed));
    expect(tester.takeException(), isNull);
  });

  widgetCase(
      'collapsed large folder rejects late sort and reopening owns a fresh result',
      (tester) async {
    final songs = [for (var i = 0; i < 600; i++) orderedSong(i)];
    final original = songs.reversed.toList();
    AudioLibrary.instance.folders = [AudioFolder(original, music, 1, 1)];
    final sorter = _ControlledSorter();
    await mount(tester, sortLargeFolder: sorter.sort);
    await expand(tester);
    expect(sorter.requests, hasLength(1));
    await expand(tester); // Collapse while the first worker is held.
    sorter.requests.single.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AudioTile), findsNothing);
    expect(
        tester
            .widget<FolderTreePane>(find.byType(FolderTreePane))
            .songsByFolder[folderTreePathId(music)],
        same(original));
    await expand(tester);
    expect(sorter.requests, hasLength(2));
    expect(find.byType(AudioTile), findsNothing);
    sorter.requests.last.complete();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FolderTreePane>(find.byType(FolderTreePane))
            .songsByFolder[folderTreePathId(music)],
        orderedEquals(songs));
    expect(cover(songs.first), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  widgetCase(
      'sort changes and library replacement reject obsolete large folder results',
      (tester) async {
    final songs = [for (var i = 0; i < 600; i++) orderedSong(i)];
    AudioLibrary.instance.folders = [
      AudioFolder(songs.reversed.toList(), music, 1, 1)
    ];
    final sorter = _ControlledSorter();
    await mount(tester, sortLargeFolder: sorter.sort);
    await expand(tester);
    final control = tester.widget<SortMethodComboBox<Audio>>(
        find.byType(SortMethodComboBox<Audio>));
    control.setSortOrder!(SortOrder.decending);
    await tester.pump();
    sorter.requests.first.complete();
    await tester.pump();
    expect(sorter.requests, hasLength(2));
    expect(sorter.requests.last.direction, SortDirection.descending);
    expect(find.byType(AudioTile), findsNothing);
    final replacement = [
      for (var i = 0; i < 600; i++)
        CategoryTestAudio('Replacement ${i.toString().padLeft(5, '0')}',
            path: path.join(
                music, 'replacement-${i.toString().padLeft(5, '0')}.mp3'))
    ];
    AudioLibrary.instance.folders = [AudioFolder(replacement, music, 1, 1)];
    AudioLibrary.changes.value++;
    await tester.pump();
    sorter.requests[1].complete();
    await tester.pump();
    expect(sorter.requests, hasLength(3));
    expect(sorter.requests.last.songs, same(replacement));
    expect(find.byType(AudioTile), findsNothing);
    sorter.requests.last.complete();
    await tester.pumpAndSettle();
    final sorted = tester
        .widget<FolderTreePane>(find.byType(FolderTreePane))
        .songsByFolder[folderTreePathId(music)]!;
    expect(sorted, orderedEquals(replacement.reversed));
    expect(sorted.first, same(replacement.last));
    expect(cover(replacement.last), findsOneWidget);
    expect(cover(songs.last), findsNothing);
    expect(tester.takeException(), isNull);
  });

  widgetCase('cold song cover uses loading paint without a false music icon',
      (tester) async {
    final audio = song(0);
    AudioLibrary.instance.folders = [
      AudioFolder([audio], music, 1, 1)
    ];
    final pending = Completer<ImageProvider?>();
    await mount(tester, loadArtwork: (_, __) => pending.future);
    await expand(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(
        find.descendant(
            of: cover(audio), matching: find.byIcon(Symbols.music_note)),
        findsNothing,
        reason: 'Pending cover decode is not a known missing cover.');
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: cover(audio), matching: find.byIcon(Symbols.music_note)),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  widgetCase('late decoded first cover fades in after expansion has settled',
      (tester) async {
    final audio = song(0);
    AudioLibrary.instance.folders = [
      AudioFolder([audio], music, 1, 1)
    ];
    final provider = _ControlledImage();
    var requests = 0;
    final image = (await tester.runAsync(() async {
      final recorder = raster.PictureRecorder();
      Canvas(recorder).drawColor(Colors.red, BlendMode.src);
      final picture = recorder.endRecording();
      final result = await picture.toImage(24, 24);
      picture.dispose();
      return result;
    }))!;
    addTearDown(image.dispose);
    await mount(tester, loadArtwork: (_, __) async {
      requests++;
      return provider;
    });
    await expand(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.descendant(of: cover(audio), matching: find.byType(RawImage)),
        findsNothing);
    provider.complete(image);
    await tester.pump();
    await tester.pump();
    final raw =
        find.descendant(of: cover(audio), matching: find.byType(RawImage));
    expect(raw, findsOneWidget);
    expect(tester.widget<RawImage>(raw).image!.isCloneOf(image), isTrue);
    expect(_opacity(tester, raw), lessThan(.99));
    await tester.pump(const Duration(milliseconds: 80));
    expect(_opacity(tester, raw), inExclusiveRange(0.0, 1.0));
    await tester.pumpAndSettle();
    expect(_opacity(tester, raw), 1);
    expect(requests, 1);
    expect(provider.loads, 1);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  for (final gate in ['hidden', 'reduced', 'entrance disabled']) {
    widgetCase('first decoded cover finishes immediately when $gate',
        (tester) async {
      sizePlaylistFeature(tester, width: 760, height: 720);
      final image = (await tester.runAsync(() async {
        final recorder = raster.PictureRecorder();
        Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
        final picture = recorder.endRecording();
        final result = await picture.toImage(24, 24);
        picture.dispose();
        return result;
      }))!;
      addTearDown(image.dispose);
      final provider = _ControlledImage();
      final audio = song(0);
      Widget artwork() => Center(
          child: AudioArtwork(
              audio: audio,
              animateFirstFrame: true,
              loadArtwork: (_, __) async => provider,
              placeholder: const ColoredBox(color: Colors.black)));
      await tester.pumpWidget(host(artwork()));
      await tester.pumpAndSettle();
      provider.complete(image);
      await tester.pump();
      await tester.pump();
      final raw = find.byType(RawImage);
      expect(_opacity(tester, raw), lessThan(.99));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpWidget(host(artwork(),
          visible: gate != 'hidden',
          reduced: gate == 'reduced',
          preferences: MotionPreferences(
              disabled:
                  gate == 'entrance disabled' ? {MotionKind.entrance} : {})));
      await tester.pump();
      expect(_opacity(tester, raw), 1);
      expect(tester.widget<RawImage>(raw).image!.isCloneOf(image), isTrue);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(host(artwork()));
      await tester.pumpAndSettle();
      expect(_opacity(tester, raw), 1,
          reason: 'Restoring motion must not restart a completed handoff.');
      expect(provider.loads, 1);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  if (!onlyRender && (onlyCase == null || onlyCase.isEmpty)) {
    test(
        'folder queue views retain identity and stable async missing-value order',
        () async {
      final first = CategoryTestAudio('同名',
          artist: 'Artist', path: path.join(music, 'a.mp3'));
      final second = CategoryTestAudio('同名',
          artist: 'Artist', path: path.join(music, 'b.mp3'));
      final missing = CategoryTestAudio('',
          artist: 'Unknown', path: path.join(music, 'c.mp3'));
      final sources = _CountedSongs([second, first, second]);
      final joined = FolderTreeAudioList([
        [],
        sources,
        [missing]
      ]);
      expect(joined.length, 4);
      expect(sources.reads, 0);
      expect(joined[2], same(second));
      expect(sources.reads, 1);
      expect(joined[3], same(missing));
      expect(() => joined[4], throwsRangeError);
      expect(() => joined[0] = missing, throwsUnsupportedError);
      expect(() => joined.length = 0, throwsUnsupportedError);
      final original = [missing, second, first, second];
      for (final direction in SortDirection.values) {
        final sorted = await sortFolderTreeSongs(
            original, AudioSortField.artist, direction);
        final expected =
            sortedAudios(original, AudioSortField.artist, direction: direction);
        for (var index = 0; index < sorted.length; index++) {
          expect(sorted[index], same(expected[index]));
        }
        expect(sorted.last, same(missing));
        expect(sorted.take(3), orderedEquals([second, first, second]));
      }
      expect(original.first, same(missing));
    });
  }
}
