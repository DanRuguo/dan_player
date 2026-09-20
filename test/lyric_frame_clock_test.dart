import 'dart:async';
import 'package:dan_player/lyric/online_lyric_parser.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
      'word visuals sample authoritative time each frame and stop on pause or hide',
      (tester) async {
    final source = StreamController<double>.broadcast(sync: true);
    final playing = ValueNotifier(true);
    final hidden = ValueNotifier(false);
    final reduced = ValueNotifier(false);
    final settings = LyricViewController();
    final lyric = parseOnlineLyricPayload(
        {'qrc': '[0,4000]Sunshine(0,4000)\n[4000,4000]Girl(4000,4000)'})!;
    var position = 1.0;
    var reads = 0;
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => ValueListenableBuilder(
            valueListenable: reduced,
            builder: (context, value, _) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: value),
                child: child!)),
        home: Material(
            child: ChangeNotifierProvider.value(
                value: settings,
                child: ValueListenableBuilder(
                    valueListenable: playing,
                    builder: (context, value, _) => VerticalLyricScrollView(
                        lyric: lyric,
                        positionStream: source.stream,
                        readPosition: () {
                          reads++;
                          return position;
                        },
                        onSeek: (_) {},
                        playing: value,
                        hidden: hidden))))));
    await tester.pump(const Duration(seconds: 1));
    position = 1.008;
    await tester.pump(const Duration(milliseconds: 8));
    final row = tester.widget<LyricViewTile>(find.byType(LyricViewTile).first);
    expect(row.position.value, const Duration(milliseconds: 1008),
        reason: 'No 33ms position-stream event was sent');
    position = 1.016;
    await tester.pump(const Duration(milliseconds: 8));
    expect(row.position.value, const Duration(milliseconds: 1016));
    source.add(1.0);
    expect(row.position.value, const Duration(milliseconds: 1016),
        reason: 'A delayed stream event must not rewind the display clock');
    position = .5;
    source.add(.5);
    expect(row.position.value, const Duration(milliseconds: 500),
        reason: 'A real native seek must still take effect immediately');
    playing.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final pausedReads = reads;
    await tester.pump(const Duration(seconds: 1));
    expect(reads, pausedReads);
    expect(tester.binding.transientCallbackCount, 0);
    playing.value = true;
    await tester.pump();
    hidden.value = true;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final hiddenReads = reads;
    await tester.pump(const Duration(seconds: 1));
    expect(reads, hiddenReads);
    expect(tester.binding.transientCallbackCount, 0);
    hidden.value = false;
    position = 5.2;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 8));
    expect(
        tester
            .widgetList<LyricViewTile>(find.byType(LyricViewTile))
            .singleWhere((r) => r.distance == 0)
            .line
            .start,
        const Duration(seconds: 4));
    reduced.value = true;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final reducedReads = reads;
    await tester.pump(const Duration(seconds: 1));
    expect(reads, reducedReads);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
    await source.close();
    playing.dispose();
    hidden.dispose();
    reduced.dispose();
    settings.dispose();
  });
}
