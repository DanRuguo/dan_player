import 'dart:io';
import 'dart:ui' as drawing;
import 'package:dan_player/entry.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playback_bookmarks.dart';
import 'package:dan_player/library/track_identity.dart';
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
  Future<List<PlaybackBookmark>> forTrack(String localPath,
      {String? stableTrackId}) async {
    final key = PlaybackBookmarkStore.trackKey(localPath);
    final legacyIsUnique = stableTrackId == null ||
        TrackIdentityRegistry.instance.resolvePath(localPath) == stableTrackId;
    return entries
        .where((item) =>
            (stableTrackId != null && item.track == stableTrackId) ||
            (legacyIsUnique && item.track == key))
        .toList();
  }

  @override
  Future<void> add(
      {required String localPath,
      String? stableTrackId,
      required String label,
      required double position,
      double? end}) async {
    entries.add(PlaybackBookmark(
        id: '${entries.length}',
        track: stableTrackId ?? PlaybackBookmarkStore.trackKey(localPath),
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
  setUpAll(() async {
    for (final font in [
      (danEmbeddedFontFamily, 'assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      )
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  late _MemoryBookmarks store;
  late _BookmarkPlayback service;
  setUp(() async {
    store = _MemoryBookmarks();
    service = _BookmarkPlayback();
    await store.add(
        localPath: service.nowPlaying!.path,
        stableTrackId: service.nowPlaying!.stableTrackId,
        label: 'Opening',
        position: 7);
    await store.add(
        localPath: service.nowPlaying!.path,
        stableTrackId: service.nowPlaying!.stableTrackId,
        label: 'Chorus',
        position: 20,
        end: 40);
    final other = CategoryTestAudio('other-bookmark-track');
    await store.add(
        localPath: other.path,
        stableTrackId: other.stableTrackId,
        label: 'Other track bookmark',
        position: 12);
  });
  tearDown(() => service.dispose());

  for (final language in UiLanguage.values) {
    testWidgets('bookmark time controls render ${language.name}',
        (tester) async {
      const output = String.fromEnvironment('DAN_BOOKMARK_RENDER');
      uiLanguage.value = language;
      addTearDown(() => uiLanguage.value = UiLanguage.zh);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final narrow in [false, true]) {
        tester.view.physicalSize = Size(narrow ? 380 : 760, narrow ? 640 : 820);
        final key = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
            key: key,
            child: UiLanguageScope(
                child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: Entry(welcome: false).fromSchemeAndFontFamily(
                        colorScheme: ColorScheme.fromSeed(
                            seedColor: Colors.teal,
                            brightness:
                                narrow ? Brightness.dark : Brightness.light)),
                    locale: language.locale,
                    supportedLocales: UiLanguage.values.map((v) => v.locale),
                    localizationsDelegates:
                        GlobalMaterialLocalizations.delegates,
                    builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                            textScaler: TextScaler.linear(narrow ? 1.4 : 1)),
                        child: child!),
                    home: Scaffold(
                        body: Builder(
                            builder: (context) => Center(
                                child:
                                    TextButton(onPressed: () => showAppDialog<void>(context: context, builder: (_) => PlaybackBookmarksDialog(service: service, store: store)), child: const Text('open')))))))));
        await tester.pumpAndSettle();
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(ui('时间段')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (output.isNotEmpty)
          await tester.runAsync(() async {
            final image = await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final data =
                await image.toByteData(format: drawing.ImageByteFormat.png);
            final file =
                File('$output/bookmark-picker-${language.name}-$narrow.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        await tester.ensureVisible(
            find.byKey(const ValueKey('bookmark-save-selection')));
        await tester.pumpAndSettle();
        expect(
            find.byKey(const ValueKey('bookmark-save-selection')).hitTestable(),
            findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    });
  }

  testWidgets('chooses point and range without seeking or changing A-B',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PlaybackBookmarksDialog(service: service, store: store))));
    await tester.pumpAndSettle();
    tester
        .widget<Slider>(find.byKey(const ValueKey('bookmark-time-picker')))
        .onChanged!(37);
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('bookmark-save-selection')));
    await tester.tap(find.byKey(const ValueKey('bookmark-save-selection')));
    await tester.pumpAndSettle();
    expect(store.entries.last.positionMs, 37000);
    expect(store.entries.last.endMs, isNull);
    await tester.ensureVisible(find.text('时间段'));
    await tester.tap(find.text('时间段'));
    await tester.pumpAndSettle();
    tester
        .widget<RangeSlider>(
            find.byKey(const ValueKey('bookmark-range-picker')))
        .onChanged!(const RangeValues(12, 28));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('bookmark-save-selection')));
    await tester.tap(find.byKey(const ValueKey('bookmark-save-selection')));
    await tester.pumpAndSettle();
    expect(store.entries.last.positionMs, 12000);
    expect(store.entries.last.endMs, 28000);
    expect(service.position, 10);
    expect(service.segmentLoop.enabled, false);
    service.changeTrack();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('bookmark-save-selection')))
            .onPressed,
        isNull);
  });

  testWidgets(
      'position and A-B recall preserve paused playback and track changes disable actions',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PlaybackBookmarksDialog(service: service, store: store))));
    await tester.pumpAndSettle();
    expect(find.text('Other track bookmark'), findsNothing);
    await tester.ensureVisible(find.text('Chorus'));
    await tester.tap(find.text('Chorus'));
    expect(service.segmentLoop.enabled, isTrue);
    expect(service.segmentLoop.end, 40);
    expect(service.position, 20);
    await tester.ensureVisible(find.text('Opening'));
    await tester.tap(find.text('Opening'));
    expect(service.segmentLoop.enabled, isFalse);
    expect(service.position, 7);
    await tester.enterText(find.byType(TextField), 'Named position');
    await tester
        .ensureVisible(find.byKey(const ValueKey('bookmark-save-position')));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('bookmark-save-position')));
      await store.forTrack(service.nowPlaying!.path,
          stableTrackId: service.nowPlaying!.stableTrackId);
    });
    await tester.pumpAndSettle();
    expect(find.text('Named position'), findsOneWidget);
    expect(
        store.entries
            .singleWhere((item) => item.label == 'Named position')
            .track,
        service.nowPlaying!.stableTrackId);
    await tester.ensureVisible(find.byType(PopupMenuButton<String>).first);
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
