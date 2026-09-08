import 'dart:io';
import 'dart:ui' as raster;
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/page/now_playing_page/component/current_playlist_view.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/play_service/queue_edits.dart';
import 'package:dan_player/play_service/queue_track_identity.dart';
import 'package:dan_player/play_service/queue_stop_boundary.dart';
import 'package:dan_player/play_service/segment_loop.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'support/music_category_fixtures.dart';

class _QueuePlayback extends ChangeNotifier implements PlaybackService {
  _QueuePlayback(List<Audio> audios, {this.selectedIndex = 0})
      : playlist = ValueNotifier(List<Audio>.from(audios)),
        entries = [for (final audio in audios) QueueOccurrence(audio)],
        nowPlaying = audios.isEmpty ? null : audios[selectedIndex];

  @override
  final ValueNotifier<List<Audio>> playlist;

  @override
  Audio? nowPlaying;

  int selectedIndex;
  int? lastPlayed;
  int? lastRemoved;
  int? lastMoved;
  List<QueueOccurrence<Audio>> entries;
  final history = QueueEditHistory<QueueOccurrence<Audio>>();
  @override
  final queueStopBoundary = QueueStopBoundary();
  @override
  final playMode = ValueNotifier(PlayMode.loop);
  @override
  int? queueOccurrenceId(int index) =>
      index >= 0 && index < entries.length ? entries[index].id : null;
  @override
  String? get queueStopTargetLabel {
    final index =
        entries.indexWhere((entry) => entry.id == queueStopBoundary.target);
    return index < 0
        ? null
        : '${index + 1} · ${entries[index].item.displayTitle}';
  }

  @override
  String? get queueStopBlockedReason => !canEditQueue
      ? '歌曲正在加载，请稍后重试'
      : segmentLoop.enabled
          ? '请先关闭 A-B 循环，再设置停止目标'
          : playMode.value == PlayMode.singleLoop
              ? '请先关闭单曲循环，再设置停止目标'
              : null;
  @override
  bool stopAfterQueueItem(int index) {
    if (queueStopBlockedReason != null || queueOccurrenceId(index) == null) {
      return false;
    }
    queueStopBoundary.arm(queueOccurrenceId(index)!);
    return true;
  }

  @override
  bool stopAfterQueueRound() => stopAfterQueueItem(entries.length - 1);
  @override
  void cancelQueueStop() =>
      queueStopBoundary.cancel(QueueStopCancelReason.userCancelled);
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
      canEditQueue && history.canUndo(entries, entries, selectedIndex);
  @override
  bool get canRedoQueueEdit =>
      canEditQueue && history.canRedo(entries, entries, selectedIndex);
  @override
  String queueHistoryReason({bool redo = false}) => !canEditQueue
      ? '歌曲正在加载，请稍后重试'
      : redo
          ? '没有可重做的队列操作'
          : '没有可撤销的队列操作';

  void commit(QueueEdit<QueueOccurrence<Audio>> edit) {
    history.record(QueueSnapshot(entries, entries, selectedIndex),
        QueueSnapshot(edit.items, edit.items, edit.currentIndex));
    selectedIndex = edit.currentIndex;
    entries = edit.items;
    playlist.value = [for (final entry in entries) entry.item];
    queueStopBoundary.retain(entries.map((entry) => entry.id));
    notifyListeners();
  }

  @override
  bool undoQueueEdit() {
    if (!canEditQueue) return false;
    final state = history.undo(entries, entries, selectedIndex);
    if (state == null) return false;
    selectedIndex = state.currentIndex;
    entries = state.items;
    playlist.value = [for (final entry in entries) entry.item];
    notifyListeners();
    return true;
  }

  @override
  bool redoQueueEdit() {
    if (!canEditQueue) return false;
    final state = history.redo(entries, entries, selectedIndex);
    if (state == null) return false;
    entries = state.items;
    selectedIndex = state.currentIndex;
    playlist.value = [for (final entry in entries) entry.item];
    notifyListeners();
    return true;
  }

  @override
  bool removeQueueItem(int index) {
    final edit = QueueEdit.remove(entries, selectedIndex, index);
    if (edit == null || !canEditQueue) return false;
    lastRemoved = index;
    commit(edit);
    return true;
  }

  @override
  bool moveQueueItemNext(int index) {
    final edit = QueueEdit.moveNext(entries, selectedIndex, index);
    if (edit == null || !canEditQueue) return false;
    lastMoved = index;
    commit(edit);
    return true;
  }

  @override
  bool keepOnlyCurrentQueueItem() {
    commit(QueueEdit([entries[selectedIndex]], 0));
    return true;
  }

  @override
  int deduplicateQueue() {
    if (!canEditQueue) return 0;
    final before = playlist.value;
    final edit = QueueEdit.deduplicate(entries, selectedIndex,
        keyOf: (entry) => queueTrackIdentity(entry.item));
    if (edit == null) return 0;
    commit(edit);
    return before.length - edit.items.length;
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
    queueStopBoundary.dispose();
    playMode.dispose();
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
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [
      (danEmbeddedFontFamily, 'assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      ),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    final windowsDirectory = Platform.environment['WINDIR'];
    if (windowsDirectory != null) {
      final font = File('$windowsDirectory/Fonts/malgun.ttf');
      if (await font.exists()) {
        await (FontLoader('Malgun Gothic')
              ..addFont(
                  Future.value(ByteData.sublistView(await font.readAsBytes()))))
            .load();
      }
    }
  });
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  testWidgets('queue keyboard undo redo yields to the focused text editor',
      (tester) async {
    final playback = _QueuePlayback(
        [CategoryTestAudio('first'), CategoryTestAudio('second')]);
    addTearDown(playback.dispose);
    await tester.pumpWidget(_host(playback));
    await tester.pumpAndSettle();
    playback.removeQueueItem(1);
    await tester.pumpAndSettle();
    Future<void> shortcut(LogicalKeyboardKey key, {bool shift = false}) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    await shortcut(LogicalKeyboardKey.keyZ);
    expect(playback.playlist.value, hasLength(2));
    await shortcut(LogicalKeyboardKey.keyY);
    expect(playback.playlist.value, hasLength(1));
    await shortcut(LogicalKeyboardKey.keyZ);
    await shortcut(LogicalKeyboardKey.keyZ, shift: true);
    expect(playback.playlist.value, hasLength(1));
    await tester.enterText(find.byKey(const ValueKey('queue-search')), 'first');
    await tester.pump(const Duration(seconds: 1));
    await shortcut(LogicalKeyboardKey.keyZ);
    expect(playback.playlist.value, hasLength(1),
        reason: 'Text undo must not restore the queue');
    await shortcut(LogicalKeyboardKey.keyY);
    expect(playback.playlist.value, hasLength(1));
    expect(playback.position, 47.25);
    expect(playback.lastPlayed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('queue menu sets exact duplicate and blocked modes explain stop',
      (tester) async {
    final audio = CategoryTestAudio('Same song');
    final playback =
        _QueuePlayback([audio, CategoryTestAudio('middle'), audio]);
    addTearDown(playback.dispose);
    await tester.pumpWidget(_host(playback));
    await tester.pumpAndSettle();
    await tester
        .longPress(find.byKey(const ValueKey('current-playlist-item-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('queue-stop-after-item-2')));
    await tester.pumpAndSettle();
    expect(playback.queueStopBoundary.target, playback.queueOccurrenceId(2));
    expect(playback.queueStopBoundary.target,
        isNot(playback.queueOccurrenceId(0)));
    expect(find.byKey(const ValueKey('queue-stop-target')), findsOneWidget);
    playback.moveQueueItemNext(2);
    await tester.pumpAndSettle();
    expect(playback.queueStopTargetLabel, '2 · Same song');
    playback.playMode.value = PlayMode.singleLoop;
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<IconButton>(
                find.byKey(const ValueKey('queue-stop-after-round')))
            .onPressed,
        isNull);
    expect(find.textContaining('请先关闭单曲循环'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('queue-cancel-stop')));
    await tester.pumpAndSettle();
    expect(playback.queueStopBoundary.active, isFalse);
    expect(playback.lastPlayed, isNull);
    expect(playback.position, 47.25);
    expect(tester.takeException(), isNull);
  });

  testWidgets('render updated queue history and stop controls', (tester) async {
    const output = String.fromEnvironment('DAN_PLAYER_UPDATE_RENDER_DIR');
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final playback = _QueuePlayback([
      CategoryTestAudio('Moonlit road · 夜空の向こうへ · 밤하늘 너머',
          artist: 'Dan Orchestra', album: 'Night suite'),
      CategoryTestAudio('The very last song of the original queue · 冬日的回声',
          artist: 'Dan Orchestra'),
      CategoryTestAudio('Appended later'),
    ]);
    addTearDown(playback.dispose);
    playback.stopAfterQueueItem(1);
    playback.removeQueueItem(2);
    playback.undoQueueEdit();
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      for (final narrow in [false, true]) {
        final size = Size(narrow ? 340 : 600, narrow ? 730 : 590);
        tester.view.physicalSize = size;
        final key = GlobalKey();
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: language.locale,
          supportedLocales: [for (final item in UiLanguage.values) item.locale],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: Entry(welcome: false).fromSchemeAndFontFamily(
              colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.teal,
                  brightness: narrow ? Brightness.dark : Brightness.light)),
          home: RepaintBoundary(
              key: key,
              child: Scaffold(
                  body: MediaQuery(
                      data: MediaQueryData(
                          size: size,
                          textScaler: TextScaler.linear(narrow ? 1.6 : 1)),
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: CurrentPlaylistView(
                              immersive: true, playbackService: playback))))),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: '${language.name} / narrow $narrow');
        expect(find.byKey(const ValueKey('queue-stop-target')), findsOneWidget);
        final redo = tester
            .widget<IconButton>(find.byKey(const ValueKey('queue-redo-edit')));
        expect(redo.onPressed, isNotNull);
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final boundary = key.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            final image = await boundary.toImage();
            try {
              final bytes =
                  (await image.toByteData(format: raster.ImageByteFormat.png))!
                      .buffer
                      .asUint8List();
              final destination = File(
                  '$output/queue-${language.name}-${narrow ? 'narrow-dark' : 'wide-light'}.png');
              await destination.parent.create(recursive: true);
              await destination.writeAsBytes(bytes, flush: true);
            } finally {
              image.dispose();
            }
          });
        }
      }
    }
  });

  testWidgets('queue rows have symmetric edges and thumb drag stays usable',
      (tester) async {
    final queue =
        List.generate(60, (index) => CategoryTestAudio('Track $index'));
    final playback = _QueuePlayback(queue);
    addTearDown(playback.dispose);
    for (final width in [280.0, 520.0]) {
      await tester.pumpWidget(_host(playback, width: width));
      await tester.pumpAndSettle();
      final bounds = tester.getRect(find.byType(Scrollbar));
      final row =
          tester.getRect(find.byKey(const ValueKey('current-playlist-item-0')));
      expect(row.left - bounds.left, closeTo(6, .01));
      expect(bounds.right - row.right, closeTo(6, .01));
      expect(tester.takeException(), isNull);
    }
    final scrollbar = find.byType(Scrollbar);
    final bounds = tester.getRect(scrollbar);
    final list = tester
        .widget<ListView>(find.byKey(const ValueKey('current-playlist-list')));
    final controller = list.controller!;
    final details = tester.getRect(find.byIcon(Symbols.info).first);
    expect(details.right, lessThanOrEqualTo(bounds.right - 14),
        reason: 'The 6px thumb must not cover a trailing details button.');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset(bounds.right - 2, bounds.top + 18));
    await tester.pumpAndSettle();
    await mouse.down(Offset(bounds.right - 2, bounds.top + 18));
    await mouse.moveBy(const Offset(0, 100));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(100));
    expect(playback.lastPlayed, isNull);
    await mouse.removePointer();
    // Filtering after thumb movement still resolves the original occurrence,
    // rather than its row number in the shortened visible list.
    await tester.enterText(
        find.byKey(const ValueKey('queue-search')), 'Track 53');
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('current-playlist-item-53')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('current-playlist-item-53')));
    await tester.pumpAndSettle();
    expect(playback.lastPlayed, 53);
    expect(playback.playlist.value, orderedEquals(queue));
    expect(tester.takeException(), isNull);
  });

  testWidgets('deduplicate notice preserves the queue undo button position',
      (tester) async {
    const dpi = 1.25;
    tester.view.physicalSize = const Size(1500, 1125);
    tester.view.devicePixelRatio = dpi;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final first = CategoryTestAudio('First');
    final playback = _QueuePlayback([
      first,
      CategoryTestAudio('Second'),
      first,
      CategoryTestAudio('Third'),
    ], selectedIndex: 2);
    addTearDown(playback.dispose);
    late BuildContext pageContext;
    await tester.pumpWidget(MaterialApp(
      builder: (_, child) => AppPresentationHost(child: child!),
      home: Scaffold(
          body: Padding(
              padding: const EdgeInsets.fromLTRB(300, 48, 12, 12),
              child: AppContentRegion(
                key: const ValueKey('queue-content-panel'),
                child: Navigator(
                    onGenerateRoute: (_) =>
                        MaterialPageRoute<void>(builder: (context) {
                          pageContext = context;
                          return const SizedBox.expand();
                        })),
              ))),
    ));
    await tester.pumpAndSettle();
    showAppDialog<void>(
        context: pageContext,
        dialogBottomInset: 16,
        builder: (_) => AlertDialog(
              insetPadding: const EdgeInsets.all(16),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              title: const AppDialogTitle('播放列表',
                  leading: SizedBox.square(
                      dimension: 40, child: Icon(Symbols.queue_music)),
                  trailing: Text('4')),
              content: SizedBox(
                  width: 520,
                  height: 440,
                  child: CurrentPlaylistView(
                      showTitle: false, playbackService: playback)),
              actions: [
                TextButton.icon(
                    onPressed: () {},
                    icon: const Icon(Symbols.close),
                    label: const Text('关闭'))
              ],
            ));
    await tester.pumpAndSettle();
    final surface = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byWidgetPredicate((widget) =>
            widget is Material && widget.type == MaterialType.card));
    // Reproduce the packaged edge case: the painted dialog already ends
    // exactly 8px above a one-line notice. Its own 16px outside inset is not
    // another required separation. Include a shell's nested Navigator and DPI.
    final dialogHeight = tester.getSize(surface).height;
    tester.view.physicalSize = Size(1500, (dialogHeight + 128 + 60) * dpi);
    await tester.pumpAndSettle();
    final beforeSurface = tester.getRect(surface);
    final panel =
        tester.getRect(find.byKey(const ValueKey('queue-content-panel')));
    expect(panel.bottom - beforeSurface.bottom, closeTo(64, .01));
    final undo = find.byKey(const ValueKey('queue-undo-edit'));
    final before = tester.getRect(undo);
    await tester.tap(find.byKey(const ValueKey('queue-deduplicate')));
    for (final delay in [0, 16, 140]) {
      await tester.pump(Duration(milliseconds: delay));
      expect(tester.getRect(undo), before);
      expect(tester.getRect(surface), beforeSurface);
    }
    expect(playback.playlist.value, hasLength(3));
    expect(find.byKey(const ValueKey('app-notice-bubble')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(
        tester.getRect(find.byKey(const ValueKey('app-notice-bubble'))).top -
            beforeSurface.bottom,
        closeTo(8, .01));
    // A click at the previously observed coordinates must reach Undo while
    // the notice is still visible, reproducing the packaged QA interaction.
    await tester.tapAt(before.center);
    await tester.pumpAndSettle();
    expect(playback.playlist.value, hasLength(4));
    expect(playback.selectedIndex, 2);
    expect(playback.position, 47.25);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(tester.getRect(undo), before);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('English narrow queue search remains usable with large text',
      (tester) async {
    uiLanguage.value = UiLanguage.en;
    final playback = _QueuePlayback([CategoryTestAudio('Canon')]);
    addTearDown(playback.dispose);
    await tester.pumpWidget(_host(playback, textScale: 3, width: 280));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('queue-search')), 'missing');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('queue-clear-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('queue-search-count')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('queue-clear-search')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('current-playlist-item-0')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('645-track search keeps original occurrence indices for actions',
      (tester) async {
    final queue = List.generate(
        645,
        (i) => CategoryTestAudio('Track $i',
            artist: i == 17 || i == 540 ? 'Orchestra' : 'Other artist',
            album: i == 540 ? 'Good Time' : 'Album'));
    final playback = _QueuePlayback(queue, selectedIndex: 320);
    addTearDown(playback.dispose);
    await tester.pumpWidget(_host(playback));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('queue-search'));
    await tester.enterText(search, 'orchestra');
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('current-playlist-item-17')), findsOneWidget);
    expect(find.byKey(const ValueKey('current-playlist-item-540')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('current-playlist-item-0')), findsNothing);
    expect(playback.playlist.value, queue);
    await tester
        .longPress(find.byKey(const ValueKey('current-playlist-item-17')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移到下一首'));
    await tester.pumpAndSettle();
    expect(playback.lastMoved, 17);
    expect(
        playback.playlist.value[playback.selectedIndex + 1], same(queue[17]));
    await tester.enterText(search, 'good TIME');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('current-playlist-item-540')));
    await tester.pumpAndSettle();
    expect(playback.lastPlayed, 540);
    expect(playback.playlist.value.length, 645);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'locating a filtered-out current track clears query and centers it',
      (tester) async {
    final playback = _QueuePlayback(
        List.generate(645, (i) => CategoryTestAudio('Track $i')),
        selectedIndex: 500);
    addTearDown(playback.dispose);
    await tester.pumpWidget(_host(playback));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('queue-search')), 'Track 17');
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('current-playlist-item-500')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('queue-locate-current')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('queue-search')))
            .controller!
            .text,
        '');
    expect(find.byKey(const ValueKey('current-playlist-item-500')),
        findsOneWidget);
    expect(playback.lastPlayed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'filtered queue deduplication operates on full queue and can undo',
      (tester) async {
    final first = CategoryTestAudio('first', path: r'C:\Music\same.mp3');
    final active = CategoryTestAudio('active', path: 'c:/music/SAME.mp3');
    final other = CategoryTestAudio('other');
    final playback =
        _QueuePlayback([first, other, active, other], selectedIndex: 2);
    addTearDown(playback.dispose);
    await tester.pumpWidget(_host(playback));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('queue-search')), 'other');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('queue-deduplicate')));
    await tester.pumpAndSettle();
    expect(playback.playlist.value, [other, active]);
    expect(playback.selectedIndex, 1);
    expect(playback.nowPlaying, same(active));
    expect(playback.position, 47.25);
    expect(playback.lastPlayed, isNull);
    await tester.tap(find.byKey(const ValueKey('queue-undo-edit')));
    await tester.pumpAndSettle();
    expect(playback.playlist.value, [first, other, active, other]);
    expect(playback.selectedIndex, 2);
    playback.resolvingAudioPath.value = 'loading';
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('queue-deduplicate')))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

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
        .ensureVisible(find.byKey(const ValueKey('current-playlist-item-0')));
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
