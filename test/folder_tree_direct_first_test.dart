import 'dart:io';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/audio_selection_toolbar.dart';
import 'package:dan_player/component/folder_tree_pane.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/folder_tree.dart';
import 'package:dan_player/page/folders_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/page/uni_page_components.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final qa = path.join(Directory.current.parent.path, 'tool', 'qa-local',
      'selection-folders-oct11', 'interaction', 'direct-first');
  final data = Directory(path.join(qa, 'data'));
  final root = path.join(qa, 'Music');
  final child = path.join(root, 'Album');
  final leaf = path.join(child, 'Disc');
  final roots = [
    for (final title in ['Root A', 'Root Z'])
      CategoryTestAudio(title, path: path.join(root, '$title.mp3')),
  ];
  final children = [
    for (final title in ['Album C', 'Album D'])
      CategoryTestAudio(title, path: path.join(child, '$title.mp3')),
  ];
  final last = CategoryTestAudio('Disc L', path: path.join(leaf, 'L.mp3'));
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const provider = MethodChannel('plugins.flutter.io/path_provider');
  late List<AudioFolder> previousFolders;
  late PagePreference previousFolderPreference, previousSongPreference;
  late int previousRevision, previousNotification;
  late PlaylistFeaturePlayback playback;

  setUpAll(() async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR'], isNull,
        reason:
            'The path_provider fixture owns its isolated application data.');
    expect(Directory.systemTemp.absolute.path.replaceAll('\\', '/'),
        contains('/tool/qa-local/'));
    await data.create(recursive: true);
    messenger.setMockMethodCallHandler(provider, (_) async => data.path);
    expect(path.isWithin(data.path, (await getAppDataDir()).path), isTrue);
    await loadPlaylistFeatureFonts();
  });
  tearDownAll(() => messenger.setMockMethodCallHandler(provider, null));
  setUp(() {
    uiLanguage.value = UiLanguage.zh;
    previousFolders = AudioLibrary.instance.folders;
    previousRevision = AudioLibrary.revision;
    previousNotification = AudioLibrary.changes.value;
    previousFolderPreference = AppPreference.instance.foldersPagePref;
    previousSongPreference = AppPreference.instance.folderDetailPagePref;
    AppPreference.instance.foldersPagePref =
        PagePreference(0, SortOrder.ascending, ContentView.table);
    AppPreference.instance.folderDetailPagePref =
        PagePreference(0, SortOrder.decending, ContentView.table);
    AudioLibrary.instance.folders = [
      AudioFolder([last], leaf, 1, 1),
      AudioFolder(roots, root, 1, 1),
      AudioFolder(children, child, 1, 1),
    ];
    playback = PlaylistFeaturePlayback([]);
  });
  tearDown(() {
    playback.dispose();
    AudioLibrary.instance.folders = previousFolders;
    AudioLibrary.revision = previousRevision;
    AudioLibrary.changes.value = previousNotification;
    AppPreference.instance.foldersPagePref = previousFolderPreference;
    AppPreference.instance.folderDetailPagePref = previousSongPreference;
    uiLanguage.value = UiLanguage.zh;
  });

  Future<void> mount(WidgetTester tester,
      {double width = 1000, double scale = 1, GlobalKey? boundary}) async {
    sizePlaylistFeature(tester, width: width, height: 1100);
    await tester.pumpWidget(UiLanguageScope(
        child: playlistFeatureHost(
            AppEntranceScope(
                child: FoldersPage(
                    dataDirectory: data,
                    initialFolderPath: leaf,
                    playbackService: playback,
                    loadArtwork: (_, __) async => null)),
            textScale: scale,
            boundary: boundary)));
    await tester.pumpAndSettle();
  }

  Finder folder(String folder) => _key('folder-open-$folder');
  Finder cover(Audio audio) => _key('folder-tree-cover-${audio.path}');
  Finder group(String folder, String kind) =>
      _key('folder-tree-group-$kind-${folderTreePathId(folder)}');

  ScrollController scroll(WidgetTester tester) =>
      tester.widget<FolderTreePane>(find.byType(FolderTreePane)).controller!;

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      // This lazy list releases earlier rows after visiting the nested leaf.
      // Bring the row into the viewport before asking for its render object.
      scroll(tester).jumpTo(0);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(finder, 180,
          scrollable: find
              .descendant(
                  of: find.byType(FolderTreePane),
                  matching: find.byType(Scrollable))
              .first);
    }
    final target = tester.widget(finder) is Text
        ? find.ancestor(of: finder, matching: find.byType(CustomPaint)).first
        : finder;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  Future<Rect> contentRect(WidgetTester tester, Finder finder) async {
    await reveal(tester, finder);
    return tester.getRect(finder).shift(Offset(0, scroll(tester).offset));
  }

  for (final language in UiLanguage.values) {
    for (final width in [1000.0, 360.0]) {
      testWidgets(
          'direct-first groups ${language.name} width $width text 2 retain nested ownership',
          (tester) async {
        uiLanguage.value = language;
        final boundary = GlobalKey();
        await mount(tester, width: width, scale: 2, boundary: boundary);
        final pane = tester.widget<FolderTreePane>(find.byType(FolderTreePane));
        expect(
            pane.tree
                .visibleSections(pane.expanded)
                .where((section) => section.songs)
                .map((section) => section.node.folder.path),
            [root, child, leaf]);
        final rootHeader = await contentRect(tester, folder(root));
        final rootCaption = await contentRect(tester, group(root, 'songs'));
        final rootSong = await contentRect(tester, cover(roots.last));
        final rootChildren =
            await contentRect(tester, group(root, 'subfolders'));
        final childHeader = await contentRect(tester, folder(child));
        final childCaption = await contentRect(tester, group(child, 'songs'));
        final childSong = await contentRect(tester, cover(children.last));
        final childChildren =
            await contentRect(tester, group(child, 'subfolders'));
        final leafHeader = await contentRect(tester, folder(leaf));
        final leafCaption = await contentRect(tester, group(leaf, 'songs'));
        final leafSong = await contentRect(tester, cover(last));
        expect(rootHeader.bottom, lessThanOrEqualTo(rootCaption.top));
        expect(rootCaption.bottom, lessThan(rootSong.top));
        expect(rootSong.bottom, lessThan(rootChildren.top));
        expect(rootChildren.bottom, lessThanOrEqualTo(childHeader.top));
        expect(childHeader.bottom, lessThanOrEqualTo(childCaption.top));
        expect(childCaption.bottom, lessThan(childSong.top));
        expect(childSong.bottom, lessThan(childChildren.top));
        expect(childChildren.bottom, lessThanOrEqualTo(leafHeader.top));
        expect(leafHeader.bottom, lessThanOrEqualTo(leafCaption.top));
        expect(leafCaption.bottom, lessThan(leafSong.top));
        expect(childSong.left - rootSong.left,
            closeTo(childHeader.left - rootHeader.left, .01));
        expect(leafSong.left - childSong.left,
            closeTo(leafHeader.left - childHeader.left, .01));
        expect(leafHeader.left - rootHeader.left, lessThan(width * .18));
        for (final folderPath in [root, child, leaf]) {
          final label = group(folderPath, 'songs');
          await reveal(tester, label);
          _expectCaption(tester, label, ui('本文件夹歌曲'), width);
        }
        for (final folderPath in [root, child]) {
          final label = group(folderPath, 'subfolders');
          await reveal(tester, label);
          _expectCaption(tester, label, ui('子文件夹'), width);
        }
        expect(group(leaf, 'subfolders'), findsNothing);
        scroll(tester).jumpTo(0);
        await tester.pumpAndSettle();
        await capturePlaylistFeature(tester, boundary,
            'folder-direct-first-${language.name}-${width.toInt()}-2');
        await reveal(tester, cover(last));
        await capturePlaylistFeature(tester, boundary,
            'folder-direct-first-${language.name}-${width.toInt()}-2-nested');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
      });
    }
  }

  testWidgets('nested range follows direct-first order across parent and child',
      (tester) async {
    await mount(tester);
    await tester.longPress(cover(roots.first));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, ui('多选')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(cover(last));
    await tester.tap(cover(last));
    await tester.pumpAndSettle();
    final actions = tester.widget<AudioMultiSelectionActions>(
        find.byType(AudioMultiSelectionActions));
    final controller = actions.controller;
    final session = controller.session;
    expect(
        actions.contentList, [...roots.reversed, ...children.reversed, last]);
    await tester.tap(_key('audio-selection-more'));
    await tester.pumpAndSettle();
    final range = _key('multi-selection-range-between');
    await tester.ensureVisible(range);
    await tester.tap(range.hitTestable());
    await tester.pumpAndSettle();
    expect(controller.selectedInOrder(actions.contentList),
        [roots.first, ...children.reversed, last]);
    await tester.ensureVisible(folder(child));
    await tester.tapAt(tester.getTopLeft(folder(child)) + const Offset(70, 35));
    await tester.pumpAndSettle();
    final toolbar = tester
        .widget<AudioSelectionToolbar>(find.byType(AudioSelectionToolbar));
    expect(controller.session, session);
    expect(controller.selected, hasLength(4));
    expect(toolbar.hiddenSelectionCount, 3);
    expect(toolbar.selected, [roots.first]);
    expect(group(root, 'songs'), findsOneWidget);
    expect(group(child, 'songs'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

void _expectCaption(
    WidgetTester tester, Finder finder, String expected, double width) {
  final text = tester.widget<Text>(finder);
  expect(text.data, expected);
  expect(text.softWrap, isTrue);
  final header = tester.widget<Semantics>(
      find.ancestor(of: finder, matching: find.byType(Semantics)).first);
  expect(header.properties.header, isTrue);
  final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: finder, matching: find.byType(RichText)).last);
  expect(paragraph.didExceedMaxLines, isFalse);
  final bounds = tester.getRect(finder);
  // labelMedium's font ink may exceed its tight line box. The padded row is
  // the real available paint area; the list viewport is the actual clip.
  final row = tester.getRect(
      find.ancestor(of: finder, matching: find.byType(CustomPaint)).first);
  final viewport = tester.getRect(find.descendant(
      of: find.byType(FolderTreePane), matching: find.byType(ListView)));
  expect(bounds.left, greaterThanOrEqualTo(0));
  expect(bounds.right, lessThanOrEqualTo(width));
  for (var index = 0; index < expected.length; index++) {
    if (expected[index].trim().isEmpty) continue;
    final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: index, extentOffset: index + 1));
    expect(boxes, isNotEmpty, reason: expected);
    for (final box in boxes) {
      final topLeft = paragraph.localToGlobal(Offset(box.left, box.top));
      final bottomRight =
          paragraph.localToGlobal(Offset(box.right, box.bottom));
      expect(topLeft.dx, greaterThanOrEqualTo(bounds.left - .5));
      expect(bottomRight.dx, lessThanOrEqualTo(bounds.right + .5));
      expect(topLeft.dy, greaterThanOrEqualTo(row.top - .5));
      expect(bottomRight.dy, lessThanOrEqualTo(row.bottom + .5));
      expect(topLeft.dy, greaterThanOrEqualTo(viewport.top - .5));
      expect(bottomRight.dy, lessThanOrEqualTo(viewport.bottom + .5));
    }
  }
}
