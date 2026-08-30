import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('online descriptor round-trips with a stable identity and added time',
      () {
    final audio = Audio.online(
      provider: 'netease',
      id: '123456',
      title: 'Test title',
      artist: 'Artist A',
      album: 'Album A',
      duration: 180,
      mediaId: 'media-id',
      artworkUrl: 'https://example.com/cover.jpg',
      created: 1700000000,
    );

    final restored = Audio.fromOnlineMap(audio.toOnlineMap());

    expect(restored.path, 'online://netease/123456');
    expect(restored.created, 1700000000);
    expect(restored.onlineMediaId, 'media-id');
    expect(restored.sourceLabel, '网易云音乐');
  });

  test('playlist preserves an online descriptor outside the total library', () {
    final audio = Audio.online(
      provider: 'qq',
      id: 'song/mid',
      title: 'Remote song',
      artist: 'Remote artist',
      album: 'Remote album',
      duration: 240,
      created: 1700000123,
    );
    final encoded = Playlist('Remote list', {audio.path: audio}).toMap();

    final restored = Playlist.fromMap(encoded);
    final restoredAudio = restored.audios.values.single;

    expect(restoredAudio.isOnline, isTrue);
    expect(restoredAudio.onlineProvider, 'qq');
    expect(restoredAudio.onlineId, 'song/mid');
    expect(restoredAudio.created, 1700000123);
    expect(restoredAudio.path, audio.path);
  });

  test('legacy online playlist paths do not become fake local files', () {
    final playlist = Playlist.fromMap({
      'name': 'Legacy',
      'audios': [
        {
          'path': 'online://netease/9988',
          'title': 'Legacy remote',
          'artist': 'Artist',
          'album': 'Album',
          'duration': 90,
        },
      ],
    });

    expect(playlist.audios.values.single.isOnline, isTrue);
    expect(playlist.audios.values.single.onlineId, '9988');
  });
}
