import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/audios_page.dart';
import 'package:dan_player/page/uni_detail_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

Widget _host(Widget child, {required bool reduced}) => MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: UiLanguageScope(child: child!),
      ),
      home: Scaffold(body: child),
    );

double _opacity(WidgetTester tester, String key) => tester
    .widget<FadeTransition>(find.descendant(
        of: find.byKey(ValueKey(key)), matching: find.byType(FadeTransition)))
    .opacity
    .value;

Future<void> _checkTransition(
    WidgetTester tester, String key, bool reduced) async {
  await tester.pump();
  expect(_opacity(tester, key), reduced ? 1 : 0);
  await tester.pump(AppMotion.standard ~/ 2);
  expect(_opacity(tester, key),
      closeTo(reduced ? 1 : AppMotion.standardCurve.transform(.5), .01));
  await tester.pump(AppMotion.standard ~/ 2);
  expect(_opacity(tester, key), 1);
  expect(tester.takeException(), isNull);
}

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
        'music context-menu selection animates both modes reduced=$reduced',
        (tester) async {
      tester.view.physicalSize = const Size(1120, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final library = AudioLibrary.instance;
      final oldSongs = library.audioCollection;
      final oldPref = AppPreference.instance.audiosPagePref;
      final oldLanguage = uiLanguage.value;
      uiLanguage.value = UiLanguage.zh;
      library.audioCollection = [
        for (var i = 0; i < 40; i++) CategoryTestAudio('Song $i')
      ];
      AppPreference.instance.audiosPagePref =
          PagePreference(0, SortOrder.ascending, ContentView.list);
      addTearDown(() {
        library.audioCollection = oldSongs;
        AppPreference.instance.audiosPagePref = oldPref;
        uiLanguage.value = oldLanguage;
      });
      await tester.pumpWidget(_host(const AudiosPage(), reduced: reduced));
      await tester.pumpAndSettle();
      final controller = tester
          .widget<UniPage<Audio>>(find.byType(UniPage<Audio>))
          .multiSelectController!;
      final scroll =
          tester.state<ScrollableState>(find.byType(Scrollable).last).position;
      scroll.jumpTo(350);
      await tester.pumpAndSettle();
      final menuTile = find.byType(AudioTile).hitTestable().first;
      final chosen = tester.widget<AudioTile>(menuTile);
      final selectedAudio = chosen.playlist[chosen.audioIndex];
      await tester.longPress(menuTile);
      await tester.pumpAndSettle();
      final enter = find.widgetWithText(MenuItemButton, '多选');
      await tester.ensureVisible(enter);
      await tester.tap(enter);
      // MenuItemButton invokes its action after closing the overlay this frame.
      await tester.pump();
      await _checkTransition(tester, 'uni-selection-transition', reduced);
      await tester.pumpAndSettle();
      expect(controller.selected, {selectedAudio});
      final selectedScroll =
          tester.state<ScrollableState>(find.byType(Scrollable).last).position;
      expect(selectedScroll.pixels, closeTo(350, 1));
      // Counts and selected items update without replaying the mode transition.
      await tester
          .tap(find.byKey(const ValueKey('audio-selection-toggle-all')));
      await tester.pump();
      expect(_opacity(tester, 'uni-selection-transition'), 1);
      expect(controller.selected.length, 40);
      await tester.tap(find.byKey(const ValueKey('audio-selection-exit')));
      await _checkTransition(tester, 'uni-selection-transition', reduced);
      await tester.pumpAndSettle();
      expect(controller.enableMultiSelectView, isFalse);
      expect(find.byKey(const ValueKey('music-search-action')), findsOneWidget);
      expect(find.byKey(const ValueKey('audio-selection-exit')), findsNothing);
      expect(
          tester
              .state<ScrollableState>(find.byType(Scrollable).last)
              .position
              .pixels,
          closeTo(350, 1));
    });

    testWidgets(
        'album detail toolbar uses the same mode motion reduced=$reduced',
        (tester) async {
      final songs = [CategoryTestAudio('First'), CategoryTestAudio('Second')];
      final selection = MultiSelectController<Audio>();
      addTearDown(selection.dispose);
      await tester.pumpWidget(_host(
          UniDetailPage<String, Audio, String>(
            pref: PagePreference(0, SortOrder.ascending, ContentView.list),
            primaryContent: 'album',
            primaryPic: Future.value(),
            backgroundPic: Future.value(),
            picShape: PicShape.rrect,
            title: 'Album',
            subtitle: '',
            secondaryContent: songs,
            secondaryContentBuilder: (_, audio, __, ___, ____) =>
                Text(audio.title),
            tertiaryContentTitle: '',
            tertiaryContent: const [],
            tertiaryContentBuilder: (_, item, __, ___) => Text(item),
            enableShufflePlay: false,
            enableSortMethod: false,
            enableSortOrder: false,
            enableSecondaryContentViewSwitch: false,
            multiSelectController: selection,
            enableMultiSelectAddToPlaylist: true,
          ),
          reduced: reduced));
      await tester.pumpAndSettle();
      selection.useMultiSelectView(true);
      await _checkTransition(
          tester, 'uni-detail-selection-transition', reduced);
      selection.select(songs.first);
      await tester.pump();
      expect(_opacity(tester, 'uni-detail-selection-transition'), 1);
      expect(find.text('已选 1 首'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('audio-selection-exit')));
      await _checkTransition(
          tester, 'uni-detail-selection-transition', reduced);
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
      expect(find.byKey(const ValueKey('audio-selection-exit')), findsNothing);
    });
  }
}
