import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dan_player/library/audio_trim.dart';
import 'package:dan_player/library/audio_trim_commit.dart';
import 'package:dan_player/taskbar_progress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/metadata_test_audio.dart';

Map<String, dynamic> probe(String format, String codec,
        {double duration = 6}) =>
    {
      'format': {'format_name': format, 'duration': '$duration'},
      'streams': [
        {
          'codec_type': 'audio',
          'codec_name': codec,
          'sample_rate': '48000',
          'channels': 2,
          'duration': '$duration',
          'bit_rate': '192000'
        }
      ],
    };

void main() {
  test('container detection follows bytes, not a misleading mp3 extension', () {
    final info = audioTrimInfoFromProbe(
        probe('mov,mp4,m4a,3gp,3g2,mj2', 'aac'), r'C:\歌曲\实际是MP4.mp3');
    expect(info.muxer, 'ipod');
    expect(info.outputExtension, '.mp3');
    expect(info.limitation, isNotNull);
    expect(info.duration, 6);
  });
  test('supported lossless containers keep their original codec', () {
    for (final (container, codec) in [
      ('flac', 'flac'),
      ('wav', 'pcm_s24le'),
      ('aiff', 'pcm_s16be'),
      ('mov,mp4', 'alac')
    ]) {
      final info =
          audioTrimInfoFromProbe(probe(container, codec), r'C:\song.audio');
      expect(info.codec, codec);
      expect(info.limitation, isNull);
    }
  });
  test('extra audio, ordinary video and unknown formats are never discarded',
      () {
    for (final kind in ['audio', 'video', 'data']) {
      final input = probe('mp3', 'mp3');
      (input['streams'] as List).add({'codec_type': kind});
      expect(() => audioTrimInfoFromProbe(input, r'C:\song.mp3'),
          throwsA(isA<AudioTrimException>()));
    }
    expect(() => audioTrimInfoFromProbe(probe('asf', 'wmav2'), r'C:\song.wma'),
        throwsA(isA<AudioTrimException>()));
    final artwork = probe('mp3', 'mp3');
    (artwork['streams'] as List).add({
      'codec_type': 'video',
      'disposition': {'attached_pic': 1}
    });
    expect(audioTrimInfoFromProbe(artwork, r'C:\song.mp3').codec, 'libmp3lame');
  });
  test('precise argv preserves Unicode and shell syntax as literal paths', () {
    const source = r'C:\音乐\a $(whoami) & 曲.mp3';
    final info = audioTrimInfoFromProbe(probe('mp3', 'mp3'), source);
    final request = AudioTrimRequest(
        destinationPath: p.absolute('copy.mp3'),
        startSeconds: 1.25,
        endSeconds: 3.5);
    final args = audioTrimEncoderArguments(source, 'out.mp3', info, request);
    expect(args[args.indexOf('-i') + 1], source);
    expect(args[args.indexOf('-ss') + 1], '1.250000');
    expect(args[args.indexOf('-t') + 1], '2.250000');
    expect(args[args.indexOf('-protocol_whitelist') + 1], 'file,pipe');
    expect(args[args.indexOf('-threads') + 1], '2');
  });
  test('invalid selection is rejected before file processing', () {
    final info = audioTrimInfoFromProbe(probe('mp3', 'mp3'), 'song.mp3');
    for (final (start, end) in [
      (-1.0, 3.0),
      (0.0, 7.0),
      (2.0, 2.01),
      (double.nan, 3.0),
      (0.0, double.infinity)
    ]) {
      expect(
          () => validateAudioTrimRequest(
              info,
              AudioTrimRequest(
                  destinationPath: p.absolute('copy.mp3'),
                  startSeconds: start,
                  endSeconds: end)),
          throwsA(isA<AudioTrimException>()));
    }
  });
  test('cancellation cannot interrupt publication once commit begins', () {
    final before = AudioTrimCancellation()..cancel();
    expect(before.beginCommit, throwsA(isA<AudioTrimException>()));
    final during = AudioTrimCancellation()
      ..beginCommit()
      ..cancel();
    expect(during.canCancel, isFalse);
    expect(during.isCancelled, isFalse);
  });

  final toolRoot = Platform.environment['DAN_PLAYER_TEST_FFMPEG_DIR'];
  group('real isolated audio tools', skip: toolRoot == null, () {
    late Directory directory;
    late File source;
    Future<String> resolve(String executable) async =>
        p.join(toolRoot!, '$executable${Platform.isWindows ? '.exe' : ''}');
    setUp(() async {
      final root = Directory(p.absolute(
          '..', 'tool', 'validation', 'sep14-audio-trim', 'fixtures'));
      await root.create(recursive: true);
      directory = await root.createTemp('engine-');
      source = File(p.join(directory.path, '原曲 & (测试).wav'));
      await runAudioTool(
          'ffmpeg',
          [
            '-v',
            'error',
            '-nostdin',
            '-f',
            'lavfi',
            '-i',
            'sine=frequency=523:sample_rate=48000:duration=3',
            '-ac',
            '2',
            '-c:a',
            'pcm_s24le',
            source.path
          ],
          resolve: resolve);
    });
    tearDown(() async {
      expect(TaskbarProgress.instance.value, isNull);
      // Only this test's verified, uniquely owned directory is removed.
      final root = p.absolute(
          '..', 'tool', 'validation', 'sep14-audio-trim', 'fixtures');
      expect(p.isWithin(root, directory.absolute.path), isTrue);
      await directory.delete(recursive: true);
    });

    Future<String> digest(File file) async =>
        '${await sha256.bind(file.openRead()).first}';
    AudioTrimOperations operations(
            {required List<String> events,
            bool failMetadata = false,
            bool failSync = false}) =>
        AudioTrimOperations(
            resolveTool: resolve,
            prepare: (path) async =>
                jsonEncode({'fingerprint': await digest(File(path))}),
            metadata: (path, temp, request) async {
              events.add('metadata');
              if (failMetadata) throw StateError('Cannot preserve metadata');
              return '{}';
            },
            releasePlayback: (path) async {
              events.add('release');
              return 'ticket';
            },
            restorePlayback: (ticket, offset) {
              if (ticket != null) events.add('restore:$offset');
            },
            commit: (path, temp, request, fingerprint) async {
              events.add('commit');
              expect(await digest(File(path)), fingerprint);
              if (request.overwrite) await File(path).delete();
              await File(temp).rename(request.destinationPath);
              return jsonEncode({'path': request.destinationPath, 'audio': {}});
            },
            synchronize: (audio, request, json) async {
              expect(TaskbarProgress.instance.value,
                  TaskbarProgressValue.fraction(.94));
              events.add('sync');
              if (failSync) throw StateError('Disk index unavailable');
            });

    test('exports both ends exactly, verifies PCM content and keeps source',
        () async {
      final hash = await digest(source);
      final audio = MetadataTestAudio()..path = source.path;
      final events = <String>[];
      final result = await performAudioTrim(
          audio,
          AudioTrimRequest(
              destinationPath: p.join(directory.path, '副本.wav'),
              startSeconds: .375,
              endSeconds: 2.125),
          operations: operations(events: events));
      expect(result.duration, closeTo(1.75, 1 / 48000));
      expect(await digest(source), hash);
      expect(events, ['metadata', 'commit', 'sync']);
      final expected = File(p.join(directory.path, 'expected.pcm'));
      final actual = File(p.join(directory.path, 'actual.pcm'));
      for (final (input, out, cut) in [
        (source.path, expected.path, true),
        (result.path, actual.path, false)
      ]) {
        await runAudioTool(
            'ffmpeg',
            [
              '-v',
              'error',
              '-i',
              input,
              if (cut) ...[
                '-af',
                'atrim=start=0.375:end=2.125,asetpts=PTS-STARTPTS'
              ],
              '-c:a',
              'pcm_s24le',
              '-f',
              's24le',
              out
            ],
            resolve: resolve);
      }
      expect(await digest(actual), await digest(expected));
      expect(
          await directory
              .list()
              .where((entry) =>
                  p.basename(entry.path).startsWith('.dan-player-trim-'))
              .isEmpty,
          isTrue);
    });
    test('metadata failure never reaches commit or releases main playback',
        () async {
      final hash = await digest(source);
      final events = <String>[];
      await expectLater(
          performAudioTrim(
              MetadataTestAudio()..path = source.path,
              AudioTrimRequest(
                  destinationPath: source.path,
                  startSeconds: .4,
                  endSeconds: 2,
                  overwrite: true),
              operations: operations(events: events, failMetadata: true)),
          throwsStateError);
      expect(await digest(source), hash);
      expect(events, ['metadata']);
    });
    test(
        'failed index sync reports an already saved file without retrying commit',
        () async {
      final events = <String>[];
      final result = await performAudioTrim(
          MetadataTestAudio()..path = source.path,
          AudioTrimRequest(
              destinationPath: source.path,
              startSeconds: .4,
              endSeconds: 2,
              overwrite: true),
          operations: operations(events: events, failSync: true));
      expect(result.libraryUpdated, isFalse);
      expect(result.warning, isNotNull);
      expect(events, ['metadata', 'release', 'commit', 'sync', 'restore:0.4']);
      expect(await File(result.path).exists(), isTrue);
    });
    test('cancellation reaps a running encoder', () async {
      final cancellation = AudioTrimCancellation();
      final pending = runAudioTool(
          'ffmpeg',
          [
            '-v',
            'error',
            '-re',
            '-f',
            'lavfi',
            '-i',
            'anullsrc=r=48000:cl=stereo',
            '-t',
            '60',
            '-f',
            'null',
            '-'
          ],
          cancellation: cancellation,
          resolve: resolve);
      Timer(const Duration(milliseconds: 200), cancellation.cancel);
      await expectLater(
          pending,
          throwsA(isA<AudioTrimException>()
              .having((e) => e.code, 'code', 'cancelled')));
    });
  });
}
