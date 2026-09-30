import 'dart:async';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Word extends SyncLyricWord {
  _Word() : super(Duration.zero, const Duration(seconds: 6), 'Held note');
}

class _Line extends SyncLyricLine {
  _Line() : super(Duration.zero, const Duration(seconds: 6), [_Word()]);
}

class _Lyrics extends Lyric {
  _Lyrics()
      : super([
          _Line(),
          for (var index = 1; index < 90; index++)
            LrcLine(Duration(seconds: index * 10), 'Line $index',
                isBlank: false, length: const Duration(seconds: 10)),
        ]);
}

Widget _host(LyricViewController settings, Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 420,
            height: 480,
            child: ChangeNotifierProvider.value(value: settings, child: child),
          ),
        ),
      ),
    );

void main() {
  testWidgets('replacing a hidden notifier presents the newly visible lyric',
      (tester) async {
    final settings =
        LyricViewController(preferences: NowPlayingPagePreference.fromMap({}));
    final oldHidden = ValueNotifier(true);
    final newHidden = ValueNotifier(false);
    final positions = StreamController<double>.broadcast(sync: true);
    final future = Future<Lyric?>.value(_Lyrics());
    addTearDown(settings.dispose);
    addTearDown(oldHidden.dispose);
    addTearDown(newHidden.dispose);
    addTearDown(positions.close);

    Widget host(ValueNotifier<bool> hidden) => _host(
        settings,
        VerticalLyricContent(
          lyricFuture: future,
          positionStream: positions.stream,
          readPosition: () => 0,
          onSeek: (_) {},
          hidden: hidden,
        ));

    await tester.pumpWidget(host(oldHidden));
    await tester.pumpAndSettle();
    expect(find.byType(VerticalLyricScrollView), findsNothing);
    await tester.pumpWidget(host(newHidden));
    await tester.pumpAndSettle();
    expect(find.byType(VerticalLyricScrollView), findsOneWidget);
    expect(positions.hasListener, isTrue);

    oldHidden.value = false;
    oldHidden.value = true;
    await tester.pump();
    expect(find.byType(VerticalLyricScrollView), findsOneWidget,
        reason: 'The replaced notifier must no longer control the surface');
    newHidden.value = true;
    await tester.pumpAndSettle();
    expect(positions.hasListener, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('manual reading suspends display sampling for offscreen words',
      (tester) async {
    final settings =
        LyricViewController(preferences: NowPlayingPagePreference.fromMap({}))
          ..setReadingMode(true);
    final positions = StreamController<double>.broadcast(sync: true);
    var reads = 0;
    addTearDown(settings.dispose);
    addTearDown(positions.close);
    await tester.pumpWidget(_host(
        settings,
        VerticalLyricScrollView(
          lyric: _Lyrics(),
          positionStream: positions.stream,
          readPosition: () {
            reads++;
            return 1;
          },
          onSeek: (_) {},
          playing: true,
        )));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    positions.add(1);
    await tester.pump();
    final scroll = find.byKey(const ValueKey('vertical-lyric-scroll'));
    final controller = tester.widget<CustomScrollView>(scroll).controller!;
    final initialReads = reads;
    await tester.pump(const Duration(milliseconds: 16));
    expect(reads, greaterThan(initialReads),
        reason: 'The visible held note still needs smooth presentation');

    controller.jumpTo(1600);
    await tester.pump();
    final offscreenReads = reads;
    await tester.pump(const Duration(milliseconds: 80));
    expect(reads, offscreenReads,
        reason: 'Manual reading must not sample invisible timed glyphs');
    expect(tester.binding.transientCallbackCount, 0);
    expect(positions.hasListener, isTrue,
        reason: 'The regular media stream must continue tracking playback');

    controller.jumpTo(0);
    await tester.pump();
    final returnedReads = reads;
    await tester.pump(const Duration(milliseconds: 16));
    expect(reads, greaterThan(returnedReads));
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
