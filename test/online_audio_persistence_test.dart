import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/artwork_image_provider.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:flutter/painting.dart';
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

  test('custom source identity and per-track permissions round-trip', () {
    final audio = Audio.online(
      provider: 'custom:home-server',
      id: 'track_42-v2',
      title: 'Custom track',
      artist: 'Artist',
      album: 'Album',
      duration: 200,
      playable: true,
      downloadAllowed: false,
    );

    final descriptor = audio.toOnlineMap();
    final restored = Audio.fromOnlineMap(descriptor);

    expect(restored.onlineProvider, 'custom:home-server');
    expect(restored.onlineId, 'track_42-v2');
    expect(restored.path, audio.path);
    expect(restored.onlinePlayable, isTrue);
    expect(restored.onlineDownloadAllowed, isFalse);
  });

  test('legacy descriptors leave per-track permissions unknown', () {
    final restored = Audio.fromOnlineMap({
      'provider': 'netease',
      'id': '9988',
      'title': 'Legacy remote',
      'artist': 'Artist',
      'album': 'Album',
      'duration': 90,
    });

    expect(restored.onlinePlayable, isNull);
    expect(restored.onlineDownloadAllowed, isNull);
    expect(restored.toOnlineMap().containsKey('playable'), isFalse);
    expect(restored.toOnlineMap().containsKey('downloadAllowed'), isFalse);
  });

  test('saved custom artwork obeys the live source enable and cover gates',
      () async {
    final previous = AppSettings.instance.customMusicSources.value;
    addTearDown(() => AppSettings.instance.customMusicSources.value = previous);
    final profile = CustomMusicSourceProfile.tryCreate(
      id: 'artwork-source',
      name: 'Artwork source',
      baseUrl: 'http://127.0.0.1:34567',
      capabilities: const {
        CustomMusicSourceCapability.search,
        CustomMusicSourceCapability.cover,
      },
      publicHeaders: const {'X-Client': 'Dan Player test'},
    )!;
    final audio = Audio.online(
      provider: profile.providerId,
      id: 'track-1',
      title: 'Track',
      artist: 'Artist',
      album: 'Album',
      duration: 90,
      artworkUrl: 'http://127.0.0.1:34567/cover.jpg',
    );

    AppSettings.instance.customMusicSources.value = [profile];
    expect(audio.canFetchRemoteArtwork, isTrue);
    final sameHost = await audio.artworkForSize(const ArtworkSize(64, 64))
        as ArtworkImageProvider;
    final sameHostSource = sameHost.source as CustomOnlineArtworkImageProvider;
    expect(sameHostSource.address, audio.artworkUrl);
    expect(identical(sameHostSource.expectedProfile, profile), isTrue);

    final external = Audio.online(
      provider: profile.providerId,
      id: 'track-2',
      title: 'Track',
      artist: 'Artist',
      album: 'Album',
      duration: 90,
      artworkUrl: 'https://images.example.test/cover.jpg',
    );
    final externalProvider = await external
        .artworkForSize(const ArtworkSize(64, 64)) as ArtworkImageProvider;
    final externalSource =
        externalProvider.source as CustomOnlineArtworkImageProvider;
    expect(identical(externalSource.expectedProfile, profile), isTrue);
    final externalCleartext = Audio.online(
      provider: profile.providerId,
      id: 'track-3',
      title: 'Track',
      artist: 'Artist',
      album: 'Album',
      duration: 90,
      artworkUrl: 'http://images.example.test/cover.jpg',
    );
    expect(
      await externalCleartext.artworkForSize(const ArtworkSize(64, 64)),
      isNull,
      reason: 'custom cleartext covers are limited to the self-hosted origin',
    );

    AppSettings.instance.customMusicSources.value = [
      profile.copyWith(enabled: false),
    ];
    expect(audio.canFetchRemoteArtwork, isFalse);
    expect(await audio.artworkForSize(const ArtworkSize(64, 64)), isNull);

    AppSettings.instance.customMusicSources.value = [
      CustomMusicSourceProfile.tryCreate(
        id: profile.id,
        name: profile.name,
        baseUrl: profile.baseUrl,
        capabilities: const {CustomMusicSourceCapability.search},
      )!,
    ];
    expect(audio.canFetchRemoteArtwork, isFalse);

    AppSettings.instance.customMusicSources.value = const [];
    expect(audio.canFetchRemoteArtwork, isFalse);
  });

  test('built-in saved artwork remains available when new search is disabled',
      () async {
    final audio = Audio.online(
      provider: 'qq',
      id: 'song-mid',
      title: 'Track',
      artist: 'Artist',
      album: 'Album',
      duration: 90,
      artworkUrl: 'https://example.test/cover.jpg',
    );

    expect(audio.canFetchRemoteArtwork, isTrue);
    final artwork = await audio.artworkForSize(const ArtworkSize(64, 64))
        as ArtworkImageProvider;
    expect(artwork.source, isA<NetworkImage>());
  });
}
