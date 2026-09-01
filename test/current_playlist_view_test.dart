import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/now_playing_page/component/current_playlist_view.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'support/music_category_fixtures.dart';

class _QueuePlayback extends ChangeNotifier implements PlaybackService {
  _QueuePlayback(List<Audio> audios, {this.selectedIndex = 0})
      : playlist = ValueNotifier(List<Audio>.from(audios)),
        nowPlaying = audios.isEmpty ? null : audios[selectedIndex];

  @override
  final ValueNotifier<List<Audio>> playlist;

  @override
  Audio? nowPlaying;

  int selectedIndex;
  int? lastPlayed;

  @override
  int get playlistIndex => selectedIndex;

  @override
  void playIndexOfPlaylist(int audioIndex) {
    if (audioIndex < 0 || audioIndex >= playlist.value.length) return;
    selectedIndex = audioIndex;
    lastPlayed = audioIndex;
    nowPlaying = playlist.value[audioIndex];
    notifyListeners();
  }

  @override
  void dispose() {
    playlist.dispose();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(_QueuePlayback playback,
        {double textScale = 1, double width = 620}) =>
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        fontFamily: 'DanQueueFixture',
      ),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: SizedBox(
            width: width,
            height: 440,
            child: CurrentPlaylistView(playbackService: playback),
          ),
        ),
      ),
    );

void main() {
  testWidgets(
      'shared queue uses app typography and one occurrence for current state',
      (tester) async {
    final duplicate = CategoryTestAudio('duplicate', duration: 125);
    final other = CategoryTestAudio('other', duration: 245);
    final playback =
        _QueuePlayback([duplicate, duplicate, other], selectedIndex: 1);
    addTearDown(playback.dispose);

    await tester.pumpWidget(_host(playback));
    await tester.pumpAndSettle();

    final heading = tester
        .widget<Text>(find.byKey(const ValueKey('current-playlist-heading')));
    final title = tester
        .widget<Text>(find.byKey(const ValueKey('current-playlist-title-0')));
    final metadata = tester.widget<Text>(
        find.byKey(const ValueKey('current-playlist-metadata-0')));
    expect(heading.style?.fontFamily, 'DanQueueFixture');
    expect(title.style?.fontFamily, 'DanQueueFixture');
    expect(metadata.style?.fontFamily, 'DanQueueFixture');
    expect(find.byIcon(Symbols.equalizer), findsOneWidget,
        reason: 'a duplicated path must not make two rows look current');
    expect(find.text('0:04:05'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('current-playlist-item-2')));
    await tester.pumpAndSettle();
    expect(playback.lastPlayed, 2);
    expect(find.byIcon(Symbols.equalizer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'queue remains usable with large text and has a stable empty state',
      (tester) async {
    final playback = _QueuePlayback([
      CategoryTestAudio('A very long queue title that must be ellipsized'),
      CategoryTestAudio('second'),
    ]);
    addTearDown(playback.dispose);

    await tester.pumpWidget(_host(playback, textScale: 3, width: 280));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('current-playlist-list')), findsOneWidget);
    expect(tester.takeException(), isNull);

    playback.nowPlaying = null;
    playback.playlist.value = const [];
    playback.notifyListeners();
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('current-playlist-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('current-playlist-list')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
