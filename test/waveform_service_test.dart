import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/play_service/waveform_service.dart';
import 'package:dan_player/src/bass/bass_waveform.dart';
import 'package:flutter_test/flutter_test.dart';

Audio song(String path, {CueTrackReference? cue}) =>
    Audio('Fixture', 'Fixture', 'Fixture', 1, 2, 128, 44100, path, 0, 0, '',
        cueTrack: cue);
WaveformData data([double peak = .4]) =>
    WaveformData(2, List.filled(512, peak));

void main() {
  late Directory folder;
  late File source;
  late File cache;
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('waveform-test-');
    source = await File('${folder.path}/audio.wav').writeAsBytes([1, 2, 3]);
    cache = File('${folder.path}/waveform_cache.json');
  });
  tearDown(() async => folder.delete(recursive: true));

  test('amplitude envelope retains silence and antiphase channel energy', () {
    final accumulator = WaveformAccumulator(4, 2, bins: 4);
    accumulator.add([0, 0, .2, -.2, .5, -.5, 1, -1]);
    final values = accumulator.finish();
    expect(values.first, 0);
    expect(values[1], greaterThan(0));
    expect(values[2], greaterThan(values[1]));
    expect(values.last, 1);
    expect(WaveformAccumulator(2, 1, bins: 2)..add([double.nan, 0]), isNotNull);
    final silence = WaveformAccumulator(2, 1, bins: 2)..add([0, 0]);
    expect(silence.finish(), [0, 0]);
  });
  test('chunk boundaries retain sample/channel/time alignment', () {
    final whole = WaveformAccumulator(3, 2, bins: 3)
      ..add([0, .2, .3, -.3, .8, -.8]);
    final chunks = WaveformAccumulator(3, 2, bins: 3)
      ..add([0])
      ..add([.2, .3, -.3])
      ..add([.8, -.8]);
    expect(chunks.finish(), whole.finish());
    expect(() => WaveformAccumulator(3, 0), throwsArgumentError);
  });
  test('precise envelope retains seconds when player length is estimated', () {
    final samples = [for (var i = 0; i < 512; i++) i < 256 ? .2 : .8];
    final exact = WaveformData(4, samples);
    expect(identical(waveformPeaksForDuration(exact, 4), exact.peaks), isTrue);
    final shorter = waveformPeaksForDuration(exact, 2);
    expect(shorter.every((value) => value == .2), isTrue);
    final longer = waveformPeaksForDuration(exact, 8);
    expect(longer[0], .2);
    expect(longer[128], .8);
    expect(longer.skip(256).every((value) => value == 0), isTrue);
    expect(waveformPeaksForDuration(exact, double.nan), isEmpty);
    expect(waveformPeaksForDuration(exact, 0), isEmpty);
  });
  test('same revision survives a service restart without decoding', () async {
    var calls = 0;
    Future<WaveformData?> decode(
        WaveformDecodeRequest _, WaveformCancellation __) async {
      calls++;
      return data();
    }

    final first = WaveformService(cacheFile: cache, decoder: decode);
    expect((await first.load(song(source.path), WaveformCancellation()))!.peaks,
        data().peaks);
    final restart = WaveformService(cacheFile: cache, decoder: decode);
    expect(
        (await restart.load(song(source.path), WaveformCancellation()))!.peaks,
        data().peaks);
    expect(calls, 1);
    expect(await source.readAsBytes(), [1, 2, 3]);
  });
  test('file revision invalidates cache', () async {
    var calls = 0;
    final service = WaveformService(
        cacheFile: cache,
        decoder: (_, __) async {
          calls++;
          return data();
        });
    await service.load(song(source.path), WaveformCancellation());
    await source.writeAsBytes([4, 5, 6, 7]);
    await service.load(song(source.path), WaveformCancellation());
    expect(calls, 2);
    final entries = jsonDecode(await cache.readAsString())['entries'] as Map;
    expect(entries, hasLength(1));
    final bound = entries.values.single as Map;
    expect(bound['sourceKey'], matches(r'^[a-f0-9]{64}$'));
    expect(bound['trackKey'], matches(r'^[a-f0-9]{64}$'));
    expect(bound['sourceRevision'], matches(r'^[a-f0-9]{64}$'));
    expect(await cache.readAsString(), isNot(contains(source.path)));
  });
  test('CUE boundaries are exact and separate cache identities', () async {
    final requests = <WaveformDecodeRequest>[];
    final service = WaveformService(
        cacheFile: cache,
        decoder: (request, _) async {
          requests.add(request);
          return data();
        });
    Audio cue(int number, int start, int end) => song('cue://fixture/$number',
        cue: CueTrackReference(
            cuePath: '${folder.path}/album.cue',
            sourcePath: source.path,
            number: number,
            startFrame: start,
            endFrame: end));
    await service.load(cue(1, 1, 151), WaveformCancellation());
    await service.load(cue(2, 151, 301), WaveformCancellation());
    await service.load(cue(1, 1, 151), WaveformCancellation());
    expect(requests, hasLength(2));
    expect(requests[0].filePath, source.absolute.path);
    expect(requests[0].start, 1 / 75);
    expect(requests[0].end, 151 / 75);
    expect(requests[1].start, 151 / 75);
    expect(jsonDecode(await cache.readAsString())['entries'], hasLength(2));
    await service.invalidatePath(source.path);
    expect(jsonDecode(await cache.readAsString())['entries'], isEmpty);
    await service.load(cue(1, 1, 151), WaveformCancellation());
    expect(requests, hasLength(3));
  });
  test(
      'deleting a source retires its bound cache and never returns orphan data',
      () async {
    final service =
        WaveformService(cacheFile: cache, decoder: (_, __) async => data());
    await service.load(song(source.path), WaveformCancellation());
    await source.delete();
    await service.invalidatePath(source.path);
    expect(jsonDecode(await cache.readAsString())['entries'], isEmpty);
    await expectLater(
        service.load(song(source.path), WaveformCancellation()),
        throwsA(isA<WaveformUnavailable>().having(
            (error) => error.reason, 'reason', WaveformFailure.missing)));
  });
  test('invalidation creates no idle cache and preserves a future cache',
      () async {
    final service = WaveformService(cacheFile: cache);
    await service.invalidatePath(source.path);
    expect(await cache.exists(), isFalse);
    const future = '{"version":2,"entries":{}}';
    await cache.writeAsString(future);
    await service.invalidatePath(source.path);
    expect(await cache.readAsString(), future);
  });
  test('cancelled decode and stale queued request do not write cache',
      () async {
    final entered = Completer<void>();
    final done = Completer<WaveformData?>();
    var calls = 0;
    final service = WaveformService(
        cacheFile: cache,
        decoder: (_, __) {
          calls++;
          entered.complete();
          return done.future;
        });
    final current = WaveformCancellation();
    final first = service.load(song(source.path), current);
    await entered.future;
    final queued = WaveformCancellation();
    final second = service.load(song(source.path), queued);
    current.cancel();
    queued.cancel();
    done.complete(data());
    expect(await first, isNull);
    expect(await second, isNull);
    expect(calls, 1);
    expect(await cache.exists(), isFalse);
  });
  test('decoder errors release serial gate for a later request', () async {
    var calls = 0;
    final service = WaveformService(
        cacheFile: cache,
        decoder: (_, __) async {
          if (++calls == 1) {
            throw const WaveformUnavailable(WaveformFailure.decode);
          }
          return data();
        });
    await expectLater(service.load(song(source.path), WaveformCancellation()),
        throwsA(isA<WaveformUnavailable>()));
    expect(await service.load(song(source.path), WaveformCancellation()),
        isNotNull);
  });
  test(
      'shutdown cancels active/queued reads, drains cleanup and rejects new work',
      () async {
    final entered = Completer<void>();
    final nativeReleased = Completer<WaveformData?>();
    var calls = 0;
    final service = WaveformService(
        cacheFile: cache,
        decoder: (_, __) {
          calls++;
          entered.complete();
          return nativeReleased.future;
        });
    final first = WaveformCancellation();
    final second = WaveformCancellation();
    final active = service.load(song(source.path), first);
    await entered.future;
    final queued = service.load(song(source.path), second);
    var closed = false;
    final close = service.close().then((_) => closed = true);
    expect(first.cancelled, isTrue);
    expect(second.cancelled, isTrue);
    expect(closed, isFalse);
    expect(
        await service.load(song(source.path), WaveformCancellation()), isNull);
    nativeReleased.complete(null);
    await close;
    expect(await active, isNull);
    expect(await queued, isNull);
    await service.close();
    expect(calls, 1);
    expect(closed, isTrue);
  });
  test(
      'physical source release cancels CUE work and gates new reads during tag write',
      () async {
    final entered = Completer<void>();
    final done = Completer<WaveformData?>();
    var calls = 0;
    final service = WaveformService(
        cacheFile: cache,
        decoder: (_, __) {
          calls++;
          entered.complete();
          return done.future;
        });
    final cue = song('cue://fixture/1',
        cue: CueTrackReference(
            cuePath: '${folder.path}/album.cue',
            sourcePath: source.path,
            number: 1,
            startFrame: 0,
            endFrame: 150));
    final token = WaveformCancellation();
    final analysis = service.load(cue, token);
    await entered.future;
    var writing = false;
    final write = service.withSourceReleased(source.path, () async {
      writing = true;
      expect(await service.load(song(source.path), WaveformCancellation()),
          isNull);
      expect(calls, 1);
      return 'committed';
    });
    await Future<void>.delayed(Duration.zero);
    expect(token.cancelled, isTrue);
    expect(writing, isFalse);
    done.complete(data());
    expect(await analysis, isNull);
    expect(await write, 'committed');
    expect(writing, isTrue);
    expect(await cache.exists(), isFalse);
  });
  test('file modified during analysis is rejected without persistence',
      () async {
    final service = WaveformService(
        cacheFile: cache,
        decoder: (_, __) async {
          await source.writeAsBytes([0]);
          return data();
        });
    await expectLater(
        service.load(song(source.path), WaveformCancellation()),
        throwsA(isA<WaveformUnavailable>().having(
            (value) => value.reason, 'reason', WaveformFailure.changed)));
    expect(await cache.exists(), isFalse);
  });
  test('missing and online sources never start a decoder', () async {
    var calls = 0;
    final service = WaveformService(
        cacheFile: cache,
        decoder: (_, __) async {
          calls++;
          return data();
        });
    await expectLater(
        service.load(
            song('${folder.path}/missing.wav'), WaveformCancellation()),
        throwsA(isA<WaveformUnavailable>()));
    final online = Audio('Fixture', 'Fixture', 'Fixture', 1, 2, 128, 44100,
        'online://provider/1', 0, 0, '',
        onlineProvider: 'provider', onlineId: '1');
    await expectLater(service.load(online, WaveformCancellation()),
        throwsA(isA<WaveformUnavailable>()));
    expect(calls, 0);
  });
  test('known long recordings skip file I/O and native prescan', () async {
    var calls = 0;
    final service = WaveformService(
        cacheFile: cache,
        decoder: (_, __) async {
          calls++;
          return data();
        });
    final recording = song('${folder.path}/missing-long.wav')..duration = 8000;
    await expectLater(
        service.load(recording, WaveformCancellation()),
        throwsA(isA<WaveformUnavailable>().having(
            (value) => value.reason, 'reason', WaveformFailure.tooLong)));
    expect(calls, 0);
    expect(await cache.exists(), isFalse);
  });
  test('future cache version is preserved while analysis still displays',
      () async {
    const original = '{"version":2,"entries":{}}';
    await cache.writeAsString(original);
    final service =
        WaveformService(cacheFile: cache, decoder: (_, __) async => data());
    expect(await service.load(song(source.path), WaveformCancellation()),
        isNotNull);
    expect(await cache.readAsString(), original);
  });
  test('cache capacity remains 128 and malformed samples are rejected',
      () async {
    final entries = <String, Object>{};
    for (var i = 0; i < 128; i++) {
      entries[i.toRadixString(16).padLeft(64, '0')] = {
        'duration': 2,
        'peaks': data().peaks,
      };
    }
    await cache.writeAsString(jsonEncode({'version': 1, 'entries': entries}));
    final service =
        WaveformService(cacheFile: cache, decoder: (_, __) async => data());
    await service.load(song(source.path), WaveformCancellation());
    expect(
        (jsonDecode(await cache.readAsString())['entries'] as Map).length, 128);
    expect(
        () => WaveformService.validateCache({
              'version': 1,
              'entries': {
                '0' * 64: {
                  'duration': 2,
                  'peaks': List.filled(512, double.nan)
                },
              }
            }),
        throwsFormatException);
  });
}
