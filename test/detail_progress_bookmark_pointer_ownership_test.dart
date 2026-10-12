import 'dart:async';

import 'package:dan_player/library/playback_bookmarks.dart';
import 'package:dan_player/page/now_playing_page/component/detail_playback_layout.dart';
import 'package:dan_player/page/now_playing_page/component/detail_progress_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _bookmark = PlaybackBookmark(
    id: 'segment', track: 'track', label: 'Saved segment', positionMs: 150000);

class _Fixture {
  final positions = StreamController<double>.broadcast(sync: true);
  late final stream = positions.stream;
  final seeks = <double>[];
  double actual = 20;

  Widget host({required bool scrolling}) {
    final timeline = DetailProgressSlider(
      positions: stream,
      readPosition: () => actual,
      duration: 200,
      trackIdentity: ('track', 1),
      bookmarks: const [_bookmark],
      onSeek: (value) {
        seeks.add(value);
        actual = value;
      },
    );
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 520,
            height: scrolling ? 300 : null,
            child: scrolling
                ? DetailPlaybackLayout(
                    display: const SizedBox.shrink(),
                    controls: Column(mainAxisSize: MainAxisSize.min, children: [
                      timeline,
                      const SizedBox(height: 300),
                    ]))
                : timeline,
          ),
        ),
      ),
    );
  }
}

Future<void> _tapMarker(WidgetTester tester) async {
  final marker = find.byKey(const ValueKey('detail-progress-bookmark-segment'));
  final secondary =
      await tester.startGesture(tester.getCenter(marker), pointer: 12);
  await secondary.up();
  await tester.pump();
}

void main() {
  for (final pending in [true, false]) {
    testWidgets(
        'direct bookmark cannot replace a primary ${pending ? 'pending touch' : 'seek preview'}',
        (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.positions.close);
      await tester.pumpWidget(fixture.host(scrolling: pending));
      await tester.pumpAndSettle();
      final primary = await tester
          .startGesture(tester.getCenter(find.byType(Slider)), pointer: 11);
      var released = false;
      try {
        if (!pending) await primary.moveBy(const Offset(60, 0));
        await tester.pump();
        final preview = tester.widget<Slider>(find.byType(Slider)).value;
        if (pending) expect(preview, 20);
        await _tapMarker(tester);
        expect(fixture.seeks, isEmpty,
            reason: 'The second physical contact cannot change transport.');
        expect(fixture.actual, 20);
        expect(tester.widget<Slider>(find.byType(Slider)).value, preview);
        await primary.moveBy(const Offset(80, 0));
        await tester.pump();
        final target = tester.widget<Slider>(find.byType(Slider)).value;
        expect(target, greaterThan(preview));
        await primary.up();
        released = true;
        await tester.pumpAndSettle();
        expect(fixture.seeks, [target]);
        await _tapMarker(tester);
        await tester.pumpAndSettle();
        expect(fixture.seeks, [target, _bookmark.position],
            reason: 'Bookmark input resumes after the owner releases.');
      } finally {
        if (!released) await primary.cancel();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }

  testWidgets('cancelled seek owner releases direct bookmark input',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.host(scrolling: false));
    final primary = await tester
        .startGesture(tester.getCenter(find.byType(Slider)), pointer: 11);
    await primary.moveBy(const Offset(60, 0));
    await tester.pump();
    await primary.cancel();
    await tester.pumpAndSettle();
    expect(fixture.seeks, isEmpty);
    await _tapMarker(tester);
    await tester.pumpAndSettle();
    expect(fixture.seeks, [_bookmark.position]);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
