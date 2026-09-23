import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/play_service/lyric_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Lyric lyric(String content) =>
      Lrc.fromLrcText('[00:01.00]$content', LrcSource.local)!;

  test('a tag edit retains the same automatic online cache identity', () {
    final audio = Audio.online(
      provider: 'netease',
      id: '456',
      title: 'old title',
      artist: 'old artist',
      album: 'old album',
      duration: 180,
      created: 0,
    );
    final before = onlineLyricCacheIdentity(audio);
    audio.title = 'new title';
    audio.artist = 'new artist';
    audio.album = 'new album';
    expect(onlineLyricCacheIdentity(audio), before);
    expect(
        onlineLyricCacheIdentity(audio,
            source: LyricSource(LyricSourceType.netease, neteaseSongId: '456')),
        isNot(before));
    expect(
        onlineLyricCacheIdentity(Audio.online(
          provider: 'netease',
          id: '457',
          title: 'new title',
          artist: 'new artist',
          album: 'new album',
          duration: 180,
          created: 0,
        )),
        isNot(before));
  });

  for (final localFirst in [true, false]) {
    test('local or cached lyrics block an automatic search ($localFirst)',
        () async {
      final calls = <String>[];
      final result = await resolveAutomaticLyricSources(
        localFirst: localFirst,
        local: () async {
          calls.add('local');
          return lyric('local');
        },
        cachedOnline: () async {
          calls.add('cached');
          return lyric('cached');
        },
      );
      expect(calls, localFirst ? ['local'] : ['cached']);
      expect((result!.lines.single as UnsyncLyricLine).content,
          localFirst ? 'local' : 'cached');
    });
  }

  test('online-first falls back to local without searching after cache miss',
      () async {
    final calls = <String>[];
    final result = await resolveAutomaticLyricSources(
      localFirst: false,
      cachedOnline: () async {
        calls.add('cached');
        return null;
      },
      local: () async {
        calls.add('local');
        return lyric('local');
      },
    );
    expect(calls, ['cached', 'local']);
    expect((result!.lines.single as UnsyncLyricLine).content, 'local');
  });

  test('a track without either saved source waits for a manual lyric search',
      () async {
    final calls = <String>[];
    final result = await resolveAutomaticLyricSources(
      localFirst: true,
      local: () async {
        calls.add('local');
        return null;
      },
      cachedOnline: () async {
        calls.add('cached');
        return null;
      },
    );
    expect(calls, ['local', 'cached']);
    expect(result, isNull);
  });
}
