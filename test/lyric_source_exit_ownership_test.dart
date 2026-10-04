import 'dart:async';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_source_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _open = ValueKey('open-source-fixture');
const _owner = ValueKey('source-owner-page');
const _close = ValueKey('lyric-source-close');
const _candidateKey = ValueKey('lyric-candidate-qq:2');

final _audio = Audio.online(
  provider: 'qq',
  id: 'MID1',
  numericId: 1,
  title: 'Song',
  artist: 'Artist',
  album: 'Album',
  duration: 120,
);
final _candidate = SongSearchResult(
  ResultSource.qq,
  'Song',
  'Artist',
  'Album',
  1,
  qqSongId: 2,
  qqSongMid: 'MID2',
);

Lyric _lyric() => Lrc([
      LrcLine(Duration.zero, 'Fixture lyric', isBlank: false),
    ], LrcSource.web);

class _Pops extends NavigatorObserver {
  int count = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => count++;
}

Future<void> _launch(
    WidgetTester tester, LyricSourceDialog dialog, _Pops observer) async {
  await tester.pumpWidget(MaterialApp(
    navigatorObservers: [observer],
    home: Builder(builder: (context) {
      return TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            key: _owner,
            body: Builder(builder: (context) {
              return TextButton(
                key: _open,
                onPressed: () =>
                    showDialog<void>(context: context, builder: (_) => dialog),
                child: const Text('Open lyric source'),
              );
            }),
          ),
        )),
        child: const Text('Enter fixture'),
      );
    }),
  ));
  await tester.tap(find.text('Enter fixture'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(_open));
  await tester.pumpAndSettle();
}

void main() {
  for (final dismissal in ['button', 'escape', 'barrier']) {
    testWidgets('$dismissal revokes a lyric source before its exit finishes',
        (tester) async {
      final pending = Completer<Lyric?>();
      final observer = _Pops();
      var saved = 0;
      var applied = 0;
      await _launch(
          tester,
          LyricSourceDialog(
            audio: _audio,
            currentTrackPath: () => _audio.path,
            search: (_) async => LyricSearchResponse(
                candidates: [_candidate], failures: const {}),
            loadCandidate: (_) => pending.future,
            persistSource: (_, __) async => saved++,
            applyCandidate: (_, __) {
              applied++;
              return true;
            },
          ),
          observer);
      await tester.tap(find.byKey(_candidateKey));
      await tester.pump();
      switch (dismissal) {
        case 'button':
          await tester.tap(find.byKey(_close));
        case 'escape':
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        case 'barrier':
          await tester.tapAt(const Offset(2, 2));
      }
      // Resolve before the reverse animation disposes the State.
      pending.complete(_lyric());
      await tester.pump();
      expect(saved, 0);
      expect(applied, 0);
      expect(observer.count, 1);
      await tester.pumpAndSettle();
      expect(find.byKey(_owner), findsOneWidget);
      expect(find.byType(LyricSourceDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a save completed during exit cannot apply or pop again',
      (tester) async {
    final saved = Completer<void>();
    final observer = _Pops();
    var started = false;
    var committed = false;
    var applied = false;
    await _launch(
        tester,
        LyricSourceDialog(
          audio: _audio,
          currentTrackPath: () => _audio.path,
          search: (_) async =>
              LyricSearchResponse(candidates: [_candidate], failures: const {}),
          loadCandidate: (_) async => _lyric(),
          persistSource: (_, __) {
            started = true;
            return saved.future.then((_) => committed = true);
          },
          applyCandidate: (_, __) => applied = true,
        ),
        observer);
    await tester.tap(find.byKey(_candidateKey));
    await tester.pump();
    expect(started, isTrue);
    await tester.tap(find.byKey(_close));
    saved.complete();
    await tester.pump();
    expect(committed, isTrue,
        reason: 'Closing revokes publication, not a completed durable write');
    expect(applied, isFalse);
    expect(observer.count, 1);
    await tester.pumpAndSettle();
    expect(find.byKey(_owner), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two close inputs in one frame preserve the owner route',
      (tester) async {
    final observer = _Pops();
    await _launch(
        tester,
        LyricSourceDialog(
          audio: _audio,
          currentTrackPath: () => _audio.path,
          search: (_) async =>
              LyricSearchResponse(candidates: const [], failures: const {}),
        ),
        observer);
    final close = tester.widget<IconButton>(find.byKey(_close)).onPressed!;
    close();
    close();
    await tester.pump();
    expect(observer.count, 1);
    await tester.pumpAndSettle();
    expect(find.byKey(_owner), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
