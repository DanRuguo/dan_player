import 'dart:async';
import 'dart:io';

import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/playlist_folder_export_dialog.dart';
import 'package:dan_player/component/playlist_ui_actions.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/library/playlist_folder_export.dart';
import 'package:dan_player/page/now_playing_page/component/current_playlist_view.dart';
import 'package:dan_player/taskbar_progress.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/listening_status_fixture.dart';
import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String name) => find.byKey(ValueKey(name));

class _CueAudio extends CategoryTestAudio {
  _CueAudio() : super('CUE', path: _reference.identity);
  static const _reference = CueTrackReference(
      cuePath: 'D:/Music/disc.cue',
      sourcePath: 'D:/Music/disc.flac',
      number: 2,
      startFrame: 300);
  @override
  CueTrackReference get cueTrack => _reference;
}

class _HeldExport {
  final completion = Completer<PlaylistFolderExportResult>();
  PlaylistFolderExportCancellation? cancellation;
  void Function(PlaylistFolderExportProgress)? progress;
  int calls = 0;

  Future<PlaylistFolderExportResult> run(
      PlaylistFolderExportPlan plan, Directory parent,
      {String name = 'Dan Player',
      required PlaylistFolderExportCancellation cancellation,
      void Function(PlaylistFolderExportProgress)? onProgress}) {
    calls++;
    this.cancellation = cancellation;
    progress = onProgress;
    return completion.future;
  }

  void cancelComplete() {
    if (calls > 0 && !completion.isCompleted) {
      completion.completeError(const PlaylistFolderExportCancelled());
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPlaylistFeatureFonts);
  late Directory fixture;
  setUp(() async {
    final parent = Directory(p.normalize(p.join(Directory.current.path, '..',
        'tool', 'qa-local', 'playlist-folder-export', 'fixtures')));
    await parent.create(recursive: true);
    fixture = await parent.createTemp('ui-');
    uiLanguage.value = UiLanguage.zh;
    playlistUiSaveError.value = null;
    playlistUiSaving.value = false;
  });
  tearDown(() async {
    final parent = p.normalize(p.join(Directory.current.path, '..', 'tool',
        'qa-local', 'playlist-folder-export', 'fixtures'));
    expect(p.isWithin(parent, fixture.path), isTrue);
    await fixture.delete(recursive: true);
    uiLanguage.value = UiLanguage.zh;
  });

  CategoryTestAudio audio(String title, String fileName) {
    final file = File(p.join(fixture.path, fileName));
    file.writeAsBytesSync([1, 2, 3, 4, 5]);
    return CategoryTestAudio(title, path: file.path);
  }

  Future<Directory> destination() async =>
      Directory(p.join(fixture.path, 'destination'))..createSync();

  Future<void> mountQueue(WidgetTester tester, ListeningStatusPlayback service,
      {FutureOr<String?> Function()? pickDirectory,
      GlobalKey? boundary,
      double scale = 1,
      double width = 1000,
      Color seed = Colors.teal,
      Brightness brightness = Brightness.light}) async {
    sizePlaylistFeature(tester, width: width, height: 900);
    await tester.pumpWidget(listeningStatusHost(
        CurrentPlaylistView(
            playbackService: service, pickFolderDirectory: pickDirectory),
        scale: scale,
        seed: seed,
        brightness: brightness,
        boundary: boundary));
    await tester.pumpAndSettle();
  }

  Future<void> openQueue(WidgetTester tester, {bool filtered = false}) async {
    await tester.ensureVisible(_key('queue-export-m3u'));
    await tester.tap(_key('queue-export-m3u'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(_key(
        filtered ? 'queue-export-folder-search' : 'queue-export-folder-all')));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.runAsync(() => tester.tap(_key('folder-export-confirm')));
    await tester.pump();
  }

  Future<void> until(WidgetTester tester, bool Function() done) async {
    final wait = Stopwatch()..start();
    while (!done()) {
      if (wait.elapsed > const Duration(seconds: 5)) {
        throw StateError('Folder export UI did not finish');
      }
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<File> exportedPlaylist(Directory parent) async {
    final folders = await parent.list().where((e) => e is Directory).toList();
    expect(folders, hasLength(1));
    return File(p.join(folders.single.path, 'playlist.m3u8'));
  }

  Widget entry(List<Audio> items, _HeldExport held,
          {FutureOr<String?> Function()? pickDirectory}) =>
      Builder(
          builder: (context) => FilledButton(
              key: const ValueKey('start-folder-export'),
              onPressed: () => unawaited(exportMusicFolder(context, items,
                  name: 'Night 夜晚 마지막 collection',
                  pickDirectory: pickDirectory ?? () => fixture.path,
                  runExport: held.run)),
              child: const Text('Export')));

  Future<void> startHeld(WidgetTester tester, _HeldExport held) async {
    sizePlaylistFeature(tester);
    await tester.pumpWidget(listeningStatusHost(entry(
        [CategoryTestAudio('Local'), CategoryTestAudio('Second')], held)));
    await tester.tap(_key('start-folder-export'));
    await tester.pumpAndSettle();
    await confirm(tester);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(PlaylistFolderExportProgressDialog), findsOneWidget);
  }

  testWidgets('queue folder export freezes repeats and metadata before dialogs',
      (tester) async {
    final first = audio('First', 'First.mp3');
    first.artist = 'Original Artist';
    final last = audio('Last', 'Last.flac');
    final parent = await destination();
    final service = ListeningStatusPlayback([
      first,
      CategoryTestAudio('Online', online: true),
      first,
      _CueAudio(),
      last
    ]);
    addTearDown(service.dispose);
    await mountQueue(tester, service, pickDirectory: () => parent.path);
    final originalQueue = service.playlist.value;
    await openQueue(tester);
    final plan = tester
        .widget<PlaylistFolderExportConfirmation>(
            find.byType(PlaylistFolderExportConfirmation))
        .plan;
    expect(plan.entries, hasLength(3));
    expect(plan.uniqueFileCount, 2);
    expect(plan.skipped, 2);
    expect(find.text(ui('跳过 {0} 项联网歌曲、CUE 分轨或不支持的文件。', [2])), findsOneWidget);
    expect(service.playlist.value, same(originalQueue));
    first.title = 'Later';
    first.artist = 'Later artist';
    first.path = 'D:/Missing/later.wav';
    first.duration = 999;
    service.replaceQueue([last]);
    await tester.pump();
    await confirm(tester);
    await until(
        tester,
        () =>
            find
                .byType(PlaylistFolderExportProgressDialog)
                .evaluate()
                .isEmpty &&
            tester.widget<IconButton>(_key('queue-export-m3u')).onPressed !=
                null);
    final file = (await tester.runAsync(() => exportedPlaylist(parent)))!;
    final text = (await tester.runAsync(file.readAsString))!;
    expect(RegExp('#EXTINF:120,Original Artist - First').allMatches(text),
        hasLength(2));
    expect(text, contains('#EXTINF:120,Artist - Last'));
    expect(text, isNot(contains('Later')));
    expect(text, isNot(contains('Online')));
    final copied = (await tester.runAsync(() => file.parent.list().toList()))!;
    expect(copied.whereType<File>(), hasLength(3));
    expect(service.playlist.value, [last]);
    expect(TaskbarProgress.instance.value, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('filtered folder export keeps clicked projection and order',
      (tester) async {
    final first = audio('Night first', 'Night first.mp3');
    final last = audio('Night last', 'Night last.flac');
    final excluded = audio('Day', 'Day.mp3');
    final parent = await destination();
    final service = ListeningStatusPlayback([first, excluded, first, last]);
    addTearDown(service.dispose);
    await mountQueue(tester, service, pickDirectory: () => parent.path);
    await tester.enterText(_key('queue-search'), 'night');
    await tester.pumpAndSettle();
    await openQueue(tester, filtered: true);
    tester.widget<TextField>(_key('queue-search')).onChanged!('day');
    service.replaceQueue([excluded]);
    await tester.pump();
    await confirm(tester);
    await until(
        tester,
        () =>
            find
                .byType(PlaylistFolderExportProgressDialog)
                .evaluate()
                .isEmpty &&
            tester.widget<IconButton>(_key('queue-export-m3u')).onPressed !=
                null);
    final file = (await tester.runAsync(() => exportedPlaylist(parent)))!;
    final text = (await tester.runAsync(file.readAsString))!;
    expect(RegExp('Artist - Night first').allMatches(text), hasLength(2));
    expect(text.indexOf('Night first'), lessThan(text.indexOf('Night last')));
    expect(text, isNot(contains('Day.mp3')));
    expect(service.playlist.value, [excluded]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('playlist menu exports child songs without changing the tree',
      (tester) async {
    sizePlaylistFeature(tester);
    final first = audio('Parent song', 'Parent song.mp3');
    final last = audio('Child song', 'Child song.flac');
    final parent = await destination();
    final tree = PlaylistTree([]);
    final playlist = tree.createPlaylist('My collection');
    final child = tree.createPlaylist('Child', parent: playlist);
    tree.addAudio(playlist, first);
    tree.addAudio(child, last);
    var saves = 0;
    await tester.pumpWidget(listeningStatusHost(PlaylistBrowser(
        tree: tree,
        initialPlaylist: playlist,
        persist: () async => saves++,
        pickFolderDirectory: () => parent.path,
        trackBuilder: (_, item, __, ___) => Text(item.displayTitle))));
    await tester.pumpAndSettle();
    await tester.tap(_key('playlist-current-settings'));
    await tester.pumpAndSettle();
    expect(_key('playlist-export-m3u'), findsOneWidget);
    await tester.runAsync(() => tester.tap(_key('playlist-export-folder')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<PlaylistFolderExportConfirmation>(
                find.byType(PlaylistFolderExportConfirmation))
            .plan
            .entries,
        hasLength(2));
    await confirm(tester);
    await until(
        tester,
        () =>
            find
                .byType(PlaylistFolderExportProgressDialog)
                .evaluate()
                .isEmpty &&
            parent.listSync().whereType<Directory>().any((directory) =>
                File(p.join(directory.path, 'playlist.m3u8')).existsSync()));
    final file = (await tester.runAsync(() => exportedPlaylist(parent)))!;
    final text = (await tester.runAsync(file.readAsString))!;
    expect(text, contains('Parent song'));
    expect(text, contains('Child song'));
    expect(tree.roots, [playlist]);
    expect(saves, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cancel confirmation or picker keeps queue and restores export',
      (tester) async {
    var picks = 0;
    final service = ListeningStatusPlayback([CategoryTestAudio('Local')]);
    addTearDown(service.dispose);
    await mountQueue(tester, service, pickDirectory: () {
      picks++;
      return null;
    });
    final original = service.playlist.value;
    await openQueue(tester);
    await tester.tap(_key('folder-export-dismiss'));
    await tester.pumpAndSettle();
    expect(picks, 0);
    await openQueue(tester);
    await confirm(tester);
    await tester.pumpAndSettle();
    expect(picks, 1);
    expect(service.playlist.value, same(original));
    expect(tester.widget<IconButton>(_key('queue-export-m3u')).onPressed,
        isNotNull);
    expect(TaskbarProgress.instance.value, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('missing file reports failure and releases taskbar and queue',
      (tester) async {
    final parent = await destination();
    final service = ListeningStatusPlayback([
      CategoryTestAudio('Missing', path: p.join(fixture.path, 'missing.mp3'))
    ]);
    addTearDown(service.dispose);
    await mountQueue(tester, service, pickDirectory: () => parent.path);
    final original = service.playlist.value;
    await openQueue(tester);
    await confirm(tester);
    await until(
        tester,
        () =>
            find
                .byType(PlaylistFolderExportProgressDialog)
                .evaluate()
                .isEmpty &&
            tester.widget<IconButton>(_key('queue-export-m3u')).onPressed !=
                null);
    expect(find.text(ui('导出失败，请检查目标目录与写入权限。')), findsOneWidget);
    expect((await tester.runAsync(() => parent.list().toList()))!, isEmpty);
    expect(service.playlist.value, same(original));
    expect(TaskbarProgress.instance.value, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'unsupported entries and empty search never launch a folder picker',
      (tester) async {
    var picks = 0;
    final service = ListeningStatusPlayback(
        [CategoryTestAudio('Online', online: true), _CueAudio()]);
    addTearDown(service.dispose);
    await mountQueue(tester, service, pickDirectory: () {
      picks++;
      return fixture.path;
    });
    await openQueue(tester);
    expect(find.byType(PlaylistFolderExportConfirmation), findsNothing);
    expect(find.text(ui('所选歌曲中没有可导出的本地文件。')), findsOneWidget);
    expect(picks, 0);
    await tester.enterText(_key('queue-search'), 'not found');
    await tester.pumpAndSettle();
    await tester.ensureVisible(_key('queue-export-m3u'));
    await tester.tap(_key('queue-export-m3u'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<MenuItemButton>(_key('queue-export-folder-search'))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<MenuItemButton>(_key('queue-export-folder-all'))
            .onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cancel and escape keep progress open until worker cleanup',
      (tester) async {
    final held = _HeldExport();
    addTearDown(held.cancelComplete);
    await startHeld(tester, held);
    expect(TaskbarProgress.instance.value!.state,
        TaskbarProgressState.indeterminate);
    held.progress!(const PlaylistFolderExportProgress(
        copiedFiles: 1, totalFiles: 2, completedBytes: 5, totalBytes: 20));
    await tester.pump();
    expect(
        tester
            .widget<LinearProgressIndicator>(_key('folder-export-progress'))
            .value,
        .25);
    expect(TaskbarProgress.instance.value!.completed, 250);
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(held.cancellation!.isCancelled, isFalse);
    expect(find.byType(PlaylistFolderExportProgressDialog), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(held.cancellation!.isCancelled, isTrue);
    expect(tester.widget<TextButton>(_key('folder-export-cancel')).onPressed,
        isNull);
    expect(find.text(ui('正在取消…')), findsOneWidget);
    expect(TaskbarProgress.instance.value, isNotNull);
    held.cancelComplete();
    await tester.pumpAndSettle();
    expect(find.byType(PlaylistFolderExportProgressDialog), findsNothing);
    expect(TaskbarProgress.instance.value, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'removing progress route cancels owner and rejects late publication',
      (tester) async {
    final held = _HeldExport();
    addTearDown(held.cancelComplete);
    await startHeld(tester, held);
    await tester.pumpWidget(const SizedBox());
    expect(held.cancellation!.isCancelled, isTrue);
    held.progress!(const PlaylistFolderExportProgress(
        copiedFiles: 1, totalFiles: 2, completedBytes: 1, totalBytes: 2));
    held.cancelComplete();
    await tester.pump();
    expect(TaskbarProgress.instance.value, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chunk progress is coalesced while phase and completion publish',
      (tester) async {
    final held = _HeldExport();
    addTearDown(held.cancelComplete);
    await startHeld(tester, held);
    held.progress!(const PlaylistFolderExportProgress(
        copiedFiles: 0,
        totalFiles: 2,
        completedBytes: 0,
        totalBytes: 100,
        preparing: true));
    held.progress!(const PlaylistFolderExportProgress(
        copiedFiles: 0, totalFiles: 2, completedBytes: 1, totalBytes: 100));
    for (var i = 2; i < 100; i++) {
      held.progress!(PlaylistFolderExportProgress(
          copiedFiles: 0, totalFiles: 2, completedBytes: i, totalBytes: 100));
    }
    await tester.pump();
    expect(
        tester
            .widget<LinearProgressIndicator>(_key('folder-export-progress'))
            .value,
        .01);
    expect(TaskbarProgress.instance.value!.completed, 10);
    held.progress!(const PlaylistFolderExportProgress(
        copiedFiles: 2, totalFiles: 2, completedBytes: 100, totalBytes: 100));
    await tester.pump();
    expect(
        tester
            .widget<LinearProgressIndicator>(_key('folder-export-progress'))
            .value,
        1);
    expect(TaskbarProgress.instance.value!.completed, 1000);
    await tester.tap(_key('folder-export-cancel'));
    held.cancelComplete();
    await tester.pumpAndSettle();
    expect(TaskbarProgress.instance.value, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('source disposal while picker waits does not begin copying',
      (tester) async {
    final held = _HeldExport();
    final picker = Completer<String?>();
    sizePlaylistFeature(tester);
    await tester.pumpWidget(listeningStatusHost(entry(
        [CategoryTestAudio('Local')], held,
        pickDirectory: () => picker.future)));
    await tester.tap(_key('start-folder-export'));
    await tester.pumpAndSettle();
    await confirm(tester);
    await tester.pumpWidget(const SizedBox());
    picker.complete(fixture.path);
    await tester.pump();
    expect(held.calls, 0);
    expect(TaskbarProgress.instance.value, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'preparing progress respects feedback reduction and hidden ticker',
      (tester) async {
    final held = _HeldExport();
    addTearDown(held.cancelComplete);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    sizePlaylistFeature(tester);
    var feedback = true;
    var ticker = true;
    late StateSetter update;
    await tester.pumpWidget(
        UiLanguageScope(child: StatefulBuilder(builder: (_, setState) {
      update = setState;
      return MotionPreferencesScope(
          preferences:
              const MotionPreferences().withKind(MotionKind.feedback, feedback),
          child: TickerMode(
              enabled: ticker,
              child: MaterialApp(
                  home: Scaffold(
                      body: entry([CategoryTestAudio('Local')], held)))));
    })));
    await tester.tap(_key('start-folder-export'));
    await tester.pumpAndSettle();
    await confirm(tester);
    await tester.pump(const Duration(milliseconds: 250));
    expect(
        tester
            .widget<LinearProgressIndicator>(_key('folder-export-progress'))
            .value,
        isNull);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    update(() => feedback = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
        tester
            .widget<LinearProgressIndicator>(_key('folder-export-progress'))
            .value,
        0);
    expect(tester.binding.transientCallbackCount, 0);
    expect(TaskbarProgress.instance.value!.state,
        TaskbarProgressState.indeterminate);
    final handle = tester.ensureSemantics();
    try {
      final data = tester
          .getSemantics(_key('folder-export-static-progress'))
          .getSemanticsData();
      expect(data.label, ui('正在准备音频文件…'));
      expect(data.value, isEmpty,
          reason: 'Unknown progress must not announce 0%');
    } finally {
      handle.dispose();
    }
    update(() => feedback = true);
    await tester.pump();
    expect(
        tester
            .widget<LinearProgressIndicator>(_key('folder-export-progress'))
            .value,
        isNull);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
        tester
            .widget<LinearProgressIndicator>(_key('folder-export-progress'))
            .value,
        0);
    expect(tester.binding.transientCallbackCount, 0);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    update(() => ticker = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
        tester
            .widget<LinearProgressIndicator>(_key('folder-export-progress'))
            .value,
        0);
    expect(tester.binding.transientCallbackCount, 0);
    update(() => ticker = true);
    await tester.pump();
    expect(
        tester
            .widget<LinearProgressIndicator>(_key('folder-export-progress'))
            .value,
        isNull);
    await tester.tap(_key('folder-export-cancel'));
    held.cancelComplete();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    await tester.pump();
    expect(TaskbarProgress.instance.value, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [true, false]) {
      testWidgets('folder controls fit ${language.name} narrow=$narrow',
          (tester) async {
        final width = narrow ? 320.0 : 1000.0;
        final scale = narrow ? 2.0 : 1.0;
        final boundary = GlobalKey();
        final seed = language.index.isEven ? Colors.teal : Colors.deepPurple;
        final brightness = narrow ? Brightness.light : Brightness.dark;
        uiLanguage.value = language;
        final service = ListeningStatusPlayback([CategoryTestAudio('Night')]);
        addTearDown(service.dispose);
        await mountQueue(tester, service,
            pickDirectory: () => null,
            boundary: boundary,
            width: width,
            scale: scale,
            seed: seed,
            brightness: brightness);
        await tester.enterText(_key('queue-search'), 'night');
        await tester.pumpAndSettle();
        await tester.ensureVisible(_key('queue-export-m3u'));
        await tester.tap(_key('queue-export-m3u'));
        await tester.pumpAndSettle();
        for (final key in [
          'queue-export-folder-all',
          'queue-export-folder-search'
        ]) {
          final rect = tester.getRect(_key(key));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
          expect(_key(key).hitTestable(), findsOneWidget);
        }
        await captureListeningStatus(tester, boundary,
            'folder-${language.name}-${narrow ? 'narrow' : 'wide'}-queue');
        await tester.tap(_key('queue-export-folder-search'));
        await tester.pumpAndSettle();
        expect(_key('folder-export-confirm').hitTestable(), findsOneWidget);
        expect(tester.getRect(find.byType(AlertDialog)).right,
            lessThanOrEqualTo(width));
        expect(tester.takeException(), isNull);
        await captureListeningStatus(tester, boundary,
            'folder-${language.name}-${narrow ? 'narrow' : 'wide'}-confirm');
        await tester.tap(_key('folder-export-dismiss'));
        await tester.pumpAndSettle();

        final held = _HeldExport();
        addTearDown(held.cancelComplete);
        await tester.pumpWidget(listeningStatusHost(
            entry([CategoryTestAudio('Local'), _CueAudio()], held),
            boundary: boundary,
            scale: scale,
            seed: seed,
            brightness: brightness));
        await tester.pumpAndSettle();
        await tester.tap(_key('start-folder-export'));
        await tester.pumpAndSettle();
        await confirm(tester);
        await tester.pump(const Duration(milliseconds: 250));
        held.progress!(const PlaylistFolderExportProgress(
            copiedFiles: 1, totalFiles: 2, completedBytes: 3, totalBytes: 4));
        await tester.pump();
        expect(_key('folder-export-cancel').hitTestable(), findsOneWidget);
        expect(tester.getRect(find.byType(AlertDialog)).right,
            lessThanOrEqualTo(width));
        final colors = Theme.of(tester.element(_key('folder-export-progress')))
            .colorScheme;
        expect(colors.brightness, brightness);
        expect(tester.takeException(), isNull);
        await captureListeningStatus(tester, boundary,
            'folder-${language.name}-${narrow ? 'narrow' : 'wide'}-progress');
        await tester.tap(_key('folder-export-cancel'));
        held.cancelComplete();
        await tester.pumpAndSettle();
        expect(TaskbarProgress.instance.value, isNull);

        final tree = PlaylistTree([]);
        final playlist = tree.createPlaylist('Night');
        tree.addAudio(playlist, CategoryTestAudio('Local'));
        await tester.pumpWidget(listeningStatusHost(
            PlaylistBrowser(
                tree: tree,
                initialPlaylist: playlist,
                persist: () async {},
                pickFolderDirectory: () => null,
                trackBuilder: (_, item, __, ___) => Text(item.displayTitle)),
            boundary: boundary,
            scale: scale,
            seed: seed,
            brightness: brightness));
        await tester.pumpAndSettle();
        await tester.ensureVisible(_key('playlist-current-settings'));
        await tester.tap(_key('playlist-current-settings'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(_key('playlist-export-folder'));
        final folderText = find.descendant(
            of: _key('playlist-export-folder'), matching: find.byType(Text));
        final folderLabel =
            find.descendant(of: folderText, matching: find.byType(RichText));
        expect(
            tester.renderObject<RenderParagraph>(folderLabel).didExceedMaxLines,
            isFalse);
        expect(_key('playlist-export-folder').hitTestable(), findsOneWidget);
        expect(tester.getRect(_key('playlist-export-folder')).right,
            lessThanOrEqualTo(width));
        expect(tester.takeException(), isNull);
        await captureListeningStatus(tester, boundary,
            'folder-${language.name}-${narrow ? 'narrow' : 'wide'}-playlist');
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
