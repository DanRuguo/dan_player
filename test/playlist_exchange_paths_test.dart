import 'package:dan_player/library/playlist_exchange.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HLS tags reject the whole file, including local audio segments', () {
    for (final document in [
      '#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\nsegment.aac',
      '#EXTM3U\nFirst.mp3\n#ext-x-endlist',
    ]) {
      expect(
          () => parseM3u(document, playlistPath: r'C:\Lists\hls.m3u8'),
          throwsA(isA<FormatException>().having((error) => error.message,
              'message', '此文件是 HLS 流媒体清单，不能作为本地歌单导入。')));
    }
  });

  test('UNC references round trip across shares and local playlist drives', () {
    const paths = [
      r'\\nas\Music\Canon.flac',
      r'\\other\Audio\Good Time.mp3',
      r'\\nas\Music\Canon.flac',
    ];
    for (final location in [r'C:\Lists\mix.m3u8', r'\\nas\Music\mix.m3u8']) {
      for (final relative in [true, false]) {
        final encoded = encodeM3u(paths.map(M3uEntry.new),
            playlistPath: location, relative: relative);
        expect(
            parseM3u(encoded, playlistPath: location)
                .entries
                .map((e) => e.path),
            paths);
      }
    }
    final external = parseM3u(
        '//nas/Music/Canon.flac\nfile://nas/Music/Good%20Time.mp3',
        playlistPath: r'C:\Lists\mix.m3u8');
    expect(external.entries.map((e) => e.path),
        [r'\\nas\Music\Canon.flac', r'\\nas\Music\Good Time.mp3']);
  });

  test('drive-root and relative paths resolve against the playlist location',
      () {
    final parsed = parseM3u(
        '\\Music\\Canon.flac\n/Music/Good Time.mp3\n../Other/Track.aifc\nD:/Music/Last.mp3',
        playlistPath: r'C:\Lists\mix.m3u8');
    expect(parsed.entries.map((e) => e.path), [
      r'C:\Music\Canon.flac',
      r'C:\Music\Good Time.mp3',
      r'C:\Other\Track.aifc',
      r'D:\Music\Last.mp3',
    ]);
    final share = parseM3u('/Music/Canon.flac',
        playlistPath: r'\\nas\share\Lists\mix.m3u8');
    expect(share.entries.single.path, r'\\nas\share\Music\Canon.flac');
    expect(isM3uLocalAudioPath(r'\Music\Canon.flac'), isFalse);
    expect(isM3uLocalAudioPath(r'C:Music\Canon.flac'), isFalse);
    expect(isM3uLocalAudioPath('Music/Canon.flac'), isFalse);
  });

  test('decoded file URI controls and unsupported exports never silently pass',
      () {
    for (final escape in ['%00', '%0A', '%0D', '%09', '%7F']) {
      final path = 'file:///C:/Music/${escape}Track.mp3';
      expect(isM3uLocalAudioPath(path), isFalse);
      final parsed = parseM3u(path, playlistPath: r'C:\Lists\mix.m3u8');
      expect(parsed.entries, isEmpty);
      expect(parsed.skipped, 1);
    }
    expect(isM3uLocalAudioPath('file:///C:/Music/Good%20Time.mp3'), isTrue);
    expect(isM3uLocalAudioPath('https://example.invalid/track.mp3'), isFalse);
    expect(isM3uLocalAudioPath(r'C:\Music\notes.txt'), isFalse);
    expect(
        () => encodeM3u(const [M3uEntry(r'C:\Music\notes.txt')],
            playlistPath: r'C:\Lists\mix.m3u8'),
        throwsFormatException);
  });

  test('all scanner formats remain exportable and are counted without drops',
      () {
    const extensions = [
      'mp3',
      'mp2',
      'mp1',
      'ogg',
      'wav',
      'wave',
      'aif',
      'aiff',
      'aifc',
      'asf',
      'wma',
      'aac',
      'adts',
      'm4a',
      'ac3',
      'amr',
      '3ga',
      'flac',
      'mpc',
      'mid',
      'wv',
      'wvc',
      'opus',
      'dsf',
      'dff',
      'ape',
    ];
    final paths = [
      for (final extension in extensions) 'C:\\Music\\Track.$extension'
    ];
    expect(paths.every(isM3uLocalAudioPath), isTrue);
    final encoded =
        encodeM3u(paths.map(M3uEntry.new), playlistPath: r'C:\Lists\mix.m3u8');
    final decoded = parseM3u(encoded, playlistPath: r'C:\Lists\mix.m3u8');
    expect(decoded.skipped, 0);
    expect(decoded.entries.map((e) => e.path), paths);
  });
}
