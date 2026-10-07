import 'dart:async';

import 'package:dan_player/library/playback_bookmarks.dart';
import 'package:dan_player/page/now_playing_page/component/detail_playback_layout.dart';
import 'package:dan_player/page/now_playing_page/component/detail_progress_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _bookmark = PlaybackBookmark(
    id: 'segment', track: 'track', label: 'Saved segment', positionMs: 90000);

class _Fixture {
  final positions = StreamController<double>.broadcast(sync: true);
  late final stream = positions.stream;
  final seeks = <double>[];
  double actual = 20;
  int session = 1;

  Widget host({Stream<double>? source, bool scrolling = false}) {
    final timeline = DetailProgressSlider(
      positions: source ?? stream,
      readPosition: () => actual,
      duration: 200,
      trackIdentity: ('track', session),
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

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('detail-progress-time-menu')));
  await tester.pumpAndSettle();
}

Future<VoidCallback> _bookmarkAction(WidgetTester tester) async {
  await _openMenu(tester);
  final submenu = find.byType(SubmenuButton);
  await tester.tap(submenu);
  await tester.pumpAndSettle();
  return tester
      .widget<MenuItemButton>(find.ancestor(
          of: find.text('1:30 · Saved segment'),
          matching: find.byType(MenuItemButton)))
      .onPressed!;
}

void main() {
  testWidgets('queued bookmark cannot replace a scrolling pending touch',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.host(scrolling: true));
    final jump = await _bookmarkAction(tester);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Slider)));
    var released = false;
    try {
      await tester.pump();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 20);
      expect(tester.widget<Slider>(find.byType(Slider)).label, '0:20');
      jump();
      await tester.pump();
      expect(fixture.seeks, isEmpty);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 20);
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();
      final preview = tester.widget<Slider>(find.byType(Slider)).value;
      expect(preview, greaterThan(20));
      await gesture.up();
      released = true;
      await tester.pumpAndSettle();
      expect(fixture.seeks, [preview]);
    } finally {
      if (!released) {
        await gesture.cancel();
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('queued bookmark cannot replace a primary touch preview',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.host());
    final jump = await _bookmarkAction(tester);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Slider)));
    var released = false;
    try {
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      final preview = tester.widget<Slider>(find.byType(Slider)).value;
      jump();
      await tester.pump();
      expect(fixture.seeks, isEmpty);
      expect(tester.widget<Slider>(find.byType(Slider)).value, preview);
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      final moved = tester.widget<Slider>(find.byType(Slider)).value;
      expect(moved, greaterThan(preview));
      await gesture.up();
      released = true;
      await tester.pumpAndSettle();
      expect(fixture.seeks, [moved]);
    } finally {
      if (!released) {
        await gesture.cancel();
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('queued undo belongs to the menu playback session',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.host());
    await tester.tapAt(tester.getCenter(find.byType(Slider)));
    await tester.pumpAndSettle();
    await _openMenu(tester);
    final undo = tester
        .widget<MenuItemButton>(
            find.byKey(const ValueKey('detail-progress-undo-seek')))
        .onPressed!;
    fixture.session++;
    fixture.actual = 0;
    await tester.pumpWidget(fixture.host());
    final before = fixture.seeks.length;
    expect(undo, returnsNormally,
        reason: 'A queued old menu action cannot dereference cleared undo.');
    await tester.pumpAndSettle();
    expect(fixture.seeks, hasLength(before));
    expect(fixture.actual, 0);
  });

  for (final revoke in ['session', 'source', 'unmounted surface']) {
    testWidgets('queued bookmark cannot seek a replacement $revoke',
        (tester) async {
      final fixture = _Fixture();
      final replacement = StreamController<double>.broadcast(sync: true);
      addTearDown(fixture.positions.close);
      addTearDown(replacement.close);
      await tester.pumpWidget(fixture.host());
      final jump = await _bookmarkAction(tester);
      if (revoke == 'session') {
        fixture.session++;
      }
      fixture.actual = 0;
      await tester.pumpWidget(revoke == 'unmounted surface'
          ? const SizedBox.shrink()
          : fixture.host(
              source: revoke == 'source' ? replacement.stream : null));
      jump();
      await tester.pumpAndSettle();
      expect(fixture.seeks, isEmpty,
          reason: 'The saved menu action must retain its original owner.');
      expect(fixture.actual, 0);
    });
  }
}
