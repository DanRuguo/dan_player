import 'dart:async';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/lyric/lyric_source_exception.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_source_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Audio _audio(String path) => Audio(
      'Song A',
      'Artist A',
      'Album A',
      0,
      180,
      null,
      null,
      path,
      0,
      0,
      null,
    );

SongSearchResult _candidate(
  int id, {
  String title = 'Song A',
  double score = 1,
}) =>
    SongSearchResult(
      ResultSource.qq,
      title,
      'Artist A',
      'Album A',
      score,
      qqSongId: id,
      qqSongMid: 'MID$id',
    );

class _TestLyric extends Lyric {
  _TestLyric(super.lines);
}

Lyric _lyric() => _TestLyric([
      LrcLine(Duration.zero, 'line', isBlank: false),
    ]);

Widget _host(Widget child, {double width = 800}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 700)),
        child: Scaffold(body: child),
      ),
    );

Widget _launcher(LyricSourceDialog dialog) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('open-lyric-source-dialog'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => dialog,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

void main() {
  setUp(LYRIC_SOURCES.clear);
  tearDown(LYRIC_SOURCES.clear);

  testWidgets(
      'short version warns about an unmarked candidate without rejecting manual selection',
      (tester) async {
    final audio = _audio(r'C:\Music\OP.wav')..title = '結想は花となる short ver.';
    await tester.pumpWidget(_host(LyricSourceDialog(
      audio: audio,
      currentTrackPath: () => audio.path,
      search: (_) async => LyricSearchResponse(candidates: [
        _candidate(1, title: '結想は花となる'),
        _candidate(2, title: '結想は花となる short ver.'),
      ], failures: const {}),
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('版本可能不同'), findsOneWidget);
    expect(
        tester
            .widget<ListTile>(
                find.byKey(const ValueKey('lyric-candidate-qq:1')))
            .onTap,
        isNotNull);
    expect(
        lyricCandidateMayUseDifferentVersion(
            audio, _candidate(2, title: '結想は花となる short ver.')),
        isFalse);
  });

  testWidgets('search is owned by State and is not recreated by build',
      (tester) async {
    final audio = _audio(r'C:\Music\Song A.mp3');
    var calls = 0;
    Future<LyricSearchResponse> search(Audio _) async {
      calls++;
      return LyricSearchResponse(
        candidates: [_candidate(1)],
        failures: const {},
      );
    }

    await tester.pumpWidget(_host(LyricSourceDialog(
      audio: audio,
      search: search,
      currentTrackPath: () => audio.path,
    )));
    await tester.pumpAndSettle();
    expect(calls, 1);

    await tester.pumpWidget(_host(
      LyricSourceDialog(
        audio: audio,
        search: search,
        currentTrackPath: () => audio.path,
      ),
      width: 760,
    ));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('candidate rows show source, current item, and partial failure',
      (tester) async {
    final audio = _audio(r'C:\Music\Song A.mp3');
    LYRIC_SOURCES[audio.path] = LyricSource(
      LyricSourceType.qq,
      qqSongId: 1,
      qqSongMid: 'MID1',
    );

    await tester.pumpWidget(_host(LyricSourceDialog(
      audio: audio,
      currentTrackPath: () => audio.path,
      search: (_) async => LyricSearchResponse(
        candidates: [_candidate(1)],
        failures: const {
          ResultSource.netease: '联网失败，请检查网络',
        },
      ),
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('来源：QQ音乐'), findsOneWidget);
    expect(find.byTooltip('当前使用'), findsOneWidget);
    expect(find.byKey(const ValueKey('lyric-source-partial-failure')),
        findsOneWidget);
    expect(find.textContaining('网易云音乐'), findsOneWidget);
    expect(find.byKey(const ValueKey('lyric-source-retry')), findsOneWidget);
  });

  testWidgets('a stale candidate search cannot replace the new song results',
      (tester) async {
    final audioA = _audio(r'C:\Music\Song A.mp3');
    final audioB = _audio(r'C:\Music\Song B.mp3');
    final oldSearch = Completer<LyricSearchResponse>();
    Future<LyricSearchResponse> searchA(Audio _) => oldSearch.future;
    Future<LyricSearchResponse> searchB(Audio _) async => LyricSearchResponse(
          candidates: [_candidate(2, title: 'Song B')],
          failures: const {},
        );

    await tester.pumpWidget(_host(LyricSourceDialog(
      audio: audioA,
      search: searchA,
      currentTrackPath: () => audioA.path,
    )));
    await tester.pump();
    await tester.pumpWidget(_host(LyricSourceDialog(
      audio: audioB,
      search: searchB,
      currentTrackPath: () => audioB.path,
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lyric-candidate-qq:2')), findsOneWidget);

    oldSearch.complete(LyricSearchResponse(
      candidates: [_candidate(1, title: 'Song A')],
      failures: const {},
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lyric-candidate-qq:2')), findsOneWidget);
    expect(find.byKey(const ValueKey('lyric-candidate-qq:1')), findsNothing);
  });

  testWidgets('a lyric response for song A cannot apply after switching to B',
      (tester) async {
    final audio = _audio(r'C:\Music\Song A.mp3');
    final playback = ChangeNotifier();
    final pending = Completer<Lyric?>();
    var currentPath = audio.path;
    var persistCalls = 0;
    var applyCalls = 0;

    await tester.pumpWidget(_host(LyricSourceDialog(
      audio: audio,
      playbackListenable: playback,
      currentTrackPath: () => currentPath,
      search: (_) async => LyricSearchResponse(
        candidates: [_candidate(1)],
        failures: const {},
      ),
      loadCandidate: (_) => pending.future,
      persistSource: (_, __) async {
        persistCalls++;
      },
      applyCandidate: (_, __) {
        applyCalls++;
        return true;
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lyric-candidate-qq:1')));
    await tester.pump();

    currentPath = r'C:\Music\Song B.mp3';
    playback.notifyListeners();
    await tester.pump();
    pending.complete(_lyric());
    await tester.pumpAndSettle();

    expect(persistCalls, 0);
    expect(applyCalls, 0);
    expect(find.byKey(const ValueKey('lyric-source-track-changed')),
        findsOneWidget);
  });

  testWidgets('a candidate without lyric remains visible with a useful error',
      (tester) async {
    final audio = _audio(r'C:\Music\Song A.mp3');
    await tester.pumpWidget(_host(LyricSourceDialog(
      audio: audio,
      currentTrackPath: () => audio.path,
      search: (_) async => LyricSearchResponse(
        candidates: [_candidate(1)],
        failures: const {},
      ),
      loadCandidate: (_) async => null,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lyric-candidate-qq:1')));
    await tester.pumpAndSettle();

    expect(find.textContaining('未返回可用歌词'), findsOneWidget);
    expect(find.byKey(const ValueKey('lyric-candidate-qq:1')), findsOneWidget);
  });

  testWidgets('a later candidate selection supersedes an older pending one',
      (tester) async {
    final audio = _audio(r'C:\Music\Song A.mp3');
    final first = Completer<Lyric?>();
    final second = Completer<Lyric?>();
    final persistedIds = <int?>[];
    final applied = <Lyric>[];
    final secondLyric = _lyric();
    final dialog = LyricSourceDialog(
      audio: audio,
      currentTrackPath: () => audio.path,
      search: (_) async => LyricSearchResponse(
        candidates: [
          _candidate(1),
          _candidate(2, title: 'Song A alternate', score: 0.9),
        ],
        failures: const {},
      ),
      loadCandidate: (candidate) =>
          candidate.qqSongId == 1 ? first.future : second.future,
      persistSource: (_, source) async {
        persistedIds.add(source.qqSongId);
      },
      applyCandidate: (_, lyric) {
        applied.add(lyric);
        return true;
      },
    );

    await tester.pumpWidget(_launcher(dialog));
    await tester.tap(find.byKey(const ValueKey('open-lyric-source-dialog')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lyric-candidate-qq:1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('lyric-candidate-qq:2')));
    await tester.pump();

    second.complete(secondLyric);
    await tester.pumpAndSettle();
    first.complete(_lyric());
    await tester.pumpAndSettle();

    expect(persistedIds, [2]);
    expect(applied, hasLength(1));
    expect(applied.single, same(secondLyric));
    expect(find.byType(LyricSourceDialog), findsNothing);
  });

  testWidgets('save failure keeps the dialog open and does not apply lyric',
      (tester) async {
    final audio = _audio(r'C:\Music\Song A.mp3');
    var applied = false;
    await tester.pumpWidget(_host(LyricSourceDialog(
      audio: audio,
      currentTrackPath: () => audio.path,
      search: (_) async => LyricSearchResponse(
        candidates: [_candidate(1)],
        failures: const {},
      ),
      loadCandidate: (_) async => _lyric(),
      persistSource: (_, __) async =>
          throw const FileSystemException('read only'),
      applyCandidate: (_, __) {
        applied = true;
        return true;
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lyric-candidate-qq:1')));
    await tester.pumpAndSettle();

    expect(applied, isFalse);
    expect(find.textContaining('旧设置已保留'), findsOneWidget);
    expect(find.byKey(const ValueKey('lyric-candidate-qq:1')), findsOneWidget);
  });

  for (final failure in <Object, String>{
    const LyricUnavailableException(): '此来源暂未提供这条录音',
    TimeoutException('fixture'): '获取歌词超时',
    const SocketException('fixture'): '连接歌词来源失败',
    const FormatException('fixture'): '内容无法解析',
  }.entries) {
    testWidgets(
        'lyric fetch ${failure.key.runtimeType} cannot save a new source',
        (tester) async {
      final audio = _audio(r'C:\Music\Song A.mp3');
      final original =
          LyricSource(LyricSourceType.netease, neteaseSongId: '123');
      LYRIC_SOURCES[audio.path] = original;
      var saved = 0;
      await tester.pumpWidget(_host(LyricSourceDialog(
        audio: audio,
        currentTrackPath: () => audio.path,
        search: (_) async => LyricSearchResponse(
            candidates: [_candidate(1)], failures: const {}),
        loadCandidate: (_) async => throw failure.key,
        persistSource: (_, __) async {
          saved++;
        },
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lyric-candidate-qq:1')));
      await tester.pumpAndSettle();
      expect(saved, 0);
      expect(LYRIC_SOURCES[audio.path], same(original));
      expect(find.textContaining(failure.value), findsOneWidget);
      expect(find.textContaining('保存来源失败'), findsNothing);
    });
  }
}
