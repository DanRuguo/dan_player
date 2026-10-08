import 'dart:io';
import 'dart:ui' as raster;
import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/detail_volume_panel.dart';
import 'package:dan_player/component/playlist_management_dialog.dart';
import 'package:dan_player/component/playlist_song_picker.dart';
import 'package:dan_player/component/playlist_exchange_dialog.dart';
import 'package:dan_player/data/backup_selection.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/settings_page/backup_selection_dialog.dart';
import 'package:dan_player/page/now_playing_page/component/detail_progress_slider.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_reading_tools.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [
      (danEmbeddedFontFamily, 'packages/desktop_lyric/assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      ),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  final root = GlobalKey();
  Widget app(Widget child, ColorScheme scheme, double scale) => RepaintBoundary(
      key: root,
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: Entry(welcome: false).fromSchemeAndFontFamily(
              colorScheme: scheme, fontFamily: danEmbeddedFontFamily),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: TextScaler.linear(scale)),
              child: child!),
          home: Scaffold(body: child)));
  Future<void> capture(WidgetTester tester, String name) async {
    final output = Platform.environment['DAN_ALIGNMENT_RENDER'];
    if (output == null) return;
    await tester.runAsync(() async {
      final img = await (root.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final bytes = await img.toByteData(format: raster.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      img.dispose();
    });
  }

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'menu check/icon columns, slider clearance and accent dark=$dark scale=$scale',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(440, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final controller = LyricViewController(
            preferences: NowPlayingPagePreference.fromMap({}));
        addTearDown(controller.dispose);
        final scheme = ColorScheme.fromSeed(
            seedColor: dark ? Colors.deepPurple : const Color(0xff965341),
            brightness: dark ? Brightness.dark : Brightness.light);
        await tester.pumpWidget(app(
            Column(children: [
              const SizedBox(height: 32),
              LyricReadingMenu(controller: controller, readLyric: () => null),
              const SizedBox(height: 24),
              DetailVolumePanel(value: .37, onChanged: (_) {}),
              const SizedBox(height: 32),
              DetailProgressSlider(
                  positions: const Stream<double>.empty(),
                  readPosition: () => 19,
                  duration: 7200,
                  trackIdentity: 'fixture',
                  onSeek: (_) {}),
            ]),
            scheme,
            scale));
        await tester.pumpAndSettle();
        final volumeSlider = find.descendant(
            of: find.byType(DetailVolumePanel), matching: find.byType(Slider));
        expect(
            tester.getRect(find.byKey(const ValueKey('volume-preset-25'))).top -
                tester.getRect(volumeSlider).bottom,
            greaterThanOrEqualTo(12));
        final time = find.byKey(const ValueKey('detail-progress-elapsed'));
        expect(DefaultTextStyle.of(tester.element(time)).style.color,
            scheme.primary);
        expect(
            tester
                .widget<Icon>(
                    find.byKey(const ValueKey('detail-progress-time-chevron')))
                .color,
            scheme.primary);
        await capture(tester, 'controls-$dark-$scale');
        await tester.tap(find.byKey(const ValueKey('lyric-reading-tools')));
        await tester.pumpAndSettle();
        final checkbox = find.byType(Checkbox).first;
        expect(
            tester.getCenter(checkbox).dx,
            closeTo(
                tester.getCenter(find.byIcon(Symbols.my_location)).dx, .01));
        expect(tester.getRect(find.text('显示歌词译文')).left,
            closeTo(tester.getRect(find.text('回到当前歌词')).left, .01));
        await capture(tester, 'menu-$dark-$scale');
        await tester.tap(find.text('显示歌词译文'));
        await tester.pumpAndSettle();
        expect(controller.showTranslation, isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'existing checkbox forms keep icon and check vertical centers at large text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(720, 1100);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final song = Audio.online(
        provider: 'qq',
        id: 'fixture',
        title: '演示歌曲',
        artist: '演示歌手',
        album: '演示专辑',
        duration: 123);
    final forms = <String, Widget>{
      'playlist-columns':
          PlaylistPresentationDialog(playlist: Playlist('演示歌单', {})),
      'song-picker':
          PlaylistSongPicker(library: [song], existingPaths: const {}),
      'export': const M3uExportDialog(count: 4, skipped: 0),
      'backup': const BackupSelectionDialog(
          contents: BackupContents(
              components: {...BackupComponent.values}, musicFolders: [])),
    };
    for (final entry in forms.entries) {
      await tester.pumpWidget(app(entry.value,
          ColorScheme.fromSeed(seedColor: const Color(0xff965341)), 1.6));
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsWidgets);
      for (final element in find.byType(CheckboxListTile).evaluate()) {
        final row = element.widget as CheckboxListTile;
        if (row.secondary == null) continue;
        final finder = find.byWidget(row);
        final check =
            find.descendant(of: finder, matching: find.byType(Checkbox));
        final icon =
            find.descendant(of: finder, matching: find.byType(Icon)).first;
        expect(
            tester.getCenter(check).dy, closeTo(tester.getCenter(icon).dy, .01),
            reason: entry.key);
      }
      await capture(tester, entry.key);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
}
