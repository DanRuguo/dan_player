import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/play_service/playback_transition_preferences.dart';
import 'package:dan_player/src/bass/bass.dart';
import 'package:dan_player/src/bass/bass_mix.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

typedef _NativeSync = Void Function(Uint32, Uint32, Uint32, Pointer<Void>);

/// This case acquires a shared endpoint, but silences this mixer's output before
/// its first start. It examines the actual playback buffer, not audible sound.
/// A synchronous native update deterministically represents the output worker
/// filling the buffer between a source seek and a redundant mixer flush.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final runtime = Platform.environment['DAN_PLAYER_TRANSITION_BASS_DIR'];
  final skip = !Platform.isWindows || runtime == null
      ? 'Set DAN_PLAYER_TRANSITION_BASS_DIR to the complete native runtime.'
      : Platform.environment['DAN_PLAYER_TRANSITION_SHARED_DEVICE_TEST'] != '1'
          ? 'Opt in with DAN_PLAYER_TRANSITION_SHARED_DEVICE_TEST=1 for a silent shared endpoint.'
          : false;
  const provider = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;

  setUpAll(() async {
    if (skip != false) return;
    final temporary = p.normalize(Directory.systemTemp.absolute.path);
    if (!temporary
        .replaceAll('\\', '/')
        .toLowerCase()
        .contains('/tool/qa-local/')) {
      throw StateError('TEMP must be a workspace QA directory.');
    }
    directory = await Directory(temporary).createTemp('shared-seek-buffer-');
    messenger.setMockMethodCallHandler(provider, (_) async => directory.path);
    expect(p.isWithin(directory.path, (await getAppDataDir()).path), isTrue);
    await File(p.join(directory.path, 'position-ramp.wav'))
        .writeAsBytes(_positionRamp());
  });
  tearDownAll(() {
    if (skip == false) messenger.setMockMethodCallHandler(provider, null);
  });

  test('shared source seek preserves target PCM filled before native return',
      () async {
    final player = BassPlayer(runtimeDirectory: runtime!);
    final library = DynamicLibrary.open(p.join(runtime, 'bass.dll'));
    final mixLibrary = DynamicLibrary.open(p.join(runtime, 'bassmix.dll'));
    final api = Bass(library);
    final getDevice = library
        .lookupFunction<Uint32 Function(), int Function()>('BASS_GetDevice');
    final getVersion = library
        .lookupFunction<Uint32 Function(), int Function()>('BASS_GetVersion');
    final getMixVersion =
        mixLibrary.lookupFunction<Uint32 Function(), int Function()>(
            'BASS_Mixer_GetVersion');
    final getData = library.lookupFunction<
        Uint32 Function(Uint32, Pointer<Void>, Uint32),
        int Function(int, Pointer<Void>, int)>('BASS_ChannelGetData');
    final update = library.lookupFunction<Int32 Function(Uint32, Uint32),
        int Function(int, int)>('BASS_ChannelUpdate');
    final mixerFlags = library.lookupFunction<
        Uint32 Function(Uint32, Uint32, Uint32),
        int Function(int, int, int)>('BASS_ChannelFlags');
    final getConfig =
        library.lookupFunction<Uint32 Function(Uint32), int Function(int)>(
            'BASS_GetConfig');
    final setConfig = library.lookupFunction<Int32 Function(Uint32, Uint32),
        int Function(int, int)>('BASS_SetConfig');
    final channels = mixLibrary.lookupFunction<
        Uint32 Function(Uint32, Pointer<Uint32>, Uint32),
        int Function(
            int, Pointer<Uint32>, int)>('BASS_Mixer_StreamGetChannels');
    final channelFlags = mixLibrary.lookupFunction<
        Uint32 Function(Uint32, Uint32, Uint32),
        int Function(int, int, int)>('BASS_Mixer_ChannelFlags');
    final setSync = library.lookupFunction<
        Uint32 Function(Uint32, Uint32, Uint64,
            Pointer<NativeFunction<_NativeSync>>, Pointer<Void>),
        int Function(int, int, int, Pointer<NativeFunction<_NativeSync>>,
            Pointer<Void>)>('BASS_ChannelSetSync');
    final removeSync = library.lookupFunction<Int32 Function(Uint32, Uint32),
        int Function(int, int)>('BASS_ChannelRemoveSync');
    final volume = calloc<Float>();
    final sourceHandles = calloc<Uint32>(1);
    final samples = calloc<Float>(128);
    final savedUpdatePeriod = getConfig(1);
    NativeCallable<_NativeSync>? callback;
    var sync = 0;
    int? mixer;
    try {
      expect(getDevice(), allOf(greaterThan(0), lessThan(0xffffffff)),
          reason: 'An opted-in shared endpoint must actually exist.');
      expect(getVersion() >> 16, 0x0204);
      expect(getMixVersion() >> 16, 0x0204);
      expect(setConfig(1, 0), isNot(0),
          reason: 'Only this process uses deterministic manual updates.');
      player.configureTransitions(const PlaybackTransitionPreferences(
          mode: PlaybackTransitionMode.gapless));
      expect(
          await player.setSource(p.join(directory.path, 'position-ramp.wav')),
          isTrue);
      mixer = player.nativeMixerHandle!;
      final flags = mixerFlags(mixer, 0, 0);
      expect(flags, isNot(0xffffffff));
      expect(flags & BASS_STREAM_DECODE, 0,
          reason: 'A DECODE mixer cannot exercise the playback buffer race.');
      expect(api.BASS_ChannelSetAttribute(mixer, 2, 0), isNot(0));
      expect(api.BASS_ChannelGetAttribute(mixer, 2, volume), isNot(0));
      expect(volume.value, 0,
          reason: 'Silence only this process before output can start.');
      player.start();
      player.pause();
      expect(player.playerState, PlayerState.paused);
      expect(channels(mixer, sourceHandles, 1), 1);
      expect(
          channelFlags(sourceHandles.value, BassMixLibrary.channelNoRampIn,
              BassMixLibrary.channelNoRampIn),
          isNot(BassMixLibrary.errorValue));
      expect(update(mixer, 100), isNot(0));
      expect(getData(mixer, nullptr, 0), greaterThan(0));

      var resets = 0;
      var refillResult = 0;
      var firstBufferBytes = 0;
      var firstReadBytes = 0;
      List<double>? firstTargetPcm;
      callback = NativeCallable<_NativeSync>.isolateLocal(
          (int handle, int channel, int value, Pointer<Void> user) {
        resets++;
        if (resets != 1) return;
        // Records only: assertions stay in the test body. MIXTIME + disabled
        // worker updating keep this synchronous callback on the calling thread.
        refillResult = update(channel, 100);
        firstBufferBytes = getData(channel, nullptr, 0);
        firstReadBytes = getData(channel, samples.cast<Void>(), 128 * 4);
        if (firstReadBytes != 0xffffffff && firstReadBytes >= 8) {
          firstTargetPcm = samples.asTypedList(firstReadBytes ~/ 4).toList();
        }
      });
      // BASS_SYNC_SETPOS | BASS_SYNC_MIXTIME. Source RESET invokes this after
      // flushing the playable mixer's previous data.
      sync =
          setSync(mixer, 11 | 0x40000000, 0, callback.nativeFunction, nullptr);
      expect(sync, isNot(0));
      player.seek(1);
      expect(refillResult, isNot(0));
      expect(firstBufferBytes, greaterThan(0));
      expect(firstReadBytes, 128 * 4);
      expect(firstTargetPcm, isNotNull);
      expect(firstTargetPcm!.first, closeTo(.25, .001),
          reason: 'The independently captured first reset starts at 1s.');

      expect(update(mixer, 100), isNot(0));
      expect(getData(mixer, samples.cast<Void>(), 128 * 4), 128 * 4);
      final actual = samples.asTypedList(128).toList();
      stdout.writeln(
          'shared-seek-buffer bass=${getVersion().toRadixString(16)} '
          'mix=${getMixVersion().toRadixString(16)} endpoint=${getDevice()} '
          'resets=$resets filledBytes=$firstBufferBytes '
          'targetFirst=${firstTargetPcm!.first} actualFirst=${actual.first}');
      for (var i = 0; i < actual.length; i++) {
        expect(actual[i], closeTo(firstTargetPcm![i], .000001),
            reason: 'A second flush must not discard target PCM sample $i.');
      }
      expect(resets, 1);
      expect(player.playerState, PlayerState.paused);
      expect(api.BASS_ChannelGetAttribute(mixer, 2, volume), isNot(0));
      expect(volume.value, 0);
    } finally {
      if (sync != 0 && mixer != null) removeSync(mixer, sync);
      callback?.close();
      setConfig(1, savedUpdatePeriod);
      await player.free();
      calloc.free(samples);
      calloc.free(sourceHandles);
      calloc.free(volume);
      mixLibrary.close();
      library.close();
    }
  }, skip: skip);
}

Uint8List _positionRamp() {
  const rate = 48000, frames = rate * 4, frameBytes = 8;
  final data = ByteData(44 + frames * frameBytes);
  void text(int offset, String value) =>
      data.buffer.asUint8List().setAll(offset, value.codeUnits);
  text(0, 'RIFF');
  data.setUint32(4, data.lengthInBytes - 8, Endian.little);
  text(8, 'WAVEfmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 3, Endian.little);
  data.setUint16(22, 2, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * frameBytes, Endian.little);
  data.setUint16(32, frameBytes, Endian.little);
  data.setUint16(34, 32, Endian.little);
  text(36, 'data');
  data.setUint32(40, frames * frameBytes, Endian.little);
  for (var frame = 0; frame < frames; frame++) {
    for (var channel = 0; channel < 2; channel++) {
      data.setFloat32(
          44 + frame * frameBytes + channel * 4, frame / frames, Endian.little);
    }
  }
  return data.buffer.asUint8List();
}
