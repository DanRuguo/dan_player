import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/folder_actions.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/folder_note_preferences.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/folders_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:desktop_lyric/l10n/catalog_folder_notes.dart';
import 'package:desktop_lyric/l10n/ui_catalog.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/playlist_feature_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final root = path.join(Directory.current.parent.path, 'tool', 'qa-local',
      'features-2606-oct4', 'folder-notes');
  final musicPath = path.join(root, 'data', 'Music', '真实音乐文件夹');
  final cachePath = path.join(root, 'data', 'PlayerCache');
  final output = Platform.environment['DAN_FOLDER_NOTES_RENDER_DIR'];
  setUpAll(() async {
    if (output != null && !path.isWithin(root, output)) {
      throw StateError(
          'Folder note render output must stay in its QA directory');
    }
    await loadPlaylistFeatureFonts();
  });
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  late ValueNotifier<FolderNotePreferences> notes;
  var saves = 0;
  Future<void> mount(WidgetTester tester,
      {FolderNotePreferences initial = const FolderNotePreferences(),
      double width = 800,
      double scale = 1,
      GlobalKey? capture,
      bool fail = false}) async {
    saves = 0;
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    notes = ValueNotifier(initial);
    addTearDown(notes.dispose);
    Future<void> save(FolderNotePreferences value) async {
      saves++;
      if (fail) throw const FileSystemException('QA save failure');
    }

    final theme = Entry(welcome: false).fromSchemeAndFontFamily(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xffa75f32)),
        fontFamily: danEmbeddedFontFamily);
    await tester.pumpWidget(UiLanguageScope(
        child: MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                    textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(
                    key: capture, child: AppPresentationHost(child: child!))),
            home: Scaffold(
                body: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      Builder(
                          builder: (context) => SizedBox(
                              height: folderTileExtent(context),
                              child: AudioFolderTile(
                                  key: const ValueKey('music-tile'),
                                  audioFolder: AudioFolder([], musicPath, 0, 0),
                                  notes: notes,
                                  saveNotes: save))),
                      Builder(
                          builder: (context) => SizedBox(
                              height: folderTileExtent(context),
                              child: PlayerDataFolderTile(
                                  key: const ValueKey('cache-tile'),
                                  directory: Directory(cachePath),
                                  notes: notes,
                                  saveNotes: save))),
                    ]))))));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, {bool cache = false}) async {
    final tile = find.byKey(ValueKey(cache ? 'cache-tile' : 'music-tile'));
    await tester
        .tap(find.descendant(of: tile, matching: find.byType(IconButton)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('folder-note-menu')));
    await tester.pumpAndSettle();
    expect(find.byType(FolderNoteDialog), findsOneWidget);
  }

  Future<void> saveImage(
      WidgetTester tester, GlobalKey capture, String name) async {
    if (output == null) return;
    await tester.runAsync(() async {
      final image = await (capture.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      try {
        final bytes =
            await image.toByteData(format: raster.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File(path.join(output, '$name.png'))
            .writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }

  test('folder note catalog has all three translations and same placeholders',
      () {
    for (final entry in catalogFolderNotes.entries) {
      expect(uiCatalog.containsKey(entry.key), isTrue);
      expect(entry.value, hasLength(3));
      for (final text in entry.value) {
        expect(text.trim(), isNotEmpty);
        expect(
            RegExp(r'\{\d+\}')
                .allMatches(text)
                .map((match) => match[0])
                .toSet(),
            RegExp(r'\{\d+\}')
                .allMatches(entry.key)
                .map((match) => match[0])
                .toSet());
      }
    }
  });

  testWidgets('cancel keeps display name and never saves', (tester) async {
    await mount(tester);
    await open(tester);
    await tester.enterText(
        find.byKey(const ValueKey('folder-note-input')), 'new name');
    await tester.tap(find.byKey(const ValueKey('folder-note-cancel')));
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(notes.value.noteFor(musicPath), isNull);
    expect(find.text(folderDisplayName(musicPath)), findsOneWidget);
  });

  testWidgets('save updates only display label and preserves full music path',
      (tester) async {
    await mount(tester);
    await open(tester);
    await tester.enterText(
        find.byKey(const ValueKey('folder-note-input')), 'My collection');
    await tester.tap(find.byKey(const ValueKey('folder-note-save')));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(find.text('My collection'), findsOneWidget);
    expect(find.text(path.windows.normalize(musicPath)), findsOneWidget);
    expect(
        notes.value.toJson().single['path'], path.windows.normalize(musicPath));
    expect(find.text(ui('缓存文件夹')), findsOneWidget);
  });

  testWidgets(
      'clear stays a draft until save and then restores actual basename',
      (tester) async {
    await mount(tester,
        initial: const FolderNotePreferences().withNote(musicPath, 'note'));
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('folder-note-clear')));
    await tester.pump();
    expect(notes.value.noteFor(musicPath), 'note');
    await tester.tap(find.byKey(const ValueKey('folder-note-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('note'), findsOneWidget);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('folder-note-clear')));
    await tester.tap(find.byKey(const ValueKey('folder-note-save')));
    await tester.pumpAndSettle();
    expect(notes.value.noteFor(musicPath), isNull);
    expect(find.text(folderDisplayName(musicPath)), findsOneWidget);
  });

  testWidgets(
      'cache note is independent and failing save restores original label',
      (tester) async {
    await mount(tester, fail: true);
    await open(tester, cache: true);
    await tester.enterText(
        find.byKey(const ValueKey('folder-note-input')), 'cache note');
    await tester.tap(find.byKey(const ValueKey('folder-note-save')));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(notes.value.noteFor(cachePath), isNull);
    expect(find.text(folderDisplayName(cachePath)), findsOneWidget);
    expect(find.text(ui('无法保存文件夹备注')), findsOneWidget);
  });

  testWidgets(
      'invalid codepoint count disables save and valid input re-enables it',
      (tester) async {
    await mount(tester);
    await open(tester);
    await tester.enterText(find.byKey(const ValueKey('folder-note-input')),
        List.filled(161, '😀').join());
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('folder-note-save')))
            .onPressed,
        isNull);
    await tester.enterText(
        find.byKey(const ValueKey('folder-note-input')), 'Valid 😀');
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('folder-note-save')))
            .onPressed,
        isNotNull);
  });

  testWidgets('right click and long press expose the existing note action',
      (tester) async {
    await mount(tester);
    final tile = find.byKey(const ValueKey('music-tile'));
    final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await mouse.down(tester.getCenter(tile));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('folder-note-menu')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('folder-note-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('folder-note-cancel')));
    await tester.pumpAndSettle();
    await tester.longPress(tile);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('folder-note-menu')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('folder-note-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('folder-note-cancel')));
    await tester.pumpAndSettle();
    await mouse.moveTo(tester.getTopLeft(tile) + const Offset(28, 28));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.text(musicPath), findsNWidgets(2),
        reason: 'Manual touch trigger keeps real mouse hover path tooltip');
    await mouse.removePointer();
  });

  testWidgets(
      'real folders page keeps cache last in list and grid without counting it',
      (tester) async {
    final library = AudioLibrary.instance;
    final originalFolders = library.folders;
    final originalPref = AppPreference.instance.foldersPagePref;
    final originalNotes = AppSettings.instance.folderNotes.value;
    addTearDown(() {
      library.folders = originalFolders;
      AppPreference.instance.foldersPagePref = originalPref;
      AppSettings.instance.folderNotes.value = originalNotes;
    });
    library.folders = [
      AudioFolder([], musicPath, 0, 0),
      AudioFolder([], path.join(root, 'data', 'Z-Music'), 0, 0)
    ];
    AppPreference.instance.foldersPagePref =
        PagePreference(0, SortOrder.ascending, ContentView.list);
    AppSettings.instance.folderNotes.value =
        const FolderNotePreferences().withNote(cachePath, 'Cache display note');
    sizePlaylistFeature(tester, width: 900, height: 800);
    final capture = GlobalKey();
    await tester.pumpWidget(UiLanguageScope(
        child: playlistFeatureHost(
            AppPresentationHost(
                child: FoldersPage(dataDirectory: Directory(cachePath))),
            boundary: capture)));
    await tester.pumpAndSettle();
    for (final view in [ContentView.list, ContentView.table]) {
      if (view == ContentView.table) {
        await tester.tap(find.text(ui('网格')));
        await tester.pumpAndSettle();
      }
      expect(find.text(ui('{0} 个文件夹', [2])), findsOneWidget);
      final page = tester
          .widget<UniPage<AudioFolder>>(find.byType(UniPage<AudioFolder>));
      expect(page.contentList.last.path, cachePath);
      expect(page.contentList, hasLength(3));
      expect(find.byType(PlayerDataFolderTile), findsOneWidget);
      expect(find.text('Cache display note'), findsOneWidget);
      final cache = find.byType(PlayerDataFolderTile);
      for (final music in find.byType(AudioFolderTile).evaluate()) {
        expect(
            tester.getTopLeft(cache).dy,
            greaterThanOrEqualTo(
                tester.getTopLeft(find.byWidget(music.widget)).dy));
      }
      await saveImage(tester, capture, 'zh-page-${view.name}');
      await tester
          .tap(find.descendant(of: cache, matching: find.byType(IconButton)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('folder-note-menu')));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextField>(
                  find.byKey(const ValueKey('folder-note-input')))
              .controller!
              .text,
          'Cache display note');
      await tester.tap(find.byKey(const ValueKey('folder-note-cancel')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets(
          '${language.name} ${narrow ? 'narrow large' : 'wide'} note dialog and tile render',
          (tester) async {
        uiLanguage.value = language;
        final capture = GlobalKey();
        await mount(tester,
            width: narrow ? 360 : 900,
            scale: narrow ? 2 : 1,
            capture: capture,
            initial: const FolderNotePreferences()
                .withNote(musicPath, '我的音乐收藏 My collection 音楽 모음집')
                .withNote(cachePath, '播放器资料 Player data プレーヤー 데이터'));
        expect(tester.takeException(), isNull);
        expect(find.text(path.windows.normalize(musicPath)), findsOneWidget);
        expect(find.text(cachePath), findsOneWidget);
        expect(find.text(ui('缓存文件夹')), findsOneWidget);
        await saveImage(tester, capture,
            '${language.name}-${narrow ? 'narrow' : 'wide'}-tiles');
        await open(tester);
        expect(tester.takeException(), isNull);
        final save = find.byKey(const ValueKey('folder-note-save'));
        await tester.ensureVisible(save);
        expect(tester.getRect(save).width, greaterThan(40));
        expect(find.text(ui('文件夹备注')), findsWidgets);
        await saveImage(tester, capture,
            '${language.name}-${narrow ? 'narrow' : 'wide'}-dialog');
      });
    }
  }
}
