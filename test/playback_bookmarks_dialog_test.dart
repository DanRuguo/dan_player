import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playback_bookmarks.dart';
import 'package:dan_player/page/now_playing_page/component/playback_bookmarks_dialog.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/play_service/segment_loop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/music_category_fixtures.dart';

class _MemoryBookmarks extends PlaybackBookmarkStore {
  _MemoryBookmarks() : super(File('unused-bookmark-widget-fixture.json'));
  final entries = <PlaybackBookmark>[];
  @override
  Future<List<PlaybackBookmark>> forTrack(String localPath) async =>
      List.of(entries);
  @override
  Future<void> add(
      {required String localPath,
      required String label,
      required double position,
      double? end}) async {
    entries.add(PlaybackBookmark(
        id: '${entries.length}',
        track: localPath,
        label: label,
        positionMs: (position * 1000).round(),
        endMs: end == null ? null : (end * 1000).round()));
  }

  @override
  Future<void> rename(String id, String label) async {
    final index = entries.indexWhere((item) => item.id == id);
    final item = entries[index];
    entries[index] = PlaybackBookmark(
        id: id,
        track: item.track,
        label: label,
        positionMs: item.positionMs,
        endMs: item.endMs);
  }

  @override
  Future<void> remove(String id) async =>
      entries.removeWhere((item) => item.id == id);
}

class _BookmarkPlayback extends ChangeNotifier implements PlaybackService {
  @override
  Audio? nowPlaying = CategoryTestAudio('bookmark-track');
  @override
  final segmentLoop = SegmentLoopController();
  @override
  final resolvingAudioPath = ValueNotifier<String?>(null);
  @override
  final isChangingOutput = ValueNotifier(false);
  @override
  double position = 10;
  @override
  double get length => 120;
  @override
  bool get canUseSegmentLoop =>
      nowPlaying?.isLocal == true && resolvingAudioPath.value == null;
  @override
  void seek(double value) => position = value;
  @override
  bool setSegmentLoopEnabled(bool value) {
    segmentLoop.setEnabled(value);
    if (value) seek(segmentLoop.start!);
    return segmentLoop.enabled;
  }

  void changeTrack() {
    nowPlaying = CategoryTestAudio('different-track');
    notifyListeners();
  }

  @override
  void dispose() {
    segmentLoop.dispose();
    resolvingAudioPath.dispose();
    isChangingOutput.dispose();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late PlaybackBookmarkStore store;
  late _BookmarkPlayback service;
  setUp(() async {
    store = _MemoryBookmarks();
    service = _BookmarkPlayback();
    await store.add(
        localPath: service.nowPlaying!.path, label: 'Opening', position: 7);
    await store.add(
        localPath: service.nowPlaying!.path,
        label: 'Chorus',
        position: 20,
        end: 40);
  });
  tearDown(() => service.dispose());

  testWidgets(
      'position and A-B recall preserve paused playback and track changes disable actions',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PlaybackBookmarksDialog(service: service, store: store))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chorus'));
    expect(service.segmentLoop.enabled, isTrue);
    expect(service.segmentLoop.end, 40);
    expect(service.position, 20);
    await tester.tap(find.text('Opening'));
    expect(service.segmentLoop.enabled, isFalse);
    expect(service.position, 7);
    await tester.enterText(find.byType(TextField), 'Named position');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('bookmark-save-position')));
      await store.forTrack(service.nowPlaying!.path);
    });
    await tester.pumpAndSettle();
    expect(find.text('Named position'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名书签'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Renamed opening');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('Renamed opening'), findsOneWidget);
    await tester.ensureVisible(find.byType(PopupMenuButton<String>).last);
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除书签'));
    await tester.pumpAndSettle();
    expect(find.text('Named position'), findsNothing);
    service.changeTrack();
    await tester.pumpAndSettle();
    final save = tester.widget<FilledButton>(
        find.byKey(const ValueKey('bookmark-save-position')));
    expect(save.onPressed, isNull);
    service.position = 1;
    await tester.ensureVisible(find.text('Renamed opening'));
    await tester.tap(find.text('Renamed opening'));
    expect(service.position, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'bookmark panel scrolls at narrow width with large text in both themes',
      (tester) async {
    tester.view.physicalSize = const Size(360, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(MaterialApp(
          theme:
              ThemeData(colorSchemeSeed: Colors.teal, brightness: brightness),
          home: MediaQuery(
              data: const MediaQueryData(
                  size: Size(360, 520), textScaler: TextScaler.linear(1.8)),
              child: Scaffold(
                  body: PlaybackBookmarksDialog(
                      key: ValueKey(brightness),
                      service: service,
                      store: store)))));
      await tester.pumpAndSettle();
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
