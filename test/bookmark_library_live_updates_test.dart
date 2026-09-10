import 'dart:async';
import 'dart:io';

import 'package:dan_player/component/listening_tools_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playback_bookmarks.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/play_service/segment_loop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

class _DeferredBookmarks extends PlaybackBookmarkStore {
  _DeferredBookmarks() : super(File('unused-deferred-bookmarks.json'));
  final reads = <Completer<List<PlaybackBookmark>>>[];
  @override
  Future<List<PlaybackBookmark>> all() {
    final read = Completer<List<PlaybackBookmark>>();
    reads.add(read);
    return read.future;
  }
}

class _MemoryBookmarks extends PlaybackBookmarkStore {
  _MemoryBookmarks(this.items) : super(File('unused-library-bookmarks.json'));
  final List<PlaybackBookmark> items;
  @override
  Future<List<PlaybackBookmark>> all() async => List.unmodifiable(items);
}

class _BookmarkPlayback implements PlaybackService {
  _BookmarkPlayback(this.nowPlaying);
  @override
  Audio? nowPlaying;
  @override
  final segmentLoop = SegmentLoopController();
  @override
  double get length => 120;
  bool succeed = true;
  double? lastPosition;
  @override
  Future<bool> playAudioAt(Audio audio,
      {required double position, bool Function()? stillCurrent}) async {
    if (!succeed || stillCurrent?.call() == false) return false;
    nowPlaying = audio;
    lastPosition = position;
    segmentLoop.manualSeek(position);
    return true;
  }

  @override
  bool setSegmentLoopEnabled(bool enabled) {
    segmentLoop.setEnabled(enabled);
    return segmentLoop.enabled;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Widget host(PlaybackBookmarkStore store, {PlaybackService? service}) =>
      MaterialApp(
          home: Scaffold(
              body: BookmarkLibraryDialog(
                  embedded: true, store: store, playbackService: service)));

  PlaybackBookmark item(String label, {String track = 'missing'}) =>
      PlaybackBookmark(
          id: label, track: track, label: label, positionMs: 20000);

  late Directory directory;
  late PlaybackBookmarkStore store;
  setUp(() async {
    final parent = Directory(
        '${Directory.current.path}/build/test-data/bookmark-library-updates');
    await parent.create(recursive: true);
    directory = await parent.createTemp('isolated-');
    store = PlaybackBookmarkStore(File('${directory.path}/bookmarks.json'));
    await store.all();
  });
  tearDown(() async => directory.delete(recursive: true));

  test('bookmark notifications follow successful durable saves only', () async {
    final before = PlaybackBookmarkStore.changes.value;
    await store.add(localPath: 'fixture.flac', label: 'Saved', position: 20);
    expect(PlaybackBookmarkStore.changes.value, before + 1);
    expect(
        (await PlaybackBookmarkStore(store.file).all()).single.label, 'Saved');
    await Directory('${store.file.path}.tmp').create();
    await expectLater(
        store.add(localPath: 'fixture.flac', label: 'Failed', position: 25),
        throwsA(isA<FileSystemException>()));
    expect(PlaybackBookmarkStore.changes.value, before + 1);
    expect((await store.all()).single.label, 'Saved');
  });

  testWidgets('open bookmark library follows external add rename and removal',
      (tester) async {
    final memory = _MemoryBookmarks([]);
    await tester.pumpWidget(host(memory));
    await tester.pumpAndSettle();
    expect(find.text('New bookmark'), findsNothing);
    memory.items.add(item('New bookmark'));
    PlaybackBookmarkStore.changes.value++;
    await tester.pumpAndSettle();
    expect(find.text('New bookmark'), findsOneWidget);
    await tester.tap(find.text('New bookmark'));
    await tester.pumpAndSettle();
    final selected = memory.items.single;
    memory.items[0] = PlaybackBookmark(
        id: selected.id,
        track: selected.track,
        label: 'Renamed',
        positionMs: selected.positionMs);
    PlaybackBookmarkStore.changes.value++;
    await tester.pumpAndSettle();
    expect(find.text('New bookmark'), findsNothing);
    expect(find.text('Renamed'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    memory.items.clear();
    PlaybackBookmarkStore.changes.value++;
    await tester.pumpAndSettle();
    expect(find.text('Renamed'), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'late bookmark loads cannot replace newer results or keep listening',
      (tester) async {
    final deferred = _DeferredBookmarks();
    await tester.pumpWidget(host(deferred));
    expect(deferred.reads, hasLength(1));
    PlaybackBookmarkStore.changes.value++;
    await tester.pump();
    expect(deferred.reads, hasLength(2));
    deferred.reads.last.complete([item('Newest')]);
    await tester.pumpAndSettle();
    deferred.reads.first.complete([item('Stale')]);
    await tester.pumpAndSettle();
    expect(find.text('Newest'), findsOneWidget);
    expect(find.text('Stale'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    PlaybackBookmarkStore.changes.value++;
    await tester.pump();
    expect(deferred.reads, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  for (final succeeds in [true, false]) {
    testWidgets(
        'point bookmark clears an existing loop only on success $succeeds',
        (tester) async {
      final audio = CategoryTestAudio('Point bookmark song');
      final original = AudioLibrary.instance.audioCollection;
      AudioLibrary.instance.audioCollection = [audio];
      addTearDown(() => AudioLibrary.instance.audioCollection = original);
      final playback = _BookmarkPlayback(audio)..succeed = succeeds;
      addTearDown(playback.segmentLoop.dispose);
      playback.segmentLoop
        ..setStart(10, 120)
        ..setEnd(40, 120)
        ..setEnabled(true);
      await tester.pumpWidget(host(
          _MemoryBookmarks([item('Inside loop', track: audio.stableTrackId)]),
          service: playback));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('从书签播放'));
      await tester.pumpAndSettle();
      expect(playback.segmentLoop.enabled, !succeeds);
      expect(playback.segmentLoop.start, 10);
      expect(playback.segmentLoop.end, 40);
      expect(playback.lastPosition, succeeds ? 20 : null);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
