import 'dart:async';
import 'dart:io';

import 'package:dan_player/component/lyric_editor_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  double textScale = 1,
}) =>
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
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
                  onlineLyricSearch: search,
                  onlineLyricCandidateLoader: loadCandidate,
                  localLyricLoader: (_) async => '[00:00.00]Local line',
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
      '[00:00.00]Local line',
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
            find.widgetWithText(FilledButton, '保存歌词'),
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
      '[00:01.00]Online line',
    );
    expect(sidecar.readAsStringSync(), '[00:00.00]Local line');
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '保存歌词'),
          )
          .onPressed,
      isNotNull,
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
      '[00:00.00]Local line',
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
      '[00:00.00]Local line',
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
      '[00:00.00]Local line',
    );
    expect(tester.takeException(), isNull);
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
}
