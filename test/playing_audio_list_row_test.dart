import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_item_ink_well.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/playing_audio_list_row.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/page/audios_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
        'current song state follows playback without rebuilding content $brightness',
        (tester) async {
      final path = ValueNotifier<String?>(null);
      addTearDown(path.dispose);
      var builds = 0;
      final children = [
        for (final id in ['a', 'b'])
          PlayingAudioListRow(
            key: ValueKey(id),
            audioPath: id,
            nowPlayingPath: path,
            child: Builder(builder: (_) {
              builds++;
              return AppItemInkWell(
                  onTap: () {},
                  child: SizedBox(height: 64, width: 300, child: Text(id)));
            }),
          ),
      ];
      final theme = ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.orange, brightness: brightness));
      await tester.pumpWidget(MaterialApp(
          theme: theme, home: Scaffold(body: Column(children: children))));
      await tester.pumpAndSettle();
      Color color(String id) => tester
          .widget<Material>(find
              .descendant(
                  of: find.byKey(ValueKey(id)), matching: find.byType(Material))
              .first)
          .color!;
      expect(color('a'), Colors.transparent);
      expect(color('b'), Colors.transparent);
      final baselineBuilds = builds;
      path.value = 'a';
      await tester.pumpAndSettle();
      expect(color('a'), theme.colorScheme.primary.withValues(alpha: .06));
      expect(color('b'), Colors.transparent);
      path.value = 'b';
      await tester.pumpAndSettle();
      expect(color('a'), Colors.transparent);
      expect(color('b'), theme.colorScheme.primary.withValues(alpha: .06));
      path.value = null;
      await tester.pumpAndSettle();
      expect(color('b'), Colors.transparent);
      expect(builds, baselineBuilds,
          reason:
              'Switching track should repaint the state layer, not metadata or artwork');
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(PlayService.isInitialized, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('playing state remains visible with all animation disabled',
      (tester) async {
    final path = ValueNotifier<String?>('a');
    addTearDown(path.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MotionPreferencesScope(
      preferences: const MotionPreferences().all(false),
      child: PlayingAudioListRow(
          audioPath: 'a',
          nowPlayingPath: path,
          child: const SizedBox(width: 300, height: 64)),
    ))));
    await tester.pump();
    final material = tester.widget<Material>(find
        .descendant(
            of: find.byType(PlayingAudioListRow),
            matching: find.byType(Material))
        .first);
    expect(material.color!.a, .06);
    expect(material.animationDuration, Duration.zero);
    path.value = null;
    await tester.pump();
    expect(
        tester
            .widget<Material>(find
                .descendant(
                    of: find.byType(PlayingAudioListRow),
                    matching: find.byType(Material))
                .first)
            .color,
        Colors.transparent);
  });

  for (final view in ContentView.values) {
    testWidgets('music opts in only for list view $view', (tester) async {
      final library = AudioLibrary.instance;
      final previousAudios = library.audioCollection;
      final preferences = AppPreference.instance;
      final previousPref = preferences.audiosPagePref;
      library.audioCollection = [
        CategoryTestAudio('One'),
        CategoryTestAudio('Two')
      ];
      preferences.audiosPagePref = PagePreference(0, SortOrder.ascending, view);
      addTearDown(() {
        library.audioCollection = previousAudios;
        preferences.audiosPagePref = previousPref;
      });
      await tester
          .pumpWidget(const MaterialApp(home: Scaffold(body: AudiosPage())));
      await tester.pumpAndSettle();
      expect(find.byType(PlayingAudioListRow),
          view == ContentView.list ? findsNWidgets(2) : findsNothing);
      expect(PlayService.isInitialized, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  for (final view in PlaylistViewMode.values) {
    testWidgets('playlist opts in only for song list rows $view',
        (tester) async {
      final tree = PlaylistTree([]);
      final parent = tree.createPlaylist('Root');
      tree.createPlaylist('Child', parent: parent);
      tree.addAudio(parent, CategoryTestAudio('One'));
      tree.addAudio(parent, CategoryTestAudio('Two'));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: PlaylistBrowser(
        initialPlaylist: parent,
        tree: tree,
        initialView: view,
        persist: () async {},
        onPlay: (_, __) {},
        trackBuilder: (_, audio, play, action) =>
            ListTile(title: Text(audio.title), trailing: action, onTap: play),
      ))));
      await tester.pumpAndSettle();
      expect(find.byType(PlayingAudioListRow),
          view == PlaylistViewMode.list ? findsNWidgets(2) : findsNothing);
      expect(PlayService.isInitialized, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
