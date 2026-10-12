import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/artwork_handoff.dart';
import 'package:dan_player/component/audio_artwork.dart';
import 'package:dan_player/component/folder_tree_pane.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/library/cover_cache.dart';
import 'package:dan_player/library/folder_tree.dart';
import 'package:dan_player/page/folders_page.dart';
import 'package:dan_player/page/audio_sort_methods.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

class _ObservedAudio extends CategoryTestAudio {
  _ObservedAudio(super.id, {required super.path});
  static int titleReads = 0;
  @override
  String get displayTitle {
    titleReads++;
    return super.displayTitle;
  }
}

class _ObservedSongs extends ListBase<Audio> {
  _ObservedSongs(this.values);
  final List<Audio> values;
  int reads = 0;
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

class _ObservedImage extends ImageProvider<_ObservedImage> {
  _ObservedImage(this.image);
  final raster.Image image;
  int decodes = 0;
  @override
  Future<_ObservedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
      _ObservedImage key, ImageDecoderCallback decode) {
    decodes++;
    return OneFrameImageStreamCompleter(
        Future.value(ImageInfo(image: image.clone())));
  }
}

void main({String? onlyCase}) {
  void widgetCase(String name, Future<void> Function(WidgetTester) callback) {
    if (onlyCase != null && onlyCase.isNotEmpty && !name.contains(onlyCase)) {
      return;
    }
    testWidgets(name, callback);
  }

  TestWidgetsFlutterBinding.ensureInitialized();
  final qa = Directory(path.join(Directory.current.parent.path, 'tool',
      'qa-local', 'kana-layout-feedback-oct11', 'folders', 'reopen-work'));
  late Directory fixture;
  late String music;
  late List<AudioFolder> oldFolders;
  late List<Audio> oldAudios;
  late Map<String, Artist> oldArtists;
  late Map<String, Album> oldAlbums;
  late int oldRevision, oldSortRevision, oldSearchRevision;
  late int oldClassificationRevision, oldChanges;
  late PagePreference oldFolderPreference, oldSongPreference;
  late UiLanguage oldLanguage;
  late PlaylistFeaturePlayback playback;

  setUpAll(loadPlaylistFeatureFonts);
  setUp(() async {
    expect(Directory.systemTemp.absolute.path.replaceAll('\\', '/'),
        contains('/tool/qa-local/'));
    await qa.create(recursive: true);
    fixture = await qa.createTemp('case-');
    music = path.join(fixture.path, 'Music');
    oldFolders = AudioLibrary.instance.folders;
    oldAudios = List.of(AudioLibrary.instance.audioCollection);
    oldArtists = Map.of(AudioLibrary.instance.artistCollection);
    oldAlbums = Map.of(AudioLibrary.instance.albumCollection);
    oldRevision = AudioLibrary.revision;
    oldSortRevision = AudioLibrary.sortRevision;
    oldSearchRevision = AudioLibrary.searchRevision;
    oldClassificationRevision = AudioLibrary.classificationRevision;
    oldChanges = AudioLibrary.changes.value;
    oldFolderPreference = AppPreference.instance.foldersPagePref;
    oldSongPreference = AppPreference.instance.folderDetailPagePref;
    oldLanguage = uiLanguage.value;
    uiLanguage.value = UiLanguage.zh;
    AppPreference.instance.foldersPagePref =
        PagePreference(0, SortOrder.ascending, ContentView.table);
    AppPreference.instance.folderDetailPagePref =
        PagePreference(0, SortOrder.ascending, ContentView.table);
    _ObservedAudio.titleReads = 0;
    playback = PlaylistFeaturePlayback([]);
  });
  tearDown(() {
    playback.dispose();
    AudioLibrary.instance.folders = oldFolders;
    AudioLibrary.instance.audioCollection = oldAudios;
    AudioLibrary.instance.artistCollection = oldArtists;
    AudioLibrary.instance.albumCollection = oldAlbums;
    AudioLibrary.revision = oldRevision;
    AudioLibrary.sortRevision = oldSortRevision;
    AudioLibrary.searchRevision = oldSearchRevision;
    AudioLibrary.classificationRevision = oldClassificationRevision;
    AudioLibrary.changes.value = oldChanges;
    AppPreference.instance.foldersPagePref = oldFolderPreference;
    AppPreference.instance.folderDetailPagePref = oldSongPreference;
    uiLanguage.value = oldLanguage;
  });

  Finder folder() => find.byKey(ValueKey('folder-open-$music'));
  Finder cover(Audio audio) =>
      find.byKey(ValueKey('folder-tree-cover-${audio.path}'));
  List<Audio> tracks(int count) => [
        for (var index = 0; index < count; index++)
          _ObservedAudio('Track ${index.toString().padLeft(5, '0')}',
              path: path.join(
                  music, 'Track ${index.toString().padLeft(5, '0')}.mp3')),
      ];

  Future<void> mount(WidgetTester tester,
      {required AudioArtworkLoader loadArtwork,
      FolderTreeSongSorter? sorter}) async {
    sizePlaylistFeature(tester, width: 760, height: 720);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows, useMaterial3: true),
        home: MotionPreferencesScope(
            preferences: const MotionPreferences(),
            child: AppEntranceScope(
                child: Scaffold(
                    body: FoldersPage(
                        dataDirectory: fixture,
                        playbackService: playback,
                        sortLargeFolder: sorter,
                        loadArtwork: loadArtwork))))));
    await tester.pumpAndSettle();
  }

  Future<void> toggle(WidgetTester tester) async {
    await tester.tapAt(tester.getTopLeft(folder()) + const Offset(70, 35));
    await tester.pump();
  }

  Future<void> sorted(WidgetTester tester) async {
    final loading =
        find.byKey(ValueKey('folder-tree-sorting-${folderTreePathId(music)}'));
    for (var attempt = 0;
        attempt < 300 && loading.evaluate().isNotEmpty;
        attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      // Snapshot batches yield with zero-duration fake-zone timers. A pump
      // without a duration flushes only microtasks, leaving the worker unstarted.
      await tester.pump(Duration.zero);
    }
    expect(loading, findsNothing, reason: 'The real sorter must finish.');
    await tester.pumpAndSettle();
  }

  widgetCase(
      'warm folder reopen reuses sorted songs and real thumbnail cache work',
      (tester) async {
    final songs = _ObservedSongs(tracks(1600).reversed.toList());
    AudioLibrary.instance.folders = [AudioFolder(songs, music, 1, 1)];
    final cacheDirectory = (await tester.runAsync(
        () => Directory(path.join(fixture.path, 'covers')).create()))!;
    final cache = CoverCache.forTesting(directory: cacheDirectory);
    final producers = <String, int>{};
    var loaderCalls = 0, sortCalls = 0;
    final recorder = raster.PictureRecorder();
    Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(4, 4);
    picture.dispose();
    final png = await tester
        .runAsync(() => image.toByteData(format: raster.ImageByteFormat.png));
    image.dispose();
    final bytes = png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
    await mount(tester, sorter: (source, field, direction) {
      sortCalls++;
      return sortFolderTreeSongs(source, field, direction);
    }, loadArtwork: (audio, size) {
      loaderCalls++;
      return cache.imageFor(
          audioPath: audio.localFilePath,
          modified: audio.modified,
          fingerprint: audio.coverFingerprint,
          width: size.width,
          height: size.height,
          produce: () async {
            producers.update(audio.path, (count) => count + 1,
                ifAbsent: () => 1);
            return bytes;
          });
    });
    expect(songs.reads, 0, reason: 'Opening a collapsed page must be lazy.');
    await toggle(tester);
    await sorted(tester);
    List<RawImage> mountedImages() => tester
        .widgetList<RawImage>(find.descendant(
            of: find.byType(AudioArtwork), matching: find.byType(RawImage)))
        .toList();
    bool allCoversDecoded() {
      final images = mountedImages();
      final artworks = find.byType(AudioArtwork).evaluate().length;
      return artworks > 0 &&
          images.length == artworks &&
          images.every((image) => image.image != null);
    }

    for (var attempt = 0; attempt < 300 && !allCoversDecoded(); attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(producers, isNotEmpty);
    expect(allCoversDecoded(), isTrue,
        reason:
            'Count reuse only after real cache files and image frames finish.');
    final firstSorted = tester
        .widget<FolderTreePane>(find.byType(FolderTreePane))
        .songsByFolder[folderTreePathId(music)];
    final readsAfterFirstSort = songs.reads;
    final produceCallsAfterFirst = producers.values.fold(0, (a, b) => a + b);
    final work = <Map<String, int>>[];
    for (var repeat = 0; repeat < 5; repeat++) {
      await toggle(tester);
      await tester.pumpAndSettle();
      final clock = Stopwatch()..start();
      final titlesBefore = _ObservedAudio.titleReads;
      final loadersBefore = loaderCalls;
      await toggle(tester);
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 300 && !allCoversDecoded(); attempt++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
      expect(allCoversDecoded(), isTrue,
          reason: 'Each reopened cover must resolve before counting reuse.');
      await tester.pumpAndSettle();
      clock.stop();
      work.add({
        'reopen': repeat,
        'driverWallMicroseconds': clock.elapsedMicroseconds,
        'uiTitleReads': _ObservedAudio.titleReads - titlesBefore,
        'loaderCalls': loaderCalls - loadersBefore,
        'originalSourceReadsSinceFirstSort': songs.reads - readsAfterFirstSort,
        'sortCalls': sortCalls,
        'decodedMountedImages': mountedImages().length,
        'activeCacheReads': cache.activeReadCount,
        'thumbnailProduceCalls': producers.values.fold(0, (a, b) => a + b),
      });
      expect(
          tester
              .widget<FolderTreePane>(find.byType(FolderTreePane))
              .songsByFolder[folderTreePathId(music)],
          same(firstSorted));
    }
    stdout.writeln('FOLDER_REOPEN_WORK ${jsonEncode(work)}');
    expect(sortCalls, 1);
    expect(songs.reads, readsAfterFirstSort);
    expect(producers.values.fold(0, (a, b) => a + b), produceCallsAfterFirst);
    expect(producers.values, everyElement(1));
    expect(cache.cachedProviderCount, producers.length,
        reason: 'This fixture must exercise persisted FileImage providers.');
    expect(await tester.runAsync(() => cacheDirectory.list().length),
        producers.length);
    expect(allCoversDecoded(), isTrue);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  widgetCase('cached decoded folder cover does not restart first-frame fade',
      (tester) async {
    final audio = tracks(1).single;
    AudioLibrary.instance.folders = [
      AudioFolder([audio], music, 1, 1)
    ];
    final recorder = raster.PictureRecorder();
    Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(4, 4);
    picture.dispose();
    final provider = _ObservedImage(image);
    addTearDown(() {
      PaintingBinding.instance.imageCache.evict(provider);
      image.dispose();
    });
    var loaderCalls = 0;
    await mount(tester, loadArtwork: (_, __) {
      loaderCalls++;
      return SynchronousFuture(provider);
    });
    await toggle(tester);
    await tester.pumpAndSettle();
    expect(provider.decodes, 1);
    expect(PaintingBinding.instance.imageCache.containsKey(provider), isTrue);
    await toggle(tester);
    await tester.pumpAndSettle();
    await toggle(tester);
    await tester.pump();
    final handoff = find.descendant(
        of: cover(audio), matching: find.byType(ArtworkHandoff));
    final fade = find.descendant(
        of: handoff,
        matching: find.byWidgetPredicate((widget) =>
            widget is FadeTransition &&
            widget.key is ValueKey &&
            (widget.key as ValueKey).value == provider));
    stdout.writeln('FOLDER_WARM_COVER_STATE ${jsonEncode({
          'loaderCalls': loaderCalls,
          'decodedFrames': provider.decodes,
          'cached': PaintingBinding.instance.imageCache.containsKey(provider),
          'coverCount': cover(audio).evaluate().length,
          'handoffCount': handoff.evaluate().length,
          'rawImages': find
              .descendant(of: handoff, matching: find.byType(RawImage))
              .evaluate()
              .length,
          'fadeKeyTypes': tester
              .widgetList<FadeTransition>(find.descendant(
                  of: handoff, matching: find.byType(FadeTransition)))
              .map((fade) => fade.key.runtimeType.toString())
              .toList(),
        })}');
    expect(cover(audio), findsOneWidget);
    expect(handoff, findsOneWidget);
    expect(fade, findsOneWidget);
    final opacity = tester.widget<FadeTransition>(fade).opacity.value;
    stdout.writeln('FOLDER_WARM_COVER ${jsonEncode({
          'loaderCalls': loaderCalls,
          'decodedFrames': provider.decodes,
          'artworkOpacity': opacity,
        })}');
    expect(provider.decodes, 1,
        reason: 'This must be a real image-cache hit, not a second decode.');
    expect(opacity, 1,
        reason: 'A hot decoded cover does not need another cold-cover fade. '
            'The containing tree item keeps its normal entrance.');
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  widgetCase('artwork-only library notification reuses completed folder sort',
      (tester) async {
    final songs = tracks(1600).reversed.toList();
    AudioLibrary.instance.folders = [AudioFolder(songs, music, 1, 1)];
    var sortCalls = 0;
    await mount(tester,
        loadArtwork: (_, __) async => null,
        sorter: (source, field, direction) {
          sortCalls++;
          return sortFolderTreeSongs(source, field, direction);
        });
    await toggle(tester);
    await sorted(tester);
    final before = tester.widget<FolderTreePane>(find.byType(FolderTreePane));
    final firstSorted = before.songsByFolder[folderTreePathId(music)];
    AudioLibrary.instance.publishArtworkChanges();
    await tester.pump();
    stdout.writeln('FOLDER_ARTWORK_REVISION ${jsonEncode({
          'sortCallsAfterArtworkNotification': sortCalls,
          'loadingRows': find
              .byKey(ValueKey('folder-tree-sorting-${folderTreePathId(music)}'))
              .evaluate()
              .length,
        })}');
    expect(sortCalls, 1,
        reason: 'Changing cover bytes does not change song-sort metadata.');
    expect(
        tester
            .widget<FolderTreePane>(find.byType(FolderTreePane))
            .songsByFolder[folderTreePathId(music)],
        same(firstSorted));
    expect(tester.takeException(), isNull);
  });

  for (final field in [AudioSortField.duration, AudioSortField.name]) {
    widgetCase('${field.name} metadata change refreshes completed folder sort',
        (tester) async {
      final songs = tracks(1600).reversed.toList();
      AudioLibrary.instance.folders = [AudioFolder(songs, music, 1, 1)];
      AppPreference.instance.folderDetailPagePref.sortMethod =
          audioSortMethods(AudioSortProfile.folder).indexWhere(
              (method) => (method as AudioSortMethodDesc).field == field);
      var sortCalls = 0;
      await mount(tester,
          loadArtwork: (_, __) async => null,
          sorter: (source, sortField, direction) {
            sortCalls++;
            return sortFolderTreeSongs(source, sortField, direction);
          });
      await toggle(tester);
      await sorted(tester);
      List<Audio> visibleOrder() => tester
          .widget<FolderTreePane>(find.byType(FolderTreePane))
          .songsByFolder[folderTreePathId(music)]!;
      final before = visibleOrder();
      final corrected =
          field == AudioSortField.duration ? songs.last : songs.first;
      expect(before.first, isNot(same(corrected)));
      if (field == AudioSortField.duration) {
        corrected.duration = 1;
        AudioLibrary.instance.publishDurationChanges();
      } else {
        corrected.title = 'A corrected song';
        // Local name sorting follows the committed filename, not its tag.
        corrected.path = path.join(music, 'A corrected song.mp3');
        AudioLibrary.instance.rebuildDerivedCollections();
      }
      await tester.pump();
      await sorted(tester);
      expect(sortCalls, 2);
      expect(visibleOrder(), isNot(same(before)));
      expect(visibleOrder().first, same(corrected));
      expect(tester.takeException(), isNull);
    });
  }
}
