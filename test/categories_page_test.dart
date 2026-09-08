import 'dart:async';

import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/component/side_nav.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/page/album_detail_page.dart';
import 'package:dan_player/page/albums_page.dart';
import 'package:dan_player/page/artist_detail_page.dart';
import 'package:dan_player/page/artists_page.dart';
import 'package:dan_player/page/categories_page.dart';
import 'package:dan_player/page/category_detail_page.dart';
import 'package:dan_player/page/playlists_page.dart';
import 'package:dan_player/page/uni_detail_page.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/music_category_fixtures.dart';

void _viewport(WidgetTester tester,
    {double width = 1000, double height = 700}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _host(Widget child,
        {double scale = 1, Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: ThemeData(
        platform: TargetPlatform.windows,
        visualDensity: VisualDensity.compact,
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal, brightness: brightness),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale), disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(body: child),
    );

void _library(List<Audio> audios) {
  final library = AudioLibrary.instance;
  library.folders = [
    AudioFolder(audios.where((audio) => audio.isLocal).toList(),
        'D:/category-test-fixtures', 0, 0),
  ];
  library.onlineAudioCollection =
      audios.where((audio) => audio.isOnline).toList();
  library.rebuildDerivedCollections();
}

Future<void> _choose(WidgetTester tester, MusicCategoryKind kind) async {
  final target = find.byKey(ValueKey('category-kind-${kind.name}'));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Finder _audioTile(Audio audio) => find.byWidgetPredicate((widget) =>
    widget is AudioTile &&
    identical(widget.playlist[widget.audioIndex], audio));

Future<void> _rightClick(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  final pointer = await tester.startGesture(tester.getCenter(target),
      kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
  await pointer.up();
  await tester.pumpAndSettle();
}

Widget _track(BuildContext context, Audio audio, VoidCallback play) =>
    TextButton(
      key: ValueKey(('track', audio.path)),
      onPressed: play,
      child: Text(audio.displayTitle),
    );

/// Reuse the production page definitions while omitting AppShell/Startup/BASS.
GoRouter _productionPages(String location, {List<GoRoute> extra = const []}) {
  final source = Entry(welcome: true).config;
  addTearDown(source.dispose);
  final shell = source.configuration.routes.whereType<ShellRoute>().single;
  final router =
      GoRouter(initialLocation: location, routes: [...extra, ...shell.routes]);
  addTearDown(router.dispose);
  return router;
}

Widget _routerHost(GoRouter router) => MaterialApp.router(
      routerConfig: router,
      theme: ThemeData(platform: TargetPlatform.windows),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: Scaffold(body: child),
      ),
    );

void main() {
  late List<AudioFolder> previousFolders;
  late List<Audio> previousOnline;
  late int previousStartPage;

  setUp(() {
    previousFolders = AudioLibrary.instance.folders;
    previousOnline = AudioLibrary.instance.onlineAudioCollection;
    previousStartPage = AppPreference.instance.startPage;
    _library([]);
  });

  tearDown(() {
    AudioLibrary.instance.folders = previousFolders;
    AudioLibrary.instance.onlineAudioCollection = previousOnline;
    AudioLibrary.instance.rebuildDerivedCollections();
    AppPreference.instance.startPage = previousStartPage;
    expect(PlayService.isInitialized, isFalse);
  });

  testWidgets('album cover action follows theme and shared toolbar geometry',
      (tester) async {
    _viewport(tester, width: 1400);
    final audio = CategoryTestAudio('Cover theme', album: 'Demo album');
    _library([audio]);
    final group =
        MusicCategories([audio]).groups(MusicCategoryKind.album).single;
    final page = AlbumDetailPage.group(groupId: group.id, initialGroup: group);
    for (final seed in [Colors.teal, Colors.deepOrange]) {
      for (final brightness in Brightness.values) {
        final theme = Entry(welcome: false).fromSchemeAndFontFamily(
            colorScheme:
                ColorScheme.fromSeed(seedColor: seed, brightness: brightness));
        await tester
            .pumpWidget(MaterialApp(theme: theme, home: Scaffold(body: page)));
        await tester.pumpAndSettle();
        final action = find.byWidgetPredicate((widget) =>
            widget is IconButton && widget.tooltip == '重新读取封面');
        final button = tester.widget<IconButton>(action);
        final scheme = theme.colorScheme;
        expect(button.style!.foregroundColor!.resolve({}), scheme.primary);
        expect(button.style!.side!.resolve({})!.color,
            scheme.outlineVariant.withValues(alpha: .7));
        expect(button.style!.backgroundColor!.resolve({}), Colors.transparent);
        expect(tester.getSize(action).height,
            appToolbarControlHeight(tester.element(action)));
        final material = tester.widget<Material>(
            find.descendant(of: action, matching: find.byType(Material)).first);
        expect(material.color, Colors.transparent);
        expect(tester.takeException(), isNull);
      }
    }
  });

  for (final width in [1000.0, 1440.0]) {
    testWidgets('desktop page exposes seven single-row chips at width $width',
        (tester) async {
      _viewport(tester, width: width);
      await tester.pumpWidget(_host(const CategoriesPage(audios: [])));
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNWidgets(8));
      expect(
          find.byKey(const ValueKey('category-kind-composer')), findsNothing);
      expect(
          find.byKey(const ValueKey('category-kind-bitrate')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('category-kind-duration')), findsOneWidget);
      expect(find.byKey(const ValueKey('category-kind-menu')), findsNothing);
      final artist = find.byKey(const ValueKey('category-kind-artist'));
      final top = tester.getTopLeft(artist).dy;
      for (final kind in MusicCategoryKind.browsableValues) {
        final chip = find.byKey(ValueKey('category-kind-${kind.name}'));
        expect(chip, findsOneWidget);
        expect(tester.getTopLeft(chip).dy, closeTo(top, .01));
        expect(tester.getSize(chip).height, greaterThanOrEqualTo(44));
      }
      final rail =
          tester.getRect(find.byKey(const ValueKey('category-kind-scroll')));
      expect(rail.left, greaterThan(tester.getRect(find.text('分类')).right));
      expect(rail.top, lessThan(tester.getRect(find.text('分类')).bottom));
      expect(find.textContaining('总乐库还没有歌曲'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'narrow category rail scrolls horizontally and supports keyboard selection',
      (tester) async {
    _viewport(tester, width: 320);
    await tester.pumpWidget(_host(const CategoriesPage(audios: [])));
    await tester.pumpAndSettle();
    final rail = find.byKey(const ValueKey('category-kind-scroll'));
    final source = find.byKey(const ValueKey('category-kind-source'));
    expect(source.hitTestable(), findsNothing);
    await tester.drag(rail, const Offset(-900, 0));
    await tester.pumpAndSettle();
    expect(source.hitTestable(), findsOneWidget);
    await tester.tap(source);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(source).selected, isTrue);
    await _choose(tester, MusicCategoryKind.artist);
    final artistLabel = find.descendant(
        of: find.byKey(const ValueKey('category-kind-artist')),
        matching: find.text('艺术家'));
    Focus.of(tester.element(artistLabel)).requestFocus();
    await tester.pump();
    for (var i = 0; i < MusicCategoryKind.browsableValues.length - 1; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(source).selected, isTrue);
    expect(source.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'category switching, owner search and selection preserve original songs',
      (tester) async {
    _viewport(tester);
    final a = CategoryTestAudio('a',
        album: 'Same', albumArtist: 'Owner A', composer: 'Writer');
    final b = CategoryTestAudio('b',
        album: 'Same', albumArtist: 'Owner B', composer: 'Writer');
    MusicCategoryGroup? opened;
    await tester.pumpWidget(_host(CategoriesPage(
        audios: [a, b],
        classificationScanner:
            MusicClassificationScanner(readLyrics: (_) async => null),
        onOpenGroup: (group) => opened = group)));
    await tester.pumpAndSettle();
    await _choose(tester, MusicCategoryKind.album);
    expect(find.text('Owner A'), findsOneWidget);
    expect(find.text('Owner B'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('category-search')), 'Owner B');
    await tester.pumpAndSettle();
    expect(find.text('Owner A'), findsNothing);
    await tester.tap(find.descendant(
        of: find.byType(CustomScrollView), matching: find.text('Owner B')));
    expect(opened!.audios, [same(b)]);
    await _choose(tester, MusicCategoryKind.bitrate);
    expect(find.text('257–320 kbps'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('category-search')))
            .controller!
            .text,
        isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'simple kinds use tags and provenance and describe unknown formats',
      (tester) async {
    _viewport(tester);
    final local = CategoryTestAudio('さくら',
        language: 'zh', path: 'D:/category-test-fixtures/song.flac');
    final online = CategoryTestAudio('English title',
        online: true, bitrate: null, duration: 0);
    await tester.pumpWidget(_host(CategoriesPage(
      audios: [local, online],
      classificationScanner:
          MusicClassificationScanner(readLyrics: (_) async => null),
    )));
    await tester.pumpAndSettle();
    await _choose(tester, MusicCategoryKind.language);
    expect(find.text('中文'), findsOneWidget);
    expect(find.text('英文'), findsOneWidget);
    expect(find.text('日文'), findsNothing);
    expect(find.textContaining('语言优先使用标签'), findsOneWidget);
    expect(find.text('标签 1'), findsOneWidget);
    expect(find.text('推断 1'), findsOneWidget);
    await _choose(tester, MusicCategoryKind.bitrate);
    expect(find.text('257–320 kbps'), findsOneWidget);
    expect(find.text('未知码率'), findsOneWidget);
    expect(find.textContaining('码率按音频索引'), findsOneWidget);
    await _choose(tester, MusicCategoryKind.duration);
    expect(find.text('2–4 分钟'), findsOneWidget);
    expect(find.text('未知时长'), findsOneWidget);
    expect(find.textContaining('时长按歌曲总时长'), findsOneWidget);
    await _choose(tester, MusicCategoryKind.format);
    expect(find.text('FLAC'), findsOneWidget);
    expect(find.text('未知格式'), findsOneWidget);
    await _choose(tester, MusicCategoryKind.source);
    expect(find.text('本地'), findsOneWidget);
    expect(find.text('联网'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'language evidence is retained when switching to a simple category',
      (tester) async {
    _viewport(tester);
    final audio = CategoryTestAudio('Unclassified');
    var reads = 0;
    final scanner = MusicClassificationScanner(readLyrics: (_) async {
      reads++;
      return '[language:ja]\n[00:00]作曲：Lyric Writer\n[00:01]さくらさくら';
    });
    MusicCategoryGroup? opened;
    await tester.pumpWidget(_host(CategoriesPage(
      initialCategory: MusicCategoryKind.language,
      audios: [audio],
      classificationScanner: scanner,
      onOpenGroup: (group) => opened = group,
    )));
    await tester.pumpAndSettle();
    expect(find.text('日文'), findsOneWidget);
    expect(find.text('歌词 1'), findsOneWidget);
    await _choose(tester, MusicCategoryKind.bitrate);
    expect(find.text('257–320 kbps'), findsOneWidget);
    await tester.tap(find.text('257–320 kbps'));
    expect(opened!.audios.single, same(audio));
    expect(opened!.evidenceCounts, isEmpty);
    expect(reads, 1,
        reason: 'switching kinds reuses the same read-only snapshot');
    expect(audio.language, isNull);
    expect(audio.composer, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'duration notification retains language evidence without a rescan',
      (tester) async {
    _viewport(tester);
    final audio = CategoryTestAudio('Duration update');
    var reads = 0;
    final scanner = MusicClassificationScanner(readLyrics: (_) async {
      reads++;
      return '[language:ja]\n[00:00]さくらさくら';
    });
    await tester.pumpWidget(_host(CategoriesPage(
      initialCategory: MusicCategoryKind.language,
      audios: [audio],
      classificationScanner: scanner,
    )));
    await tester.pumpAndSettle();
    expect(find.text('日文'), findsOneWidget);
    expect(reads, 1);

    audio.duration++;
    AudioLibrary.instance.publishDurationChanges();
    await tester.pumpAndSettle();

    expect(find.text('日文'), findsOneWidget);
    expect(reads, 1,
        reason: 'duration-only changes reuse the classification snapshot');
    expect(tester.takeException(), isNull);
  });

  testWidgets('duration notification moves a visible duration category',
      (tester) async {
    _viewport(tester);
    final audio = CategoryTestAudio('Duration bucket', duration: 60);
    await tester.pumpWidget(_host(CategoriesPage(
      initialCategory: MusicCategoryKind.duration,
      audios: [audio],
    )));
    await tester.pumpAndSettle();
    expect(find.text('少于 2 分钟'), findsOneWidget);

    audio.duration = 360;
    AudioLibrary.instance.publishDurationChanges();
    await tester.pumpAndSettle();

    expect(find.text('少于 2 分钟'), findsNothing);
    expect(find.text('5–9 分钟'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('equivalent category page rebuild retains classification scan',
      (tester) async {
    _viewport(tester);
    final audios = [CategoryTestAudio('Stable category rebuild')];
    var reads = 0;
    final scanner = MusicClassificationScanner(readLyrics: (_) async {
      reads++;
      return '[language:ja]\n[00:00]さくらさくら';
    });
    Widget page() => _host(CategoriesPage(
          initialCategory: MusicCategoryKind.language,
          audios: audios,
          classificationScanner: scanner,
        ));

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('日文'), findsOneWidget);
    expect(reads, 1);

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('日文'), findsOneWidget);
    expect(reads, 1,
        reason: 'an equivalent parent rebuild must not restart lyric I/O');
    expect(tester.takeException(), isNull);
  });

  testWidgets('equivalent category detail rebuild retains classification scan',
      (tester) async {
    _viewport(tester);
    final audios = [CategoryTestAudio('Stable detail rebuild')];
    var reads = 0;
    final scanner = MusicClassificationScanner(readLyrics: (_) async {
      reads++;
      return '[language:ja]\n[00:00]さくらさくら';
    });
    Widget page() => _host(CategoryDetailPage(
          kind: MusicCategoryKind.language,
          groupId: '["language","japanese"]',
          audios: audios,
          classificationScanner: scanner,
          trackBuilder: _track,
        ));

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('日文'), findsOneWidget);
    expect(reads, 1);

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('日文'), findsOneWidget);
    expect(reads, 1,
        reason: 'an equivalent parent rebuild must not restart lyric I/O');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'broad composer groups label contributing artist fallback explicitly',
      (tester) async {
    _viewport(tester);
    final audio = CategoryTestAudio('Song', artist: 'Contributing Artist');
    await tester.pumpWidget(_host(CategoriesPage(
      initialCategory: MusicCategoryKind.composer,
      audios: [audio],
      classificationScanner:
          MusicClassificationScanner(readLyrics: (_) async => null),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Contributing Artist'), findsOneWidget);
    expect(find.text('艺术家回退 1'), findsOneWidget);
    expect(find.textContaining('作曲家采用宽口径'), findsOneWidget);
    expect(audio.composer, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new page data ignores a late classification result',
      (tester) async {
    _viewport(tester);
    final oldAudio = CategoryTestAudio('Old');
    final currentAudio = CategoryTestAudio('Current');
    final oldRead = Completer<String?>();
    final currentRead = Completer<String?>();
    final scanner = MusicClassificationScanner(
        readLyrics: (path) =>
            path == oldAudio.path ? oldRead.future : currentRead.future);
    Widget page(Audio audio) => _host(CategoriesPage(
          initialCategory: MusicCategoryKind.composer,
          audios: [audio],
          classificationScanner: scanner,
        ));
    await tester.pumpWidget(page(oldAudio));
    await tester.pumpWidget(page(currentAudio));
    currentRead.complete('[00:00]作曲：Current Writer');
    await tester.pumpAndSettle();
    expect(find.text('Current Writer'), findsOneWidget);
    oldRead.complete('[00:00]作曲：Stale Writer');
    await tester.pumpAndSettle();
    expect(find.text('Current Writer'), findsOneWidget);
    expect(find.text('Stale Writer'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('library refresh rereads lyric evidence without mutating tags',
      (tester) async {
    _viewport(tester);
    final audio = CategoryTestAudio('Song');
    var lyric = '[00:00]作曲：Before';
    final scanner = MusicClassificationScanner(readLyrics: (_) async => lyric);
    await tester.pumpWidget(_host(CategoriesPage(
      initialCategory: MusicCategoryKind.composer,
      audios: [audio],
      classificationScanner: scanner,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Before'), findsOneWidget);
    lyric = '[00:00]作曲：After';
    AudioLibrary.instance.rebuildDerivedCollections();
    await tester.pumpAndSettle();
    expect(find.text('Before'), findsNothing);
    expect(find.text('After'), findsOneWidget);
    expect(audio.composer, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'derived composer deep link resolves after local evidence is read',
      (tester) async {
    _viewport(tester);
    final audio = CategoryTestAudio('Composer song');
    const lyric = '[00:00]作曲：Deep Link Writer';
    final snapshot =
        await MusicClassificationScanner(readLyrics: (_) async => lyric)
            .scan([audio]);
    final group = MusicCategories([audio], classifications: snapshot)
        .groups(MusicCategoryKind.composer)
        .single;
    final pending = Completer<String?>();
    await tester.pumpWidget(_host(CategoryDetailPage(
      kind: group.kind,
      groupId: group.id,
      audios: [audio],
      classificationScanner:
          MusicClassificationScanner(readLyrics: (_) => pending.future),
      trackBuilder: _track,
    )));
    await tester.pump();
    expect(find.textContaining('正在只读检查'), findsOneWidget);
    expect(find.textContaining('此分类已不存在'), findsNothing);
    pending.complete(lyric);
    await tester.pumpAndSettle();
    expect(find.text('Deep Link Writer'), findsOneWidget);
    expect(find.text('分类依据：歌词 1'), findsOneWidget);
    expect(find.byKey(ValueKey(('track', audio.path))), findsOneWidget);
    expect(audio.composer, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'changed lyric evidence does not resurrect the old detail navigation group',
      (tester) async {
    _viewport(tester);
    final audio = CategoryTestAudio('Song');
    _library([audio]);
    var lyric = '[00:00]作曲：Before';
    final scanner = MusicClassificationScanner(readLyrics: (_) async => lyric);
    final snapshot = await scanner.scan([audio]);
    final group = MusicCategories([audio], classifications: snapshot)
        .groups(MusicCategoryKind.composer)
        .single;
    await tester.pumpWidget(_host(CategoryDetailPage(
      kind: group.kind,
      groupId: group.id,
      initialGroup: group,
      classificationScanner: scanner,
      trackBuilder: _track,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Before'), findsOneWidget);
    lyric = '[00:00]作曲：After';
    AudioLibrary.instance.rebuildDerivedCollections();
    await tester.pumpAndSettle();
    expect(find.text('Before'), findsNothing);
    expect(find.textContaining('此分类已不存在或标签已更新'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 440.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'single-row chips retain a scrolling list at $width/507, 200% text, $brightness',
          (tester) async {
        _viewport(tester, width: width, height: 507);
        final pending = CategoryTestAudio('未读',
            artist: '', duration: 0, classificationVersion: 0);
        await tester.pumpWidget(_host(
            CategoriesPage(
              initialCategory: MusicCategoryKind.duration,
              audios: [pending],
              classificationScanner:
                  MusicClassificationScanner(readLyrics: (_) async => null),
            ),
            scale: 2,
            brightness: brightness));
        await tester.pumpAndSettle();
        expect(find.byType(ChoiceChip), findsNWidgets(8));
        expect(find.byKey(const ValueKey('category-kind-menu')), findsNothing);
        final selector = find.byKey(const ValueKey('category-kind-scroll'));
        expect(tester.getSize(selector).height, greaterThanOrEqualTo(44));
        final duration = find.byKey(const ValueKey('category-kind-duration'));
        expect(tester.getRect(duration).overlaps(tester.getRect(selector)),
            isTrue);
        final top = tester.getTopLeft(duration).dy;
        for (final kind in MusicCategoryKind.browsableValues) {
          final chip = find.byKey(ValueKey('category-kind-${kind.name}'));
          expect(tester.getTopLeft(chip).dy, closeTo(top, .01));
        }
        final list = find.byType(CustomScrollView);
        expect(tester.getSize(list).height, greaterThanOrEqualTo(96));
        expect(find.textContaining('缺失或无效值'), findsOneWidget);
        // Large text can place the first group beyond lazy-list cache extent.
        // Scroll the real viewport until it is built, then assert visibility.
        await tester.scrollUntilVisible(find.text('未知时长'), 120,
            scrollable: find
                .descendant(of: list, matching: find.byType(Scrollable))
                .first);
        await tester.pumpAndSettle();
        expect(tester.getRect(find.text('未知时长')).overlaps(tester.getRect(list)),
            isTrue);
        await _choose(tester, MusicCategoryKind.format);
        expect(find.text('MP3'), findsOneWidget);
        // Every category remains available without opening any overflow menu.
        for (final kind in MusicCategoryKind.browsableValues) {
          await _choose(tester, kind);
          final chip = find.byKey(ValueKey('category-kind-${kind.name}'));
          expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
          expect(
              tester.getRect(chip).overlaps(tester.getRect(selector)), isTrue);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('library revision refreshes live grouping after metadata changes',
      (tester) async {
    _viewport(tester);
    final audio = CategoryTestAudio('a', composer: 'Before');
    _library([audio]);
    await tester.pumpWidget(_host(CategoriesPage(
        initialCategory: MusicCategoryKind.composer,
        classificationScanner:
            MusicClassificationScanner(readLyrics: (_) async => null))));
    await tester.pumpAndSettle();
    expect(find.text('Before'), findsOneWidget);
    audio.composer = 'After';
    AudioLibrary.instance.rebuildDerivedCollections();
    await tester.pumpAndSettle();
    expect(find.text('Before'), findsNothing);
    expect(find.text('After'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'detail sorting, filtering, play and add keep an immutable source queue',
      (tester) async {
    _viewport(tester);
    final first = CategoryTestAudio('Zeta', track: 2);
    final second = CategoryTestAudio('Alpha', track: 1);
    final remote = CategoryTestAudio('Remote', track: 3, online: true);
    final songs = [first, second, remote];
    final group = MusicCategories(songs).groups(MusicCategoryKind.album).single;
    int? index;
    List<Audio>? played;
    List<Audio>? added;
    await tester.pumpWidget(_host(CategoryDetailPage(
      kind: group.kind,
      groupId: group.id,
      audios: songs,
      trackBuilder: _track,
      onPlay: (value, queue) {
        index = value;
        played = queue;
      },
      onAddToPlaylist: (queue) => added = queue,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(('track', second.path))));
    expect(index, 0);
    expect(played, [same(second), same(first), same(remote)]);
    await tester.tap(find.byKey(const ValueKey('category-add-playlist')));
    expect(added, [same(second), same(first), same(remote)]);
    await tester.tap(find.byKey(const ValueKey('category-track-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category-sort-title')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(('track', second.path))));
    expect(played, [same(second), same(remote), same(first)]);
    await tester.enterText(
        find.byKey(const ValueKey('category-track-search')), 'Remote');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(('track', remote.path))));
    expect(index, 0);
    expect(played, [same(remote)]);
    expect(songs, [same(first), same(second), same(remote)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty detail searches are explicit and disable bulk actions',
      (tester) async {
    _viewport(tester);
    final audio = CategoryTestAudio('a');
    final group =
        MusicCategories([audio]).groups(MusicCategoryKind.artist).single;
    await tester.pumpWidget(_host(CategoryDetailPage(
        kind: group.kind,
        groupId: group.id,
        audios: [audio],
        trackBuilder: _track)));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('category-track-search')), 'not present');
    await tester.pumpAndSettle();
    expect(find.text('此分类中未找到匹配的歌曲'), findsOneWidget);
    expect(find.byKey(const ValueKey('playback-mode-shuffle')), findsOneWidget);
    expect(find.byKey(const ValueKey('playback-mode-repeat')), findsOneWidget);
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('category-add-playlist')))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'detail button and sort painted heights agree with compact desktop theme at $scale text',
        (tester) async {
      _viewport(tester, width: 440, height: 507);
      final audio = CategoryTestAudio('a', composer: 'Writer');
      final group =
          MusicCategories([audio]).groups(MusicCategoryKind.composer).single;
      await tester.pumpWidget(_host(
          CategoryDetailPage(
              kind: group.kind,
              groupId: group.id,
              audios: [audio],
              classificationScanner:
                  MusicClassificationScanner(readLyrics: (_) async => null),
              trackBuilder: _track),
          scale: scale));
      await tester.pumpAndSettle();
      final play = find.byKey(const ValueKey('playback-mode-shuffle'));
      final add = find.byKey(const ValueKey('category-add-playlist'));
      final sort = find.byKey(const ValueKey('category-track-sort'));
      final height = tester.getSize(play).height;
      expect(height, greaterThanOrEqualTo(44));
      expect(tester.getSize(add).height, closeTo(height, .01));
      expect(tester.getSize(sort).height, closeTo(height, .01));
      expect(tester.widget<IconButton>(play).style!.visualDensity,
          VisualDensity.standard);
      expect(tester.widget<OutlinedButton>(add).style!.visualDensity,
          VisualDensity.standard);
      expect(tester.getSize(find.byType(ListView)).height, greaterThan(80));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('deleted live groups do not resurrect their navigation snapshots',
      (tester) async {
    _viewport(tester);
    final audio = CategoryTestAudio('a');
    _library([audio]);
    final group =
        MusicCategories([audio]).groups(MusicCategoryKind.artist).single;
    await tester.pumpWidget(_host(CategoryDetailPage(
        kind: group.kind,
        groupId: group.id,
        initialGroup: group,
        trackBuilder: _track)));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey(('track', audio.path))), findsOneWidget);
    _library([]);
    await tester.pumpAndSettle();
    expect(find.textContaining('此分类已不存在或标签已更新'), findsOneWidget);
    expect(find.byKey(ValueKey(('track', audio.path))), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'real category AudioTiles retain local and online menu capabilities',
      (tester) async {
    _viewport(tester);
    final local = CategoryTestAudio('Local');
    final remote = CategoryTestAudio('Remote', online: true);
    final group =
        MusicCategories([local, remote]).groups(MusicCategoryKind.album).single;
    await tester.pumpWidget(_host(CategoryDetailPage(
        kind: group.kind, groupId: group.id, audios: [local, remote])));
    await tester.pumpAndSettle();
    await _rightClick(tester, _audioTile(local));
    expect(find.text('编辑歌曲信息'), findsOneWidget);
    expect(find.text('编辑歌词'), findsOneWidget);
    expect(find.text('加入歌单…'), findsOneWidget);
    // Use the supported outside-tap dismissal, and verify that the old overlay
    // is gone before clicking the next row. A raw MenuAnchor right-click does
    // not automatically focus menu items for an immediate Escape key press.
    await tester.tap(find.byKey(const ValueKey('category-track-search')));
    await tester.pumpAndSettle();
    expect(find.text('编辑歌曲信息'), findsNothing);
    await _rightClick(tester, _audioTile(remote));
    expect(find.text('编辑歌曲信息'), findsNothing);
    expect(find.text('编辑歌词'), findsNothing);
    expect(find.text('联网歌曲详情'), findsOneWidget);
    expect(find.text('来源：QQ音乐'), findsOneWidget);
    expect(find.text('加入歌单…'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'real category song rows support 200 percent text without overflow',
      (tester) async {
    _viewport(tester, width: 440, height: 507);
    final audio =
        CategoryTestAudio('A long title with metadata', composer: 'Writer');
    final group =
        MusicCategories([audio]).groups(MusicCategoryKind.composer).single;
    await tester.pumpWidget(_host(
        CategoryDetailPage(
            kind: group.kind,
            groupId: group.id,
            audios: [audio],
            classificationScanner:
                MusicClassificationScanner(readLyrics: (_) async => null)),
        scale: 2));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(_audioTile(audio), 120,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_audioTile(audio), findsOneWidget);
  });

  testWidgets('touch long press exposes the existing category song menu',
      (tester) async {
    _viewport(tester);
    final audio = CategoryTestAudio('Local');
    final group =
        MusicCategories([audio]).groups(MusicCategoryKind.artist).single;
    await tester.pumpWidget(_host(CategoryDetailPage(
        kind: group.kind, groupId: group.id, audios: [audio])));
    await tester.pumpAndSettle();
    await tester.longPress(_audioTile(audio));
    await tester.pumpAndSettle();
    expect(find.text('多选'), findsOneWidget);
    expect(find.text('编辑歌曲信息'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'actual AudioTile album menu uses production disambiguated category route',
      (tester) async {
    _viewport(tester);
    final a =
        CategoryTestAudio('A', album: 'Same album', albumArtist: 'Release A');
    final b =
        CategoryTestAudio('B', album: 'Same album', albumArtist: 'Release B');
    _library([a, b]);
    final expected = MusicCategories.albumGroupFor(a, [a, b]);
    final router = _productionPages('/fixture', extra: [
      GoRoute(
        path: '/fixture',
        builder: (_, __) =>
            Material(child: AudioTile(audioIndex: 0, playlist: [a])),
      )
    ]);
    await tester.pumpWidget(_routerHost(router));
    await tester.pumpAndSettle();
    await _rightClick(tester, _audioTile(a));
    await tester.tap(find.widgetWithText(MenuItemButton, 'Same album'));
    await tester.pumpAndSettle();
    final detail = tester.widget<AlbumDetailPage>(find.byType(AlbumDetailPage));
    expect(detail.groupId, expected.id);
    expect(
        GoRouterState.of(tester.element(find.byType(AlbumDetailPage))).uri.path,
        app_paths.CATEGORY_DETAIL_PAGE);
    expect(find.textContaining('Release A'), findsOneWidget);
    expect(find.textContaining('Release B'), findsNothing);
    expect(_audioTile(a), findsOneWidget);
    expect(_audioTile(b), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'production category deep links need no extra and malformed ids are safe',
      (tester) async {
    _viewport(tester);
    final audio =
        CategoryTestAudio('Composer song', composer: 'Writer', language: 'en');
    _library([audio]);
    final group =
        MusicCategories([audio]).groups(MusicCategoryKind.composer).single;
    final router = _productionPages(group.location);
    await tester.pumpWidget(_routerHost(router));
    await tester.pumpAndSettle();
    expect(find.text('Writer'), findsOneWidget);
    expect(_audioTile(audio), findsOneWidget);
    router.go('/categories/detail?by=composer&group=not-found');
    await tester.pumpAndSettle();
    expect(find.textContaining('此分类已不存在或标签已更新'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'artist and album category routes share the polished detail implementation',
      (tester) async {
    _viewport(tester);
    final first = CategoryTestAudio('First',
        artist: 'Route Artist', album: 'Route Album', track: 0);
    final second = CategoryTestAudio('Second',
        artist: 'Route Artist', album: 'Route Album', track: 0);
    _library([first, second]);
    final categories = MusicCategories([first, second]);
    final artist = categories.groups(MusicCategoryKind.artist).single;
    final album = categories.groups(MusicCategoryKind.album).single;
    final router = _productionPages(artist.location);
    await tester.pumpWidget(_routerHost(router));
    await tester.pumpAndSettle();

    expect(find.byType(ArtistDetailPage), findsOneWidget);
    expect(find.byType(UniDetailPage<String, Audio, MusicCategoryGroup>),
        findsOneWidget);
    expect(find.byKey(const ValueKey('playback-mode-repeat')), findsOneWidget);
    expect(find.byKey(const ValueKey('playback-mode-shuffle')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-add-all-to-playlist')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('uni-detail-search')), findsOneWidget);
    expect(find.text('搜索标题、歌手或专辑'), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('uni-detail-cover'))).width,
        176);
    var header =
        tester.getRect(find.byKey(const ValueKey('uni-detail-header-scroll')));
    var cover = tester.getRect(find.byKey(const ValueKey('uni-detail-cover')));
    expect(cover.top, greaterThan(header.top));
    expect(cover.bottom, lessThan(header.bottom));

    await tester.enterText(
        find.byKey(const ValueKey('uni-detail-search')), 'Second');
    await tester.pumpAndSettle();
    expect(_audioTile(first), findsNothing);
    expect(_audioTile(second), findsOneWidget);
    final visibleSecond = tester.widget<AudioTile>(_audioTile(second));
    expect(visibleSecond.audioIndex, 0);
    expect(visibleSecond.playlist, [same(second)]);
    await tester.enterText(
        find.byKey(const ValueKey('uni-detail-search')), 'Missing');
    await tester.pumpAndSettle();
    expect(find.byTooltip('清除搜索'), findsOneWidget);
    expect(find.text('未找到匹配的歌曲'), findsOneWidget);

    router.go(album.location);
    await tester.pumpAndSettle();
    expect(find.byType(AlbumDetailPage), findsOneWidget);
    expect(find.byType(CategoryDetailPage), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('uni-detail-cover'))).width,
        200);
    header =
        tester.getRect(find.byKey(const ValueKey('uni-detail-header-scroll')));
    cover = tester.getRect(find.byKey(const ValueKey('uni-detail-cover')));
    expect(cover.top, greaterThan(header.top));
    expect(cover.bottom, lessThan(header.bottom));
    expect(find.text('00'), findsNothing);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('02'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unified artist detail keeps a song viewport at 200 percent text',
      (tester) async {
    _viewport(tester, width: 440, height: 507);
    final audio = CategoryTestAudio('Readable song', artist: 'Readable artist');
    _library([audio]);
    final group =
        MusicCategories([audio]).groups(MusicCategoryKind.artist).single;
    await tester.pumpWidget(_host(
        ArtistDetailPage.group(groupId: group.id, initialGroup: group),
        scale: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uni-detail-search')), findsOneWidget);
    expect(
        tester
            .getSize(find.byKey(const ValueKey('uni-detail-content-scroll')))
            .height,
        greaterThan(80));
    expect(_audioTile(audio), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'unified detail selects only visible songs and prunes removed selections',
      (tester) async {
    _viewport(tester);
    final first = CategoryTestAudio('First', artist: 'Selection artist');
    final second = CategoryTestAudio('Second', artist: 'Selection artist');
    _library([first, second]);
    final group = MusicCategories([first, second])
        .groups(MusicCategoryKind.artist)
        .single;
    await tester.pumpWidget(
        _host(ArtistDetailPage.group(groupId: group.id, initialGroup: group)));
    await tester.pumpAndSettle();
    final detail =
        tester.widget<UniDetailPage<String, Audio, MusicCategoryGroup>>(
            find.byType(UniDetailPage<String, Audio, MusicCategoryGroup>));
    final selection = detail.multiSelectController!;
    await tester.enterText(
        find.byKey(const ValueKey('uni-detail-search')), 'Second');
    selection.useMultiSelectView(true);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('全选'));
    await tester.pumpAndSettle();
    expect(selection.selected, {second});

    _library([first]);
    await tester.pumpAndSettle();
    expect(selection.selected, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final kind in [MusicCategoryKind.artist, MusicCategoryKind.album]) {
    testWidgets(
        '${kind.name} detail uses its initial group once and never resurrects it',
        (tester) async {
      _viewport(tester);
      final initial = CategoryTestAudio('Initial snapshot',
          artist: 'Snapshot artist',
          album: 'Snapshot album',
          albumArtist: 'Snapshot owner');
      final group = MusicCategories([initial]).groups(kind).single;
      final page = switch (kind) {
        MusicCategoryKind.artist =>
          ArtistDetailPage.group(groupId: group.id, initialGroup: group),
        MusicCategoryKind.album =>
          AlbumDetailPage.group(groupId: group.id, initialGroup: group),
        _ => throw StateError('unsupported fixture'),
      };
      _library([]);
      await tester.pumpWidget(_host(page));
      await tester.pumpAndSettle();
      expect(_audioTile(initial), findsOneWidget);

      final live = CategoryTestAudio('Live replacement',
          artist: initial.artist,
          album: initial.album,
          albumArtist: initial.albumArtist);
      _library([live]);
      await tester.pumpAndSettle();
      expect(_audioTile(initial), findsNothing);
      expect(_audioTile(live), findsOneWidget);

      _library([]);
      await tester.pumpAndSettle();
      expect(find.byType(CategoriesPage), findsOneWidget);
      expect(_audioTile(initial), findsNothing);
      expect(_audioTile(live), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  test('playlist album count uses the same release identity as categories', () {
    final a = CategoryTestAudio('A',
        album: 'Shared title', albumArtist: 'Release owner A');
    final b = CategoryTestAudio('B',
        album: 'Shared title', albumArtist: 'Release owner B');
    final songs = [a, b];
    expect(libraryAlbumReleaseCount(songs), 2);
    expect(libraryAlbumReleaseCount(songs),
        MusicCategories(songs).groups(MusicCategoryKind.album).length);
  });

  testWidgets(
      'legacy artist and album routes remain safe without navigation extras',
      (tester) async {
    _viewport(tester);
    final audio = CategoryTestAudio('a');
    _library([audio]);
    final router = _productionPages(app_paths.ARTISTS_PAGE);
    await tester.pumpWidget(_routerHost(router));
    await tester.pumpAndSettle();
    expect(find.byType(ArtistsPage), findsOneWidget);
    expect(
        tester
            .widget<CategoriesPage>(find.byType(CategoriesPage))
            .initialCategory,
        MusicCategoryKind.artist);
    router.go(app_paths.ALBUMS_PAGE);
    await tester.pumpAndSettle();
    expect(find.byType(AlbumsPage), findsOneWidget);
    expect(
        tester
            .widget<CategoriesPage>(find.byType(CategoriesPage))
            .initialCategory,
        MusicCategoryKind.album);
    for (final route in [
      app_paths.ARTIST_DETAIL_PAGE,
      app_paths.ALBUM_DETAIL_PAGE
    ]) {
      router.go(route);
      await tester.pumpAndSettle();
      expect(find.byType(CategoriesPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'legacy mixed album extras ask for a release rather than merge owners',
      (tester) async {
    _viewport(tester);
    final album = Album(name: 'Same')
      ..works = [
        CategoryTestAudio('A', album: 'Same', albumArtist: 'Owner A'),
        CategoryTestAudio('B', album: 'Same', albumArtist: 'Owner B'),
      ];
    await tester.pumpWidget(_host(AlbumDetailPage(album: album)));
    await tester.pumpAndSettle();
    expect(find.byType(CategoriesPage), findsOneWidget);
    expect(find.text('Owner A'), findsOneWidget);
    expect(find.text('Owner B'), findsOneWidget);
    await tester
        .pumpWidget(_host(ArtistDetailPage(artist: Artist(name: 'Empty'))));
    await tester.pumpAndSettle();
    expect(find.byType(CategoriesPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'sidebar category selection keeps saved index one and legacy highlighting',
      (tester) async {
    _viewport(tester, width: 900);
    final routes = {
      ...destinations.map((item) => item.desPath),
      app_paths.ARTISTS_PAGE,
      app_paths.ALBUMS_PAGE
    };
    final router = GoRouter(initialLocation: app_paths.AUDIOS_PAGE, routes: [
      for (final route in routes)
        GoRoute(
            path: route,
            builder: (_, __) => const Scaffold(
                  body: Row(children: [SideNav(), Expanded(child: SizedBox())]),
                )),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(_routerHost(router));
    await tester.pumpAndSettle();
    expect(find.text('分类'), findsOneWidget);
    expect(find.text('艺术家'), findsNothing);
    await tester.tap(find.text('分类'));
    await tester.pumpAndSettle();
    expect(AppPreference.instance.startPage, 1);
    expect(app_paths.START_PAGES[1], app_paths.ARTISTS_PAGE);
    expect(GoRouterState.of(tester.element(find.byType(SideNav))).uri.path,
        app_paths.CATEGORIES_PAGE);
    final selected = destinations
        .indexWhere((item) => item.desPath == app_paths.CATEGORIES_PAGE);
    for (final route in [app_paths.ARTISTS_PAGE, app_paths.ALBUMS_PAGE]) {
      router.go(route);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<NavigationRail>(find.byType(NavigationRail))
              .selectedIndex,
          selected);
    }
    expect(tester.takeException(), isNull);
  });
}
