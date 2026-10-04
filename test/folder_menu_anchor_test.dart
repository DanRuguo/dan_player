import 'dart:io';

import 'package:dan_player/folder_note_preferences.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/folders_page.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playlist_feature_fixture.dart';

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  Future<void> mount(WidgetTester tester, double width, bool cache,
      {GlobalKey? boundary}) async {
    sizePlaylistFeature(tester, width: width, height: 600);
    final notes = ValueNotifier(const FolderNotePreferences());
    addTearDown(notes.dispose);
    // Neither tile reads or writes these display-only paths.
    const directory = r'J:\QA\Music';
    await tester.pumpWidget(playlistFeatureHost(
        Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.topCenter,
            child: Builder(
                builder: (context) => SizedBox(
                    height: folderTileExtent(context),
                    child: cache
                        ? PlayerDataFolderTile(
                            directory: Directory(directory), notes: notes)
                        : AudioFolderTile(
                            audioFolder: AudioFolder([], directory, 0, 0),
                            notes: notes))),
          ),
        ),
        boundary: boundary));
    await tester.pumpAndSettle();
  }

  Rect menuRect(WidgetTester tester) => tester
      .getRect(find.byType(MenuItemButton).first)
      .expandToInclude(tester.getRect(find.byType(MenuItemButton).last));

  for (final width in [1080.0, 360.0]) {
    for (final cache in [false, true]) {
      testWidgets(
          '${cache ? "cache" : "music"} more menu follows right button at $width',
          (tester) async {
        final boundary = GlobalKey();
        await mount(tester, width, cache, boundary: boundary);
        final button = find.byType(IconButton);
        final trigger = tester.getRect(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.byType(MenuItemButton), findsNWidgets(4));
        final menu = menuRect(tester);
        expect(menu.right, greaterThanOrEqualTo(trigger.center.dx - 24));
        expect(menu.right, lessThanOrEqualTo(width));
        expect(menu.left, greaterThanOrEqualTo(0));
        expect(menu.top, greaterThanOrEqualTo(trigger.bottom - 12));
        expect(find.text(ui('文件夹备注')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capturePlaylistFeature(tester, boundary,
            'folder-menu-${cache ? "cache" : "music"}-${width.toInt()}');
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.byType(MenuItemButton), findsNothing);
      });
    }
  }

  for (final touch in [false, true]) {
    testWidgets('${touch ? "touch" : "secondary"} menu follows input point',
        (tester) async {
      await mount(tester, 1000, false);
      final tile = find.byType(AudioFolderTile);
      final location = tester.getTopLeft(tile) + const Offset(600, 35);
      if (touch) {
        final pointer = await tester.startGesture(location);
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
        await pointer.up();
      } else {
        final pointer = await tester.createGesture(
            kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
        await pointer.down(location);
        await pointer.up();
      }
      await tester.pumpAndSettle();
      final menu = menuRect(tester);
      expect(menu.left, closeTo(location.dx, 16));
      expect(menu.top, closeTo(location.dy, 16));
      expect(find.byType(MenuItemButton), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    });
  }
}
