import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Audio song(int index) => Audio.fromMap({
        'path': 'D:/Synthetic/track-$index.flac',
        'title': 'Song $index',
        'artist': 'Artist',
        'album': 'Album',
        'language': 'en',
      });

  test(
      'large-library file ranking matches measured totals and a full reference',
      () async {
    final audios = [for (var index = 0; index < 4000; index++) song(index)];
    final sizes = {
      for (var index = 0; index < audios.length; index++)
        audios[index].path: (index * 7919) % 4099,
    };
    var reads = 0;
    final snapshot = await LibraryStatisticsScanner(
      windowsPaths: true,
      inspectFile: (path) async {
        reads++;
        return LocalAudioFileInfo.available(sizes[path]!);
      },
      readLyrics: (_) async => throw StateError('known tags require no lyrics'),
    ).scan(audios);
    final reference = List<Audio>.of(audios)
      ..sort((a, b) => sizes[b.path]!.compareTo(sizes[a.path]!));
    expect(reads, audios.length);
    expect(snapshot.measuredLocalTracks, audios.length);
    expect(
        snapshot.totalLocalBytes, sizes.values.fold<int>(0, (a, b) => a + b));
    expect(snapshot.largestFiles.map((file) => file.path),
        reference.take(6).map((audio) => audio.path));
    expect(snapshot.largestFiles.map((file) => file.bytes),
        reference.take(6).map((audio) => sizes[audio.path]));
    expect(() => snapshot.largestFiles.clear(), throwsUnsupportedError);
  });

  test('a late large file displaces the cutoff while equal files stay readable',
      () async {
    final audios = [for (var index = 0; index < 12; index++) song(index)];
    final snapshot = await LibraryStatisticsScanner(
      windowsPaths: true,
      inspectFile: (path) async =>
          LocalAudioFileInfo.available(path == audios.last.path ? 200 : 100),
    ).scan(audios);
    expect(snapshot.totalLocalBytes, 1300);
    expect(snapshot.largestFiles.map((file) => file.path),
        [audios.last.path, ...audios.take(5).map((audio) => audio.path)]);
  });
}
