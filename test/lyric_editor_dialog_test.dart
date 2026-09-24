import 'dart:async';
import 'dart:io';

import 'package:dan_player/component/lyric_editor_dialog.dart';
import 'package:dan_player/component/lyric_playback_preview.dart';
import 'package:dan_player/component/app_scrollbar.dart';
import 'package:dan_player/component/touch_gestures.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/lyric/lyric_edit_codec.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/lyric/lyric_preview.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:desktop_lyric/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'lyric_preview_test.dart' show ProcessFake;

Audio _audio(String path) => Audio(
      'Song',
      'Artist',
      'Album',
      0,
      180,
      null,
      null,
      path,
      0,
      0,
      null,
    );

Widget _host(
  Audio audio, {
  required OnlineLyricEditorSearch search,
  required OnlineLyricEditorCandidateLoader loadCandidate,
  List<CustomLyricSourceChoice> customChoices = const [],
  OnlineLyricEditorCustomCandidateLoader? loadCustomCandidate,
  double textScale = 1,
  TargetPlatform? platform,
  LyricAudioPreview? preview,
  Future<bool> Function()? ensureTools,
  LyricEditFormat initialFormat = LyricEditFormat.lrc,
  LocalLyricEditorLoader? localLyricLoader,
  bool disableAnimations = true,
  MotionPreferences motionPreferences = const MotionPreferences(),
}) =>
    MaterialApp(
      scrollBehavior: const DanPlayerScrollBehavior(),
      theme: ThemeData(useMaterial3: true, platform: platform),
      builder: (context, child) => MotionPreferencesScope(
        preferences: motionPreferences,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: disableAnimations,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              key: const ValueKey('open-lyric-editor'),
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => LyricEditorDialog(
                  audio: audio,
                  initialFormat: initialFormat,
                  onlineLyricSearch: search,
                  onlineLyricCandidateLoader: loadCandidate,
                  customLyricChoices: customChoices,
                  customLyricCandidateLoader:
                      loadCustomCandidate ?? (_, __) async => null,
                  localLyricLoader:
                      localLyricLoader ?? (_) async => '[00:00.00]Local line',
                  preview: preview,
                  ensureTools: ensureTools,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

SongSearchResult _candidate(String id, String title) => SongSearchResult(
      ResultSource.netease,
      title,
      'Online artist',
      'Online album',
      .9,
      neteaseSongId: id,
    );

Lyric _lyric(String content, int seconds) => Lrc(
      [
        LrcLine(
          Duration(seconds: seconds),
          content,
          isBlank: false,
        ),
      ],
      LrcSource.web,
    );

CustomLyricSourceChoice _customChoice(String id, String name) =>
    CustomLyricSourceChoice(
      CustomMusicSourceProfile.tryCreate(
        id: id,
        name: name,
        baseUrl: 'https://example.com',
        capabilities: const {CustomMusicSourceCapability.lyrics},
        endpoints: const {CustomMusicSourceCapability.lyrics: '/lyrics'},
      )!,
    );

(Directory, File, Audio) _fixture() {
  final directory = Directory.systemTemp.createTempSync('lyric-editor-ui-');
  final audioPath =
      '${directory.path}${Platform.pathSeparator}fixture-song.mp3';
  final sidecar = File(
    '${directory.path}${Platform.pathSeparator}fixture-song.lrc',
  );
  sidecar.writeAsStringSync('[00:00.00]Local line');
  return (directory, sidecar, _audio(audioPath));
}

Future<void> _pumpDialogTransition(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

Future<void> _pumpCandidateTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

void main() {
  setUp(LYRIC_SOURCES.clear);
  tearDown(LYRIC_SOURCES.clear);

  test('editor borrows only the current track media clock', () {
    const first = CueTrackReference(
        cuePath: r'J:\library\album.cue',
        sourcePath: r'J:\library\album.flac',
        number: 1,
        startFrame: 0,
        endFrame: 750);
    const second = CueTrackReference(
        cuePath: r'J:\library\album.cue',
        sourcePath: r'J:\library\album.flac',
        number: 2,
        startFrame: 750,
        endFrame: 1500);
    Audio track(CueTrackReference? cue) => Audio('CUE Song', 'Artist', 'Album',
        0, 10, null, null, r'J:\library\album.flac', 0, 0, null,
        cueTrack: cue);
    final edited = track(second);
    expect(matchingLyricEditorPlaybackPosition(edited, track(first), 4, 10),
        isNull);
    expect(matchingLyricEditorPlaybackPosition(edited, track(null), 4, 10),
        isNull);
    expect(matchingLyricEditorPlaybackPosition(edited, track(second), .42, 10),
        .42);
    expect(
        matchingLyricEditorPlaybackPosition(
            edited, track(second), double.nan, 10),
        isNull);
  });

  test('source persistence failure restores the old LRC and association',
      () async {
    final (directory, sidecar, audio) = _fixture();
    addTearDown(() => directory.deleteSync(recursive: true));
    final previous = LyricSource(
      LyricSourceType.netease,
      neteaseSongId: 'previous-source',
    );
    LYRIC_SOURCES[audio.path] = previous;

    await expectLater(
      persistEditedLyric(
        audioPath: audio.path,
        sidecarPath: sidecar.path,
        text: '[00:01.00]Replacement line',
        persistSource: (path, source) async {
          // Simulate a persistence implementation that mutates memory before
          // its index write fails, as the historical editor did.
          LYRIC_SOURCES[path] = source;
          throw StateError('injected lyric source failure');
        },
      ),
      throwsA(isA<StateError>()),
    );

    expect(sidecar.readAsStringSync(), '[00:00.00]Local line');
    expect(identical(LYRIC_SOURCES[audio.path], previous), isTrue);
    expect(File('${sidecar.path}.bak').existsSync(), isFalse);
    expect(File('${sidecar.path}.tmp').existsSync(), isFalse);
  });

  testWidgets('online lyric shows candidates and fills only the chosen result',
      (tester) async {
    final (directory, sidecar, audio) = _fixture();
    addTearDown(() => directory.deleteSync(recursive: true));
    final first = _candidate('first', 'First candidate');
    final second = _candidate('second', 'Second candidate');
    final pending = Completer<Lyric?>();
    await tester.pumpWidget(_host(
      audio,
      search: (_) async => LyricSearchResponse(
        candidates: [first, second],
        failures: const {},
      ),
      loadCandidate: (candidate) => candidate.identity == second.identity
          ? pending.future
          : Future.value(_lyric('Wrong line', 2)),
    ));
    await tester.tap(find.byKey(const ValueKey('open-lyric-editor')));
    await _pumpDialogTransition(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('lyric-editor-field')))
          .controller!
          .text,
      '[00:00.000]Local line',
    );

    await tester.tap(find.byKey(const ValueKey('lyric-editor-fill-online')));
    await _pumpCandidateTransition(tester);
    expect(
        find.byKey(const ValueKey('online-lyric-candidates')), findsOneWidget);
    expect(find.text('First candidate'), findsOneWidget);
    expect(find.text('Second candidate'), findsOneWidget);
    expect(sidecar.readAsStringSync(), '[00:00.00]Local line');

    await tester
        .tap(find.byKey(ValueKey('online-lyric-candidate-${second.identity}')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(ValueKey('online-lyric-candidate-${second.identity}')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '保存编辑副本'),
          )
          .onPressed,
      isNull,
      reason: 'old editor text must not be saved while replacement is pending',
    );
    pending.complete(_lyric('Online line', 1));
    // A focused multiline TextField owns a blinking cursor, so a bounded pump
    // is the correct assertion boundary instead of waiting for all animation.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('lyric-editor-field')))
          .controller!
          .text,
      '[00:01.000]Online line',
    );
    expect(sidecar.readAsStringSync(), '[00:00.00]Local line');
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '保存编辑副本'),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom lyric source requests only after the user chooses it',
      (tester) async {
    final (directory, sidecar, audio) = _fixture();
    addTearDown(() => directory.deleteSync(recursive: true));
    final choice = _customChoice('editor-custom', 'My lyric source');
    var requests = 0;
    await tester.pumpWidget(_host(
      audio,
      search: (_) async =>
          LyricSearchResponse(candidates: [], failures: const {}),
      loadCandidate: (_) async => null,
      customChoices: [choice],
      loadCustomCandidate: (_, selected) async {
        requests++;
        expect(selected.identity, choice.identity);
        return _lyric('Chosen custom line', 3);
      },
    ));
    await tester.tap(find.byKey(const ValueKey('open-lyric-editor')));
    await _pumpDialogTransition(tester);
    await tester.tap(find.byKey(const ValueKey('lyric-editor-fill-online')));
    await _pumpCandidateTransition(tester);

    expect(find.text('My lyric source'), findsOneWidget);
    expect(requests, 0, reason: 'listing a custom source must not query it');
    await tester.tap(
      find.byKey(const ValueKey('online-lyric-custom-editor-custom')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(requests, 1);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('lyric-editor-field')))
          .controller!
          .text,
      '[00:03.000]Chosen custom line',
    );
    expect(sidecar.readAsStringSync(), '[00:00.00]Local line');
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing a pending custom lyric request keeps the editor intact',
      (tester) async {
    final (directory, _, audio) = _fixture();
    addTearDown(() => directory.deleteSync(recursive: true));
    final choice = _customChoice('pending-custom', 'Pending custom source');
    final pending = Completer<Lyric?>();
    await tester.pumpWidget(_host(
      audio,
      search: (_) async =>
          LyricSearchResponse(candidates: [], failures: const {}),
      loadCandidate: (_) async => null,
      customChoices: [choice],
      loadCustomCandidate: (_, __) => pending.future,
    ));
    await tester.tap(find.byKey(const ValueKey('open-lyric-editor')));
    await _pumpDialogTransition(tester);
    await tester.tap(find.byKey(const ValueKey('lyric-editor-fill-online')));
    await _pumpCandidateTransition(tester);
    await tester.tap(
      find.byKey(const ValueKey('online-lyric-custom-pending-custom')),
    );
    await tester.pump();
    await tester.tapAt(const Offset(2, 2));
    await _pumpCandidateTransition(tester);
    expect(find.byType(LyricEditorDialog), findsOneWidget);

    pending.complete(_lyric('Late custom line', 4));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('lyric-editor-field')))
          .controller!
          .text,
      '[00:00.000]Local line',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling a pending candidate search preserves the editor',
      (tester) async {
    final (directory, _, audio) = _fixture();
    addTearDown(() => directory.deleteSync(recursive: true));
    final pending = Completer<LyricSearchResponse>();
    await tester.pumpWidget(_host(
      audio,
      search: (_) => pending.future,
      loadCandidate: (_) async => null,
    ));
    await tester.tap(find.byKey(const ValueKey('open-lyric-editor')));
    await _pumpDialogTransition(tester);
    final fillOnline = find.byKey(const ValueKey('lyric-editor-fill-online'));
    await tester.ensureVisible(fillOnline);
    await tester.tap(fillOnline);
    await tester.pump();
    expect(find.byKey(const ValueKey('online-lyric-candidate-loading')),
        findsOneWidget);
    // Exercise the route/barrier path, not only the dialog's explicit cancel
    // callback: the route remains mounted during its exit animation.
    await tester.tapAt(const Offset(2, 2));
    await _pumpCandidateTransition(tester);
    await tester.tap(find.byKey(const ValueKey('lyric-editor-close')));
    await _pumpDialogTransition(tester);
    expect(find.byType(LyricEditorDialog), findsNothing);

    pending.complete(LyricSearchResponse(candidates: [], failures: const {}));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling a pending candidate load cannot pop the lyric editor',
      (tester) async {
    final (directory, _, audio) = _fixture();
    addTearDown(() => directory.deleteSync(recursive: true));
    final candidate = _candidate('pending', 'Pending candidate');
    final pending = Completer<Lyric?>();
    await tester.pumpWidget(_host(
      audio,
      search: (_) async => LyricSearchResponse(
        candidates: [candidate],
        failures: const {},
      ),
      loadCandidate: (_) => pending.future,
    ));
    await tester.tap(find.byKey(const ValueKey('open-lyric-editor')));
    await _pumpDialogTransition(tester);
    await tester.tap(find.byKey(const ValueKey('lyric-editor-fill-online')));
    await _pumpCandidateTransition(tester);
    await tester.tap(
      find.byKey(ValueKey('online-lyric-candidate-${candidate.identity}')),
    );
    await tester.pump();
    // Barrier dismissal must invalidate the pending candidate Future before
    // the route's exit animation disposes its State.
    await tester.tapAt(const Offset(2, 2));
    await _pumpCandidateTransition(tester);
    expect(find.byType(LyricEditorDialog), findsOneWidget);

    pending.complete(_lyric('Late online line', 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(LyricEditorDialog), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('lyric-editor-field')),
          )
          .controller!
          .text,
      '[00:00.000]Local line',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty candidate result keeps local edits and shows retry help',
      (tester) async {
    final (directory, _, audio) = _fixture();
    addTearDown(() => directory.deleteSync(recursive: true));
    await tester.pumpWidget(_host(
      audio,
      search: (_) async =>
          LyricSearchResponse(candidates: [], failures: const {}),
      loadCandidate: (_) async => null,
    ));
    await tester.tap(find.byKey(const ValueKey('open-lyric-editor')));
    await _pumpDialogTransition(tester);
    final fillOnline = find.byKey(const ValueKey('lyric-editor-fill-online'));
    await tester.ensureVisible(fillOnline);
    await tester.tap(fillOnline);
    await _pumpCandidateTransition(tester);

    expect(
      find.byKey(const ValueKey('online-lyric-candidate-empty')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('lyric-editor-field')))
          .controller!
          .text,
      '[00:00.000]Local line',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('candidate load failure stays selectable and keeps local text',
      (tester) async {
    final (directory, _, audio) = _fixture();
    addTearDown(() => directory.deleteSync(recursive: true));
    final candidate = _candidate('broken', 'Broken candidate');
    await tester.pumpWidget(_host(
      audio,
      search: (_) async => LyricSearchResponse(
        candidates: [candidate],
        failures: const {},
      ),
      loadCandidate: (_) async => throw StateError('injected failure'),
    ));
    await tester.tap(find.byKey(const ValueKey('open-lyric-editor')));
    await _pumpDialogTransition(tester);
    await tester.tap(find.byKey(const ValueKey('lyric-editor-fill-online')));
    await _pumpCandidateTransition(tester);
    await tester.tap(
        find.byKey(ValueKey('online-lyric-candidate-${candidate.identity}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('获取歌词失败，可选择其他候选或重试。'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('lyric-editor-field')))
          .controller!
          .text,
      '[00:00.000]Local line',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Windows lyric candidates share one scroll position with the thumb',
      (tester) async {
    final (directory, _, audio) = _fixture();
    addTearDown(() => directory.deleteSync(recursive: true));
    await tester.pumpWidget(_host(
      audio,
      platform: TargetPlatform.windows,
      search: (_) async => LyricSearchResponse(
        candidates: List.generate(40, (i) => _candidate('$i', 'Candidate $i')),
        failures: const {},
      ),
      loadCandidate: (_) async => _lyric('Online line', 1),
    ));
    await tester.tap(find.byKey(const ValueKey('open-lyric-editor')));
    await _pumpDialogTransition(tester);
    await tester.tap(find.byKey(const ValueKey('lyric-editor-fill-online')));
    await _pumpCandidateTransition(tester);
    final listFinder = find.byKey(const ValueKey('online-lyric-candidates'));
    final list = tester.widget<ListView>(listFinder);
    final scrollbar = tester.widget<AppScrollbar>(find
        .ancestor(of: listFinder, matching: find.byType(AppScrollbar))
        .first);
    expect(list.controller, same(scrollbar.controller));
    expect(list.controller!.positions, hasLength(1));
    await tester.drag(listFinder, const Offset(0, -250));
    // The editor underneath retains its blinking text cursor.
    await tester.pump(const Duration(seconds: 1));
    expect(list.controller!.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('candidate choice remains usable in a short large-text window',
      (tester) async {
    tester.view.physicalSize = const Size(400, 440);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (directory, _, audio) = _fixture();
    addTearDown(() => directory.deleteSync(recursive: true));
    final candidate = _candidate('scaled', 'Large text candidate');
    await tester.pumpWidget(_host(
      audio,
      textScale: 2,
      search: (_) async => LyricSearchResponse(
        candidates: [candidate],
        failures: const {},
      ),
      loadCandidate: (_) async => _lyric('Online line', 1),
    ));
    await tester.tap(find.byKey(const ValueKey('open-lyric-editor')));
    await _pumpDialogTransition(tester);
    final fillOnline = find.byKey(const ValueKey('lyric-editor-fill-online'));
    await tester.ensureVisible(fillOnline);
    await tester.tap(fillOnline);
    await _pumpCandidateTransition(tester);

    expect(
      find.byKey(const ValueKey('online-lyric-candidates')),
      findsOneWidget,
    );
    expect(find.text('Large text candidate'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short text editor shares its scroll controller with the thumb',
      (tester) async {
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (directory, _, audio) = _fixture();
    addTearDown(() => directory.deleteSync(recursive: true));
    await tester.pumpWidget(_host(
      audio,
      platform: TargetPlatform.windows,
      search: (_) async =>
          LyricSearchResponse(candidates: [], failures: const {}),
      loadCandidate: (_) async => null,
    ));
    await tester.tap(find.byKey(const ValueKey('open-lyric-editor')));
    await _pumpDialogTransition(tester);
    final scroll = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('lyric-editor-compact-scroll')));
    final thumb = tester.widget<AppScrollbar>(find
        .ancestor(
            of: find.byKey(const ValueKey('lyric-editor-compact-scroll')),
            matching: find.byType(AppScrollbar))
        .first);
    expect(scroll.controller, same(thumb.controller));
    expect(scroll.controller!.positions, hasLength(1));
    expect(scroll.controller!.position.maxScrollExtent, greaterThan(0));
    scroll.controller!.jumpTo(scroll.controller!.position.maxScrollExtent);
    await tester.pump();
    expect(scroll.controller!.offset, greaterThan(0));
    expect(
        tester.getRect(find.byKey(const ValueKey('lyric-editor-save'))).bottom,
        lessThanOrEqualTo(400));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'editor audition keys, text focus and preview handoff share one decoder',
      (tester) async {
    final (directory, _, audio) = _fixture();
    addTearDown(() => directory.deleteSync(recursive: true));
    final launches = <(double, double, ProcessFake)>[];
    late void Function(double) clock;
    final player = LyricAudioPreview(audio,
        probeDuration: (_) async => audio.duration.toDouble(),
        mainPlayback: () => null,
        launch: (_, start, duration, onPosition) async {
          clock = onPosition;
          final process = ProcessFake();
          launches.add((start, duration, process));
          return process;
        });
    await tester.pumpWidget(_host(audio,
        search: (_) async =>
            LyricSearchResponse(candidates: [], failures: const {}),
        loadCandidate: (_) async => null,
        preview: player,
        ensureTools: () async => true));
    await tester.tap(find.byKey(const ValueKey('open-lyric-editor')));
    await _pumpDialogTransition(tester);
    await tester.tap(find.byKey(const ValueKey('lyric-editor-audition-play')));
    await tester.pump();
    expect(launches.single.$1, 0);
    expect(player.playing, isTrue);
    clock(1.2);
    await tester.pump();
    expect(find.text('当前时刻 00:01.200 / 03:00.000'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(launches.last.$1, closeTo(1.3, .0001));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(launches.last.$1, closeTo(1.2, .0001));
    tester
        .widget<Slider>(
            find.byKey(const ValueKey('lyric-editor-audition-seek')))
        .focusNode!
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(launches.last.$1, closeTo(1.3, .0001));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(launches.last.$1, closeTo(1.2, .0001));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(player.playing, isFalse);
    final countWhilePaused = launches.length;
    final field = find.byKey(const ValueKey('lyric-editor-field'));
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(player.playing, isFalse);
    expect(launches.length, countWhilePaused);

    await tester.ensureVisible(
        find.byKey(const ValueKey('lyric-editor-audition-play')));
    await tester.tap(find.byKey(const ValueKey('lyric-editor-audition-play')));
    await tester.pump();
    expect(player.playing, isTrue);

    final previewTab = find.byKey(const ValueKey('lyric-editor-tab-3'));
    await tester.ensureVisible(previewTab);
    await tester.tap(previewTab);
    await tester.pump();
    expect(player.playing, isFalse);
    expect(
        find.byKey(const ValueKey('lyric-editor-audition-play')), findsNothing);
    final launchesBeforePreview = launches.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(launches.length, launchesBeforePreview);
    final openPreview = find.byKey(const ValueKey('lyric-editor-play-preview'));
    await tester.ensureVisible(openPreview);
    await tester.tap(openPreview);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(LyricPlaybackPreview), findsOneWidget);
    expect(player.playing, isTrue);
    expect(launches.last.$1, 0);
    clock(2);
    await tester.pump();
    final countInPreview = launches.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(launches.length, countInPreview);
    await tester.tap(find.byKey(const ValueKey('lyric-preview-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(LyricPlaybackPreview), findsNothing);
    expect(player.playing, isFalse);
    expect(
        find.byKey(const ValueKey('lyric-editor-audition-play')), findsNothing);
    await tester
        .ensureVisible(find.byKey(const ValueKey('lyric-editor-tab-0')));
    await tester.tap(find.byKey(const ValueKey('lyric-editor-tab-0')));
    await tester.pump();
    expect(find.text('当前时刻 00:02.000 / 03:00.000'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(launches.last.$1, 2);
    expect(player.playing, isTrue);
    await tester.tap(find.byKey(const ValueKey('lyric-editor-close')));
    await tester.pump(const Duration(milliseconds: 350));
    if (find.text('放弃修改').evaluate().isNotEmpty) {
      await tester.tap(find.text('放弃修改'));
      await tester.pump(const Duration(milliseconds: 350));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(launches.last.$3.killed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'audition clock follows the active lyric timestamp format without seeking',
      (tester) async {
    const cue = CueTrackReference(
        cuePath: r'J:\library\album.cue',
        sourcePath: r'J:\library\album.flac',
        number: 2,
        startFrame: 750,
        endFrame: 1500);
    final audio = Audio('CUE Song', 'Artist', 'Album', 0, 10, null, null,
        cue.sourcePath, 0, 0, null,
        cueTrack: cue);
    final starts = <double>[];
    late void Function(double) clock;
    final player = LyricAudioPreview(audio,
        probeDuration: (_) async => audio.duration.toDouble(),
        mainPlayback: () => null,
        launch: (_, start, __, onPosition) async {
          starts.add(start);
          clock = onPosition;
          return ProcessFake();
        });
    await tester.pumpWidget(_host(audio,
        search: (_) async =>
            LyricSearchResponse(candidates: [], failures: const {}),
        loadCandidate: (_) async => null,
        localLyricLoader: (_) async => '',
        initialFormat: LyricEditFormat.qrc,
        preview: player,
        ensureTools: () async => true));
    await tester.tap(find.byKey(const ValueKey('open-lyric-editor')));
    await _pumpDialogTransition(tester);
    await tester.tap(find.byKey(const ValueKey('lyric-editor-audition-play')));
    await tester.pump();
    expect(starts.single, 10);
    clock(10.42);
    await tester.pump();
    expect(find.text('当前时刻 420 毫秒 / 10000 毫秒'), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('lyric-editor-audition-forward')));
    await tester.pump();
    expect(starts.last, closeTo(10.52, .0001));
    expect(find.text('当前时刻 520 毫秒 / 10000 毫秒'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(player.playing, isFalse);
    final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('lyric-editor-audition-seek')));
    slider.onChangeStart!(.52);
    slider.onChanged!(.725);
    await tester.pump();
    expect(find.text('当前时刻 725 毫秒 / 10000 毫秒'), findsOneWidget);
    expect(slider.semanticFormatterCallback!(.725), '725 毫秒');
    slider.onChangeEnd!(.725);
    await tester.pump();
    expect(player.position, closeTo(.725, .0001));
    expect(player.playing, isFalse);
    final startsBeforeFormats = starts.length;

    Future<void> choose(LyricEditFormat next, String expected) async {
      final button = find.byKey(const ValueKey('lyric-editor-format'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      final target = find.byKey(ValueKey('lyric-format-${next.name}'));
      await tester.scrollUntilVisible(target, 160,
          scrollable: find
              .descendant(
                  of: find.byType(AlertDialog).last,
                  matching: find.byType(Scrollable))
              .last);
      tester.widget<ListTile>(target).onTap!();
      await tester.pumpAndSettle();
      expect(find.text(next.label), findsOneWidget);
      expect(find.text('当前时刻 $expected'), findsOneWidget);
      expect(player.position, closeTo(.725, .0001));
      expect(starts.length, startsBeforeFormats);
    }

    await choose(LyricEditFormat.krc, '725 毫秒 / 10000 毫秒');
    await choose(LyricEditFormat.yrc, '725 毫秒 / 10000 毫秒');
    await choose(LyricEditFormat.lrc, '00:00.725 / 00:10.000');
    await choose(LyricEditFormat.enhanced, '00:00.725 / 00:10.000');
    await choose(LyricEditFormat.plain, '00:00.725 / 00:10.000');
    await choose(LyricEditFormat.lossless, '00:00.725 / 00:10.000');
    expect(tester.takeException(), isNull);
  });

  testWidgets('dense audition clock uses the same millisecond format',
      (tester) async {
    tester.view.physicalSize = const Size(640, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final audio = _audio('fixture.mp3');
    late void Function(double) clock;
    final player = LyricAudioPreview(audio,
        probeDuration: (_) async => audio.duration.toDouble(),
        mainPlayback: () => null,
        launch: (_, __, ___, onPosition) async {
          clock = onPosition;
          return ProcessFake();
        });
    await tester.pumpWidget(_host(audio,
        search: (_) async =>
            LyricSearchResponse(candidates: [], failures: const {}),
        loadCandidate: (_) async => null,
        localLyricLoader: (_) async => '',
        initialFormat: LyricEditFormat.qrc,
        preview: player,
        ensureTools: () async => true,
        textScale: 2));
    await tester.tap(find.byKey(const ValueKey('open-lyric-editor')));
    await _pumpDialogTransition(tester);
    await tester.tap(find.byKey(const ValueKey('lyric-editor-audition-play')));
    await tester.pump();
    clock(1.2);
    await tester.pump();
    final clockText = find.byKey(const ValueKey('lyric-editor-audition-time'));
    expect(tester.widget<Text>(clockText).data, '1200 毫秒');
    final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: clockText, matching: find.byType(Tooltip)));
    expect(tooltip.message, '当前时刻 1200 毫秒 / 180000 毫秒');
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing preview tools show the existing installation card',
      (tester) async {
    tester.view.physicalSize = const Size(480, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (directory, _, audio) = _fixture();
    addTearDown(() => directory.deleteSync(recursive: true));
    final player = LyricAudioPreview(audio,
        probeDuration: (_) async => audio.duration.toDouble(),
        mainPlayback: () => null,
        launch: (_, __, ___, ____) async => ProcessFake());
    await tester.pumpWidget(_host(audio,
        search: (_) async =>
            LyricSearchResponse(candidates: [], failures: const {}),
        loadCandidate: (_) async => null,
        preview: player,
        ensureTools: () async => false));
    await tester.tap(find.byKey(const ValueKey('open-lyric-editor')));
    await _pumpDialogTransition(tester);
    await tester.tap(find.byKey(const ValueKey('lyric-editor-audition-play')));
    await tester.pump();
    expect(find.byKey(const ValueKey('lyric-editor-audition-install')),
        findsOneWidget);
    expect(player.playing, isFalse);
    expect(
        tester.getRect(find.byKey(const ValueKey('lyric-editor-save'))).bottom,
        lessThanOrEqualTo(420));
    expect(tester.takeException(), isNull);
    await tester
        .tap(find.byKey(const ValueKey('lyric-editor-audition-install')));
    await tester.pumpAndSettle();
    expect(find.text('我已安装好'), findsOneWidget);
    expect(find.text('从 GitHub 下载'), findsOneWidget);
    expect(find.byType(AppScrollbar), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing while tool check is pending cannot start late playback',
      (tester) async {
    final (directory, _, audio) = _fixture();
    addTearDown(() => directory.deleteSync(recursive: true));
    final ready = Completer<bool>();
    var launches = 0;
    final player = LyricAudioPreview(audio,
        probeDuration: (_) async => audio.duration.toDouble(),
        mainPlayback: () => null,
        launch: (_, __, ___, ____) async {
          launches++;
          return ProcessFake();
        });
    await tester.pumpWidget(_host(audio,
        search: (_) async =>
            LyricSearchResponse(candidates: [], failures: const {}),
        loadCandidate: (_) async => null,
        preview: player,
        ensureTools: () => ready.future));
    await tester.tap(find.byKey(const ValueKey('open-lyric-editor')));
    await _pumpDialogTransition(tester);
    await tester.tap(find.byKey(const ValueKey('lyric-editor-audition-play')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('lyric-editor-close')));
    await tester.pumpAndSettle();
    ready.complete(true);
    await tester.pump();
    expect(launches, 0);
    expect(player.playing, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview tab collapse follows layout and system motion choices',
      (tester) async {
    final (directory, _, audio) = _fixture();
    addTearDown(() => directory.deleteSync(recursive: true));
    for (final (systemReduced, preference, expected) in [
      (false, const MotionPreferences(), AppMotion.standard),
      (
        false,
        const MotionPreferences(disabled: {MotionKind.layout}),
        Duration.zero
      ),
      (true, const MotionPreferences(), Duration.zero),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_host(audio,
          search: (_) async =>
              LyricSearchResponse(candidates: [], failures: const {}),
          loadCandidate: (_) async => null,
          disableAnimations: systemReduced,
          motionPreferences: preference));
      await tester.tap(find.byKey(const ValueKey('open-lyric-editor')));
      await _pumpDialogTransition(tester);
      final switcher =
          find.byKey(const ValueKey('lyric-editor-audition-collapse'));
      expect(tester.widget<AnimatedSwitcher>(switcher).duration, expected);
      await tester
          .ensureVisible(find.byKey(const ValueKey('lyric-editor-tab-3')));
      await tester.tap(find.byKey(const ValueKey('lyric-editor-tab-3')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lyric-editor-audition-play')),
          findsNothing);
      await tester
          .ensureVisible(find.byKey(const ValueKey('lyric-editor-tab-0')));
      await tester.tap(find.byKey(const ValueKey('lyric-editor-tab-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lyric-editor-audition-play')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('CUE audition and timestamp insertion use segment media time',
      (tester) async {
    const cue = CueTrackReference(
        cuePath: r'J:\library\album.cue',
        sourcePath: r'J:\library\album.flac',
        number: 2,
        startFrame: 750,
        endFrame: 1500);
    final audio = Audio('CUE Song', 'Artist', 'Album', 0, 10, null, null,
        cue.sourcePath, 0, 0, null,
        cueTrack: cue);
    final starts = <double>[];
    late void Function(double) clock;
    final player = LyricAudioPreview(audio,
        probeDuration: (_) async => audio.duration.toDouble(),
        mainPlayback: () => null,
        launch: (file, start, duration, onPosition) async {
          expect(file, cue.sourcePath);
          starts.add(start);
          clock = onPosition;
          return ProcessFake();
        });
    await tester.pumpWidget(_host(audio,
        search: (_) async =>
            LyricSearchResponse(candidates: [], failures: const {}),
        loadCandidate: (_) async => null,
        preview: player,
        ensureTools: () async => true));
    await tester.tap(find.byKey(const ValueKey('open-lyric-editor')));
    await _pumpDialogTransition(tester);
    await tester.tap(find.byKey(const ValueKey('lyric-editor-audition-play')));
    await tester.pump();
    expect(starts.single, 10);
    clock(10.42);
    await tester.pump();
    expect(find.text('当前时刻 00:00.420 / 00:10.000'), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('lyric-editor-audition-forward')));
    await tester.pump();
    expect(starts.last, closeTo(10.52, .0001));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(player.playing, isFalse);
    final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('lyric-editor-audition-seek')));
    slider.onChangeStart!(.52);
    slider.onChanged!(.725);
    await tester.pump();
    expect(find.text('当前时刻 00:00.725 / 00:10.000'), findsOneWidget);
    slider.onChangeEnd!(.725);
    await tester.pump();
    expect(player.playing, isFalse);
    expect(player.position, closeTo(.725, .0001));
    await tester.tap(find.byKey(const ValueKey('lyric-editor-audition-play')));
    await tester.pump();
    expect(starts.last, closeTo(10.725, .0001));
    final insert = find.byKey(const ValueKey('lyric-editor-insert-time'));
    await tester.ensureVisible(insert);
    await tester.tap(insert);
    await tester.pump();
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('lyric-editor-field')))
            .controller!
            .text,
        '[00:00.725]Local line');
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor slider ignores second pointer cancel and restores first',
      (tester) async {
    final (directory, _, audio) = _fixture();
    addTearDown(() => directory.deleteSync(recursive: true));
    late void Function(double) clock;
    final starts = <double>[];
    final player = LyricAudioPreview(audio,
        probeDuration: (_) async => audio.duration.toDouble(),
        mainPlayback: () => null,
        launch: (_, start, __, onPosition) async {
          starts.add(start);
          clock = onPosition;
          return ProcessFake();
        });
    await tester.pumpWidget(_host(audio,
        search: (_) async =>
            LyricSearchResponse(candidates: [], failures: const {}),
        loadCandidate: (_) async => null,
        preview: player,
        ensureTools: () async => true));
    await tester.tap(find.byKey(const ValueKey('open-lyric-editor')));
    await _pumpDialogTransition(tester);
    await tester.tap(find.byKey(const ValueKey('lyric-editor-audition-play')));
    await tester.pump();
    clock(1.2);
    await tester.pump();
    final seek = find.byKey(const ValueKey('lyric-editor-audition-seek'));
    final first = await tester.startGesture(tester.getCenter(seek));
    await first.moveBy(const Offset(65, 0));
    await tester.pump();
    expect(player.playing, isFalse);
    final second =
        await tester.startGesture(tester.getCenter(seek), pointer: 2);
    await second.cancel();
    await tester.pump();
    expect(player.playing, isFalse);
    await first.cancel();
    await tester.pump();
    expect(player.playing, isTrue);
    expect(starts.last, closeTo(1.2, .0001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('paused final preview drag stays paused and shows milliseconds',
      (tester) async {
    final audio = _audio('missing-preview.mp3');
    late void Function(double) clock;
    var launches = 0;
    final player = LyricAudioPreview(audio,
        probeDuration: (_) async => audio.duration.toDouble(),
        mainPlayback: () => null,
        launch: (_, __, ___, onPosition) async {
          launches++;
          clock = onPosition;
          return ProcessFake();
        });
    addTearDown(player.dispose);
    await tester.pumpWidget(MaterialApp(
        home: LyricPlaybackPreview(
            audio: audio,
            lyric: _lyric('Line', 1),
            preview: player,
            ensureTools: () async => true)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(player.playing, isTrue);
    clock(1.2);
    await tester.tap(find.byKey(const ValueKey('lyric-preview-play')));
    await tester.pump();
    expect(player.playing, isFalse);
    final seek =
        tester.widget<Slider>(find.byKey(const ValueKey('lyric-preview-seek')));
    seek.onChangeStart!(1.2);
    seek.onChanged!(2.345);
    await tester.pump();
    expect(find.text('00:02.345 / 03:00.000'), findsOneWidget);
    seek.onChangeEnd!(2.345);
    await tester.pump();
    expect(player.playing, isFalse);
    expect(player.position, closeTo(2.345, .0001));
    expect(launches, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('borrowed final preview reports zero duration without launching',
      (tester) async {
    final audio = Audio('Song', 'Artist', 'Album', 0, 0, null, null,
        'missing-preview.mp3', 0, 0, null);
    var launches = 0;
    final player = LyricAudioPreview(audio,
        probeDuration: (_) async => null,
        mainPlayback: () => null,
        launch: (_, __, ___, ____) async {
          launches++;
          return ProcessFake();
        });
    addTearDown(player.dispose);
    await tester.pumpWidget(MaterialApp(
        home: LyricPlaybackPreview(
            audio: audio,
            lyric: _lyric('Line', 1),
            preview: player,
            ensureTools: () async => true)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('无法读取歌曲时长，无法试听。'), findsOneWidget);
    expect(find.text('安装试听组件'), findsNothing);
    expect(player.playing, isFalse);
    expect(launches, 0);
    expect(tester.takeException(), isNull);
  });
}
