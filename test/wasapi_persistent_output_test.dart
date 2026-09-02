import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/src/bass/bass_player.dart').readAsStringSync();

  test('ordinary source release never tears down persistent WASAPI', () {
    final start = source.indexOf('void freeFStream()');
    final end = source.indexOf('void _disposeExclusiveOutput()', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final release = source.substring(start, end);

    expect(release, contains('_mix?.removeChannel(handle)'));
    expect(release, isNot(contains('BASS_WASAPI_Stop')));
    expect(release, isNot(contains('BASS_WASAPI_Free')));
  });

  test('WASAPI consumes one resident mixer instead of each song decoder', () {
    final mix = File('lib/src/bass/bass_mix.dart').readAsStringSync();
    expect(source, contains('BassMixLibrary.nonstop'));
    expect(mix, contains('channelDownmix'));
    expect(mix, contains('channelDownmix | (paused ? channelPaused : 0)'));
    expect(
      source,
      contains('ffi.Pointer<ffi.Void>.fromAddress(_exclusiveMixer!)'),
    );
    expect(source, contains('_mix!.addChannel(mixer, uncommittedHandle'));
    expect(source, contains('_mix!.setChannelPaused(stream, false)'));
  });

  test('device teardown is limited to mode exit and final shutdown', () {
    final start = source.indexOf('void _disposeExclusiveOutput()');
    final end = source.indexOf('bool freeSourceIfPath', start);
    final dispose = source.substring(start, end);
    expect(dispose, contains('BASS_WASAPI_Stop(BASS.TRUE)'));
    expect(dispose, contains('BASS_WASAPI_Free()'));
    expect(dispose, contains('BASS_StreamFree(mixer)'));
    expect(
      RegExp(r'_disposeExclusiveOutput\(\);').allMatches(source).length,
      greaterThanOrEqualTo(3),
    );
  });

  test('pause only freezes the source and never blocks on the endpoint', () {
    final pauseStart = source.indexOf('void _pause_wasapiExclusive()');
    final pauseEnd = source.indexOf('/// pause channel', pauseStart);
    final pause = source.substring(pauseStart, pauseEnd);
    expect(pause, contains('setChannelPaused(_fstream!, true)'));
    expect(pause, isNot(contains('BASS_WASAPI_Stop')));
    expect(pause, isNot(contains('BASS_WASAPI_Free')));
    expect(
      source,
      contains('_bassWasapi.BASS_WASAPI_IsStarted() == BASS.TRUE &&'),
    );
  });

  test('release manifest pins and requires the official BASSmix bytes', () {
    final prepare = File('scripts/prepare_bass_runtime.ps1').readAsStringSync();
    final assemble =
        File('scripts/assemble_windows_release.ps1').readAsStringSync();
    expect(prepare, contains("Name = 'BASSMIX'"));
    expect(prepare, contains("Archive = 'bassmix24.zip'"));
    expect(prepare, contains("Dll = 'bassmix.dll'"));
    expect(prepare, contains('runtime-x64-9pkg'));
    expect(assemble, contains("'BASS/bassmix.dll'"));
    expect(assemble, contains("'licenses/UN4SEEN/bassmix.txt'"));
  });
}
