import 'dart:async';
import 'dart:io';
import 'package:dan_player/component/playlist_exchange_dialog.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/page/now_playing_page/component/current_playlist_view.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'support/listening_status_fixture.dart';
import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String name) => find.byKey(ValueKey(name));

class _CueAudio extends CategoryTestAudio {
  _CueAudio() : super('CUE part', path: _reference.identity);
  static const _reference = CueTrackReference(
      cuePath: 'D:/Music/disc.cue',
      sourcePath: 'D:/Music/disc.flac',
      number: 2,
      startFrame: 300);
  @override
  CueTrackReference get cueTrack => _reference;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPlaylistFeatureFonts);
  late Directory fixture;
  setUp(() async {
    final parent = Directory(path.normalize(path.join(Directory.current.path,
        '..', 'tool', 'qa-local', 'listening-status', 'export-data')));
    await parent.create(recursive: true);
    fixture = await parent.createTemp('queue-m3u-');
  });
  tearDown(() async {
    final parent = path.normalize(path.join(Directory.current.path, '..',
        'tool', 'qa-local', 'listening-status', 'export-data'));
    expect(path.isWithin(parent, fixture.path), isTrue);
    await fixture.delete(recursive: true);
    uiLanguage.value = UiLanguage.zh;
  });

  Future<void> mount(WidgetTester tester, ListeningStatusPlayback service,
      {FutureOr<String?> Function(String)? pickFile,
      GlobalKey? boundary,
      double scale = 1,
      double width = 1000}) async {
    sizePlaylistFeature(tester, width: width, height: 900);
    await tester.pumpWidget(listeningStatusHost(
        CurrentPlaylistView(playbackService: service, pickM3uFile: pickFile),
        scale: scale,
        boundary: boundary));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, {bool filtered = false}) async {
    await tester.ensureVisible(_key('queue-export-m3u'));
    await tester.tap(_key('queue-export-m3u'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(
        _key(filtered ? 'queue-export-m3u-search' : 'queue-export-m3u-all')));
    await tester.pumpAndSettle();
  }

  Future<void> confirmFile(WidgetTester tester, File file) async {
    await tester.tap(_key('m3u-export-confirm'));
    await tester.pumpAndSettle();
    final wait = Stopwatch()..start();
    // Menu activation can retain the fake zone. Alternate real I/O with frame
    // pumps so write/flush/rename continuations and the dialog exit can finish.
    while (true) {
      final exists = (await tester.runAsync(file.exists))!;
      final finished =
          tester.widget<IconButton>(_key('queue-export-m3u')).onPressed != null;
      if (exists && finished) return;
      if (wait.elapsed > const Duration(seconds: 5)) {
        throw StateError('M3U8 export did not finish');
      }
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
  }

  testWidgets('queue export freezes repeated paths and metadata before dialogs',
      (tester) async {
    final first = CategoryTestAudio('First',
        artist: 'Original Artist', path: 'D:/Music/First.mp3', duration: 120);
    final last =
        CategoryTestAudio('Last', path: 'D:/Music/Last.flac', duration: 90);
    final online = CategoryTestAudio('Remote', online: true);
    final service =
        ListeningStatusPlayback([first, online, first, _CueAudio(), last]);
    addTearDown(service.dispose);
    final file = File(path.join(fixture.path, 'queue.m3u8'));
    await mount(tester, service, pickFile: (_) => file.path);
    final originalQueue = service.playlist.value;
    await open(tester);
    final options =
        tester.widget<M3uExportDialog>(find.byType(M3uExportDialog));
    expect(options.count, 3);
    expect(options.skipped, 2);
    expect(find.text(ui('跳过 {0} 项联网歌曲或不支持的文件引用。', [2])), findsOneWidget);
    expect(service.playlist.value, same(originalQueue));
    first.title = 'Later title';
    first.artist = 'Later artist';
    first.duration = 999;
    first.path = 'D:/Music/Later.wav';
    service.replaceQueue([online]);
    await tester.pump();
    await confirmFile(tester, file);
    final text = (await tester.runAsync(file.readAsString))!;
    expect(RegExp('#EXTINF:').allMatches(text), hasLength(3));
    expect(RegExp('Original Artist - First').allMatches(text), hasLength(2));
    expect(RegExp('First.mp3').allMatches(text), hasLength(2));
    expect(text, contains('#EXTINF:120,Original Artist - First'));
    expect(text, contains('#EXTINF:90,Artist - Last'));
    expect(text, isNot(contains('Later')));
    expect(text, isNot(contains('Remote')));
    expect(text, isNot(contains('cue:')));
    expect(service.playlist.value, [online]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'filtered export freezes clicked projection before queue and query changes',
      (tester) async {
    final first =
        CategoryTestAudio('Night first', path: 'D:/Music/Night first.mp3');
    final last =
        CategoryTestAudio('Night last', path: 'D:/Music/Night last.mp3');
    final excluded = CategoryTestAudio('Day', path: 'D:/Music/day.mp3');
    final service = ListeningStatusPlayback([first, excluded, first, last]);
    addTearDown(service.dispose);
    final file = File(path.join(fixture.path, 'filtered.m3u8'));
    await mount(tester, service, pickFile: (_) => file.path);
    await tester.enterText(_key('queue-search'), 'night');
    await tester.pumpAndSettle();
    await open(tester, filtered: true);
    expect(
        tester.widget<M3uExportDialog>(find.byType(M3uExportDialog)).count, 3);
    tester.widget<TextField>(_key('queue-search')).onChanged!('day');
    service.replaceQueue([excluded]);
    await tester.pump();
    await confirmFile(tester, file);
    final text = (await tester.runAsync(file.readAsString))!;
    expect(RegExp('#EXTINF:120,Artist - Night first').allMatches(text),
        hasLength(2));
    expect(RegExp('Night first.mp3').allMatches(text), hasLength(2));
    expect(text.indexOf('Night first'), lessThan(text.indexOf('Night last')));
    expect(text, isNot(contains('day.mp3')));
    expect(service.playlist.value, [excluded]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cancel options and picker leave queue untouched and allow retry',
      (tester) async {
    final service = ListeningStatusPlayback([CategoryTestAudio('Local')]);
    addTearDown(service.dispose);
    var picks = 0;
    await mount(tester, service, pickFile: (_) {
      picks++;
      return null;
    });
    final original = service.playlist.value;
    await open(tester);
    await tester.tap(find.widgetWithText(TextButton, ui('取消')));
    await tester.pumpAndSettle();
    expect(picks, 0);
    expect(service.playlist.value, same(original));
    expect(tester.widget<IconButton>(_key('queue-export-m3u')).onPressed,
        isNotNull);
    await open(tester);
    await tester.tap(_key('m3u-export-confirm'));
    await tester.pumpAndSettle();
    expect(picks, 1);
    expect(service.playlist.value, same(original));
    expect(tester.widget<IconButton>(_key('queue-export-m3u')).onPressed,
        isNotNull);
    expect(fixture.listSync(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'unsupported-only queue reports no local references without picker',
      (tester) async {
    final service = ListeningStatusPlayback(
        [CategoryTestAudio('Remote', online: true), _CueAudio()]);
    addTearDown(service.dispose);
    var picks = 0;
    await mount(tester, service, pickFile: (_) {
      picks++;
      return null;
    });
    await open(tester);
    expect(find.byType(M3uExportDialog), findsNothing);
    expect(find.text(ui('所选歌曲中没有可导出的本地文件。')), findsOneWidget);
    expect(picks, 0);
    expect(service.playlist.value, hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('empty queue and empty search keep export unavailable',
      (tester) async {
    final service = ListeningStatusPlayback([]);
    addTearDown(service.dispose);
    await mount(tester, service, pickFile: (_) => null);
    expect(
        tester.widget<IconButton>(_key('queue-export-m3u')).onPressed, isNull);
    service.replaceQueue([CategoryTestAudio('Local')]);
    await tester.pumpAndSettle();
    await tester.enterText(_key('queue-search'), 'absent');
    await tester.pumpAndSettle();
    await tester.ensureVisible(_key('queue-export-m3u'));
    await tester.tap(_key('queue-export-m3u'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<MenuItemButton>(_key('queue-export-m3u-search'))
            .onPressed,
        isNull);
    expect(
        tester.widget<MenuItemButton>(_key('queue-export-m3u-all')).onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final language in UiLanguage.values) {
    for (final width in [380.0, 1000.0]) {
      testWidgets('queue export menu fits ${language.name}/$width',
          (tester) async {
        uiLanguage.value = language;
        final service = ListeningStatusPlayback([CategoryTestAudio('Night')]);
        addTearDown(service.dispose);
        final boundary = GlobalKey();
        await mount(tester, service,
            pickFile: (_) => null,
            boundary: boundary,
            width: width,
            scale: width < 500 ? 2 : 1);
        await tester.enterText(_key('queue-search'), 'night');
        await tester.pumpAndSettle();
        await tester.ensureVisible(_key('queue-export-m3u'));
        await tester.tap(_key('queue-export-m3u'));
        await tester.pumpAndSettle();
        for (final key in ['queue-export-m3u-all', 'queue-export-m3u-search']) {
          final rect = tester.getRect(_key(key));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
          expect(_key(key).hitTestable(), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await captureListeningStatus(
            tester, boundary, 'export-menu-${language.name}-${width.toInt()}');
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
