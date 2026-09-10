import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/online/kugou_music_api.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/online/qq_public_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('live screenshot song keeps its selected artwork through enrichment',
      () async {
    final api = KugouMusicApi(CustomMusicSourceProfile.kugouPreset());
    final results = await api.search('哈基米泰曼波', limit: 5);
    final selected = results.tracks
        .firstWhere((song) => song.title == '哈基米泰曼波' && song.artist == '哈基米');
    final detailed = await api.metadata(selected);
    expect(selected.artworkUrl, isNotNull);
    expect(detailed.artworkUrl, selected.artworkUrl);
    stdout
        .writeln('Kugou: ${selected.title}; preserved ${detailed.artworkUrl}');

    final qq = await QqPublicSearchTransport().search('哈基米泰曼波', 5);
    expect(qq, isNotEmpty);
    final song = qq.firstWhere((song) => song.albumMid != null);
    final candidate = Audio.online(
      provider: 'qq',
      id: song.mid,
      title: song.title,
      artist: song.artists,
      album: song.album,
      duration: song.durationSeconds,
      artworkUrl:
          'https://y.qq.com/music/photo_new/T002R300x300M000${song.albumMid}.jpg',
    );
    final enriched =
        await OnlineMusicService.instance.refreshMetadata(candidate);
    expect(enriched.artworkUrl, candidate.artworkUrl);
    stdout.writeln('QQ: ${song.title}; preserved ${enriched.artworkUrl}');
  }, skip: Platform.environment['METADATA_COVER_LIVE_TEST'] != '1');
}
