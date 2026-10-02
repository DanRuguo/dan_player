import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/library/loudness_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

Audio track(String path, {CueTrackReference? cue, int duration = 6}) =>
    Audio('Tone', 'Fixture', 'QA', 1, duration, 1536, 48000, path, 0, 0, 'QA',
        cueTrack: cue);

const summary = '''
[Parsed_ebur128_0] Summary:
  Integrated loudness:
    I:         -21.1 LUFS
    Threshold: -31.1 LUFS
  Loudness range:
    LRA:         0.0 LU
    Threshold: -41.1 LUFS
  Sample peak:
    Peak:      -21.1 dBFS
  True peak:
    Peak:      -20.9 dBFS
''';

void main() {
  test('uses final complete R128 summary and caps reference gain by true peak',
      () {
    final report = parseLoudnessSummary('$summary\n$summary');
    expect(report.integratedLufs, -21.1);
    expect(report.truePeakDb, -20.9);
    expect(report.suggestedGain(-18), closeTo(3.1, 1e-8));
    expect(report.suggestedGain(-23), closeTo(-1.9, 1e-8));
    final nearPeak =
        parseLoudnessSummary(summary.replaceAll('-20.9 dBFS', '-0.2 dBFS'));
    expect(nearPeak.suggestedGain(-18), closeTo(-.8, 1e-8));
    expect(() => report.suggestedGain(double.nan), throwsArgumentError);
  });

  test('silence and below gate never become a gain or infinite UI values', () {
    final silent = parseLoudnessSummary(summary
        .replaceAll('-21.1 LUFS', '-70.0 LUFS')
        .replaceAll('-21.1 dBFS', '-inf dBFS')
        .replaceAll('-20.9 dBFS', '-inf dBFS'));
    expect(silent.integratedLufs, isNull);
    expect(silent.samplePeakDb, isNull);
    expect(silent.truePeakDb, isNull);
    expect(silent.suggestedGain(-18), isNull);
  });

  test('missing, truncated and invalid metrics reject the whole report', () {
    for (final log in [
      '',
      summary.replaceAll('Summary:', ''),
      '$summary\nSummary: incomplete',
      summary.replaceAll('-20.9 dBFS', 'inf dBFS'),
      summary.replaceAll('0.0 LU', '-1.0 LU'),
      summary.replaceAll('-21.1 LUFS', 'NaN LUFS')
    ]) {
      expect(() => parseLoudnessSummary(log),
          throwsA(isA<LoudnessAnalysisException>()));
    }
  });

  test(
      'CUE selects exact segment before R128 with argv path and no output file',
      () {
    const cue = CueTrackReference(
        cuePath: r'J:\QA\test.cue',
        sourcePath: r'J:\QA\file & unicode 音乐.wav',
        number: 2,
        startFrame: 150,
        endFrame: 375);
    final args = loudnessArguments(track(cue.identity, cue: cue));
    expect(args[args.indexOf('-i') + 1], cue.sourcePath);
    expect(
        args[args.indexOf('-af') + 1],
        startsWith(
            'atrim=start=2.000000000:end=5.000000000,asetpts=PTS-STARTPTS,ebur128'));
    expect(args.sublist(args.length - 3), ['-f', 'null', '-']);
    expect(args, containsAll(['-nostdin', '-vn', '-sn', '-dn']));
  });

  final ffmpeg = Platform.environment['DAN_LOUDNESS_FFMPEG'];
  final qa = Platform.environment['DAN_LOUDNESS_QA'];
  final native = ffmpeg != null && qa != null;
  late Directory directory;
  late File tone, silence, longTone;
  setUpAll(() async {
    if (!native) return;
    directory = Directory(qa);
    await directory.create(recursive: true);
    tone = File('${directory.path}/tone & Unicode 音乐.wav');
    silence = File('${directory.path}/silence.wav');
    longTone = File('${directory.path}/long.wav');
    for (final item in [
      (tone, 'sine=frequency=1000:sample_rate=48000:duration=6'),
      (silence, 'anullsrc=r=48000:cl=stereo:d=3'),
      (longTone, 'sine=frequency=1000:sample_rate=48000:duration=180')
    ]) {
      final result = await Process.run(ffmpeg, [
        '-nostdin',
        '-v',
        'error',
        '-f',
        'lavfi',
        '-i',
        item.$2,
        '-ac',
        '2',
        '-c:a',
        'pcm_s16le',
        '-y',
        item.$1.path
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }
  });

  test('real FFmpeg tone/silence/CUE and short gate stay read only', () async {
    final before = await tone.readAsBytes();
    final analyzer = LoudnessAnalyzer(executable: ffmpeg);
    final progress = <double>[];
    final result = await analyzer.analyze(
        track(tone.path), LoudnessCancellation(),
        onProgress: progress.add);
    expect(result.integratedLufs, closeTo(-21.1, .15));
    expect(result.truePeakDb, closeTo(-21.1, .15));
    expect(result.analyzedSeconds, closeTo(6, .001));
    expect(progress.last, 1);
    final silent =
        await analyzer.analyze(track(silence.path), LoudnessCancellation());
    expect(silent.integratedLufs, isNull);
    expect(silent.truePeakDb, isNull);
    const start = 150, end = 375;
    final cue = CueTrackReference(
        cuePath: '${directory.path}/fixture.cue',
        sourcePath: tone.path,
        number: 2,
        startFrame: start,
        endFrame: end);
    final segment = await analyzer.analyze(
        track(cue.identity, cue: cue), LoudnessCancellation());
    expect(segment.analyzedSeconds, closeTo(3, .001));
    expect(segment.integratedLufs, closeTo(result.integratedLufs!, .1));
    final shortCue = CueTrackReference(
        cuePath: cue.cuePath,
        sourcePath: tone.path,
        number: 3,
        startFrame: 0,
        endFrame: 15);
    expect(
        (await analyzer.analyze(track(shortCue.identity, cue: shortCue),
                LoudnessCancellation()))
            .integratedLufs,
        isNull);
    expect(await tone.readAsBytes(), before);
  }, skip: !native);

  test(
      'real invalid CUE ranges do not report silent or partial source as successful',
      () async {
    final analyzer = LoudnessAnalyzer(executable: ffmpeg);
    for (final bounds in [(750, 825), (375, 750)]) {
      final cue = CueTrackReference(
          cuePath: '${directory.path}/fixture.cue',
          sourcePath: tone.path,
          number: 2,
          startFrame: bounds.$1,
          endFrame: bounds.$2);
      await expectLater(
          analyzer.analyze(
              track(cue.identity, cue: cue), LoudnessCancellation()),
          throwsA(isA<LoudnessAnalysisException>()
              .having((e) => e.message, 'message', '歌曲范围超出音频文件，请检查分轨信息')));
    }
  }, skip: !native);

  test('real cancellation/timeout reap child and release exclusive scan lease',
      () async {
    final analyzer = LoudnessAnalyzer(executable: ffmpeg);
    final cancellation = LoudnessCancellation();
    final pending =
        analyzer.analyze(track(longTone.path, duration: 180), cancellation);
    await expectLater(
        analyzer.analyze(track(tone.path), LoudnessCancellation()),
        throwsA(isA<LoudnessAnalysisException>()
            .having((e) => e.message, 'message', '已有响度分析正在进行，请稍后重试')));
    cancellation.cancel();
    await expectLater(
        pending,
        throwsA(isA<LoudnessAnalysisException>()
            .having((e) => e.message, 'message', '已取消响度分析')));
    await expectLater(
        LoudnessAnalyzer(executable: ffmpeg, timeout: Duration.zero)
            .analyze(track(longTone.path), LoudnessCancellation()),
        throwsA(isA<LoudnessAnalysisException>()
            .having((e) => e.message, 'message', '响度分析超时，请重试')));
    expect(
        (await analyzer.analyze(track(tone.path), LoudnessCancellation()))
            .integratedLufs,
        isNotNull);
  }, skip: !native);

  test('real scan rejects changed source and does not retain progress timer',
      () async {
    var changed = false;
    final cancellation = LoudnessCancellation();
    final pending = LoudnessAnalyzer(executable: ffmpeg).analyze(
        track(longTone.path, duration: 180), cancellation, onProgress: (value) {
      if (!changed && value < 1) {
        changed = true;
        longTone.setLastModifiedSync(DateTime.utc(2020));
      }
    });
    await expectLater(
        pending,
        throwsA(isA<LoudnessAnalysisException>()
            .having((e) => e.message, 'message', '分析期间源文件已改变，请重新分析')));
    expect(changed, isTrue);
  }, skip: !native);
}
