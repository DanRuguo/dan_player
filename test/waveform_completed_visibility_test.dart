import 'dart:async';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/now_playing_page/component/detail_progress_slider.dart';
import 'package:dan_player/page/now_playing_page/component/waveform_progress.dart';
import 'package:dan_player/play_service/waveform_service.dart';
import 'package:dan_player/src/bass/bass_waveform.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _CompletedWaveformService extends WaveformService {
  int reads = 0;

  @override
  Future<WaveformData?> load(Audio audio, WaveformCancellation cancellation) {
    reads++;
    return Future.value(WaveformData(2, List.filled(512, reads / 10)));
  }
}

class _Fixture {
  final service = _CompletedWaveformService();
  final positions = StreamController<double>.broadcast(sync: true);
  late final stream = positions.stream;
  final hidden = ValueNotifier(false);
  final audio = Audio('Fixture', 'Artist', 'Album', 1, 2, null, null,
      r'C:\isolated-fixture\waveform.wav', 0, 0, null);

  Widget host({bool visible = true, bool waveform = true}) => MaterialApp(
        home: Scaffold(
          body: TickerMode(
            enabled: visible,
            child: WaveformProgress(
              audio: audio,
              waveformEnabled: waveform,
              positions: stream,
              readPosition: () => .4,
              duration: 2,
              trackIdentity: audio.path,
              onSeek: (_) {},
              service: service,
              hidden: hidden,
            ),
          ),
        ),
      );

  DetailProgressSlider slider(WidgetTester tester) =>
      tester.widget<DetailProgressSlider>(find.byType(DetailProgressSlider));

  Future<void> dispose() async {
    hidden.dispose();
    await positions.close();
  }
}

void main() {
  for (final concealment in ['native hidden', 'offstage', 'paused lifecycle']) {
    testWidgets('completed waveform survives $concealment without another read',
        (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      addTearDown(() => tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      await tester.pumpWidget(fixture.host());
      await tester.pumpAndSettle();
      final peaks = fixture.slider(tester).waveform;
      expect(peaks, isNotNull);
      expect(fixture.service.reads, 1);

      switch (concealment) {
        case 'native hidden':
          fixture.hidden.value = true;
        case 'offstage':
          await tester.pumpWidget(fixture.host(visible: false));
        case 'paused lifecycle':
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.paused);
      }
      await tester.pump();
      expect(fixture.positions.hasListener, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
      expect(fixture.slider(tester).waveform, same(peaks),
          reason: 'Visibility does not change an already analyzed source');
      fixture.hidden.value = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(fixture.host());
      await tester.pumpAndSettle();
      expect(fixture.service.reads, 1,
          reason: 'Restoring a window must not reopen completed waveform data');
      expect(fixture.slider(tester).waveform, same(peaks));
      expect(fixture.positions.hasListener, isTrue);
    });
  }

  testWidgets('a source revision while hidden invalidates completed peaks',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.host());
    await tester.pumpAndSettle();
    expect(fixture.slider(tester).waveform!.first, .1);
    fixture.hidden.value = true;
    await tester.pump();
    fixture.audio.modified++;
    await tester.pumpWidget(fixture.host());
    expect(fixture.slider(tester).waveform, isNull);
    expect(fixture.service.reads, 1);
    fixture.hidden.value = false;
    await tester.pumpAndSettle();
    expect(fixture.service.reads, 2);
    expect(fixture.slider(tester).waveform!.first, .2);
  });

  testWidgets('turning waveform style off retires its completed data',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.host());
    await tester.pumpAndSettle();
    await tester.pumpWidget(fixture.host(waveform: false));
    expect(fixture.slider(tester).waveform, isNull);
    await tester.pumpWidget(fixture.host());
    await tester.pumpAndSettle();
    expect(fixture.service.reads, 2);
    expect(fixture.slider(tester).waveform!.first, .2);
  });
}
