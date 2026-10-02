import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dan_player/library/audio_integrity.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_trim.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:flutter_test/flutter_test.dart';

Audio _track(String path, {CueTrackReference? cue}) =>
    Audio('Integrity QA', 'Fixture', 'QA', 1, 6, 1536, 48000, path, 0, 0, 'QA',
        cueTrack: cue);

Matcher _error(String message) => throwsA(isA<AudioIntegrityException>()
    .having((e) => e.message, 'message', message));

void main() {
  test(
      'Windows AVERROR is data failure while DLL/access violations are runtime failure',
      () {
    expect(isAudioToolRuntimeFailure(-1094995529), isFalse);
    expect(isAudioToolRuntimeFailure(0xbebbb1b7), isFalse);
    expect(isAudioToolRuntimeFailure(-22), isFalse);
    expect(isAudioToolRuntimeFailure(1), isFalse);
    expect(isAudioToolRuntimeFailure(0xc0000135), isTrue);
    expect(isAudioToolRuntimeFailure(-1073741819), isTrue);
  });

  test('check argv is read only, strict and bounded to one audio stream', () {
    final args = audioIntegrityArguments(r'J:\fixture & 音乐\file.wav');
    expect(args[args.indexOf('-i') + 1], r'J:\fixture & 音乐\file.wav');
    expect(args[args.indexOf('-map') + 1], '0:a:0');
    expect(args[args.indexOf('-err_detect') + 1],
        'crccheck+bitstream+buffer+explode');
    expect(args, containsAll(['-nostdin', '-xerror', '-vn', '-sn', '-dn']));
    expect(args.sublist(args.length - 3), ['-f', 'null', '-']);
    expect(args, isNot(contains('-y')));
    expect(args, isNot(contains('atrim')));
  });

  final ffmpeg = Platform.environment['DAN_INTEGRITY_FFMPEG'];
  final qa = Platform.environment['DAN_INTEGRITY_QA'];
  final native = ffmpeg != null && qa != null;
  late File tone, flac, longTone;
  setUpAll(() async {
    if (!native) return;
    final dir = Directory(qa);
    await dir.create(recursive: true);
    tone = File('${dir.path}/tone & 音乐.wav');
    flac = File('${dir.path}/tone.flac');
    longTone = File('${dir.path}/long.wav');
    for (final input in [(tone, '6'), (flac, '6'), (longTone, '180')]) {
      final result = await Process.run(ffmpeg, [
        '-nostdin',
        '-v',
        'error',
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=1000:sample_rate=48000:duration=${input.$2}',
        '-ac',
        '2',
        '-y',
        input.$1.path
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }
  });

  test('real full decoding and worker hash agree without changing source',
      () async {
    final before = await tone.readAsBytes();
    final phases = <AudioIntegrityPhase>[];
    final result = await AudioIntegrityInspector(executable: ffmpeg).inspect(
        _track(tone.path), AudioTrimCancellation(),
        onProgress: (value) => phases.add(value.phase));
    expect(result.sha256, sha256.convert(before).toString());
    expect(result.bytes, before.length);
    expect(result.path, tone.path);
    expect(result.decodedSeconds, closeTo(6, .002));
    expect(
        phases,
        containsAllInOrder(
            [AudioIntegrityPhase.hashing, AudioIntegrityPhase.decoding]));
    expect(await tone.readAsBytes(), before);
  }, skip: !native);

  test('real FLAC errors and truncated WAV cannot produce a success report',
      () async {
    final bad = File('${qa!}/corrupt.flac');
    final bytes = await flac.readAsBytes();
    for (var i = bytes.length ~/ 2; i < bytes.length ~/ 2 + 500; i++) {
      bytes[i] ^= 0xff;
    }
    await bad.writeAsBytes(bytes);
    final truncated = File('$qa/truncated.wav');
    final wave = await tone.readAsBytes();
    await truncated.writeAsBytes(wave.sublist(0, wave.length ~/ 2));
    final inspector = AudioIntegrityInspector(executable: ffmpeg);
    for (final file in [bad, truncated]) {
      await expectLater(
          inspector.inspect(_track(file.path), AudioTrimCancellation()),
          _error('解码检查未通过，请检查文件或编码格式'));
    }
  }, skip: !native);

  test('real CUE checks whole backing file rather than one declared segment',
      () async {
    final cue = CueTrackReference(
        cuePath: '$qa/disc.cue',
        sourcePath: tone.path,
        number: 2,
        startFrame: 150,
        endFrame: 225);
    final result = await AudioIntegrityInspector(executable: ffmpeg)
        .inspect(_track(cue.identity, cue: cue), AudioTrimCancellation());
    expect(result.path, tone.path);
    expect(result.decodedSeconds, closeTo(6, .002));
    expect(result.sha256, sha256.convert(await tone.readAsBytes()).toString());
  }, skip: !native);

  test('missing and empty sources reject before launching decoder', () async {
    final empty = File('${qa!}/empty.wav');
    await empty.writeAsBytes([]);
    final inspector = AudioIntegrityInspector(executable: ffmpeg);
    for (final path in ['$qa/absent.wav', empty.path]) {
      await expectLater(
          inspector.inspect(_track(path), AudioTrimCancellation()),
          _error('无法读取本地音频文件'));
    }
  }, skip: !native);

  test('cancelling at worker startup terminates hash and releases lease',
      () async {
    final token = AudioTrimCancellation();
    await expectLater(
        AudioIntegrityInspector(executable: ffmpeg)
            .inspect(_track(longTone.path), token, onProgress: (value) {
          if (value.phase == AudioIntegrityPhase.hashing) token.cancel();
        }).timeout(const Duration(seconds: 5)),
        _error('已取消文件校验'));
    final result = await AudioIntegrityInspector(executable: ffmpeg)
        .inspect(_track(tone.path), AudioTrimCancellation());
    expect(result.bytes, await tone.length());
  }, skip: !native);

  test('cancelling between hash and process startup reaps real decoder',
      () async {
    final token = AudioTrimCancellation();
    await expectLater(
        AudioIntegrityInspector(executable: ffmpeg)
            .inspect(_track(longTone.path), token, onProgress: (value) {
          if (value.phase == AudioIntegrityPhase.decoding) token.cancel();
        }).timeout(const Duration(seconds: 5)),
        _error('已取消文件校验'));
  }, skip: !native);

  test('changed source cannot pair an old hash with a new decode result',
      () async {
    final changed = await tone.copy('${qa!}/changed.wav');
    await expectLater(
        AudioIntegrityInspector(executable: ffmpeg).inspect(
            _track(changed.path), AudioTrimCancellation(), onProgress: (value) {
          if (value.phase == AudioIntegrityPhase.decoding) {
            changed.setLastModifiedSync(
                DateTime.now().add(const Duration(days: 1)));
          }
        }),
        _error('校验期间源文件已改变，请重新校验'));
  }, skip: !native);

  test('concurrent scans are rejected and cancelled owner frees lease',
      () async {
    final inspector = AudioIntegrityInspector(executable: ffmpeg);
    final token = AudioTrimCancellation();
    final pending = inspector.inspect(_track(longTone.path), token);
    final first = expectLater(pending, _error('已取消文件校验'));
    await expectLater(
        inspector.inspect(_track(tone.path), AudioTrimCancellation()),
        _error('已有文件校验正在进行，请稍后重试'));
    token.cancel();
    await first;
  }, skip: !native);

  test('worker timeout terminates work instead of returning a partial digest',
      () async {
    await expectLater(
        AudioIntegrityInspector(executable: ffmpeg, timeout: Duration.zero)
            .inspect(_track(longTone.path), AudioTrimCancellation()),
        _error('文件校验超时，请重试'));
  }, skip: !native);
}
