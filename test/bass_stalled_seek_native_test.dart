import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:dan_player/src/bass/bass.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

/// Generated PCM on NoSound device 0 exercises native starvation, successful
/// reset-seek and automatic refill recovery with the production seek polling
/// policy. It does not instantiate BassPlayer's real-device constructor or
/// claim speaker, WASAPI endpoint, HTTP buffering or audible quality coverage.
void main() {
  final dlls = Platform.environment['DAN_PLAYER_STALLED_SEEK_BASS_DIR'];
  final skip = !Platform.isWindows || dlls == null
      ? 'Set DAN_PLAYER_STALLED_SEEK_BASS_DIR for an isolated device-0 check.'
      : false;

  test('native stalled seek observes refill progress and one natural stop',
      () async {
    final fixture = _NativePushFixture(dlls!);
    Timer? poll;
    try {
      expect(fixture.api.BASS_ChannelStart(fixture.stream), isNot(0));
      expect(fixture.state, BASS_ACTIVE_STALLED);
      var completions = 0;
      final positions = <int>[];
      Timer create() =>
          Timer.periodic(const Duration(milliseconds: 33), (tick) {
            positions.add(fixture.position);
            if (fixture.state == BASS_ACTIVE_STOPPED) {
              completions++;
              tick.cancel();
            }
          });
      poll = create();
      expect(
          fixture.api.BASS_ChannelSetPosition(fixture.stream, 0, BASS_POS_BYTE),
          isNot(0));
      expect(fixture.state, BASS_ACTIVE_STALLED);
      poll = rearmBassPositionUpdaterAfterSeek(
        poll,
        stateBeforeSeek: PlayerState.stalled,
        create: create,
      );

      fixture.refill(ended: true);
      // StreamPutData resumes playback itself; never issue another Play here.
      expect(fixture.state, BASS_ACTIVE_PLAYING);
      await fixture.waitUntil(() => fixture.state == BASS_ACTIVE_STOPPED);
      expect(fixture.position, fixture.sampleBytes);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(positions.any((bytes) => bytes > 0), isTrue,
          reason: 'Native refill must remain visible after the stalled seek.');
      expect(completions, 1);
      expect(poll?.isActive, isFalse);
    } finally {
      poll?.cancel();
      fixture.close();
    }
  }, skip: skip);

  test('native paused seek and refill preserve pause with no polling',
      () async {
    final fixture = _NativePushFixture(dlls!);
    Timer? poll;
    try {
      expect(fixture.api.BASS_ChannelStart(fixture.stream), isNot(0));
      expect(fixture.state, BASS_ACTIVE_STALLED);
      expect(fixture.api.BASS_ChannelPause(fixture.stream), isNot(0));
      expect(fixture.state, BASS_ACTIVE_PAUSED);
      expect(
          fixture.api.BASS_ChannelSetPosition(fixture.stream, 0, BASS_POS_BYTE),
          isNot(0));
      poll = rearmBassPositionUpdaterAfterSeek(
        null,
        stateBeforeSeek: PlayerState.paused,
        create: () => fail('A paused seek cannot resume its position poll.'),
      );
      fixture.refill(ended: false);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(fixture.state, BASS_ACTIVE_PAUSED);
      expect(fixture.position, 0);
      expect(poll, isNull);
    } finally {
      poll?.cancel();
      fixture.close();
    }
  }, skip: skip);
}

class _NativePushFixture {
  _NativePushFixture(String dlls) {
    final library = DynamicLibrary.open('$dlls/bass.dll');
    api = Bass(library);
    expect(api.BASS_Init(0, 44100, 0, nullptr, nullptr), isNot(0));
    final create = library.lookupFunction<
        Uint32 Function(Uint32, Uint32, Uint32, Pointer<Void>, Pointer<Void>),
        int Function(int, int, int, Pointer<Void>, Pointer<Void>)>(
      'BASS_StreamCreate',
    );
    put = library.lookupFunction<Uint32 Function(Uint32, Pointer<Void>, Uint32),
        int Function(int, Pointer<Void>, int)>('BASS_StreamPutData');
    // STREAMPROC_PUSH is the native sentinel -1, not a Dart callback running
    // on the BASS worker thread. This fixture writes generated silent PCM.
    stream = create(44100, 1, 0, Pointer<Void>.fromAddress(-1), nullptr);
    expect(stream, isNot(0));
    samples = calloc<Int16>(sampleBytes ~/ 2);
  }

  static const frames = 11025;
  final sampleBytes = frames * 2;
  late final Bass api;
  late final int stream;
  late final Pointer<Int16> samples;
  late final int Function(int, Pointer<Void>, int) put;

  int get state => api.BASS_ChannelIsActive(stream);
  int get position => api.BASS_ChannelGetPosition(stream, BASS_POS_BYTE);

  void refill({required bool ended}) {
    final queued = put(stream, samples.cast(),
        sampleBytes | (ended ? 0x80000000 : 0)); // BASS_STREAMPROC_END
    expect(queued, isNot(0xffffffff));
  }

  Future<void> waitUntil(bool Function() predicate) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (!predicate() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(predicate(), isTrue, reason: 'The device-0 stream must reach EOF.');
  }

  void close() {
    calloc.free(samples);
    api.BASS_Free();
  }
}
