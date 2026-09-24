import 'dart:io';
import 'package:dan_player/lyric/lyric_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'native slow preview clock maps back to source time at every supported rate',
      () async {
    final dir = await Directory.systemTemp.createTemp('tap-rate-');
    addTearDown(() => dir.delete(recursive: true));
    final root = Platform.environment['DAN_PLAYER_FFMPEG_DIR']!;
    final file = '${dir.path}/tone.wav';
    final generated = await Process.run('$root/ffmpeg.exe', [
      '-v',
      'error',
      '-y',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=440:sample_rate=44100',
      '-t',
      '5',
      file
    ]);
    expect(generated.exitCode, 0);
    for (final rate in [.25, .5, .75, 1.0]) {
      final clock = Stopwatch()..start();
      final points = <({double wall, double media})>[];
      final process = await launchLyricPreview(file, 1, 2, (position) {
        points.add((wall: clock.elapsedMicroseconds / 1e6, media: position));
      }, rate: rate);
      final code = await process.exitCode.timeout(const Duration(seconds: 14),
          onTimeout: () {
        process.kill();
        return -1;
      });
      expect(code, 0, reason: '$rate');
      expect(points.length, greaterThan(8));
      expect(points.first.media, closeTo(1, .2));
      final first = points[2], last = points[points.length - 2];
      expect((last.media - first.media) / (last.wall - first.wall),
          closeTo(rate, .12),
          reason: '$rate source clock');
      expect(last.media, inInclusiveRange(2.4, 3.2));
    }
  }, skip: Platform.environment['DAN_PLAYER_FFMPEG_DIR'] == null);
}
