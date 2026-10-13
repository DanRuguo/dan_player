import 'dart:io';

import 'package:dan_player/folder_note_preferences.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/folders_page.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/playlist_feature_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  final qa = path.join(Directory.current.parent.path, 'tool', 'qa-local',
      'folder-tooltip-oct13', 'display-only');
  final longPath = path.windows.normalize(path.join(
      qa, 'Collection with a deliberately long folder name 音楽 모음집 0123456789'));
  const displayName = 'My complete music collection 音楽 모음집 0123456789';
  const shortPath = r'J:\q';
  const tileKey = ValueKey('tooltip-folder-card');

  Future<void> mount(WidgetTester tester,
      {required bool cache,
      required double width,
      String directoryPath = '',
      String? name,
      double scale = 1,
      ValueChanged<bool>? onExpanded}) async {
    sizePlaylistFeature(tester, width: width, height: 600);
    final folderPath = directoryPath.isEmpty ? longPath : directoryPath;
    final notes = ValueNotifier(name == null
        ? const FolderNotePreferences()
        : const FolderNotePreferences().withNote(folderPath, name));
    addTearDown(notes.dispose);
    var expanded = false;
    // All paths are labels only. Inject notes and saving so neither card reads
    // global settings, scans a folder or writes a real application data file.
    Future<void> saveNotes(FolderNotePreferences _) async =>
        fail('Opening or hovering a folder card must not save notes');
    await tester.pumpWidget(UiLanguageScope(
        child: playlistFeatureHost(
      Padding(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topCenter,
          child: StatefulBuilder(builder: (context, setState) {
            return SizedBox(
              height: folderTileExtent(context),
              child: cache
                  ? PlayerDataFolderTile(
                      key: tileKey,
                      directory: Directory(folderPath),
                      notes: notes,
                      saveNotes: saveNotes)
                  : AudioFolderTile(
                      key: tileKey,
                      audioFolder: AudioFolder([], folderPath, 0, 0),
                      notes: notes,
                      saveNotes: saveNotes,
                      treeRow: true,
                      expanded: expanded,
                      onToggle: () => setState(() {
                            expanded = !expanded;
                            onExpanded?.call(expanded);
                          })),
            );
          }),
        ),
      ),
      textScale: scale,
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  String description(bool cache, String name, String folderPath) =>
      '$name\n$folderPath\n${cache ? ui('缓存文件夹') : '${ui('音乐文件夹')} · ${ui('{0} 首歌曲 · 修改于 {1}', [
              0,
              ui('未知日期')
            ])}'}';

  List<Tooltip> descriptionTooltips(String folderPath) => testerTooltips()
      .where((tooltip) => tooltip.message?.contains(folderPath) ?? false)
      .toList(growable: false);

  Finder textInCard(String value) =>
      find.descendant(of: find.byKey(tileKey), matching: find.text(value));

  Future<TestGesture> hover(WidgetTester tester, Offset position) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(position);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    return mouse;
  }

  for (final language in UiLanguage.values) {
    for (final cache in [false, true]) {
      testWidgets(
          '${language.name} ${cache ? 'cache' : 'music'} wide card has no description bubble',
          (tester) async {
        uiLanguage.value = language;
        await mount(tester, cache: cache, width: 1100, name: displayName);
        expect(descriptionTooltips(longPath), isEmpty);
        expect(find.byTooltip(ui('更多')), findsOneWidget);
        final mouse = await hover(tester,
            tester.getTopLeft(find.byKey(tileKey)) + const Offset(80, 32));
        expect(
            find.text(description(cache, displayName, longPath)), findsNothing);
        await mouse.moveTo(tester.getCenter(textInCard(longPath)));
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pumpAndSettle();
        expect(
            find.text(description(cache, displayName, longPath)), findsNothing);
        expect(textInCard(longPath), findsOneWidget,
            reason: 'The original complete path remains in the visible text');
        await mouse.removePointer();
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          '${language.name} ${cache ? 'cache' : 'music'} compact card uses one bubble across all labels',
          (tester) async {
        uiLanguage.value = language;
        final semantics = tester.ensureSemantics();
        try {
          await mount(tester, cache: cache, width: 320, name: displayName);
          final expected = description(cache, displayName, longPath);
          expect(descriptionTooltips(longPath), hasLength(1));
          expect(descriptionTooltips(longPath).single.message, expected);
          expect(find.byTooltip(longPath), findsNothing,
              reason: 'The old independent path bubble is gone');
          expect(find.bySemanticsLabel(RegExp(RegExp.escape(displayName))),
              findsWidgets);
          expect(find.bySemanticsLabel(RegExp(RegExp.escape(longPath))),
              findsWidgets);
          final summary = cache
              ? ui('缓存文件夹')
              : '${ui('音乐文件夹')} · ${ui('{0} 首歌曲 · 修改于 {1}', [0, ui('未知日期')])}';
          final positions = [
            tester.getTopLeft(find.byKey(tileKey)) +
                Offset(cache ? 36 : 72, 32),
            tester.getCenter(textInCard(displayName)),
            tester.getCenter(textInCard(longPath)),
            tester.getCenter(textInCard(summary)),
            tester.getTopLeft(find.byKey(tileKey)) + const Offset(4, 35),
          ];
          final mouse = await hover(tester, positions.first);
          expect(find.text(expected), findsOneWidget);
          for (final position in positions.skip(1)) {
            await mouse.moveTo(position);
            await tester.pump(const Duration(milliseconds: 800));
            await tester.pumpAndSettle();
            expect(find.text(expected), findsOneWidget,
                reason:
                    'Icon, labels and blank card area share the same bubble');
            expect(descriptionTooltips(longPath), hasLength(1));
          }
          await mouse.removePointer();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });

      testWidgets(
          '${language.name} ${cache ? 'cache' : 'music'} compact card retains menu and expansion actions',
          (tester) async {
        uiLanguage.value = language;
        final semantics = tester.ensureSemantics();
        try {
          final expansions = <bool>[];
          await mount(tester,
              cache: cache,
              width: 320,
              name: displayName,
              onExpanded: expansions.add);
          expect(find.byTooltip(ui('更多')), findsOneWidget);
          expect(
              tester
                  .getSemantics(find.byTooltip(ui('更多')))
                  .getSemanticsData()
                  .tooltip,
              ui('更多'));
          await tester.tap(find.byTooltip(ui('更多')));
          await tester.pumpAndSettle();
          expect(find.byType(MenuItemButton), findsNWidgets(4));
          expect(
              find.byKey(const ValueKey('folder-note-menu')), findsOneWidget);
          // Opening this pointer menu does not move keyboard focus into it.
          // Material requests focus on an actual item hover before Escape.
          final menuMouse = await hover(
              tester, tester.getCenter(find.byType(MenuItemButton).first));
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byType(MenuItemButton), findsNothing);
          await menuMouse.removePointer();
          if (!cache) {
            final toggle = find.byKey(ValueKey('folder-open-$longPath'));
            final expansion = find.byWidgetPredicate((widget) =>
                widget is Semantics && widget.properties.expanded != null);
            expect(
                tester
                    .getSemantics(expansion)
                    .getSemanticsData()
                    .flagsCollection
                    .isExpanded
                    .toBoolOrNull(),
                isNotNull);
            expect(
                tester
                    .getSemantics(expansion)
                    .getSemanticsData()
                    .flagsCollection
                    .isExpanded
                    .toBoolOrNull(),
                isFalse);
            await tester.tap(toggle);
            await tester.pumpAndSettle();
            expect(expansions, [true]);
            expect(
                tester
                    .getSemantics(expansion)
                    .getSemanticsData()
                    .flagsCollection
                    .isExpanded
                    .toBoolOrNull(),
                isTrue);
            await tester.tap(toggle);
            await tester.pumpAndSettle();
            expect(expansions, [true, false]);
          }
          final pointer = await tester.startGesture(
              tester.getTopLeft(find.byKey(tileKey)) + const Offset(80, 32));
          await tester
              .pump(kLongPressTimeout + const Duration(milliseconds: 20));
          await pointer.up();
          await tester.pumpAndSettle();
          expect(find.byType(MenuItemButton), findsNWidgets(4),
              reason:
                  'The compact hover bubble must not steal touch long press');
          expect(
              find.byKey(const ValueKey('folder-note-menu')), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }

    testWidgets('${language.name} compact complete labels need no bubble',
        (tester) async {
      uiLanguage.value = language;
      // This short path is display-only; no filesystem operation is invoked.
      await mount(tester,
          cache: true, width: 312, directoryPath: shortPath, name: 'q');
      expect(descriptionTooltips(shortPath), isEmpty);
      final mouse =
          await hover(tester, tester.getCenter(textInCard(shortPath)));
      expect(find.text(description(true, 'q', shortPath)), findsNothing);
      expect(textInCard(shortPath), findsOneWidget);
      expect(find.byTooltip(ui('更多')), findsOneWidget);
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    });
  }
}

Iterable<Tooltip> testerTooltips() => find
    .descendant(
        of: find.byKey(const ValueKey('tooltip-folder-card')),
        matching: find.byType(Tooltip))
    .evaluate()
    .map((element) => element.widget as Tooltip);
