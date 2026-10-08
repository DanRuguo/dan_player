import 'dart:async';
import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/category_cover_store.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/library/playback_bookmarks.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:dan_player/page/categories_page.dart';
import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/music_category_fixtures.dart';

class _Personal extends PersonalLibrary {
  _Personal(super.file);
  var reads = 0;
  @override
  Future<Map<String, PersonalTrack>> snapshot() {
    reads++;
    return super.snapshot();
  }
}

class _Bookmarks extends PlaybackBookmarkStore {
  _Bookmarks(super.file);
  var reads = 0;
  @override
  Future<List<PlaybackBookmark>> all() {
    reads++;
    return super.all();
  }
}

class _Covers extends CategoryCoverStore {
  _Covers(Directory directory) : super(dataDirectory: () async => directory);
  @override
  Future<void> load() async {}
  @override
  Future<void> reconcileKind(
      MusicCategoryKind kind, Iterable<MusicCategoryGroup> groups) async {}
}

class _HeldPersonal extends PersonalLibrary {
  _HeldPersonal(super.file);
  final result = Completer<Map<String, PersonalTrack>>();
  @override
  Future<Map<String, PersonalTrack>> snapshot() => result.future;
}

class _MemoryPersonal extends PersonalLibrary {
  _MemoryPersonal(super.file, this.data);
  final Map<String, PersonalTrack> data;
  @override
  Future<Map<String, PersonalTrack>> snapshot() async => Map.unmodifiable(data);
}

class _MemoryBookmarks extends PlaybackBookmarkStore {
  _MemoryBookmarks(super.file, this.items);
  final List<PlaybackBookmark> items;
  @override
  Future<List<PlaybackBookmark>> all() async => List.unmodifiable(items);
}

Widget _host(Widget child,
        {UiLanguage language = UiLanguage.zh,
        double scale = 1,
        Brightness brightness = Brightness.light,
        GlobalKey? boundary}) =>
    UiLanguageScope(
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: language.locale,
            supportedLocales:
                UiLanguage.values.map((language) => language.locale),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: applyAppControlTheme(ThemeData(
                platform: TargetPlatform.windows,
                fontFamily: AppFontPolicy.defaults(language: language).uiFamily,
                fontFamilyFallback: danFontFamilyFallback,
                colorScheme: ColorScheme.fromSeed(
                    seedColor: Colors.teal, brightness: brightness))),
            builder: (context, child) => RepaintBoundary(
                key: boundary,
                child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(scale),
                        disableAnimations: true),
                    child: AppFontScope(
                        policy: AppFontPolicy.defaults(language: language),
                        child: child!))),
            home: Scaffold(body: child)));

Future<void> _metadataFrames(WidgetTester tester) async {
  // The real serialized stores were opened outside the fake frame clock.
  // Let their finite metadata callbacks finish before settling the widgets.
  for (var i = 0; i < 5; i++) {
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }
  await tester.pumpAndSettle();
}

Future<void> _personal(WidgetTester tester) async {
  final chip = find.byKey(const ValueKey('category-kind-personal'));
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await _metadataFrames(tester);
}

Future<void> _capture(
    WidgetTester tester, GlobalKey boundary, String name) async {
  final directory = Platform.environment['DAN_PERSONAL_SUMMARY_RENDER_DIR'];
  if (directory == null) return;
  final qa = p.normalize(p.absolute('..', 'tool', 'qa-local'));
  expect(p.isWithin(qa, p.normalize(p.absolute(directory))), true);
  await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary)
        .toImage();
    try {
      final bytes = await image.toByteData(format: raster.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File(p.join(directory, '$name.png'))
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory fixture;
  late _Personal personal;
  late _Bookmarks bookmarks;
  late _Covers covers;
  late CategoryTestAudio a, b, c, stale;
  late List<Audio> audios;
  late List<AudioFolder> previousFolders;
  late List<Audio> previousOnline;
  late Map<String, PersonalTrack> previousPersonal;
  late UiLanguage previousLanguage;
  late Map<String, PersonalTrack> savedPersonal;
  late List<PlaybackBookmark> savedBookmarks;

  setUpAll(() async {
    await ensureAppFontsLoaded(AppFontPolicy.defaults());
    for (final font in [
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      )
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  setUp(() async {
    fixture = await Directory.systemTemp.createTemp('personal-summary-');
    final qa = p.normalize(p.absolute('..', 'tool', 'qa-local'));
    expect(p.isWithin(qa, fixture.absolute.path), true);
    await TrackIdentityRegistry.instance.initialize(directory: fixture);
    personal = _Personal(File(p.join(fixture.path, 'personal.json')));
    bookmarks = _Bookmarks(File(p.join(fixture.path, 'bookmarks.json')));
    covers = _Covers(fixture);
    a = CategoryTestAudio('Piano', path: p.join(fixture.path, 'a.mp3'));
    b = CategoryTestAudio('Guitar', path: p.join(fixture.path, 'b.mp3'));
    c = CategoryTestAudio('Unmarked', path: p.join(fixture.path, 'c.mp3'));
    stale =
        CategoryTestAudio('Removed', path: p.join(fixture.path, 'removed.mp3'));
    audios = [a, b, c, CategoryTestAudio('Duplicate', path: a.path)];
    previousFolders = AudioLibrary.instance.folders;
    previousOnline = AudioLibrary.instance.onlineAudioCollection;
    previousPersonal = PersonalLibrary.latest;
    previousLanguage = uiLanguage.value;
    uiLanguage.value = UiLanguage.zh;
    AudioLibrary.instance.folders = [AudioFolder(audios, fixture.path, 0, 0)];
    AudioLibrary.instance.onlineAudioCollection = [];
    AudioLibrary.instance.rebuildDerivedCollections();
    await personal.store.update((root) {
      root['tracks'] = {
        a.stableTrackId: {
          'rating': 5,
          'tags': ['Night', 'Piano']
        },
        b.stableTrackId: {
          'rating': 1,
          'tags': ['Night']
        },
        stale.stableTrackId: {
          'rating': 4,
          'tags': ['Outside']
        },
      };
    });
    for (final entry in [(a, 1.0), (a, 2.0), (b, 3.0), (stale, 4.0)]) {
      await bookmarks.add(
          localPath: entry.$1.path,
          stableTrackId: entry.$1.stableTrackId,
          label: 'Bookmark ${entry.$2}',
          position: entry.$2);
    }
    savedPersonal = await personal.snapshot();
    savedBookmarks = await bookmarks.all();
  });
  tearDown(() async {
    AudioLibrary.instance.folders = previousFolders;
    AudioLibrary.instance.onlineAudioCollection = previousOnline;
    AudioLibrary.instance.rebuildDerivedCollections();
    PersonalLibrary.latest = previousPersonal;
    uiLanguage.value = previousLanguage;
    covers.dispose();
    await fixture.delete(recursive: true);
  });

  Widget page(
          {List<Audio>? tracks,
          PersonalLibrary? store,
          PlaybackBookmarkStore? bookmarkStore,
          bool useLiveLibrary = false}) =>
      CategoriesPage(
          audios: useLiveLibrary ? null : tracks ?? audios,
          personalStore: store ?? personal,
          bookmarkStore: bookmarkStore ?? bookmarks,
          coverStore: covers);

  testWidgets('personal category summary includes all valid annotations once',
      (tester) async {
    await tester.pumpWidget(_host(page()));
    await tester.pumpAndSettle();
    await _personal(tester);
    expect(find.text(ui('共 {0} 首歌曲 · {1} 个标注', [4, 8])), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('projection counts ratings and per-track tags without stale identities',
      () {
    final online = CategoryTestAudio('Online', online: true);
    final records = {
      a.stableTrackId:
          const PersonalTrack(rating: 5, tags: ['Night', 'Night', 'Piano']),
      b.stableTrackId: const PersonalTrack(rating: 1, tags: ['Night']),
      c.stableTrackId: const PersonalTrack(rating: 6),
      online.stableTrackId: const PersonalTrack(rating: 3, tags: ['Jazz']),
      stale.stableTrackId: const PersonalTrack(rating: 5, tags: ['Ghost']),
    };
    final summary = PersonalOrganizationSummary.project(
        audios: [...audios, online],
        personal: records,
        bookmarks: [
          PlaybackBookmark(
              id: 'a1', track: a.stableTrackId, label: 'A1', positionMs: 1),
          PlaybackBookmark(
              id: 'a2', track: a.stableTrackId, label: 'A2', positionMs: 2),
          PlaybackBookmark(
              id: 'b1', track: b.stableTrackId, label: 'B1', positionMs: 3),
          PlaybackBookmark(
              id: 'a1',
              track: a.stableTrackId,
              label: 'Duplicate',
              positionMs: 1),
          PlaybackBookmark(
              id: 'gone',
              track: stale.stableTrackId,
              label: 'Gone',
              positionMs: 4),
        ]);
    expect(summary.ratingCounts, {1: 1, 2: 0, 3: 1, 4: 0, 5: 1});
    expect(summary.ratedTracks, 3);
    expect(summary.tagCounts, {'Night': 2, 'Piano': 1, 'Jazz': 1});
    expect(summary.tagAnnotations, 4);
    expect(summary.bookmarkCount, 3);
    expect(summary.totalAnnotations, 10);
    expect(() => summary.ratingCounts[1] = 9, throwsUnsupportedError);
    expect(() => summary.tagCounts.clear(), throwsUnsupportedError);
    records[a.stableTrackId] = const PersonalTrack(rating: 2, tags: ['New']);
    expect(summary.tagCounts, {'Night': 2, 'Piano': 1, 'Jazz': 1});
    expect(summary.ratingCounts[5], 1);
  });

  test('frozen track IDs and Audio projection share one detached distribution',
      () async {
    final records = await personal.snapshot();
    final items = await bookmarks.all();
    final ids =
        List<String>.unmodifiable(audios.map((audio) => audio.stableTrackId));
    final projected = PersonalOrganizationSummary.project(
        audios: audios, personal: records, bookmarks: items);
    audios.clear();
    final frozen = PersonalOrganizationSummary.fromTrackIds(
        trackIds: ids, personal: records);
    expect(frozen.ratingCounts, projected.ratingCounts);
    expect(frozen.tagCounts, projected.tagCounts);
    expect(frozen.ratedTracks, 2);
    expect(frozen.tagAnnotations, 3);
    expect(frozen.bookmarkCount, 0);
    expect(frozen.totalAnnotations, 5);
    expect(projected.bookmarkCount, 3);
    expect(projected.totalAnnotations, 8);
  });

  test('legacy bookmark aliases must resolve to a unique current-library ID',
      () {
    final identities = TrackIdentityRegistry.inMemory();
    final oldPath = p.join(fixture.path, 'before.mp3');
    final newPath = p.join(fixture.path, 'after.mp3');
    final id = identities.idFor(oldPath);
    identities.remapPaths((path) => path == oldPath ? newPath : path);
    final items = [
      for (var i = 0; i < 2; i++)
        PlaybackBookmark(
            id: 'legacy-$i',
            track: PlaybackBookmarkStore.trackKey(oldPath),
            label: 'Legacy $i',
            positionMs: i * 1000),
      PlaybackBookmark(
          id: 'stable', track: id, label: 'Stable', positionMs: 3000),
      const PlaybackBookmark(
          id: 'outside',
          track: 'D:/unknown-file.mp3',
          label: 'Outside',
          positionMs: 1),
    ];
    PersonalOrganizationSummary summary() =>
        PersonalOrganizationSummary.fromTrackIds(
            trackIds: [id, id],
            personal: const {},
            bookmarks: items,
            identities: identities);
    expect(summary().bookmarkCount, 3);
    final replacement = identities.idFor(oldPath);
    expect(replacement, isNot(id));
    expect(identities.resolvePath(oldPath), isNull);
    expect(summary().bookmarkCount, 1,
        reason: 'A reused path must not attach old bookmarks to either song.');
  });

  test('unmarked current songs do not inherit removed tracks annotations', () {
    final summary = PersonalOrganizationSummary.fromTrackIds(trackIds: [
      c.stableTrackId
    ], personal: {
      stale.stableTrackId: const PersonalTrack(rating: 4, tags: ['Gone'])
    });
    expect(summary.ratingCounts, {1: 0, 2: 0, 3: 0, 4: 0, 5: 0});
    expect(summary.tagCounts, isEmpty);
    expect(summary.totalAnnotations, 0);
  });

  testWidgets(
      'rating and tag filters retain the library total without rereading',
      (tester) async {
    await tester.pumpWidget(_host(page()));
    await tester.pumpAndSettle();
    await _personal(tester);
    final previousReads = (personal.reads, bookmarks.reads);
    await tester.tap(find.byKey(const ValueKey('personal-rating-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('personal-rating-5')));
    await tester.pumpAndSettle();
    final field = find
        .descendant(
            of: find.byType(CategoriesPage), matching: find.byType(TextField))
        .first;
    await tester.enterText(field, 'No matching tag');
    await tester.pumpAndSettle();
    expect(find.text(ui('共 {0} 首歌曲 · {1} 个标注', [4, 8])), findsOneWidget);
    expect((personal.reads, bookmarks.reads), previousReads);
    uiLanguage.value = UiLanguage.en;
    await tester.pumpWidget(
        _host(page(), language: UiLanguage.en, brightness: Brightness.dark));
    await tester.pumpAndSettle();
    expect(find.text(ui('共 {0} 首歌曲 · {1} 个标注', [4, 8])), findsOneWidget);
    expect((personal.reads, bookmarks.reads), previousReads,
        reason:
            'Theme, locale and local filters only format the cached summary.');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'saved annotation changes and live library removals refresh totals',
      (tester) async {
    final viewPersonal = _MemoryPersonal(
        File(p.join(fixture.path, 'memory-personal.json')),
        Map.of(savedPersonal));
    final viewBookmarks = _MemoryBookmarks(
        File(p.join(fixture.path, 'memory-bookmarks.json')),
        List.of(savedBookmarks));
    await tester.pumpWidget(_host(page(
        useLiveLibrary: true,
        store: viewPersonal,
        bookmarkStore: viewBookmarks)));
    await tester.pumpAndSettle();
    await _personal(tester);
    Future<void> expectCount(int count, {int songs = 4}) async {
      await _metadataFrames(tester);
      expect(
          find.text(ui('共 {0} 首歌曲 · {1} 个标注', [songs, count])), findsOneWidget);
    }

    viewPersonal.data[a.stableTrackId] = const PersonalTrack(tags: ['Night']);
    PersonalLibrary.changes.value++;
    await expectCount(6);
    viewBookmarks.items.add(PlaybackBookmark(
        id: 'new', track: c.stableTrackId, label: 'New', positionMs: 5000));
    PlaybackBookmarkStore.changes.value++;
    await expectCount(7);
    viewPersonal.data[b.stableTrackId] = const PersonalTrack(rating: 1);
    PersonalLibrary.changes.value++;
    await expectCount(6);
    final first =
        viewBookmarks.items.firstWhere((item) => item.track == a.stableTrackId);
    viewBookmarks.items.removeWhere((item) => item.id == first.id);
    PlaybackBookmarkStore.changes.value++;
    await expectCount(5);
    AudioLibrary.instance.folders = [
      AudioFolder([a, c, audios.last], fixture.path, 0, 0)
    ];
    AudioLibrary.instance.rebuildDerivedCollections();
    await expectCount(3, songs: 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('actual persisted edits publish the same annotation totals', () async {
    Future<int> total() async => PersonalOrganizationSummary.project(
            audios: audios,
            personal: await personal.snapshot(),
            bookmarks: await bookmarks.all())
        .totalAnnotations;
    expect(await total(), 8);
    await personal.apply([a, audios.last],
        changeRating: true,
        rating: null,
        changeTags: true,
        removeTags: ['Piano']);
    expect(await total(), 6);
    await bookmarks.add(
        localPath: c.path,
        stableTrackId: c.stableTrackId,
        label: 'New',
        position: 5);
    expect(await total(), 7);
    await personal.apply([b], changeTags: true, removeTags: ['Night']);
    expect(await total(), 6);
    final first = (await bookmarks.all())
        .firstWhere((item) => item.track == a.stableTrackId);
    await bookmarks.remove(first.id);
    expect(await total(), 5);
    expect(await personal.store.file.exists(), true);
    expect(await bookmarks.file.exists(), true);
  });

  testWidgets('a replaced personal store cannot publish its late summary',
      (tester) async {
    final held = _HeldPersonal(File(p.join(fixture.path, 'held.json')));
    await tester.pumpWidget(_host(page(store: held)));
    await tester.pumpAndSettle();
    final chip = find.byKey(const ValueKey('category-kind-personal'));
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();
    expect(find.text(ui('共 {0} 首歌曲', [4])), findsOneWidget);
    await tester.pumpWidget(_host(page()));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(find.text(ui('共 {0} 首歌曲 · {1} 个标注', [4, 8])), findsOneWidget);
    held.result.complete({a.stableTrackId: const PersonalTrack(rating: 1)});
    await tester.pumpAndSettle();
    expect(find.text(ui('共 {0} 首歌曲 · {1} 个标注', [4, 8])), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final language in UiLanguage.values) {
    for (final width in [360.0, 1100.0]) {
      testWidgets(
          'personal total is complete ${language.name} width=$width large text',
          (tester) async {
        uiLanguage.value = language;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundary = GlobalKey();
        await tester.pumpWidget(
            _host(page(), language: language, scale: 2, boundary: boundary));
        await tester.pumpAndSettle();
        await _personal(tester);
        final label = ui('共 {0} 首歌曲 · {1} 个标注', [4, 8]);
        final finder = find.text(label);
        expect(finder, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(finder);
        await _capture(
            tester, boundary, '${language.name}-${width.toInt()}-2x');
        expect(paragraph.didExceedMaxLines, isFalse,
            reason: '$label ${paragraph.size} '
                'maxLines=${paragraph.maxLines} overflow=${paragraph.overflow}');
        final boxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: label.length));
        expect(boxes, isNotEmpty);
        final bounds = tester.getRect(finder);
        for (final box in boxes) {
          final rect = box.toRect().shift(paragraph.localToGlobal(Offset.zero));
          expect(rect.left, greaterThanOrEqualTo(bounds.left - 1));
          expect(rect.right, lessThanOrEqualTo(bounds.right + 1));
          expect(rect.bottom, lessThanOrEqualTo(bounds.bottom + 1));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
