import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/now_playing_page/component/current_playlist_view.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/play_service/queue_edits.dart';
import 'package:dan_player/play_service/segment_loop.dart';
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
  int? lastRemoved;
  int? lastMoved;
  final history = QueueEditHistory<Audio>();
  @override
  double get position => 47.25;
  @override
  final resolvingAudioPath = ValueNotifier<String?>(null);
  @override
  final isChangingOutput = ValueNotifier(false);
  @override
  final segmentLoop = SegmentLoopController();
  @override
  bool get canEditQueue => resolvingAudioPath.value == null;

  @override
  bool get canUndoQueueEdit =>
      canEditQueue &&
      history.canUndo(playlist.value, playlist.value, selectedIndex);

  void commit(QueueEdit<Audio> edit) {
    history.record(QueueSnapshot(playlist.value, playlist.value, selectedIndex),
        QueueSnapshot(edit.items, edit.items, edit.currentIndex));
    selectedIndex = edit.currentIndex;
    playlist.value = edit.items;
    notifyListeners();
  }

  @override
  bool undoQueueEdit() {
    if (!canEditQueue) return false;
    final state = history.undo(playlist.value, playlist.value, selectedIndex);
    if (state == null) return false;
    selectedIndex = state.currentIndex;
    playlist.value = state.items;
    notifyListeners();
    return true;
  }

  @override
  bool removeQueueItem(int index) {
    final edit = QueueEdit.remove(playlist.value, selectedIndex, index);
    if (edit == null || !canEditQueue) return false;
    lastRemoved = index;
    commit(edit);
    return true;
  }

  @override
  bool moveQueueItemNext(int index) {
    final edit = QueueEdit.moveNext(playlist.value, selectedIndex, index);
    if (edit == null || !canEditQueue) return false;
    lastMoved = index;
    commit(edit);
    return true;
  }

  @override
  bool keepOnlyCurrentQueueItem() {
    commit(QueueEdit([nowPlaying!], 0));
    return true;
  }

  @override
  int get playlistIndex => selectedIndex;

  @override
  void playIndexOfPlaylist(int audioIndex) {
    if (audioIndex < 0 || audioIndex >= playlist.value.length) return;
    history.clear();
    selectedIndex = audioIndex;
    lastPlayed = audioIndex;
    nowPlaying = playlist.value[audioIndex];
    notifyListeners();
  }

  @override
  void dispose() {
    playlist.dispose();
    resolvingAudioPath.dispose();
    isChangingOutput.dispose();
    segmentLoop.dispose();
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
  testWidgets('queue action icons share a center line at every text scale',
      (tester) async {
    final playback = _QueuePlayback([CategoryTestAudio('first')]);
    addTearDown(playback.dispose);
    for (final scale in [1.0, 2.0, 3.0]) {
      await tester.pumpWidget(_host(playback, textScale: scale));
      await tester.pumpAndSettle();
      final center = tester.getCenter(find.byIcon(Symbols.my_location)).dy;
      for (final icon in [
        Symbols.playlist_add,
        Symbols.playlist_remove,
        Symbols.undo,
        Symbols.repeat
      ]) {
        expect(tester.getCenter(find.byIcon(icon)).dy, closeTo(center, 0.1),
            reason: 'toolbar icon at text scale $scale');
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('undo restores the current occurrence and waits through loading',
      (tester) async {
    final same = CategoryTestAudio('same');
    final last = CategoryTestAudio('last');
    final playback = _QueuePlayback([same, last, same], selectedIndex: 2);
    addTearDown(playback.dispose);
    await tester.pumpWidget(_host(playback));
    await tester.pumpAndSettle();
    IconButton undo() => tester
        .widget<IconButton>(find.byKey(const ValueKey('queue-undo-edit')));
    expect(undo().onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('queue-keep-current')));
    await tester.pumpAndSettle();
    expect(undo().onPressed, isNotNull);
    playback.resolvingAudioPath.value = 'pending';
    await tester.pumpAndSettle();
    expect(undo().onPressed, isNull);
    expect(playback.undoQueueEdit(), isFalse);
    playback.resolvingAudioPath.value = null;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('queue-undo-edit')));
    await tester.pumpAndSettle();
    expect(playback.playlist.value, [same, last, same]);
    expect(playback.selectedIndex, 2);
    expect(playback.nowPlaying, same);
    expect(playback.position, 47.25);
    expect(playback.lastPlayed, isNull);
    expect(undo().onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('queue edits preserve the active duplicate and block during load',
      (tester) async {
    final duplicate = CategoryTestAudio('same');
    final playback = _QueuePlayback([
      duplicate,
      CategoryTestAudio('second'),
      duplicate,
      CategoryTestAudio('last')
    ], selectedIndex: 2);
    addTearDown(playback.dispose);
    await tester.pumpWidget(_host(playback));
    await tester.pumpAndSettle();
    await tester
        .longPress(find.byKey(const ValueKey('current-playlist-item-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从播放队列移除'));
    await tester.pumpAndSettle();
    expect(playback.lastRemoved, 0);
    expect(playback.selectedIndex, 1);
    expect(playback.nowPlaying, same(duplicate));
    expect(playback.playlist.value.length, 3);
    playback.resolvingAudioPath.value = 'loading';
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<IconButton>(
                find.byKey(const ValueKey('queue-keep-current')))
            .onPressed,
        isNull);
    playback.resolvingAudioPath.value = null;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('queue-keep-current')));
    await tester.pumpAndSettle();
    expect(playback.playlist.value, [duplicate]);
    expect(playback.selectedIndex, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel saving a queue leaves it unchanged and allows retry',
      (tester) async {
    final playback = _QueuePlayback([CategoryTestAudio('first')]);
    addTearDown(playback.dispose);
    await tester.pumpWidget(_host(playback));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('queue-save-playlist')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('playlist-name-input')), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(playback.playlist.value.length, 1);
    expect(
        tester
            .widget<IconButton>(
                find.byKey(const ValueKey('queue-save-playlist')))
            .onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
  });

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
