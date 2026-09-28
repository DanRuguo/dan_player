import 'dart:async';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playback_bookmarks.dart';
import 'package:dan_player/page/now_playing_page/component/playback_timeline_bookmarks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store extends PlaybackBookmarkStore {
  _Store()
      : super(
            File('${Directory.systemTemp.path}/unused-timeline-fixture.json'));
  final requests = <String, List<Completer<List<PlaybackBookmark>>>>{};
  @override
  Future<List<PlaybackBookmark>> forTrack(String localPath,
      {String? stableTrackId}) {
    final result = Completer<List<PlaybackBookmark>>();
    requests.putIfAbsent(localPath, () => []).add(result);
    return result.future;
  }
}

Audio _audio(String path) =>
    Audio('Fixture', 'Fixture', 'Fixture', 1, 200, 128, 44100, path, 0, 0, '');

void main() {
  const point = PlaybackBookmark(
      id: 'point', track: 'fixture', label: 'saved', positionMs: 12000);
  testWidgets(
      'changing songs rejects a late bookmark read and retains marks during same-track refresh',
      (tester) async {
    final store = _Store();
    final first = _audio('J:/isolated-fixture/first.wav');
    final second = _audio('J:/isolated-fixture/second.wav');
    Widget host(Audio audio) => MaterialApp(
        home: PlaybackTimelineBookmarks(
            audio: audio,
            store: store,
            builder: (items) => Text(items.map((e) => e.label).join(','))));
    await tester.pumpWidget(host(first));
    await tester.pumpWidget(host(second));
    store.requests[first.path]!.single.complete([point]);
    await tester.pump();
    expect(find.text('saved'), findsNothing);
    store.requests[second.path]!.single.complete([point]);
    await tester.pumpAndSettle();
    expect(find.text('saved'), findsOneWidget);
    PlaybackBookmarkStore.changes.value++;
    await tester.pump();
    expect(find.text('saved'), findsOneWidget,
        reason: 'an unrelated store update must not flash empty marks');
    store.requests[second.path]!.last.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('saved'), findsNothing);
  });

  testWidgets(
      'hidden timeline performs no bookmark reads until visible and rejects disposed results',
      (tester) async {
    final store = _Store();
    final audio = _audio('J:/isolated-fixture/hidden.wav');
    final hidden = ValueNotifier(true);
    addTearDown(hidden.dispose);
    await tester.pumpWidget(MaterialApp(
        home: PlaybackTimelineBookmarks(
            audio: audio,
            store: store,
            hidden: hidden,
            builder: (items) => Text('${items.length}'))));
    expect(store.requests, isEmpty);
    PlaybackBookmarkStore.changes.value++;
    await tester.pump();
    expect(store.requests, isEmpty);
    hidden.value = false;
    await tester.pump();
    expect(store.requests[audio.path], hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    store.requests[audio.path]!.single.complete([point]);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
