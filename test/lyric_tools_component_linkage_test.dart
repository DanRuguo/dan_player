import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_checkbox_menu_button.dart';
import 'package:dan_player/component/settings_section_visibility.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/japanese_lyric_readings.dart';
import 'package:dan_player/lyric/japanese_lyric_cache.dart';
import 'package:dan_player/lyric/japanese_phonetic_channel.dart';
import 'package:dan_player/lyric/japanese_online_readings.dart';
import 'package:dan_player/lyric/japanese_reading_preferences.dart';
import 'package:dan_player/lyric/japanese_reading_analyzer.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_text_search.dart';
import 'package:dan_player/lyric_display_coordinator.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_reading_tools.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:dan_player/page/settings_page/grouped_settings.dart';
import 'package:dan_player/page/settings_page/lyric_experience_settings.dart';
import 'package:dan_player/play_service/desktop_lyric_service.dart';
import 'package:dan_player/play_service/lyric_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:dan_player/taskbar_lyric_service.dart';
import 'package:dan_player/taskbar_lyrics_publisher.dart';
import 'package:desktop_lyric/appearance_controller.dart';
import 'package:desktop_lyric/app_motion.dart';
import 'package:desktop_lyric/component/desktop_lyric_appearance_options.dart';
import 'package:desktop_lyric/component/desktop_lyric_text.dart';
import 'package:desktop_lyric/component/lyric_line_display_area.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/message.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'lyric_letter_spacing_render_test.dart' show loadLetterSpacingFonts;
import 'support/playlist_feature_fixture.dart'
    show capturePlaylistFeature, loadPlaylistFeatureFonts, sizePlaylistFeature;

const _settingsSlider = ValueKey('settings-lyric-letter-spacing-slider');
const _desktopReset = ValueKey('desktop-lyric-letter-spacing-reset');
const _readingOpen = ValueKey('lyric-reading-tools');
const _generate = ValueKey('lyric-show-japanese-reading');
const _automatic = ValueKey('japanese-reading-auto-switch');
const _mainLine = ValueKey('linkage-main-line');
const _diagnostics = bool.fromEnvironment('DAN_LYRIC_LINKAGE_DIAGNOSTICS');

// Match the analyzer's contextual word contract. An entire mixed-language
// sentence with unresolved Han in its reading is deliberately not ruby-safe.
List<JapanesePhoneticWord> _analyzedWords(String chunk) {
  final words = <JapanesePhoneticWord>[];
  var cursor = 0;
  for (final match in RegExp('夜空|終点').allMatches(chunk)) {
    if (cursor < match.start) {
      final original = chunk.substring(cursor, match.start);
      words.add(JapanesePhoneticWord(original, original));
    }
    final original = match.group(0)!;
    words.add(
        JapanesePhoneticWord(original, original == '夜空' ? 'よぞら' : 'しゅうてん'));
    cursor = match.end;
  }
  if (cursor < chunk.length) {
    final original = chunk.substring(cursor);
    words.add(JapanesePhoneticWord(original, original));
  }
  return words;
}

class _Word extends SyncLyricWord {
  _Word(int index, String text, {int base = 0})
      : super(Duration(milliseconds: base + index * 700),
            const Duration(milliseconds: 1600), text);
}

class _Line extends SyncLyricLine {
  _Line({int start = 0, String first = '夜空かな ', String last = '한글 終点'})
      : super(
            Duration(milliseconds: start),
            const Duration(seconds: 8),
            [
              _Word(0, first, base: start),
              _Word(1, 'English e\u0301 ', base: start),
              _Word(2, last, base: start),
            ],
            'The night sky');
}

class _Document extends Lyric {
  _Document(LyricLine line, {LyricLine? next})
      : super([line, if (next != null) next]);
}

class _Audio extends Fake implements Audio {
  _Audio([this.id = '']);
  final String id;
  @override
  String get path =>
      'synthetic-linkage${id.isEmpty ? '' : '-$id'}-not-opened.wav';
  @override
  String get stableTrackId => 'synthetic-lyric-tools-linkage$id';
  @override
  bool get isOnline => false;
  @override
  String? get language => 'ja';
}

class _Playback extends Fake implements PlaybackService {
  final positions = StreamController<double>.broadcast(sync: true);
  @override
  Audio get nowPlaying => replacement ?? _audio;
  final _audio = _Audio();
  Audio? replacement;
  @override
  Stream<double> get positionStream => positions.stream;
  double currentPosition = 1.55;
  @override
  double get position => currentPosition;
  @override
  Future<void> close() async {}
}

/// Only the OS process transport is substituted. Both message directions use
/// the production service/controller, JSON parser and revision/acknowledgment.
class _PipeProcess extends Fake implements Process {
  _PipeProcess(this.helper) {
    _input.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      received.add(Map<String, dynamic>.from(jsonDecode(line) as Map));
      helper.handleMessage(line);
    });
    input = IOSink(_input.sink, encoding: utf8);
  }
  final DesktopLyricController helper;
  final _input = StreamController<List<int>>();
  final _output = StreamController<List<int>>();
  final _errors = StreamController<List<int>>();
  final _exit = Completer<int>();
  final received = <Map<String, dynamic>>[];
  late final IOSink input;
  @override
  IOSink get stdin => input;
  @override
  Stream<List<int>> get stdout => _output.stream;
  @override
  Stream<List<int>> get stderr => _errors.stream;
  @override
  Future<int> get exitCode => _exit.future;
  void emit(String line) => _output.add(utf8.encode(line));
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exit.isCompleted) _exit.complete(0);
    return true;
  }

  Future<void> close() async {
    await input.close();
    unawaited(_output.close());
    unawaited(_errors.close());
  }
}

class _LyricSource extends TaskbarLyricSource {
  _LyricSource(this.service) {
    service.addListener(_changed);
  }
  final LyricService service;
  void _changed() => notifyListeners();
  @override
  Future<Lyric?> get lyric => service.currLyricFuture;
  @override
  int get generation => service.resolutionGeneration;
  @override
  int get session => 1;
  @override
  bool get hasTrack => true;
  @override
  double get position => 1.55;
  @override
  bool get playing => false;
  @override
  void dispose() {
    service.removeListener(_changed);
    super.dispose();
  }
}

class _Rig {
  _Rig(
      {_Document? document,
      JapaneseChunkAnalyzer? analyze,
      JapaneseReadingProjector? projector,
      Future<void> Function()? persistSettings,
      this.continuousReadingActions = false})
      : canonical = document ?? _Document(_Line()),
        _persistSettings = persistSettings {
    helper = DesktopLyricController.detached(
        clock: PlaybackClock(automaticTicks: false, nowMilliseconds: () => 0),
        sendMessage: (line) => process.emit(line),
        setIgnoreMouseEvents: (_) async {},
        closeWindow: () async {});
    process = _PipeProcess(helper);
    facade = PlayService.forTesting(
      readiness: readiness,
      createPlayback: (_) => playback,
      createDesktopLyric: (owner) => DesktopLyricService(owner,
          playbackReady: desktopReady,
          executableExists: (_) => true,
          readTheme: () => ColorScheme.fromSeed(seedColor: Colors.teal),
          readFontPolicy: () => AppFontPolicy.defaults(),
          displayCoordinator: LyricDisplayCoordinator(),
          saveAppearance: persist,
          startProcess: (_, arguments) async {
            helper.applyInitialState(InitArgsMessage.fromJson(
                Map<String, dynamic>.from(jsonDecode(arguments.last) as Map)));
            return process;
          }),
      createLyric: (owner) =>
          LyricService.forTesting(owner, resolveDefaultLyric: (_) async {
        lookups++;
        return canonical;
      },
              japanesePreferences: AppSettings.instance.japaneseReadings,
              japaneseProjector: projector ??
                  JapaneseReadingProjector(analyze: (chunks) async {
                    analyses++;
                    if (analyze != null) return analyze(chunks);
                    return JapanesePhoneticBatch([
                      for (final chunk in chunks) _analyzedWords(chunk),
                    ]);
                  })),
    );
    controller = LyricViewController(
        preferences: NowPlayingPagePreference.fromMap({}),
        appearance: AppSettings.instance.desktopLyricAppearance,
        persistAppearance: persist);
    taskbar = TaskbarLyricService(
        preferences: taskbarPreferences,
        playbackReady: taskbarReady,
        createSource: () => _LyricSource(lyrics),
        coordinator: LyricDisplayCoordinator(),
        savePreferences: () async {},
        rendering: AppSettings.instance.rendering,
        appearanceChanges: AppSettings.instance.desktopLyricAppearance);
  }
  _Document canonical;
  final bool continuousReadingActions;
  final Future<void> Function()? _persistSettings;
  final playback = _Playback();
  final readiness = PlaybackReadiness();
  final desktopReady = ValueNotifier(false);
  final taskbarReady = ValueNotifier(true);
  final taskbarPreferences =
      ValueNotifier(const PlayerExperiencePreferences(taskbarLyrics: true));
  final position = ValueNotifier(const Duration(milliseconds: 1550));
  final packets = <Map<String, Object>>[];
  final manualResults = <JapaneseReadingResult>[];
  late final DesktopLyricController helper;
  late final _PipeProcess process;
  late final PlayService facade;
  late final LyricViewController controller;
  late final TaskbarLyricService taskbar;
  int writes = 0, lookups = 0, analyses = 0;
  int pendingWrites = 0;
  String closingStage = 'not started';
  LyricService get lyrics => facade.lyricService;
  Future<void> persist() async {
    writes++;
    pendingWrites++;
    try {
      await _persistSettings?.call();
    } finally {
      pendingWrites--;
    }
  }

  Future<void> initialize({bool waitForLyrics = true}) async {
    await facade.desktopLyricService.startDesktopLyric();
    lyrics.updateLyric();
    if (waitForLyrics) await lyrics.currLyricFuture;
    taskbar.attach(
        appearance: () => TaskbarLyricAppearance(
            accent: Colors.teal.toARGB32(),
            fontFamily: AppFontPolicy.defaults().uiFamily,
            fontPath: '',
            lyricLetterSpacing: AppSettings
                .instance.desktopLyricAppearance.value.lyricLetterSpacing),
        send: (packet) async => packets.add(Map<String, Object>.of(packet)),
        onError: (error, stack) => fail('$error\n$stack'));
    await _drain();
    await process.input.flush();
    helper.playbackClock
        .sync(PlaybackTimelineMessage(helper.activeSequence, 1550, false));
  }

  Future<void> generate(NavigatorState navigator) async {
    if (continuousReadingActions) {
      controller.toggleJapaneseReadingGeneration();
      if (!controller.showJapaneseReading) {
        lyrics.cancelJapaneseReadingsForCurrentTrack(
            expectedGeneration: lyrics.resolutionGeneration);
      }
      await controller.persistJapaneseReadingVisibility();
    } else {
      controller.toggleJapaneseReading();
    }
    if (!controller.showJapaneseReading) return;
    final generation = lyrics.resolutionGeneration;
    final mode = AppSettings.instance.automaticOnlineLyrics.value
        ? JapaneseReadingRequestMode.automatic
        : JapaneseReadingRequestMode.offline;
    if (!navigator.mounted || generation != lyrics.resolutionGeneration) {
      return;
    }
    final result = await lyrics.ensureJapaneseReadingsForCurrentTrack(
        expectedGeneration: generation, mode: mode);
    if (navigator.mounted && generation == lyrics.resolutionGeneration) {
      manualResults.add(result);
    }
  }

  Future<void> close() async {
    closingStage = 'taskbar';
    await taskbar.dispose();
    closingStage = 'main controller';
    controller.dispose();
    closingStage = 'facade';
    await facade.close();
    closingStage = 'desktop helper';
    helper.dispose();
    closingStage = 'process pipes';
    await process.close();
    closingStage = 'playback stream';
    await playback.positions.close();
    readiness.dispose();
    desktopReady.dispose();
    taskbarReady.dispose();
    taskbarPreferences.dispose();
    position.dispose();
    closingStage = 'complete';
  }
}

Future<void> _drain() async {
  for (var index = 0; index < 8; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _pumpTransport(WidgetTester tester) async {
  for (var index = 0; index < 5; index++) {
    await tester.runAsync(_drain);
    await tester.pump();
  }
}

Future<void> _drainCachedSource(WidgetTester tester, _Rig rig) async {
  final future = rig.lyrics.currLyricFuture;
  var completed = false;
  Object? failure;
  StackTrace? stack;
  unawaited(future.then<void>((_) => completed = true,
      onError: (Object error, StackTrace trace) {
    failure = error;
    stack = trace;
    completed = true;
  }));
  // This cache read was started by the widget's fake-async action. Real file
  // events and its subsequent fake-zone continuations must both finish before
  // pumpAndSettle can verify the remaining finite visual work.
  for (var index = 0; !completed && index < 100; index++) {
    await _pumpTransport(tester);
    expect(rig.lyrics.currLyricFuture, same(future),
        reason: 'No consumer may continuously replace the source future');
  }
  expect(completed, isTrue, reason: 'The owned cache read must finish');
  if (failure != null) Error.throwWithStackTrace(failure!, stack!);
}

Future<void> _closeRig(WidgetTester tester, _Rig rig) async {
  await tester.pumpWidget(const SizedBox.shrink());
  var finished = false;
  Object? error;
  StackTrace? stack;
  // Runtime notifier callbacks can create fake-zone save/publication tails.
  // Drain both those microtasks and the real IOSink events while closing.
  unawaited(rig.close().then((_) => finished = true,
      onError: (Object failure, StackTrace trace) {
    error = failure;
    stack = trace;
    finished = true;
  }));
  for (var index = 0; index < 100 && !finished; index++) {
    await tester.runAsync(_drain);
    await tester.pump();
    if (_diagnostics) debugPrint('linkage close: ${rig.closingStage}');
  }
  expect(finished, isTrue,
      reason: 'Fixture shutdown stalled at ${rig.closingStage}');
  if (error != null) Error.throwWithStackTrace(error!, stack!);
}

void _expectIdle(WidgetTester tester) {
  if (_diagnostics && tester.binding.transientCallbackCount != 0) {
    final previous = FlutterError.onError;
    try {
      FlutterError.onError = (details) =>
          FlutterError.dumpErrorToConsole(details, forceReport: true);
      tester.binding.debugAssertNoTransientCallbacks(
          'Lyric linkage idle registration diagnostics');
    } finally {
      FlutterError.onError = previous;
    }
  }
  expect(tester.binding.transientCallbackCount, 0);
}

void _expectMainReading(WidgetTester tester, String reading) {
  final labels = tester
      .widgetList<Semantics>(find.descendant(
          of: find.byKey(_mainLine), matching: find.byType(Semantics)))
      .map((widget) => widget.properties.label)
      .whereType<String>();
  expect(labels, contains(contains(reading)));
}

Widget _host(_Rig rig,
        {double scale = 1,
        bool ticker = true,
        bool motion = true,
        GlobalKey? boundary}) =>
    TickerMode(
      enabled: ticker,
      child: MaterialApp(
        theme: applyAppControlTheme(ThemeData(
            platform: TargetPlatform.windows,
            fontFamily:
                AppFontPolicy.defaults(language: uiLanguage.value).uiFamily,
            fontFamilyFallback:
                AppFontPolicy.defaults(language: uiLanguage.value).fallback,
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal))),
        builder: (context, child) => RepaintBoundary(
            key: boundary,
            child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: !motion),
                child: child!)),
        home: Scaffold(
            body: AppFontScope(
                policy: AppFontPolicy.defaults(language: uiLanguage.value),
                child: TickerMode(
                    enabled: ticker,
                    child: ChangeNotifierProvider.value(
                        value: rig.controller,
                        child: SingleChildScrollView(
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(children: [
                                  LyricExperienceSettings(persist: rig.persist),
                                  const SizedBox(height: 16),
                                  Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        const LyricFontSizeMenu(),
                                        LyricReadingMenu(
                                            controller: rig.controller,
                                            readLyric: () =>
                                                rig.lyrics.currLyricFuture,
                                            japaneseReadingsBusy:
                                                rig.lyrics.japaneseReadingsBusy,
                                            onToggleJapaneseReading:
                                                rig.generate),
                                      ]),
                                  ListenableBuilder(
                                      listenable: rig.lyrics,
                                      builder: (_, __) => FutureBuilder<Lyric?>(
                                          future: rig.lyrics.currLyricFuture,
                                          builder: (_, snapshot) => snapshot
                                                  .hasData
                                              ? LyricViewTile(
                                                  key: _mainLine,
                                                  line: snapshot
                                                      .data!.lines.single,
                                                  position: rig.position,
                                                  opacity: 1,
                                                  distance: 0,
                                                  reducedMotion:
                                                      !ticker || !motion)
                                              : const SizedBox.shrink())),
                                  MultiProvider(
                                      providers: [
                                        ChangeNotifierProvider<
                                                TextDisplayController>.value(
                                            value: rig.helper.appearance),
                                        Provider<ThemeChangedMessage>.value(
                                            value: rig.helper.theme.value),
                                      ],
                                      child: LyricLineDisplayArea(
                                          controller: rig.helper)),
                                  ListenableBuilder(
                                      listenable: rig.helper.appearance,
                                      builder: (_, __) =>
                                          DesktopLyricAppearanceOptions(
                                              appearance:
                                                  rig.helper.appearance.value,
                                              section: DesktopLyricOptionSection
                                                  .sliders,
                                              onChanged: rig
                                                  .helper.appearance.update)),
                                ]))))))),
      ),
    );

List<TextPainter> _mainPainters(WidgetTester tester, String text) => tester
    .widgetList<CustomPaint>(find.descendant(
        of: find.byKey(_mainLine), matching: find.byType(CustomPaint)))
    .map((widget) => switch (widget.painter) {
          LyricWordHighlightPainter painter => painter.text,
          PlainLyricWordFollowPainter painter => painter.text,
          _ => null,
        })
    .whereType<TextPainter>()
    .where((painter) => painter.text?.toPlainText() == text)
    .toList();

DesktopLyricTextPainter _desktopPainter(WidgetTester tester) => tester
    .widget<CustomPaint>(find.descendant(
        of: find.byKey(const ValueKey('desktop-primary-lyric')),
        matching: find.byType(CustomPaint)))
    .painter! as DesktopLyricTextPainter;

void _completeLabel(WidgetTester tester, Finder root, String text,
    {required double width}) {
  final label = find.descendant(of: root, matching: find.text(text));
  expect(label, findsOneWidget);
  final widget = tester.widget<Text>(label);
  expect(widget.overflow, isNot(TextOverflow.ellipsis));
  final paragraph = tester.renderObject<RenderParagraph>(label);
  final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: text.length - 1, extentOffset: text.length));
  expect(boxes, isNotEmpty);
  for (final box in boxes) {
    final start = paragraph.localToGlobal(Offset(box.left, box.top));
    final end = paragraph.localToGlobal(Offset(box.right, box.bottom));
    expect(start.dx, greaterThanOrEqualTo(0));
    expect(end.dx, lessThanOrEqualTo(width));
    expect(start.dy, greaterThanOrEqualTo(0));
    expect(end.dy, lessThanOrEqualTo(tester.view.physicalSize.height));
  }
}

Widget _lateReadingHost(_Rig rig, {bool motion = true}) => MaterialApp(
      theme: applyAppControlTheme(ThemeData(
          platform: TargetPlatform.windows,
          fontFamily: AppFontPolicy.defaults().uiFamily,
          fontFamilyFallback: AppFontPolicy.defaults().fallback,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal))),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: !motion),
          child: child!),
      home: Scaffold(
        body: AppFontScope(
          policy: AppFontPolicy.defaults(),
          child: RenderingPreferencesScope(
            preferences: AppSettings.instance.rendering,
            child: ChangeNotifierProvider.value(
              value: rig.controller,
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  LyricReadingMenu(
                      controller: rig.controller,
                      readLyric: () => rig.lyrics.currLyricFuture,
                      onToggleJapaneseReading: rig.generate,
                      japaneseReadingsBusy: rig.lyrics.japaneseReadingsBusy),
                ]),
                SizedBox(
                  key: _mainLine,
                  height: 480,
                  child: ListenableBuilder(
                    listenable: rig.lyrics,
                    builder: (_, __) => VerticalLyricContent(
                        sourceIdentity: (rig.lyrics.resolutionGeneration, 1),
                        initialPresentation: rig.lyrics.currentPresentation,
                        lyricFuture: rig.lyrics.currLyricFuture,
                        positionStream: rig.playback.positionStream,
                        readPosition: () => rig.playback.position,
                        onSeek: (_) => fail('A display toggle must not seek')),
                  ),
                ),
                MultiProvider(providers: [
                  ChangeNotifierProvider<TextDisplayController>.value(
                      value: rig.helper.appearance),
                  Provider<ThemeChangedMessage>.value(
                      value: rig.helper.theme.value),
                ], child: LyricLineDisplayArea(controller: rig.helper)),
              ]),
            ),
          ),
        ),
      ),
    );

double _mainRubyVisibility(WidgetTester tester, String text) {
  final values = tester
      .widgetList<CustomPaint>(find.descendant(
          of: find.byKey(_mainLine), matching: find.byType(CustomPaint)))
      .map((paint) => switch (paint.painter) {
            LyricWordHighlightPainter painter
                when painter.text.text?.toPlainText() == text =>
              painter.rubyVisibility,
            PlainLyricWordFollowPainter painter
                when painter.text.text?.toPlainText() == text =>
              painter.rubyVisibility,
            _ => null,
          })
      .whereType<double>()
      .toList();
  expect(values, isNotEmpty, reason: 'The current primary stays painted');
  return values.reduce((a, b) => a > b ? a : b);
}

Future<void> _toggleReadingMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(_readingOpen));
  await tester.pump();
  expect(find.byKey(_generate).hitTestable(), findsOneWidget);
  await tester.tap(find.byKey(_generate));
  await _pumpTransport(tester);
}

void _lateStage(String stage) {
  if (_diagnostics) debugPrint('JAPANESE_LATE_STAGE $stage');
}

Future<({Directory directory, JapaneseLyricReadingCache cache})>
    _seedCachedReadings(_Document document) async {
  final root = await Directory(
          'J:/temp/codex/software/danplayer/tool/qa-local/blur-position-feedback-oct12/cache/linkage')
      .create(recursive: true);
  final directory = await root.createTemp('case-');
  final cache = JapaneseLyricReadingCache(
      directory: () async => directory, engine: 'linked-cache-v1');
  final projector = JapaneseReadingProjector(
      cache: cache,
      waitForCacheWrites: true,
      analyze: (chunks) async => JapanesePhoneticBatch([
            for (final chunk in chunks) _analyzedWords(chunk),
          ]));
  try {
    final generated = await projector.project(document,
        enabled: false, force: true, stillCurrent: () => true);
    expect(generated.result, JapaneseReadingResult.applied);
    await cache.flush();
  } finally {
    projector.dispose();
  }
  return (directory: directory, cache: cache);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadLetterSpacingFonts();
    await loadPlaylistFeatureFonts();
  });
  setUp(() {
    final settings = AppSettings.instance;
    final appearance = settings.desktopLyricAppearance.value;
    final experience = settings.experience.value;
    final readings = settings.japaneseReadings.value;
    final rendering = settings.rendering.value;
    final automaticOnline = settings.automaticOnlineLyrics.value;
    final language = uiLanguage.value;
    final motion = desktopMotionPreferences.value;
    settings.desktopLyricAppearance.value = DesktopLyricAppearance.defaults;
    settings.experience.value = const PlayerExperiencePreferences();
    settings.japaneseReadings.value = const JapaneseReadingPreferences();
    settings.rendering.value = const RenderingPreferences();
    settings.automaticOnlineLyrics.value = false;
    desktopMotionPreferences.value = const MotionPreferences();
    addTearDown(() {
      settings.desktopLyricAppearance.value = appearance;
      settings.experience.value = experience;
      settings.japaneseReadings.value = readings;
      settings.rendering.value = rendering;
      settings.automaticOnlineLyrics.value = automaticOnline;
      uiLanguage.value = language;
      desktopMotionPreferences.value = motion;
    });
  });

  testWidgets(
      'checked cached song mounts Japanese main desktop and taskbar together',
      (tester) async {
    sizePlaylistFeature(tester, width: 1000, height: 900);
    final canonical = _Document(_Line());
    final fixture =
        (await tester.runAsync(() => _seedCachedReadings(canonical)))!;
    // The legacy stored display flag predates the automatic-generation setting.
    // Restoring it authorizes a read, not dictionary work or network access.
    AppSettings.instance.desktopLyricAppearance.value =
        DesktopLyricAppearance.fromJson({
      ...DesktopLyricAppearance.defaults.toJson(),
      'showJapaneseReading': true,
    });
    var calls = 0;
    final rig = (await tester.runAsync(() async => _Rig(
        document: canonical,
        projector: JapaneseReadingProjector(
            cache: fixture.cache,
            analyze: (_) async {
              calls++;
              throw StateError('A restored checkbox is not generation consent');
            }))))!;
    addTearDown(() async {
      await _closeRig(tester, rig);
      await tester.runAsync(() async {
        await fixture.cache.flush();
        await fixture.directory.delete(recursive: true);
      });
    });
    final published = <Lyric>[];
    rig.lyrics.addListener(() {
      final value = rig.lyrics.currentPresentation;
      if (value != null) published.add(value);
    });
    await tester.runAsync(rig.initialize);
    await tester.pumpWidget(_lateReadingHost(rig));
    await _pumpTransport(tester);
    await tester.pumpAndSettle();
    final primary = (canonical.lines.single as SyncLyricLine).content;
    expect(published, isNotEmpty);
    expect(
        published.every(
            (value) => value.lines.single.japaneseReadingSpans.isNotEmpty),
        isTrue);
    expect(_mainRubyVisibility(tester, primary), 1);
    expect(_desktopPainter(tester).rubyVisibility, 1);
    expect(
        rig.helper.detailedLyricLine.value!.japaneseReadingSpans, isNotEmpty);
    expect(rig.packets.last['text'], primary);
    expect(rig.packets.last['enabled'], isTrue);
    expect(calls, 0);
    expect(AppSettings.instance.japaneseReadings.value.enabled, isFalse);
    expect(AppSettings.instance.automaticOnlineLyrics.value, isFalse);
    expect(canonical.lines.single.japaneseReadingSpans, isEmpty);

    final other = _Document(_Line(first: 'Plain ', last: '한글'));
    rig.playback.replacement = _Audio('other');
    rig.lyrics.useSpecificLyric(other);
    await _pumpTransport(tester);
    await tester.pumpAndSettle();
    expect(rig.lyrics.currentPresentation, same(other));
    expect(_desktopPainter(tester).rubyVisibility, 0);
    published.clear();
    rig.playback.replacement = null;
    rig.lyrics.useSpecificLyric(canonical);
    await _drainCachedSource(tester, rig);
    await tester.pumpAndSettle();
    expect(published, isNotEmpty);
    expect(
        published.every(
            (value) => value.lines.single.japaneseReadingSpans.isNotEmpty),
        isTrue,
        reason: 'Returning to a cached song never publishes a plain copy');
    expect(_mainRubyVisibility(tester, primary), 1);
    expect(_desktopPainter(tester).rubyVisibility, 1);
    expect(rig.packets.last['text'], primary);
    expect(calls, 0);
    expect(rig.controller.showJapaneseReading, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'late checked cache cannot replace another song in any lyric view',
      (tester) async {
    sizePlaylistFeature(tester, width: 1000, height: 900);
    final canonical = _Document(_Line());
    final fixture =
        (await tester.runAsync(() => _seedCachedReadings(canonical)))!;
    final waiting = Completer<Directory>();
    final rig = (await tester.runAsync(() async => _Rig(
        document: canonical,
        projector: JapaneseReadingProjector(
            cache: JapaneseLyricReadingCache(
                directory: () => waiting.future, engine: 'linked-cache-v1'),
            analyze: (_) =>
                throw StateError('Late cache must not analyze')))))!;
    addTearDown(() async {
      if (!waiting.isCompleted) waiting.complete(fixture.directory);
      await _closeRig(tester, rig);
      await tester.runAsync(() async {
        await fixture.cache.flush();
        await fixture.directory.delete(recursive: true);
      });
    });
    await tester.runAsync(() => rig.initialize(waitForLyrics: false));
    final old = rig.lyrics.currLyricFuture;
    await tester.pumpWidget(_lateReadingHost(rig));
    await _pumpTransport(tester);
    expect(rig.lyrics.currentPresentation, isNull);
    final other = _Document(_Line(first: 'Plain ', last: '한글'));
    final primary = (other.lines.single as SyncLyricLine).content;
    rig.playback.replacement = _Audio('other');
    rig.lyrics.useSpecificLyric(other);
    await _pumpTransport(tester);
    await tester.pumpAndSettle();
    expect(rig.lyrics.currentPresentation, same(other));
    expect(_mainRubyVisibility(tester, primary), 0);
    expect(_desktopPainter(tester).rubyVisibility, 0);
    final count = rig.packets.length;
    waiting.complete(fixture.directory);
    await _pumpTransport(tester);
    expect(await tester.runAsync(() => old), isNull);
    await tester.pumpAndSettle();
    expect(rig.lyrics.currentPresentation, same(other));
    expect(rig.helper.detailedLyricLine.value!.content, primary);
    expect(rig.helper.detailedLyricLine.value!.japaneseReadingSpans, isEmpty);
    expect(rig.packets.last['text'], primary);
    expect(
        rig.packets.skip(count).every(
            (packet) => packet['enabled'] != true || packet['text'] == primary),
        isTrue);
    expect(_mainRubyVisibility(tester, primary), 0);
    expect(_desktopPainter(tester).rubyVisibility, 0);
    expect(canonical.lines.single.japaneseReadingSpans, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'explicit reader checkbox shares continuous generation with settings',
      (tester) async {
    sizePlaylistFeature(tester, width: 1000, height: 900);
    final pending = Completer<JapanesePhoneticBatch>();
    var calls = 0, onlineCalls = 0;
    final policy = JapaneseReadingAnalyzerPolicy(
        onlineAllowed: () => AppSettings.instance.automaticOnlineLyrics.value,
        clientId: () => 'remembered-but-not-authorized-client',
        online: JapaneseOnlineReadingAnalyzer(request: (_, __, ___) async {
          onlineCalls++;
          throw StateError(
              'Remembered credentials do not grant network access');
        }),
        hasDictionary: () async => true,
        cancelOffline: () {},
        offline: (chunks) async {
          calls++;
          if (calls == 1) return pending.future;
          return JapanesePhoneticBatch([
            for (final chunk in chunks) _analyzedWords(chunk),
          ]);
        });
    addTearDown(policy.dispose);
    final rig = (await tester.runAsync(() async => _Rig(
        continuousReadingActions: true,
        projector: JapaneseReadingProjector(
            policy: policy,
            analyze: (_) =>
                throw StateError('The policy owns this fixture')))))!;
    addTearDown(() async {
      if (!pending.isCompleted) {
        pending.complete(const JapanesePhoneticBatch([], available: false));
      }
      await _closeRig(tester, rig);
    });
    await tester.runAsync(rig.initialize);
    rig.controller.setShowJapaneseReading(false);
    await tester.pumpWidget(_lateReadingHost(rig));
    await _pumpTransport(tester);
    await tester.pumpAndSettle();
    await _toggleReadingMenu(tester);
    expect(rig.controller.showJapaneseReading, isTrue);
    expect(AppSettings.instance.japaneseReadings.value.enabled, isTrue);
    expect(AppSettings.instance.japaneseReadings.value.offlineGenerationAllowed,
        isTrue);
    expect(AppSettings.instance.automaticOnlineLyrics.value, isFalse);
    expect(calls, 1,
        reason: 'The preference listener and current-track ensure share work');
    expect(rig.lyrics.japaneseReadingsBusy.value, isTrue);
    pending.complete(JapanesePhoneticBatch([
      for (final line in rig.canonical.lines)
        _analyzedWords((line as SyncLyricLine).content),
    ]));
    await _pumpTransport(tester);
    await tester.pumpAndSettle();
    expect(rig.manualResults, [JapaneseReadingResult.applied]);
    expect(_desktopPainter(tester).rubyVisibility, 1);
    expect(calls, 1);
    final other = _Document(_Line(first: '夜空かな 次 ', last: '한글 終点'));
    rig.playback.replacement = _Audio('other');
    rig.lyrics.useSpecificLyric(other);
    await _pumpTransport(tester);
    await tester.pumpAndSettle();
    final primary = (other.lines.single as SyncLyricLine).content;
    expect(calls, 2,
        reason: 'The checked option also applies to the next song');
    expect(onlineCalls, 0);
    expect(_mainRubyVisibility(tester, primary), 1);
    expect(_desktopPainter(tester).rubyVisibility, 1);
    expect(rig.packets.last['text'], primary);
    await _toggleReadingMenu(tester);
    await tester.pumpAndSettle();
    expect(rig.controller.showJapaneseReading, isFalse);
    expect(AppSettings.instance.japaneseReadings.value.enabled, isFalse);
    expect(_desktopPainter(tester).rubyVisibility, 0);
    expect(other.lines.single.japaneseReadingSpans, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'cached reader activation persists intent without replacing its owner',
      (tester) async {
    sizePlaylistFeature(tester, width: 1000, height: 900);
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
    expect(Directory.systemTemp.absolute.path.replaceAll('\\', '/'),
        contains('/tool/qa-local/'));
    final oldPreferences = JapaneseReadingPreferences.fromJson(const {
      'enabled': true,
      'lastManualMode': 'online',
      'yahooClientId': 'remembered-is-not-new-permission',
    });
    expect(oldPreferences.offlineGenerationAllowed, isFalse);
    expect(oldPreferences.toJson().containsKey('offlineGenerationAllowed'),
        isFalse);
    final canonical = _Document(_Line());
    final fixture =
        (await tester.runAsync(() => _seedCachedReadings(canonical)))!;
    const provider = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        provider, (_) async => fixture.directory.path);
    var calls = 0;
    final rig = (await tester.runAsync(() async => _Rig(
        document: canonical,
        continuousReadingActions: true,
        persistSettings: () => AppSettings.instance
            .saveSettings(throwOnError: true, captureWindowSize: false),
        projector: JapaneseReadingProjector(
            cache: fixture.cache,
            analyze: (_) async {
              calls++;
              throw StateError('Existing cached readings need no analysis');
            }))))!;
    addTearDown(() async {
      await _closeRig(tester, rig);
      messenger.setMockMethodCallHandler(provider, null);
      await tester.runAsync(() async {
        await fixture.cache.flush();
        await fixture.directory.delete(recursive: true);
      });
    });
    final support = (await tester.runAsync(getAppDataDir))!;
    expect(path.isWithin(fixture.directory.path, support.path), isTrue);
    await tester.runAsync(rig.initialize);
    rig.controller.setShowJapaneseReading(false);
    await tester.pumpWidget(_lateReadingHost(rig));
    await _pumpTransport(tester);
    await tester.pumpAndSettle();
    final future = rig.lyrics.currLyricFuture;
    final display = (await tester.runAsync(() => future))!;
    rig.controller
        .revealForReading(LyricReadingTarget(display, 0, display.lines.single));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(VerticalLyricScrollView));
    final request = rig.controller.readingRequest;
    final sequence = rig.helper.activeSequence;
    await _toggleReadingMenu(tester);
    await tester.pumpAndSettle();
    expect(rig.lyrics.currLyricFuture, same(future));
    expect(rig.lyrics.currentPresentation, same(display));
    expect(rig.controller.readingTarget!.belongsTo(display), isTrue);
    expect(rig.controller.readingRequest, request);
    expect(tester.state(find.byType(VerticalLyricScrollView)), same(state));
    expect(rig.helper.activeSequence, sequence);
    expect(_desktopPainter(tester).rubyVisibility, 1);
    expect(calls, 0);
    expect(rig.manualResults, [JapaneseReadingResult.unchanged]);
    expect(AppSettings.instance.japaneseReadings.value.enabled, isTrue);
    expect(AppSettings.instance.japaneseReadings.value.offlineGenerationAllowed,
        isTrue);
    expect(AppSettings.instance.automaticOnlineLyrics.value, isFalse);
    // The menu callback owns real disk I/O but was delivered in fake async.
    // Drain both environments until that actual save finishes before reading it.
    for (var index = 0; rig.pendingWrites != 0 && index < 100; index++) {
      await _pumpTransport(tester);
    }
    expect(rig.pendingWrites, 0,
        reason: 'The actual settings save must finish before disk reload');
    final saved = (await tester.runAsync(() async => jsonDecode(
            await File(path.join(support.path, 'settings.json')).readAsString())
        as Map))!;
    final restored =
        JapaneseReadingPreferences.fromJson(saved['japaneseReadings']);
    expect(restored.enabled, isTrue);
    expect(restored.offlineGenerationAllowed, isTrue);
    expect((saved['DesktopLyricAppearance'] as Map)['showJapaneseReading'],
        isTrue);
    expect(canonical.lines.single.japaneseReadingSpans, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'reader OFF revokes both continuous and legacy pending generation',
      (tester) async {
    sizePlaylistFeature(tester, width: 1000, height: 900);
    final pending = [
      Completer<JapanesePhoneticBatch>(),
      Completer<JapanesePhoneticBatch>(),
    ];
    var calls = 0;
    final rig = (await tester.runAsync(() async => _Rig(
        continuousReadingActions: true,
        analyze: (_) => pending[calls++].future)))!;
    addTearDown(() async {
      for (final completion in pending) {
        if (!completion.isCompleted) {
          completion
              .complete(const JapanesePhoneticBatch([], available: false));
        }
      }
      await _closeRig(tester, rig);
    });
    await tester.runAsync(rig.initialize);
    rig.controller.setShowJapaneseReading(false);
    await tester.pumpWidget(_lateReadingHost(rig));
    await _pumpTransport(tester);
    await tester.pumpAndSettle();
    await _toggleReadingMenu(tester);
    final continuous = rig.lyrics.currLyricFuture;
    expect(calls, 1);
    expect(rig.lyrics.japaneseReadingsBusy.value, isTrue);
    expect(AppSettings.instance.japaneseReadings.value.offlineGenerationAllowed,
        isTrue);
    await _toggleReadingMenu(tester);
    expect(rig.controller.showJapaneseReading, isFalse);
    expect(AppSettings.instance.japaneseReadings.value.enabled, isFalse);
    expect(AppSettings.instance.japaneseReadings.value.offlineGenerationAllowed,
        isFalse);
    expect(rig.lyrics.japaneseReadingsBusy.value, isFalse);
    final source = rig.canonical.lines.single as SyncLyricLine;
    pending[0]
        .complete(JapanesePhoneticBatch([_analyzedWords(source.content)]));
    await _pumpTransport(tester);
    expect(await tester.runAsync(() => continuous), isNull);
    await tester.pumpAndSettle();
    expect(rig.lyrics.currentPresentation, same(rig.canonical));
    expect(_mainRubyVisibility(tester, source.content), 0);
    expect(_desktopPainter(tester).rubyVisibility, 0);

    // A prior explicit one-track request did not change generation preferences.
    // OFF must retire it even when writing false again emits no preference event.
    rig.controller.setShowJapaneseReading(true);
    final legacy = rig.lyrics.generateJapaneseReadingsForCurrentTrack(
        expectedGeneration: rig.lyrics.resolutionGeneration,
        mode: JapaneseReadingRequestMode.offline);
    await _pumpTransport(tester);
    expect(calls, 2);
    expect(rig.lyrics.japaneseReadingsBusy.value, isTrue);
    expect(AppSettings.instance.japaneseReadings.value.enabled, isFalse);
    await _toggleReadingMenu(tester);
    expect(rig.lyrics.japaneseReadingsBusy.value, isFalse);
    expect(rig.controller.showJapaneseReading, isFalse);
    pending[1]
        .complete(JapanesePhoneticBatch([_analyzedWords(source.content)]));
    await _pumpTransport(tester);
    expect(await tester.runAsync(() => legacy), JapaneseReadingResult.stale);
    await tester.pumpAndSettle();
    expect(rig.lyrics.currentPresentation, same(rig.canonical));
    expect(_mainRubyVisibility(tester, source.content), 0);
    expect(_desktopPainter(tester).rubyVisibility, 0);
    expect(rig.helper.detailedLyricLine.value!.japaneseReadingSpans, isEmpty);
    expect(rig.packets.last['text'], source.content);
    expect(source.japaneseReadingSpans, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed Japanese display reopens without replacing its reader',
      (tester) async {
    _lateStage('start');
    sizePlaylistFeature(tester, width: 1000, height: 900);
    final rig = (await tester.runAsync(() async =>
        _Rig(document: _Document(_Line(), next: _Line(start: 8000)))))!;
    addTearDown(() => _closeRig(tester, rig));
    await tester.runAsync(rig.initialize);
    _lateStage('initialized');
    await tester.runAsync(() => rig.lyrics
        .ensureJapaneseReadingsForCurrentTrack(
            expectedGeneration: rig.lyrics.resolutionGeneration));
    _lateStage('generated');
    await tester.pumpWidget(_lateReadingHost(rig));
    await _pumpTransport(tester);
    _lateStage('mounted');
    await tester.pumpAndSettle();
    _lateStage('settled');
    final completed = rig.lyrics.currLyricFuture;
    // This projection was created in runAsync. Read its result in the same
    // real async environment instead of awaiting it directly in fake async.
    final display = (await tester.runAsync(() => completed))!;
    _lateStage('observed completed display');
    rig.controller
        .revealForReading(LyricReadingTarget(display, 1, display.lines[1]));
    await tester.pumpAndSettle();
    _lateStage('reading target settled');
    final state = tester.state(find.byType(VerticalLyricScrollView));
    final request = rig.controller.readingRequest;
    final sequence = rig.helper.activeSequence;
    final packetCount = rig.packets.length;
    await _toggleReadingMenu(tester);
    await tester.pumpAndSettle();
    _lateStage('hidden');
    expect(rig.controller.showJapaneseReading, isFalse);
    await _toggleReadingMenu(tester);
    _lateStage('reopened');
    expect(rig.controller.showJapaneseReading, isTrue);
    expect(rig.lyrics.currLyricFuture, same(completed));
    expect(tester.state(find.byType(VerticalLyricScrollView)), same(state));
    expect(rig.controller.readingTarget!.belongsTo(display), isTrue);
    expect(rig.controller.readingRequest, request);
    expect(rig.controller.readingMode, isTrue);
    expect(rig.analyses, 1);
    expect(rig.manualResults, [JapaneseReadingResult.unchanged]);
    expect(rig.helper.activeSequence, sequence);
    expect(rig.helper.appearance.value.showJapaneseReading, isTrue);
    expect(
        rig.packets.skip(packetCount).every(
            (packet) => packet['enabled'] != true || packet['text'] != ''),
        isTrue);
    await tester.pumpAndSettle();
    _lateStage('complete');
    expect(tester.takeException(), isNull);
  });

  for (final alreadyShown in [false, true]) {
    testWidgets(
        'late Japanese data reveals after its display flag settled '
        'alreadyShown=$alreadyShown', (tester) async {
      sizePlaylistFeature(tester, width: 1000, height: 900);
      final pending = Completer<JapanesePhoneticBatch>();
      final rig = (await tester
          .runAsync(() async => _Rig(analyze: (_) => pending.future)))!;
      addTearDown(() => _closeRig(tester, rig));
      await tester.runAsync(rig.initialize);
      if (!alreadyShown) rig.controller.setShowJapaneseReading(false);
      await tester.pumpWidget(_lateReadingHost(rig));
      await _pumpTransport(tester);
      await tester.pumpAndSettle();
      if (alreadyShown) {
        rig.controller.revealForReading(
            LyricReadingTarget(rig.canonical, 0, rig.canonical.lines.single));
        await tester.pumpAndSettle();
      }
      final primary = (rig.canonical.lines.single as SyncLyricLine).content;
      final state = tester.state(find.byType(VerticalLyricScrollView));
      final readingRequest = rig.controller.readingRequest;
      final originalDetailed = rig.helper.detailedLyricLine.value;
      final sequence = rig.helper.activeSequence;
      if (alreadyShown) {
        AppSettings.instance.automaticOnlineLyrics.value = true;
        AppSettings.instance.japaneseReadings.value =
            const JapaneseReadingPreferences(enabled: true);
        await _pumpTransport(tester);
      } else {
        await _toggleReadingMenu(tester);
      }
      await tester.pump(const Duration(milliseconds: 700));
      expect(rig.controller.showJapaneseReading, isTrue);
      expect(rig.lyrics.japaneseReadingsBusy.value, isTrue);
      expect(tester.state(find.byType(VerticalLyricScrollView)), same(state));
      expect(_mainRubyVisibility(tester, primary), 0);
      expect(rig.helper.detailedLyricLine.value, same(originalDetailed));
      expect(_desktopPainter(tester).rubyVisibility, 0);
      pending.complete(JapanesePhoneticBatch([
        for (final line in rig.canonical.lines)
          _analyzedWords((line as SyncLyricLine).content),
      ]));
      await _pumpTransport(tester);
      expect(tester.state(find.byType(VerticalLyricScrollView)), same(state));
      if (alreadyShown) {
        final display =
            (await tester.runAsync(() => rig.lyrics.currLyricFuture))!;
        expect(rig.controller.readingTarget!.belongsTo(display), isTrue);
        expect(rig.controller.readingRequest, readingRequest);
        expect(rig.controller.readingMode, isTrue);
      }
      expect(rig.lyrics.japaneseReadingsBusy.value, isFalse);
      expect(_mainRubyVisibility(tester, primary), lessThan(1),
          reason: 'Late data starts its own reveal instead of flashing fully');
      expect(_desktopPainter(tester).rubyVisibility, lessThan(1));
      await tester.pump(const Duration(milliseconds: 90));
      expect(_mainRubyVisibility(tester, primary), greaterThan(0));
      expect(_mainRubyVisibility(tester, primary), lessThan(1));
      expect(_desktopPainter(tester).rubyVisibility, greaterThan(0));
      expect(_desktopPainter(tester).rubyVisibility, lessThan(1));
      await tester.pumpAndSettle();
      expect(_mainRubyVisibility(tester, primary), 1);
      expect(_desktopPainter(tester).rubyVisibility, 1);
      expect(rig.helper.activeSequence, sequence);
      expect(rig.analyses, 1);
      expect(rig.canonical.lines.single.japaneseReadingSpans, isEmpty);
      expect(rig.packets.last['text'], primary);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('initial automatic Japanese projection reveals over mounted text',
      (tester) async {
    sizePlaylistFeature(tester, width: 1000, height: 900);
    AppSettings.instance.automaticOnlineLyrics.value = true;
    AppSettings.instance.japaneseReadings.value =
        const JapaneseReadingPreferences(enabled: true);
    final pending = Completer<JapanesePhoneticBatch>();
    final rig = (await tester
        .runAsync(() async => _Rig(analyze: (_) => pending.future)))!;
    addTearDown(() => _closeRig(tester, rig));
    // Start the real transport without awaiting its final lyric projection.
    await tester.runAsync(rig.facade.desktopLyricService.startDesktopLyric);
    rig.lyrics.updateLyric();
    final future = rig.lyrics.currLyricFuture;
    var completed = false;
    unawaited(future.then((_) => completed = true));
    await tester.runAsync(_drain);
    expect(rig.lyrics.currentPresentation, same(rig.canonical));
    expect(completed, isFalse);
    await tester.pumpWidget(_lateReadingHost(rig));
    await _pumpTransport(tester);
    await tester.pumpAndSettle();
    final primary = (rig.canonical.lines.single as SyncLyricLine).content;
    final state = tester.state(find.byType(VerticalLyricScrollView));
    final sequence = rig.helper.activeSequence;
    expect(rig.controller.showJapaneseReading, isTrue);
    expect(_mainRubyVisibility(tester, primary), 0);
    expect(_desktopPainter(tester).rubyVisibility, 0);
    expect(rig.helper.detailedLyricLine.value!.content, primary);
    await tester.pump(const Duration(milliseconds: 700));
    expect(completed, isFalse);
    expect(tester.state(find.byType(VerticalLyricScrollView)), same(state));
    pending.complete(JapanesePhoneticBatch([
      for (final line in rig.canonical.lines)
        _analyzedWords((line as SyncLyricLine).content),
    ]));
    await _pumpTransport(tester);
    expect(completed, isTrue);
    expect(tester.state(find.byType(VerticalLyricScrollView)), same(state));
    expect(_mainRubyVisibility(tester, primary), lessThan(1));
    expect(_desktopPainter(tester).rubyVisibility, lessThan(1));
    await tester.pump(const Duration(milliseconds: 90));
    expect(_mainRubyVisibility(tester, primary), greaterThan(0));
    expect(_mainRubyVisibility(tester, primary), lessThan(1));
    expect(_desktopPainter(tester).rubyVisibility, greaterThan(0));
    expect(_desktopPainter(tester).rubyVisibility, lessThan(1));
    await tester.pumpAndSettle();
    expect(_mainRubyVisibility(tester, primary), 1);
    expect(_desktopPainter(tester).rubyVisibility, 1);
    expect(rig.helper.activeSequence, sequence);
    expect(rig.analyses, 1);
    expect(rig.canonical.lines.single.japaneseReadingSpans, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid Japanese hide and reopen retains one pending projection',
      (tester) async {
    sizePlaylistFeature(tester, width: 1000, height: 900);
    final pending = Completer<JapanesePhoneticBatch>();
    final rig = (await tester
        .runAsync(() async => _Rig(analyze: (_) => pending.future)))!;
    addTearDown(() => _closeRig(tester, rig));
    await tester.runAsync(rig.initialize);
    rig.controller.setShowJapaneseReading(false);
    await tester.pumpWidget(_lateReadingHost(rig));
    await _pumpTransport(tester);
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(VerticalLyricScrollView));
    await _toggleReadingMenu(tester);
    final projected = rig.lyrics.currLyricFuture;
    await _toggleReadingMenu(tester);
    expect(rig.controller.showJapaneseReading, isFalse);
    await _toggleReadingMenu(tester);
    expect(rig.controller.showJapaneseReading, isTrue);
    expect(rig.lyrics.currLyricFuture, same(projected));
    expect(rig.analyses, 1);
    pending.complete(JapanesePhoneticBatch([
      _analyzedWords((rig.canonical.lines.single as SyncLyricLine).content),
    ]));
    await _pumpTransport(tester);
    final primary = (rig.canonical.lines.single as SyncLyricLine).content;
    expect(tester.state(find.byType(VerticalLyricScrollView)), same(state));
    expect(_mainRubyVisibility(tester, primary), lessThan(1));
    await tester.pump(const Duration(milliseconds: 90));
    final midpoint = _mainRubyVisibility(tester, primary);
    expect(midpoint, greaterThan(0));
    expect(midpoint, lessThan(1));
    await _toggleReadingMenu(tester);
    await tester.pumpAndSettle();
    expect(_mainRubyVisibility(tester, primary), 0);
    expect(_desktopPainter(tester).rubyVisibility, 0);
    await _toggleReadingMenu(tester);
    expect(rig.lyrics.currLyricFuture, same(projected));
    await tester.pumpAndSettle();
    expect(_mainRubyVisibility(tester, primary), 1);
    expect(_desktopPainter(tester).rubyVisibility, 1);
    expect(rig.analyses, 1);
    expect(rig.controller.showJapaneseReading, isTrue);
    expect(rig.helper.appearance.value.showJapaneseReading, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final empty in [true, false]) {
    testWidgets(
        'Japanese display availability leaves no pending motion '
        '${empty ? 'without Han readings' : 'with animation disabled'}',
        (tester) async {
      sizePlaylistFeature(tester, width: 1000, height: 900);
      final rig = (await tester.runAsync(() async => _Rig(
          document:
              empty ? _Document(_Line(first: 'かな ', last: '한글 かな')) : null)))!;
      addTearDown(() => _closeRig(tester, rig));
      await tester.runAsync(rig.initialize);
      rig.controller.setShowJapaneseReading(false);
      await tester.pumpWidget(_lateReadingHost(rig, motion: empty));
      await _pumpTransport(tester);
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(VerticalLyricScrollView));
      await _toggleReadingMenu(tester);
      await tester.pumpAndSettle();
      final primary = (rig.canonical.lines.single as SyncLyricLine).content;
      expect(tester.state(find.byType(VerticalLyricScrollView)), same(state));
      expect(rig.controller.showJapaneseReading, isTrue);
      expect(_mainRubyVisibility(tester, primary), empty ? 0 : 1);
      expect(_desktopPainter(tester).rubyVisibility, empty ? 0 : 1);
      expect(rig.analyses, empty ? 0 : 1);
      expect(rig.lyrics.japaneseReadingsBusy.value, isFalse);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      _expectIdle(tester);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (retain, change) in [
    (true, ''),
    (false, ''),
    (false, 'line advance'),
    (false, 'width'),
    (false, 'font'),
    (false, 'source'),
  ]) {
    testWidgets(
        'opaque settings spacing change has a visible handoff when lyrics '
        'return retain=$retain${change.isEmpty ? '' : ' $change'}',
        (tester) async {
      sizePlaylistFeature(tester, width: 1000, height: 900);
      final rig = (await tester.runAsync(() async => _Rig(
          document: change == 'line advance'
              ? _Document(_Line(), next: _Line(start: 8000, first: '星空かな '))
              : null)))!;
      addTearDown(() => _closeRig(tester, rig));
      await tester.runAsync(rig.initialize);
      final navigator = GlobalKey<NavigatorState>();
      var lyricWidth = 290.0;
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        theme: applyAppControlTheme(ThemeData(
            platform: TargetPlatform.windows,
            fontFamily: AppFontPolicy.defaults().uiFamily,
            fontFamilyFallback: AppFontPolicy.defaults().fallback,
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal))),
        builder: (context, child) => AppFontScope(
            policy: AppFontPolicy.defaults(),
            child: RenderingPreferencesScope(
                preferences: AppSettings.instance.rendering,
                child: ChangeNotifierProvider.value(
                    value: rig.controller, child: child!))),
        onGenerateRoute: (_) => MaterialPageRoute<void>(
            maintainState: retain,
            builder: (_) => Scaffold(
                body: Center(
                    child: SizedBox(
                        key: _mainLine,
                        width: lyricWidth,
                        height: 600,
                        child: VerticalLyricScrollView(
                            lyric: rig.canonical,
                            positionStream: rig.playback.positionStream,
                            readPosition: () => rig.playback.position,
                            onSeek: (_) =>
                                fail('A layout setting must not seek'),
                            playing: false))))),
      ));
      await _pumpTransport(tester);
      await tester.pumpAndSettle();
      final originalLine = rig.canonical.lines.first as SyncLyricLine;
      var line = originalLine;
      final oldPainter = _mainPainters(tester, line.content).single;
      final naturalSpacing = oldPainter.text!.style!.letterSpacing ?? 0;
      unawaited(navigator.currentState!.push<void>(MaterialPageRoute(
          builder: (_) => Scaffold(
              body: SingleChildScrollView(
                  child: LyricExperienceSettings(persist: rig.persist))))));
      await tester.pumpAndSettle();
      if (retain) {
        final covered =
            tester.element(find.byKey(_mainLine, skipOffstage: false));
        expect(TickerMode.valuesOf(covered).enabled, isFalse);
      } else {
        expect(find.byKey(_mainLine, skipOffstage: false), findsNothing,
            reason:
                'The actual now-playing route does not retain its glyph tree');
      }
      final slider = find.byKey(_settingsSlider);
      await tester.ensureVisible(slider);
      final drag =
          await tester.startGesture(tester.getCenter(slider), pointer: 27);
      await drag.moveBy(const Offset(100, 0));
      await tester.pump();
      expect(rig.writes, 0);
      expect(rig.controller.lyricLetterSpacing, 0);
      await drag.up();
      await _pumpTransport(tester);
      await tester.pumpAndSettle();
      final target = rig.controller.lyricLetterSpacing;
      expect(target, greaterThan(0));
      expect(rig.writes, 1);
      expect(rig.helper.appearance.lyricLetterSpacing, target);
      expect(rig.packets.last['lyricLetterSpacing'], target);
      // Waiting longer than the finite transition while covered must not consume
      // the only visible feedback of this settings change.
      await tester.pump(const Duration(milliseconds: 600));
      if (change == 'line advance') {
        rig.playback.currentPosition = 9.4;
        rig.playback.positions.add(9.4);
        line = rig.canonical.lines.last as SyncLyricLine;
        expect(line, isNot(same(originalLine)));
      } else if (change == 'width') {
        lyricWidth = 360;
      } else if (change == 'font') {
        rig.controller.setFontSize(36);
      } else if (change == 'source') {
        rig.canonical = _Document(_Line(first: '新词かな '));
        rig.lyrics.updateLyric();
        await _pumpTransport(tester);
        line = rig.canonical.lines.single as SyncLyricLine;
      }
      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      final endpoints = _mainPainters(tester, line.content);
      final restores = change.isEmpty || change == 'line advance';
      expect(endpoints, hasLength(restores ? 2 : 1),
          reason:
              'Returning to the real lyric surface must show the old and new '
              'fixed glyph endpoints, not only the already-final hidden value');
      expect(endpoints.map((painter) => painter.text!.style!.letterSpacing),
          [if (restores) naturalSpacing, naturalSpacing + target]);
      await tester.pump(const Duration(milliseconds: 60));
      expect(_mainPainters(tester, line.content), endpoints);
      await tester.pumpAndSettle();
      expect(
          _mainPainters(tester, line.content).single.text!.style!.letterSpacing,
          naturalSpacing + target);
      expect(rig.position.value, const Duration(milliseconds: 1550));
      expect(rig.playback.position, change == 'line advance' ? 9.4 : 1.55,
          reason: 'Restoring spacing must not restore an earlier media pose');
      expect(rig.lookups, change == 'source' ? 2 : 1);
      expect(rig.writes, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'settings spacing release and desktop reset reach all real consumers without touching media',
      (tester) async {
    sizePlaylistFeature(tester, width: 1000, height: 900);
    final rig = (await tester.runAsync(() async => _Rig()))!;
    addTearDown(() => _closeRig(tester, rig));
    await tester.runAsync(rig.initialize);
    await tester.pumpWidget(_host(rig));
    await _pumpTransport(tester);
    await tester.pumpAndSettle();
    final line = rig.canonical.lines.single as SyncLyricLine;
    final oldMain = _mainPainters(tester, line.content).single;
    final naturalSpacing = oldMain.text!.style!.letterSpacing ?? 0;
    final oldDesktop = _desktopPainter(tester).cachedShapingIdentities;
    final initialPacket = Map<String, Object>.of(rig.packets.last);
    final slider = find.byKey(_settingsSlider);
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    final drag =
        await tester.startGesture(tester.getCenter(slider), pointer: 7);
    await drag.moveBy(const Offset(90, 0));
    await tester.pump();
    expect(rig.writes, 0);
    expect(rig.controller.lyricLetterSpacing, 0);
    expect(_mainPainters(tester, line.content).single, same(oldMain));
    expect(_desktopPainter(tester).cachedShapingIdentities, oldDesktop);
    await drag.up();
    await _pumpTransport(tester);
    final spacing =
        AppSettings.instance.desktopLyricAppearance.value.lyricLetterSpacing;
    expect(spacing, greaterThan(0));
    expect(spacing * 2, (spacing * 2).roundToDouble());
    expect(rig.writes, 1);
    expect(rig.controller.lyricLetterSpacing, spacing);
    expect(rig.helper.appearance.lyricLetterSpacing, spacing);
    expect(rig.packets.last['lyricLetterSpacing'], spacing);
    expect(_mainPainters(tester, line.content), hasLength(2));
    expect(_desktopPainter(tester).retainsPreviousLayout, isTrue);
    await tester.pump(const Duration(milliseconds: 90));
    expect(_desktopPainter(tester).layoutProgress, greaterThan(0));
    expect(_desktopPainter(tester).layoutProgress, lessThan(1));
    await tester.pumpAndSettle();
    expect(
        _mainPainters(tester, line.content).single.text!.style!.letterSpacing,
        naturalSpacing + spacing);
    await tester.ensureVisible(find.byKey(_desktopReset));
    await tester.tap(find.byKey(_desktopReset));
    await _pumpTransport(tester);
    expect(AppSettings.instance.desktopLyricAppearance.value.lyricLetterSpacing,
        0);
    expect(rig.controller.lyricLetterSpacing, 0);
    expect(rig.helper.appearance.lyricLetterSpacing, 0);
    expect(rig.packets.last['lyricLetterSpacing'], 0);
    await tester.pumpAndSettle();
    for (final key in [
      'text',
      'words',
      'lineIdentity',
      'positionMilliseconds',
      'lineStartMilliseconds',
      'lineEndMilliseconds',
    ]) {
      expect(rig.packets.last[key], initialPacket[key], reason: key);
    }
    expect(rig.helper.detailedLyricLine.value!.content, line.content);
    expect(
        rig.helper.detailedLyricLine.value!.words.map((word) => word.content),
        line.words.map((word) => word.content));
    expect(rig.position.value, const Duration(milliseconds: 1550));
    expect(rig.helper.playbackClock.positionMilliseconds, 1550);
    AppSettings.instance.desktopLyricAppearance.value = AppSettings
        .instance.desktopLyricAppearance.value
        .copyWith(lyricLetterSpacing: 8);
    await _pumpTransport(tester);
    await tester.pump(const Duration(milliseconds: 32));
    rig.helper.setWindowLifecycle(AppLifecycleState.hidden);
    await tester.pumpWidget(_host(rig, ticker: false));
    await tester.pump();
    final themeSurfaces = tester.elementList(find.byType(AnimatedTheme));
    expect(themeSurfaces, isNotEmpty);
    for (final surface in themeSurfaces) {
      expect(TickerMode.valuesOf(surface).enabled, isFalse,
          reason: 'The hidden fixture also mutes every theme surface');
    }
    expect(_mainPainters(tester, line.content), hasLength(1));
    expect(_desktopPainter(tester).retainsPreviousLayout, isFalse);
    expect(rig.packets.last['lyricLetterSpacing'], 8);
    expect(rig.helper.playbackClock.positionMilliseconds, 1550);
    _expectIdle(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'automatic settings and Japanese display toggle publish one canonical projection to both views',
      (tester) async {
    sizePlaylistFeature(tester, width: 1000, height: 900);
    final rig = (await tester.runAsync(() async => _Rig()))!;
    addTearDown(() => _closeRig(tester, rig));
    await tester.runAsync(rig.initialize);
    await tester.pumpWidget(_host(rig, motion: false));
    await _pumpTransport(tester);
    await tester.pumpAndSettle();
    expect(rig.analyses, 0);
    await tester.ensureVisible(find.byKey(_automatic));
    await tester.tap(find.byKey(_automatic));
    await _pumpTransport(tester);
    final automatic = (await rig.lyrics.currLyricFuture)!;
    expect(automatic.lines.single.japaneseReading, contains('よぞら'));
    _expectMainReading(tester, automatic.lines.single.japaneseReading!);
    expect(rig.helper.detailedLyricLine.value!.japaneseReading,
        automatic.lines.single.japaneseReading);
    final endWordOffset =
        (automatic.lines.single as SyncLyricLine).content.indexOf('終点');
    final expectedSpans = [
      (0, 2, 'よぞら'),
      (endWordOffset, endWordOffset + 2, 'しゅうてん'),
    ];
    expect(
        automatic.lines.single.japaneseReadingSpans
            .map((span) => (span.start, span.end, span.text)),
        expectedSpans);
    expect(
        rig.helper.detailedLyricLine.value!.japaneseReadingSpans, isNotEmpty);
    expect(
        rig.helper.detailedLyricLine.value!.japaneseReadingSpans
            .map((span) => (span.start, span.end, span.text)),
        expectedSpans);
    expect(automatic.lines.single.romanization, isNull);
    expect(rig.lyrics.rawCurrentLyric, same(rig.canonical));
    expect(rig.canonical.lines.single.romanization, isNull);
    expect(rig.canonical.lines.single.japaneseReadingSpans, isEmpty);
    expect(rig.lookups, 1);
    expect(rig.analyses, 1);
    await tester.tap(find.byKey(_automatic));
    await _pumpTransport(tester);
    expect(await rig.lyrics.currLyricFuture, same(rig.canonical));
    rig.controller.setShowJapaneseReading(false);
    expect(rig.controller.showJapaneseReading, isFalse);
    await tester.ensureVisible(find.byKey(_readingOpen));
    await tester.tap(find.byKey(_readingOpen));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(_generate));
    await tester.tap(find.byKey(_generate));
    await tester.pumpAndSettle();
    await _pumpTransport(tester);
    final manual = (await rig.lyrics.currLyricFuture)!;
    _expectMainReading(tester, manual.lines.single.japaneseReading!);
    expect(rig.manualResults, [JapaneseReadingResult.applied]);
    expect(AppSettings.instance.japaneseReadings.value.enabled, isFalse);
    expect(rig.helper.detailedLyricLine.value!.japaneseReading,
        manual.lines.single.japaneseReading);
    expect(
        rig.helper.detailedLyricLine.value!.japaneseReadingSpans
            .map((span) => (span.start, span.end, span.text)),
        expectedSpans);
    expect(manual.lines.single.japaneseReading,
        automatic.lines.single.japaneseReading);
    expect(rig.lookups, 1);
    expect(rig.analyses, 1,
        reason: 'The completed source projection is reused');
    expect(rig.lyrics.rawCurrentLyric, same(rig.canonical));
    expect(rig.canonical.lines.single.romanization, isNull);
    expect(rig.packets.last['text'],
        (manual.lines.single as SyncLyricLine).content);
    expect(rig.packets.last['positionMilliseconds'], 1550);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'retained lyric section cancels its spacing draft even when hidden animation stays enabled',
      (tester) async {
    sizePlaylistFeature(tester, width: 1000, height: 900);
    final rendering =
        ValueNotifier(const RenderingPreferences(pauseWhenHidden: false));
    addTearDown(rendering.dispose);
    var writes = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RenderingPreferencesScope(
                preferences: rendering,
                child: GroupedSettings(initialSection: 'lyrics', sections: [
                  SettingsSection(
                      id: 'lyrics',
                      title: 'Lyrics',
                      icon: Icons.lyrics_outlined,
                      children: [
                        LyricExperienceSettings(persist: () async => writes++),
                      ]),
                  const SettingsSection(
                      id: 'other',
                      title: 'Other',
                      icon: Icons.settings_outlined,
                      children: [Text('Other settings')]),
                ])))));
    await tester.pumpAndSettle();
    final slider = find.byKey(_settingsSlider);
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    final drag =
        await tester.startGesture(tester.getCenter(slider), pointer: 7);
    await drag.moveBy(const Offset(90, 0));
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, greaterThan(0));
    await tester.tap(find.byKey(const ValueKey('settings-category-other')),
        pointer: 101);
    await tester.pumpAndSettle();
    final retained = find.byKey(_settingsSlider, skipOffstage: false);
    expect(retained, findsOneWidget);
    final context = tester.element(retained);
    expect(TickerMode.valuesOf(context).enabled, isTrue,
        reason: 'This preference keeps hidden visual effects enabled');
    expect(SettingsSectionVisibility.isVisibleOf(context), isFalse);
    await drag.up();
    await tester.pumpAndSettle();
    expect(writes, 0, reason: 'Input ownership ends when its category is left');
    expect(AppSettings.instance.desktopLyricAppearance.value.lyricLetterSpacing,
        0);
    await tester.tap(find.byKey(const ValueKey('settings-category-lyrics')),
        pointer: 102);
    await tester.pumpAndSettle();
    await tester.ensureVisible(slider);
    final reentered =
        await tester.startGesture(tester.getCenter(slider), pointer: 9);
    await reentered.moveBy(const Offset(70, 0));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('settings-category-other')),
        pointer: 103);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-category-lyrics')),
        pointer: 104);
    await tester.pumpAndSettle();
    await reentered.moveBy(const Offset(20, 0));
    await reentered.up();
    await tester.pumpAndSettle();
    expect(writes, 0,
        reason: 'Returning cannot revive the cancelled physical gesture');
    final fresh =
        await tester.startGesture(tester.getCenter(slider), pointer: 11);
    await fresh.moveBy(const Offset(50, 0));
    await fresh.up();
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(AppSettings.instance.desktopLyricAppearance.value.lyricLetterSpacing,
        greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'retained lyric section rejects Japanese switch release after leaving category',
      (tester) async {
    sizePlaylistFeature(tester, width: 1000, height: 900);
    final rendering =
        ValueNotifier(const RenderingPreferences(pauseWhenHidden: false));
    addTearDown(rendering.dispose);
    var writes = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RenderingPreferencesScope(
                preferences: rendering,
                child: GroupedSettings(initialSection: 'lyrics', sections: [
                  SettingsSection(
                      id: 'lyrics',
                      title: 'Lyrics',
                      icon: Icons.lyrics_outlined,
                      children: [
                        LyricExperienceSettings(persist: () async => writes++),
                      ]),
                  const SettingsSection(
                      id: 'other',
                      title: 'Other',
                      icon: Icons.settings_outlined,
                      children: [Text('Other settings')]),
                ])))));
    await tester.pumpAndSettle();
    final automatic = find.byKey(_automatic);
    await tester.ensureVisible(automatic);
    await tester.pumpAndSettle();
    final control =
        find.descendant(of: automatic, matching: find.byType(Switch));
    expect(control, findsOneWidget);
    final held =
        await tester.startGesture(tester.getCenter(control), pointer: 41);
    await tester.pump();
    expect(AppSettings.instance.japaneseReadings.value.enabled, isFalse);
    expect(writes, 0);
    await tester.tap(find.byKey(const ValueKey('settings-category-other')),
        pointer: 42);
    await tester.pumpAndSettle();
    final retained = find.byKey(_automatic, skipOffstage: false);
    expect(retained, findsOneWidget);
    expect(SettingsSectionVisibility.isVisibleOf(tester.element(retained)),
        isFalse);
    expect(TickerMode.valuesOf(tester.element(retained)).enabled, isTrue);
    await held.up();
    await tester.pumpAndSettle();
    expect(writes, 0,
        reason: 'The inactive setting cannot commit a retained tap');
    expect(AppSettings.instance.japaneseReadings.value.enabled, isFalse);
    await tester.tap(find.byKey(const ValueKey('settings-category-lyrics')),
        pointer: 43);
    await tester.pumpAndSettle();
    await tester.ensureVisible(automatic);
    final returning =
        await tester.startGesture(tester.getCenter(control), pointer: 45);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('settings-category-other')),
        pointer: 46);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-category-lyrics')),
        pointer: 47);
    await tester.pumpAndSettle();
    await returning.up();
    await tester.pumpAndSettle();
    expect(writes, 0,
        reason: 'Returning cannot revive the same cancelled switch tap');
    expect(AppSettings.instance.japaneseReadings.value.enabled, isFalse);
    await tester.tap(control, pointer: 44);
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(AppSettings.instance.japaneseReadings.value.enabled, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    for (final width in [1000.0, 360.0]) {
      testWidgets(
          'linked reading and appearance controls ${language.code} width=$width at 200 percent',
          (tester) async {
        uiLanguage.value = language;
        sizePlaylistFeature(tester, width: width, height: 900);
        AppSettings.instance.desktopLyricAppearance.value =
            DesktopLyricAppearance.defaults.copyWith(lyricLetterSpacing: 6);
        final rig = (await tester.runAsync(() async => _Rig()))!;
        addTearDown(() => _closeRig(tester, rig));
        await tester.runAsync(rig.initialize);
        rig.controller.toggleJapaneseReading();
        expect(rig.controller.showJapaneseReading, isFalse);
        final boundary = GlobalKey();
        await tester.pumpWidget(
            _host(rig, scale: 2, motion: false, boundary: boundary));
        await _pumpTransport(tester);
        await tester.pumpAndSettle();
        final automatic = find.byKey(_automatic);
        await tester.ensureVisible(automatic);
        await tester.pumpAndSettle();
        expect(automatic.hitTestable(), findsOneWidget);
        final tile = tester.widget<SwitchListTile>(automatic);
        final iconSlot = find.byWidget(tile.secondary!);
        final icon = find.descendant(of: iconSlot, matching: find.byType(Icon));
        expect(icon, findsOneWidget);
        expect(tester.widget<Icon>(icon).icon, Icons.translate_outlined);
        expect(tester.getSize(iconSlot), const Size.square(24));
        expect((tester.getCenter(iconSlot) - tester.getCenter(icon)).distance,
            lessThan(.001));
        final iconRect = tester.getRect(icon);
        expect(iconRect.left, greaterThanOrEqualTo(0));
        expect(iconRect.right, lessThanOrEqualTo(width));
        expect(iconRect.top, greaterThanOrEqualTo(0));
        expect(iconRect.bottom,
            lessThanOrEqualTo(tester.view.physicalSize.height));
        expect((tile.title! as Text).data, ui('自动生成日语假名'));
        _completeLabel(tester, automatic, ui('自动生成日语假名'), width: width);
        await tester.ensureVisible(find.byKey(_readingOpen));
        await tester.tap(find.byKey(_readingOpen));
        await tester.pumpAndSettle();
        final generate = find.byKey(_generate);
        await tester.ensureVisible(generate);
        await tester.pumpAndSettle();
        _completeLabel(tester, generate, ui('显示日语假名'), width: width);
        expect(tester.widget<AppCheckboxMenuButton>(generate).value, isFalse);
        expect(find.descendant(of: generate, matching: find.byType(Checkbox)),
            findsOneWidget);
        expect(generate.hitTestable(), findsOneWidget);
        await capturePlaylistFeature(tester, boundary,
            'lyric-linkage-${language.code}-${width.toInt()}-2-reading');
        await tester.tap(generate);
        await tester.pumpAndSettle();
        await _pumpTransport(tester);
        expect(rig.manualResults, [JapaneseReadingResult.applied]);
        expect(rig.helper.detailedLyricLine.value!.japaneseReading,
            contains('よぞら'));
        final reset = find.byKey(_desktopReset);
        await tester.ensureVisible(reset);
        await tester.pumpAndSettle();
        expect(reset.hitTestable(), findsOneWidget);
        _completeLabel(tester, reset, ui('恢复默认字间距'), width: width);
        expect(tester.getRect(reset).right, lessThanOrEqualTo(width));
        await capturePlaylistFeature(tester, boundary,
            'lyric-linkage-${language.code}-${width.toInt()}-2-appearance');
        await tester.tap(reset);
        await _pumpTransport(tester);
        expect(rig.controller.lyricLetterSpacing, 0);
        expect(rig.helper.appearance.lyricLetterSpacing, 0);
        expect(rig.packets.last['lyricLetterSpacing'], 0);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets(
    'Japanese generated OFF retains outgoing ruby through the shared reveal',
    (tester) async {
      sizePlaylistFeature(tester, width: 1000, height: 900);
      final rig = (await tester.runAsync(
        () async =>
            _Rig(continuousReadingActions: true, projector: _retentionProjector()),
      ))!;
      addTearDown(() => _closeRig(tester, rig));
      await tester.runAsync(rig.initialize);
      rig.controller.setShowJapaneseReading(false);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: boundary, child: _lateReadingHost(rig)),
      );
      await _pumpTransport(tester);
      await tester.pumpAndSettle();

      await _toggleReadingMenu(tester);
      await _drainCachedSource(tester, rig);
      await tester.pumpAndSettle();
      final primary = (rig.canonical.lines.single as SyncLyricLine).content;
      final projected = rig.lyrics.currentPresentation!;
      expect(projected.lines.single.japaneseReadingSpans, isNotEmpty);
      expect(_presentedTimedPainter(tester, rig, primary).rubyLayout, isNotNull);
      expect(_mainRubyVisibility(tester, primary), 1);
      expect(_desktopPainter(tester).rubyVisibility, 1);
      await capturePlaylistFeature(tester, boundary, 'outgoing-open');

      // Real MenuItemButton -> explicit generation bridge -> service canonical
      // OFF -> same-source Vertical/desktop repaint. No DTO or mock toggle.
      await _toggleReadingMenu(tester);
      await _drainCachedSource(tester, rig);
      expect(rig.controller.showJapaneseReading, isFalse);
      expect(AppSettings.instance.japaneseReadings.value.enabled, isFalse);
      expect(
        rig.lyrics.currentPresentation,
        same(rig.canonical),
        reason: 'The service must retain its valid canonical OFF contract',
      );
      expect(rig.canonical.lines.single.japaneseReadingSpans, isEmpty);
      await tester.pump(const Duration(milliseconds: 240));
      final painter = _presentedTimedPainter(tester, rig, primary);
      final scalar = _mainRubyVisibility(tester, primary);
      debugPrint(
        'JAPANESE_BOUNDARY ${jsonEncode({'stage': 'generated-off-half-frame', 'scalar': scalar, 'mainRubyLayout': painter.rubyLayout != null, 'mainLineSpanCount': painter.line.japaneseReadingSpans.length, 'desktopScalar': _desktopPainter(tester).rubyVisibility, 'desktopLineSpanCount': rig.helper.detailedLyricLine.value!.japaneseReadingSpans.length})}',
      );
      await capturePlaylistFeature(tester, boundary, 'outgoing-half-frame');
      expect(scalar, greaterThan(0));
      expect(scalar, lessThan(1));
      expect(_desktopPainter(tester).rubyVisibility, greaterThan(0));
      expect(_desktopPainter(tester).rubyVisibility, lessThan(1));
      expect(
        _desktopPainter(tester).rubyLayout,
        isNotNull,
        reason: 'The actual JSON/IPC consumer also retains closing ruby',
      );
      expect(
        rig.helper.detailedLyricLine.value!.lyricSourceGeneration,
        rig.lyrics.resolutionGeneration,
      );
      expect(
        painter.rubyLayout,
        isNotNull,
        reason:
            'A nonzero closing reveal must still paint outgoing readings; '
            'the service canonical model remains unmodified',
      );
      // Same track, same visible text/index, different real lyric-source owner.
      // Old generated data must disappear immediately, not finish onto this source.
      final sequence = rig.helper.activeSequence;
      final generation = rig.lyrics.resolutionGeneration;
      final replacement = _Document(_Line());
      rig.lyrics.useSpecificLyric(replacement);
      await _drainCachedSource(tester, rig);
      await _pumpTransport(tester);
      expect(rig.lyrics.currentPresentation, same(replacement));
      expect(rig.lyrics.resolutionGeneration, greaterThan(generation));
      expect(
        rig.helper.activeSequence,
        sequence,
        reason:
            'The test genuinely replaces the document without changing track',
      );
      expect(
        rig.helper.detailedLyricLine.value!.lyricSourceGeneration,
        rig.lyrics.resolutionGeneration,
      );
      final activeOwner = (rig.lyrics.resolutionGeneration, 1);
      expect(tester.widget<VerticalLyricScrollView>(_presentedVertical(rig)).sourceIdentity, activeOwner);
      final activePaint = tester.widgetList<CustomPaint>(find.descendant(
          of: _presentedVertical(rig), matching: find.byType(CustomPaint)))
          .map((paint) => paint.painter).whereType<LyricWordHighlightPainter>()
          .where((paint) => paint.text.text!.toPlainText() == primary).toList();
      expect(activePaint, hasLength(1), reason: 'The newly-owned paragraph is unique; retiring old sources are separate subtrees');
      expect(activePaint.single.rubyLayout, isNull);
      expect(_desktopPainter(tester).rubyLayout, isNull);
      expect(_desktopPainter(tester).rubyVisibility, 0);
      await capturePlaylistFeature(
        tester,
        boundary,
        'outgoing-new-source-no-ruby',
      );
      await tester.pumpAndSettle();
      expect(_mainRubyVisibility(tester, primary), 0);
      expect(tester.takeException(), isNull);
      _expectIdle(tester);
    },
  );

  testWidgets(
    'Japanese reveal releases reading pending on a kana-only current line',
    (tester) async {
      sizePlaylistFeature(tester, width: 1000, height: 900);
      final document = _Document(
        _Line(first: 'かな ', last: '한글 かな'),
        next: _Line(start: 8000),
      );
      final rig = (await tester.runAsync(
        () async => _Rig(
          document: document,
          continuousReadingActions: true,
          projector: _retentionProjector(),
        ),
      ))!;
      addTearDown(() => _closeRig(tester, rig));
      await tester.runAsync(rig.initialize);
      rig.controller.setShowJapaneseReading(false);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: boundary, child: _lateReadingHost(rig)),
      );
      await _pumpTransport(tester);
      await tester.pumpAndSettle();
      rig.controller.revealForReading(
        LyricReadingTarget(rig.canonical, 0, rig.canonical.lines[0]),
      );
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(VerticalLyricScrollView));
      final request = rig.controller.readingRequest;

      await _toggleReadingMenu(tester);
      await _drainCachedSource(tester, rig);
      await tester.pumpAndSettle();
      final projected = rig.lyrics.currentPresentation!;
      expect(projected.lines[0].japaneseReadingSpans, isEmpty);
      expect(projected.lines[1].japaneseReadingSpans, isNotEmpty);
      expect(rig.controller.readingRequest, request);
      expect(rig.controller.readingTarget!.belongsTo(projected), isTrue);
      expect(tester.state(find.byType(VerticalLyricScrollView)), same(state));
      final position = _presentedScrollPosition(tester, rig);
      final beforeFind = position.pixels;
      rig.controller.revealForReading(
          LyricReadingTarget(rig.lyrics.currentPresentation!, 1,
              rig.lyrics.currentPresentation!.lines[1]));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(beforeFind),
          reason: 'The completed content owner must not defer the next reading action');
      final found = position.pixels;
      rig.controller.returnToCurrent();
      await tester.pumpAndSettle();
      expect(position.pixels, lessThan(found));
      expect(tester.takeException(), isNull);
      _expectIdle(tester);
    },
  );
  testWidgets(
    'Japanese partial cached document completes a manual same-source reveal',
    (tester) async {
      sizePlaylistFeature(tester, width: 1000, height: 900);
      final canonical = _Document(
        _Line(last: '한글 夜空'),
        next: _Line(start: 8000),
      );
      var analyses = 0;
      final transports = <Map<String, Object?>>[];
      final cache = _PartialReadingCache(canonical);
      final policy = JapaneseReadingAnalyzerPolicy(
        onlineAllowed: () => false,
        clientId: () => 'qa-public-client-identifier',
        offline: (_) async => throw StateError(
          'The explicit online result must not need fallback',
        ),
        cancelOffline: () {},
        hasDictionary: () async => true,
        online: JapaneseOnlineReadingAnalyzer(
          request: (body, clientId, active) async {
            analyses++;
            final transport = {
              'active': active(),
              'clientId': clientId,
              'method': body['method'],
            };
            transports.add(transport);
            final query = (body['params'] as Map)['q'] as String;
            return {
              'jsonrpc': '2.0',
              'id': body['id'],
              'result': {
                'word': [
                  for (final word in _analyzedWords(query))
                    {
                      'surface': word.text,
                      if (word.reading != word.text) 'furigana': word.reading,
                    },
                ],
              },
            };
          },
        ),
      );
      addTearDown(policy.dispose);
      final projector = JapaneseReadingProjector(cache: cache, policy: policy);
      final rig = (await tester.runAsync(
        () async => _Rig(document: canonical, projector: projector),
      ))!;
      addTearDown(() => _closeRig(tester, rig));
      await tester.runAsync(rig.initialize);
      final cached = rig.lyrics.currentPresentation!;
      expect(cached.lines[0].japaneseReadingSpans, isEmpty);
      expect(cached.lines[1].japaneseReadingSpans, isNotEmpty);
      expect(
        canonical.lines.every((line) => line.japaneseReadingSpans.isEmpty),
        isTrue,
      );
      expect(
        analyses,
        0,
        reason: 'This really starts from the cache-only publication',
      );
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: boundary, child: _lateReadingHost(rig)),
      );
      await _pumpTransport(tester);
      await tester.pumpAndSettle();
      rig.controller.revealForReading(
        LyricReadingTarget(cached, 0, cached.lines[0]),
      );
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(VerticalLyricScrollView));
      final readingRequest = rig.controller.readingRequest;
      final source = rig.lyrics.resolutionGeneration;
      final primary = (canonical.lines[0] as SyncLyricLine).content;
      expect(_mainRubyVisibility(tester, primary), 0);
      final manual = rig.lyrics.generateJapaneseReadingsForCurrentTrack(
        expectedGeneration: source,
        mode: JapaneseReadingRequestMode.online,
      );
      await _drainCachedSource(tester, rig);
      final manualResult = await manual;
      expect(transports, hasLength(1));
      expect(transports.single['active'], isTrue);
      expect(transports.single['clientId'], 'qa-public-client-identifier');
      expect(transports.single['method'], 'jlp.furiganaservice.furigana');
      expect(manualResult, JapaneseReadingResult.applied);
      expect(analyses, 1);
      final complete = rig.lyrics.currentPresentation!;
      expect(
        complete.lines.every((line) => line.japaneseReadingSpans.isNotEmpty),
        isTrue,
      );
      expect(rig.lyrics.resolutionGeneration, source);
      expect(
        canonical.lines.every((line) => line.japaneseReadingSpans.isEmpty),
        isTrue,
      );
      expect(tester.state(find.byType(VerticalLyricScrollView)), same(state));
      expect(rig.controller.readingRequest, readingRequest);
      await tester.pump(const Duration(milliseconds: 240));
      expect(_mainRubyVisibility(tester, primary), greaterThan(0));
      expect(_mainRubyVisibility(tester, primary), lessThan(1));
      await capturePlaylistFeature(
        tester,
        boundary,
        'partial-cache-manual-half',
      );
      await tester.pumpAndSettle();
      expect(_mainRubyVisibility(tester, primary), 1);
      expect(rig.controller.readingTarget!.belongsTo(complete), isTrue);
      final position = _presentedScrollPosition(tester, rig);
      final beforeFind = position.pixels;
      rig.controller.revealForReading(
          LyricReadingTarget(rig.lyrics.currentPresentation!, 1,
              rig.lyrics.currentPresentation!.lines[1]));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(beforeFind),
          reason: 'The completed content owner must not defer the next reading action');
      final found = position.pixels;
      rig.controller.returnToCurrent();
      await tester.pumpAndSettle();
      expect(position.pixels, lessThan(found));

      expect(tester.takeException(), isNull);
      _expectIdle(tester);
    },
  );
}


// This transport owns no filesystem. The production projector still computes
// and validates the full source/engine/namespace fingerprint and UTF-16 spans.
class _RetentionCache extends JapaneseLyricReadingCache {
  _RetentionCache() : super(engine: 'retention-linkage');
  @override
  Future<Map<int, JapaneseCachedReading>?> read(String fingerprint,
      {required bool Function() stillCurrent}) async => null;
  @override
  Future<void> write(String fingerprint, Map<int, JapaneseCachedReading> readings,
      {required bool Function() stillCurrent}) async {}
}

JapaneseReadingProjector _retentionProjector() => JapaneseReadingProjector(
    cache: _RetentionCache(),
    analyze: (chunks) async => JapanesePhoneticBatch([
      for (final chunk in chunks) _analyzedWords(chunk),
    ]));

class _PartialReadingCache extends _RetentionCache {
  _PartialReadingCache(this.source);
  final Lyric source;
  @override
  Future<Map<int, JapaneseCachedReading>?> read(String key,
      {required bool Function() stillCurrent}) async {
    if (!stillCurrent() || key != fingerprint(source)) return null;
    final text = (source.lines[1] as SyncLyricLine).content;
    return {1: JapaneseCachedReading(
      text.replaceAll('夜空', 'よぞら').replaceAll('終点', 'しゅうてん'),
      List.unmodifiable([
        const JapaneseLyricReadingSpan(start: 0, end: 2, text: 'よぞら'),
        JapaneseLyricReadingSpan(start: text.length - 2, end: text.length, text: 'しゅうてん'),
      ]),
    )};
  }
}

Finder _presentedVertical(_Rig rig) => find.byWidgetPredicate((widget) =>
    widget is VerticalLyricScrollView &&
    identical(widget.lyric, rig.lyrics.currentPresentation));

LyricWordHighlightPainter _presentedTimedPainter(
    WidgetTester tester, _Rig rig, String text) => tester
    .widgetList<CustomPaint>(find.descendant(of: _presentedVertical(rig),
        matching: find.byType(CustomPaint)))
    .map((paint) => paint.painter)
    .whereType<LyricWordHighlightPainter>()
    .firstWhere((paint) => paint.text.text!.toPlainText() == text);

ScrollPosition _presentedScrollPosition(WidgetTester tester, _Rig rig) => tester
    .state<ScrollableState>(find.descendant(of: _presentedVertical(rig),
        matching: find.byType(Scrollable)).first).position;
