import 'dart:async';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/page/now_playing_page/component/detail_progress_slider.dart';
import 'package:dan_player/page/now_playing_page/component/waveform_progress.dart';
import 'package:dan_player/play_service/waveform_service.dart';
import 'package:dan_player/src/bass/bass_waveform.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Audio song(String path) =>
    Audio('Fixture', 'Fixture', 'Fixture', 1, 2, 128, 44100, path, 0, 0, '');

// Cache/native I/O is exercised in waveform_service_test and native tests.
// UI races use a controllable public service boundary instead of retaining a
// global ProtectedJsonStore commit future across separate fake-time test zones.
class _UiWaveformService extends WaveformService {
  _UiWaveformService({super.cacheFile, required WaveformDecoder decoder})
      : _decode = decoder,
        super(decoder: decoder);
  final WaveformDecoder _decode;
  @override
  Future<WaveformData?> load(Audio audio, WaveformCancellation cancellation) =>
      _decode(
          WaveformDecodeRequest('fixture', audio.localFilePath,
              start: audio.cueTrack?.startSeconds ?? 0,
              end: audio.cueTrack?.endSeconds),
          cancellation);
}

Future<void> flushIo(WidgetTester tester) async {
  // File futures resume in the fake zone; alternate real I/O with pumps.
  for (var i = 0; i < 20; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

void main() {
  late Directory folder;
  late Audio a;
  late Audio b;
  late StreamController<double> positions;
  late ValueNotifier<bool> hidden;
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('waveform-ui-');
    a = song((await File('${folder.path}/a.wav').writeAsBytes([1])).path);
    b = song((await File('${folder.path}/b.wav').writeAsBytes([2])).path);
    positions = StreamController.broadcast(sync: true);
    hidden = ValueNotifier(false);
  });
  tearDown(() async {
    await positions.close();
    hidden.dispose();
    await folder.delete(recursive: true);
  });
  Widget host(WaveformService service,
          {Audio? audio, bool style = true, bool visible = true}) =>
      MaterialApp(
          home: Scaffold(
              body: TickerMode(
        enabled: visible,
        child: WaveformProgress(
            audio: audio ?? a,
            waveformEnabled: style,
            positions: positions.stream,
            readPosition: () => .4,
            duration: 2,
            trackIdentity: (audio ?? a).path,
            onSeek: (_) {},
            service: service,
            hidden: hidden),
      )));
  DetailProgressSlider slider(WidgetTester tester) =>
      tester.widget<DetailProgressSlider>(find.byType(DetailProgressSlider));

  testWidgets('default style never analyzes audio or creates cache',
      (tester) async {
    var calls = 0;
    final cache = File('${folder.path}/cache.json');
    final service = _UiWaveformService(
        cacheFile: cache,
        decoder: (_, __) async {
          calls++;
          return WaveformData(2, List.filled(512, .4));
        });
    await tester.pumpWidget(host(service, style: false));
    await flushIo(tester);
    expect(calls, 0);
    expect(slider(tester).waveform, isNull);
    expect(await tester.runAsync(cache.exists), isFalse);
  });
  testWidgets('loading has an honest hint and progress remains enabled',
      (tester) async {
    final pending = Completer<WaveformData?>();
    final service = _UiWaveformService(
        cacheFile: File('${folder.path}/cache.json'),
        decoder: (_, __) => pending.future);
    await tester.pumpWidget(host(service));
    await flushIo(tester);
    expect(slider(tester).waveform, isNull);
    expect(slider(tester).waveformTooltip, contains('正在分析'));
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
    pending.complete(WaveformData(2, List.filled(512, .6)));
    await flushIo(tester);
    await flushIo(tester);
    expect(slider(tester).waveform, isNotNull);
    expect(slider(tester).waveformTooltip, contains('振幅'));
  });
  testWidgets('switching style cancels pending work and rejects stale result',
      (tester) async {
    final pending = Completer<WaveformData?>();
    WaveformCancellation? token;
    final service = _UiWaveformService(
        cacheFile: File('${folder.path}/cache.json'),
        decoder: (_, value) {
          token = value;
          return pending.future;
        });
    await tester.pumpWidget(host(service));
    await flushIo(tester);
    expect(token, isNotNull);
    await tester.pumpWidget(host(service, style: false));
    expect(token!.cancelled, isTrue);
    pending.complete(WaveformData(2, List.filled(512, .6)));
    await flushIo(tester);
    expect(slider(tester).waveform, isNull);
    expect(slider(tester).waveformTooltip, isNull);
  });
  testWidgets('new track rejects old peaks and displays only its own amplitude',
      (tester) async {
    final pending = Completer<WaveformData?>();
    var calls = 0;
    WaveformCancellation? first;
    final service = _UiWaveformService(
        cacheFile: File('${folder.path}/cache.json'),
        decoder: (_, value) {
          if (++calls == 1) {
            first = value;
            return pending.future;
          }
          return Future.value(WaveformData(2, List.filled(512, .8)));
        });
    await tester.pumpWidget(host(service));
    await flushIo(tester);
    await tester.pumpWidget(host(service, audio: b));
    expect(first!.cancelled, isTrue);
    expect(slider(tester).waveform, isNull);
    pending.complete(WaveformData(2, List.filled(512, .2)));
    await flushIo(tester);
    await flushIo(tester);
    expect(calls, 2);
    expect(slider(tester).waveform, isNotNull,
        reason: slider(tester).waveformTooltip);
    expect(slider(tester).waveform!.first, .8);
  });
  testWidgets(
      'hidden/offstage cancel analysis and release progress subscriptions',
      (tester) async {
    final pending = Completer<WaveformData?>();
    WaveformCancellation? token;
    final service = _UiWaveformService(
        cacheFile: File('${folder.path}/cache.json'),
        decoder: (_, value) {
          token = value;
          return pending.future;
        });
    await tester.pumpWidget(host(service));
    await flushIo(tester);
    hidden.value = true;
    await tester.pump();
    expect(token!.cancelled, isTrue);
    expect(positions.hasListener, isFalse);
    pending.complete(null);
    await flushIo(tester);
    hidden.value = false;
    await tester.pumpWidget(host(service, visible: false));
    await tester.pump();
    expect(slider(tester).waveform, isNull);
    expect(positions.hasListener, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
  });
  testWidgets('online and decode failure fall back without disabling seek',
      (tester) async {
    final service = _UiWaveformService(
        cacheFile: File('${folder.path}/cache.json'),
        decoder: (_, __) async =>
            throw const WaveformUnavailable(WaveformFailure.decode));
    final online = Audio('Fixture', 'Fixture', 'Fixture', 1, 2, 128, 44100,
        'online://provider/1', 0, 0, '',
        onlineProvider: 'provider', onlineId: '1');
    await tester.pumpWidget(host(service, audio: online));
    expect(slider(tester).waveformTooltip, contains('联网'));
    await tester.pumpWidget(host(service));
    await flushIo(tester);
    expect(slider(tester).waveformTooltip, contains('无法读取'));
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
  });
  testWidgets('visible inactive window retains waveform without reanalysis',
      (tester) async {
    var calls = 0;
    final service = _UiWaveformService(decoder: (_, __) async {
      calls++;
      return WaveformData(2, List.filled(512, .4));
    });
    await tester.pumpWidget(host(service));
    await tester.pump();
    expect(slider(tester).waveform, isNotNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(slider(tester).waveform, isNotNull);
    expect(calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });
  testWidgets(
      'same CUE identity with changed source boundaries reloads exact segment',
      (tester) async {
    final requests = <WaveformDecodeRequest>[];
    final service = _UiWaveformService(decoder: (request, _) async {
      requests.add(request);
      return WaveformData(2, List.filled(512, .4));
    });
    Audio cue(int start) => Audio('Fixture', 'Fixture', 'Fixture', 1, 2, 128,
        44100, 'cue://fixture/1', 0, 0, '',
        cueTrack: CueTrackReference(
            cuePath: '${folder.path}/album.cue',
            sourcePath: a.localFilePath,
            number: 1,
            startFrame: start,
            endFrame: start + 150));
    await tester.pumpWidget(host(service, audio: cue(0)));
    await tester.pump();
    await tester.pumpWidget(host(service, audio: cue(75)));
    await tester.pump();
    expect(requests.map((value) => value.start), [0, 1]);
    expect(requests.map((value) => value.end), [2, 3]);
    expect(slider(tester).waveform, isNotNull);
  });
  testWidgets(
      'external source release ends pending state without a stale loading hint',
      (tester) async {
    final pending = Completer<WaveformData?>();
    WaveformCancellation? token;
    final service = _UiWaveformService(decoder: (_, value) {
      token = value;
      return pending.future;
    });
    await tester.pumpWidget(host(service));
    await tester.pump();
    token!.cancel();
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(slider(tester).waveform, isNull);
    expect(slider(tester).waveformTooltip, contains('分析已取消'));
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
  });
}
