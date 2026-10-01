import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/playlist_ui_actions.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/page/now_playing_page/component/current_playlist_view.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String name) => find.byKey(ValueKey(name));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory fixture;
  late Directory data;
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
    final parent = Directory(path.normalize(path.join(Directory.current.path,
        '..', 'tool', 'qa-local', 'playlist-features', 'data')));
    await parent.create(recursive: true);
    fixture = await parent.createTemp('queue-save-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => fixture.path);
    data = await getAppDataDir();
    expect(path.isWithin(fixture.path, data.path), isTrue);
    await readPlaylists();
    expect(PLAYLISTS, isEmpty);
    playlistUiSaveError.value = null;
    uiLanguage.value = UiLanguage.zh;
  });
  tearDown(() async {
    PLAYLISTS.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    final parent = path.normalize(path.join(Directory.current.path, '..',
        'tool', 'qa-local', 'playlist-features', 'data'));
    expect(path.isWithin(parent, fixture.path), isTrue);
    await fixture.delete(recursive: true);
    uiLanguage.value = UiLanguage.zh;
  });

  Future<void> mount(
      WidgetTester tester, PlaylistFeaturePlayback playback) async {
    sizePlaylistFeature(tester);
    await tester.pumpWidget(
        playlistFeatureHost(CurrentPlaylistView(playbackService: playback)));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester, String name) async {
    await tester.enterText(_key('playlist-name-input'), name);
    await tester.runAsync(() async {
      // Construct the completion in the real zone too: a fake-zone Completer
      // cannot finish while runAsync is waiting for that zone's microtasks.
      final written = Completer<void>();
      void changed() {
        if (!playlistUiSaving.value && !written.isCompleted) written.complete();
      }

      playlistUiSaving.addListener(changed);
      try {
        await tester.tap(find.widgetWithText(FilledButton, ui('保存')));
        await written.future.timeout(const Duration(seconds: 5));
      } finally {
        playlistUiSaving.removeListener(changed);
      }
    });
    await tester.pumpAndSettle();
    expect(playlistUiSaveError.value, isNull);
  }

  testWidgets(
      'filtered save preserves clicked occurrences across queue replacement',
      (tester) async {
    final first = CategoryTestAudio('Night first', artist: 'Selected Artist');
    final excluded = CategoryTestAudio('Day', artist: 'Other Artist');
    final second = CategoryTestAudio('Night last', artist: 'Selected Artist');
    final playback = PlaylistFeaturePlayback([first, excluded, first, second],
        currentIndex: 1);
    await mount(tester, playback);
    final originalQueue = playback.playlist.value;
    await tester.enterText(_key('queue-search'), 'night selected');
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(_key('queue-search-count')).data,
        contains('3 / 4'));
    // Start the dialog's asynchronous save operation in the real I/O zone.
    // Its continuation retains that zone when the name form later completes.
    await tester.runAsync(() => tester.tap(_key('queue-save-search-playlist')));
    await tester.pumpAndSettle();
    expect(playback.playlist.value, same(originalQueue));
    expect(playback.playlistIndex, 1);
    expect(playback.nowPlaying, same(excluded));
    expect(tester.widget<IconButton>(_key('queue-save-playlist')).onPressed,
        isNull);
    // The search field and queue can change while a modal owns focus.
    tester.widget<TextField>(_key('queue-search')).onChanged!('day');
    playback.replaceQueue([excluded]);
    await tester.pump();
    await confirm(tester, 'Saved search');
    expect(PLAYLISTS.single.flattenAudios(), [first, first, second]);
    expect(
        PLAYLISTS.single.flattenEntries().map((entry) => entry.entryId).toSet(),
        hasLength(3));
    expect(playback.playlist.value, [excluded]);
    expect(playback.nowPlaying, same(excluded));
    final json = (await tester.runAsync(() async => jsonDecode(
        await File(path.join(data.path, 'playlists.json')).readAsString())))!;
    expect(json.toString(), contains('Saved search'));
    await tester.pumpWidget(const SizedBox());
    playback.dispose();
  });

  testWidgets('empty and cancelled filtered saves preserve playlists and queue',
      (tester) async {
    final playback = PlaylistFeaturePlayback([CategoryTestAudio('Night')]);
    await mount(tester, playback);
    final queue = playback.playlist.value;
    expect(_key('queue-save-search-playlist'), findsNothing);
    await tester.enterText(_key('queue-search'), 'absent');
    await tester.pumpAndSettle();
    expect(
        tester.widget<IconButton>(_key('queue-save-search-playlist')).onPressed,
        isNull);
    await tester.enterText(_key('queue-search'), 'night');
    await tester.pumpAndSettle();
    await tester.tap(_key('queue-save-search-playlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, ui('取消')));
    await tester.pumpAndSettle();
    expect(PLAYLISTS, isEmpty);
    expect(playback.playlist.value, same(queue));
    expect(
        tester.widget<IconButton>(_key('queue-save-search-playlist')).onPressed,
        isNotNull);
    await tester.pumpWidget(const SizedBox());
    playback.dispose();
  });

  testWidgets('whole queue save remains available while search is active',
      (tester) async {
    final first = CategoryTestAudio('Night');
    final second = CategoryTestAudio('Day');
    final playback = PlaylistFeaturePlayback([first, second]);
    await mount(tester, playback);
    final queue = playback.playlist.value;
    await tester.enterText(_key('queue-search'), 'night');
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(_key('queue-save-playlist')));
    await tester.pumpAndSettle();
    await confirm(tester, 'Whole queue');
    expect(PLAYLISTS.single.flattenAudios(), [first, second]);
    expect(playback.playlist.value, same(queue));
    expect(playback.playlistIndex, 0);
    await tester.pumpWidget(const SizedBox());
    playback.dispose();
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets(
          'filtered save is readable and tappable $language narrow=$narrow',
          (tester) async {
        sizePlaylistFeature(tester, width: narrow ? 380 : 1100, height: 900);
        uiLanguage.value = language;
        final boundary = GlobalKey();
        final playback = PlaylistFeaturePlayback([
          CategoryTestAudio('Night song', artist: 'Artist', album: 'Album'),
          CategoryTestAudio('Day song'),
        ]);
        await tester.pumpWidget(playlistFeatureHost(
            CurrentPlaylistView(playbackService: playback),
            textScale: narrow ? 2 : 1,
            boundary: boundary));
        await tester.enterText(_key('queue-search'), 'night');
        await tester.pumpAndSettle();
        final count = tester.renderObject(_key('queue-search-count'));
        expect(count.paintBounds.width, greaterThan(100));
        final save = _key('queue-save-search-playlist');
        expect(save.hitTestable(), findsOneWidget);
        expect(tester.getSize(save).shortestSide, greaterThanOrEqualTo(40));
        expect(tester.widget<IconButton>(save).tooltip, ui('将搜索结果保存为歌单'));
        if (language != UiLanguage.zh) {
          expect(tester.widget<IconButton>(save).tooltip, isNot('将搜索结果保存为歌单'));
        }
        expect(tester.takeException(), isNull);
        await capturePlaylistFeature(tester, boundary,
            '${language.name}-${narrow ? 'narrow' : 'wide'}-queue');
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(_key('playlist-name-input').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capturePlaylistFeature(tester, boundary,
            '${language.name}-${narrow ? 'narrow' : 'wide'}-queue-name');
        await tester.tap(find.widgetWithText(TextButton, ui('取消')));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        playback.dispose();
      });
    }
  }
}
