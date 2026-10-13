import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:dan_player/src/bass/bass.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/src/bass/wasapi_output_policy.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Real BASS starvation, output pause/start and replacement on NoSound device
/// 0 exercise the shared transport policies. This does not initialize a real
/// BassPlayer/WASAPI endpoint or claim HTTP, soundcard or listening coverage.
void main() {
  final runtime = Platform.environment['DAN_PLAYER_STALLED_SEEK_BASS_DIR'];
  final skip = !Platform.isWindows || runtime == null
      ? 'Set DAN_PLAYER_STALLED_SEEK_BASS_DIR for an isolated device-0 check.'
      : false;

  for (final paused in [false, true]) {
    for (final rejected in [false, true]) {
      test('native stalled output seek paused=$paused rejected=$rejected',
          () async {
        final fixture = _PushOutput(runtime!);
        try {
          final stream = fixture.create();
          expect(fixture.api.BASS_ChannelStart(stream), 1);
          expect(fixture.state(stream), PlayerState.stalled);
          if (paused) {
            expect(fixture.api.BASS_ChannelPause(stream), 1);
            expect(fixture.state(stream), PlayerState.paused);
          }
          final before = fixture.state(stream);
          void seek() => seekWasapiOutput(
                wasPlaying: before.keepsPlaybackIntent,
                flush: () => expect(fixture.pauseOutput(), 1),
                move: () {
                  final moved = fixture.api.BASS_ChannelSetPosition(
                      stream, rejected ? 1000 : 0, BASS_POS_BYTE);
                  if (moved == 0) {
                    throw StateError(
                        'Native seek rejected: ${fixture.api.BASS_ErrorGetCode()}');
                  }
                },
                resume: () => expect(fixture.api.BASS_Start(), 1),
              );
          if (rejected) {
            expect(seek, throwsStateError,
                reason: 'A PUSH stream supports reset to zero only.');
          } else {
            seek();
          }
          // BASS_IsStarted is DWORD: 1=started/active, 2=started/inactive
          // while a starved stream has no samples. Only 0 means stopped.
          expect(fixture.outputStarted(), paused ? equals(0) : anyOf(1, 2),
              reason: 'Temporary starvation must retain active output intent.');
          expect(fixture.state(stream),
              paused ? PlayerState.paused : PlayerState.stalled);
          fixture.refill(stream);
          if (paused) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            expect(fixture.state(stream), PlayerState.paused);
            expect(fixture.position(stream), 0);
          } else {
            await fixture.until(() => fixture.position(stream) > 0);
            await fixture
                .until(() => fixture.state(stream) == PlayerState.stopped);
            expect(fixture.position(stream), _PushOutput.sampleBytes);
          }
        } finally {
          fixture.close();
        }
      }, skip: skip);
    }
  }

  for (final commands in <List<bool>>[
    [],
    [false],
    [true],
    [false, true],
    [true, false],
  ]) {
    test('native stalled replacement honors latest transport $commands',
        () async {
      final fixture = _PushOutput(runtime!);
      try {
        final old = fixture.create();
        expect(fixture.api.BASS_ChannelStart(old), 1);
        expect(fixture.state(old), PlayerState.stalled);
        final intent = OutputPlaybackIntent();
        final opened = Completer<void>();
        late int replacement;
        final transaction = () async {
          await opened.future;
          // The final observation occurs before the retained source is freed,
          // as in useExclusiveMode's onBeforeCommit callback.
          final wasPlaying = fixture.state(old).keepsPlaybackIntent;
          replacement = fixture.create();
          expect(fixture.api.BASS_StreamFree(old), 1);
          if (intent.resolve(wasPlaying)) {
            expect(fixture.api.BASS_ChannelStart(replacement), 1);
          }
        }();
        for (final playing in commands) {
          intent.request(playing);
          if (playing) {
            expect(fixture.api.BASS_ChannelStart(old), 1);
          } else {
            expect(fixture.api.BASS_ChannelPause(old), 1);
          }
        }
        opened.complete();
        await transaction;
        fixture.refill(replacement);
        if (commands.isEmpty || commands.last) {
          await fixture.until(() => fixture.position(replacement) > 0);
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(fixture.state(replacement), PlayerState.stopped);
          expect(fixture.position(replacement), 0);
        }
      } finally {
        fixture.close();
      }
    }, skip: skip);
  }

  test('native unavailable output is not temporary starvation', () async {
    final fixture = _PushOutput(runtime!);
    try {
      final stream = fixture.create();
      expect(fixture.api.BASS_ChannelStart(stream), 1);
      expect(fixture.state(stream), PlayerState.stalled);
      expect(fixture.pauseOutput(), 1);
      expect(fixture.state(stream), PlayerState.pausedDevice);
      final intent = OutputPlaybackIntent();
      expect(
          intent.resolve(fixture.state(stream).keepsPlaybackIntent), isFalse);
      fixture.refill(stream);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(fixture.outputStarted(), 0);
      expect(fixture.position(stream), 0);
    } finally {
      fixture.close();
    }
  }, skip: skip);
}

class _PushOutput {
  _PushOutput(String runtime) {
    library = DynamicLibrary.open(p.join(runtime, 'bass.dll'));
    api = Bass(library);
    expect(api.BASS_Init(0, 44100, 0, nullptr, nullptr), 1);
    createStream = library.lookupFunction<
        Uint32 Function(Uint32, Uint32, Uint32, Pointer<Void>, Pointer<Void>),
        int Function(int, int, int, Pointer<Void>, Pointer<Void>)>(
      'BASS_StreamCreate',
    );
    put = library.lookupFunction<Uint32 Function(Uint32, Pointer<Void>, Uint32),
        int Function(int, Pointer<Void>, int)>('BASS_StreamPutData');
    pauseOutput =
        library.lookupFunction<Int32 Function(), int Function()>('BASS_Pause');
    outputStarted = library
        .lookupFunction<Uint32 Function(), int Function()>('BASS_IsStarted');
    samples = calloc<Int16>(sampleBytes ~/ 2);
  }

  static const sampleBytes = 11025 * 2;
  late final DynamicLibrary library;
  late final Bass api;
  late final int Function(int, int, int, Pointer<Void>, Pointer<Void>)
      createStream;
  late final int Function(int, Pointer<Void>, int) put;
  late final int Function() pauseOutput, outputStarted;
  late final Pointer<Int16> samples;

  int create() {
    final stream =
        createStream(44100, 1, 0, Pointer<Void>.fromAddress(-1), nullptr);
    expect(stream, isNot(0));
    return stream;
  }

  PlayerState state(int stream) => switch (api.BASS_ChannelIsActive(stream)) {
        BASS_ACTIVE_PLAYING => PlayerState.playing,
        BASS_ACTIVE_STALLED => PlayerState.stalled,
        BASS_ACTIVE_PAUSED => PlayerState.paused,
        BASS_ACTIVE_PAUSED_DEVICE => PlayerState.pausedDevice,
        BASS_ACTIVE_STOPPED => PlayerState.stopped,
        _ => throw StateError('Unexpected native state'),
      };

  int position(int stream) =>
      api.BASS_ChannelGetPosition(stream, BASS_POS_BYTE);

  void refill(int stream) {
    expect(put(stream, samples.cast(), sampleBytes | 0x80000000),
        isNot(0xffffffff));
  }

  Future<void> until(bool Function() predicate) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (!predicate() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(predicate(), isTrue,
        reason: 'Native device-0 playback must progress.');
  }

  void close() {
    expect(api.BASS_Free(), 1);
    calloc.free(samples);
    library.close();
  }
}
