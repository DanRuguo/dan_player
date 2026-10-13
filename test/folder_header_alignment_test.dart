import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/folder_tree_pane.dart';
import 'package:dan_player/folder_note_preferences.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/folders_page.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as path;

import 'support/playlist_feature_fixture.dart';

const _music = r'J:\display-only\Music 音楽 음악';
const _leaf = r'J:\display-only\Empty folder 空文件夹';
const _cache = r'J:\display-only\Player cache';
const _cacheKey = ValueKey('aligned-cache-header');

Finder _row(String folder) => find.byKey(ValueKey('folder-open-$folder'));
Finder _art(String folder) => find.byKey(ValueKey('folder-artwork-$folder'));

Future<void> _mount(WidgetTester tester,
    {required double width,
    required double scale,
    required GlobalKey boundary,
    List<bool>? changes}) async {
  sizePlaylistFeature(tester, width: width, height: 900);
  final notes = ValueNotifier(const FolderNotePreferences());
  addTearDown(notes.dispose);
  var expanded = false;
  Future<void> save(FolderNotePreferences _) async =>
      fail('Header input must not save notes or touch real folders.');
  await tester.pumpWidget(UiLanguageScope(
    child: playlistFeatureHost(
      Padding(
        padding: const EdgeInsets.all(16),
        child: StatefulBuilder(builder: (context, setState) {
          return Column(children: [
            SizedBox(
              height: folderTileExtent(context),
              child: AudioFolderTile(
                audioFolder: AudioFolder([], _music, 0, 0),
                notes: notes,
                saveNotes: save,
                treeRow: true,
                expanded: expanded,
                onToggle: () => setState(() {
                  expanded = !expanded;
                  changes?.add(expanded);
                }),
              ),
            ),
            SizedBox(
              height: folderTileExtent(context),
              child: AudioFolderTile(
                audioFolder: AudioFolder([], _leaf, 0, 0),
                notes: notes,
                saveNotes: save,
                treeRow: true,
              ),
            ),
            SizedBox(
              height: folderTileExtent(context),
              child: PlayerDataFolderTile(
                key: _cacheKey,
                directory: Directory(_cache),
                notes: notes,
                saveNotes: save,
              ),
            ),
          ]);
        }),
      ),
      textScale: scale,
      boundary: boundary,
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _capture(
    WidgetTester tester, GlobalKey boundary, String name) async {
  final output = Platform.environment['DAN_FOLDER_HEADER_RENDER_DIR'];
  if (output == null) return;
  final qa = path.join(Directory.current.parent.path, 'tool', 'qa-local');
  final destination = path.normalize(path.absolute(output));
  if (!path.isWithin(qa, destination)) {
    throw StateError('Folder header render output must stay in QA.');
  }
  await tester.runAsync(() async {
    await Directory(destination).create(recursive: true);
    final image = await (boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary)
        .toImage();
    try {
      final bytes = await image.toByteData(format: raster.ImageByteFormat.png);
      await File(path.join(destination, '$name.png'))
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

SemanticsNode _matchingNode(
    WidgetTester tester, bool Function(SemanticsData) matches) {
  SemanticsNode? result;
  void visit(SemanticsNode node) {
    if (matches(node.getSemanticsData())) {
      result = node;
      return;
    }
    node.visitChildren((child) {
      visit(child);
      return result == null;
    });
  }

  // The expanded flag belongs to the card's outer Semantics; its inner
  // InkWell has a separate actionable node because the menu is independent.
  final expansion = find.descendant(
      of: find.byWidgetPredicate((widget) =>
          widget is AudioFolderTile && widget.audioFolder.path == _music),
      matching: find.byWidgetPredicate((widget) =>
          widget is Semantics && widget.properties.expanded != null));
  expect(expansion, findsOneWidget);
  visit(tester.getSemantics(expansion));
  expect(result, isNotNull);
  return result!;
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  for (final language in UiLanguage.values) {
    for (final size in [(320.0, 2.0), (960.0, 1.0)]) {
      testWidgets(
          'folder headers align without toggle ${language.name} ${size.$1}',
          (tester) async {
        uiLanguage.value = language;
        final boundary = GlobalKey();
        await _mount(tester,
            width: size.$1, scale: size.$2, boundary: boundary);
        final cacheIcon = find.descendant(
            of: find.byKey(_cacheKey), matching: find.byIcon(Symbols.database));
        expect(tester.getCenter(_art(_music)).dx,
            closeTo(tester.getCenter(cacheIcon).dx, .01));
        expect(tester.getTopLeft(_art(_leaf)).dx,
            closeTo(tester.getTopLeft(_art(_music)).dx, .01));
        expect(
            tester.getTopLeft(_art(_music)).dx -
                tester.getTopLeft(_row(_music)).dx,
            folderTreeContentInset);
        expect(find.byIcon(Symbols.chevron_right), findsNothing);
        for (final folder in [_music, _leaf]) {
          expect(
              find.descendant(
                  of: _row(folder), matching: find.byType(IconButton)),
              findsOneWidget,
              reason: 'Only the existing menu button remains.');
          final title =
              tester.getRect(find.byKey(ValueKey('folder-name-$folder')));
          expect(title.left,
              closeTo(tester.getRect(_art(folder)).right + 12, .01));
          expect(title.width, greaterThan(0));
        }
        expect(tester.takeException(), isNull);
        await _capture(tester, boundary,
            'folder-headers-${language.name}-${size.$1.toInt()}');
      });
    }
  }

  testWidgets('folder card retains tap keyboard semantics and context menus',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final changes = <bool>[];
      await _mount(tester,
          width: 960, scale: 1, boundary: GlobalKey(), changes: changes);
      await tester.tapAt(tester.getCenter(_art(_music)));
      await tester.pumpAndSettle();
      expect(changes, [true]);

      Focus.of(
              tester.element(find.byKey(const ValueKey('folder-name-$_music'))))
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(changes, [true, false]);
      final expanded = _matchingNode(tester,
          (data) => data.flagsCollection.isExpanded.toBoolOrNull() != null);
      expect(
          expanded.getSemanticsData().flagsCollection.isExpanded.toBoolOrNull(),
          isFalse);
      final action = _matchingNode(
          tester,
          (data) =>
              data.hasAction(SemanticsAction.tap) &&
              data.label.contains('Music'));
      action.owner!.performAction(action.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(changes, [true, false, true]);
      expect(
          _matchingNode(
                  tester,
                  (data) =>
                      data.flagsCollection.isExpanded.toBoolOrNull() != null)
              .getSemanticsData()
              .flagsCollection
              .isExpanded
              .toBoolOrNull(),
          isTrue);

      final mouse = await tester.startGesture(tester.getCenter(_art(_music)),
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNWidgets(4));
      expect(changes, [true, false, true]);
      await mouse.moveTo(Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(MenuItemButton).first));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await mouse.removePointer();
      expect(find.byType(MenuItemButton), findsNothing);

      final touch = await tester.startGesture(tester.getCenter(_art(_music)));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
      await touch.up();
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNWidgets(4));
      expect(changes, [true, false, true]);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
    }
  });
}
