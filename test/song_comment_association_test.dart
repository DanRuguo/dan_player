import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/online/song_comment_association.dart';
import 'package:dan_player/online/song_comments.dart';
import 'package:flutter_test/flutter_test.dart';

Audio _local(String path, {String title = '本地歌曲'}) => Audio(
      title,
      '演唱者',
      '专辑',
      0,
      180,
      320,
      44100,
      path,
      1,
      1,
      'test',
      composer: '作曲者',
      fileSizeBytes: 1024,
    );

Audio _online(String provider, String id, {int? numericId}) => Audio.online(
      provider: provider,
      id: id,
      numericId: numericId,
      title: '候选歌曲',
      artist: '候选演唱者',
      album: '候选专辑',
      composer: '候选作曲者',
      duration: 180,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  final store = SongCommentAssociationStore.instance;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dan-comment-binding-');
    store.resetForTesting();
    LYRIC_SOURCES.clear();
    await store.initialize(directory: root);
  });

  tearDown(() async {
    store.resetForTesting();
    LYRIC_SOURCES.clear();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('independent local association persists exact provider ID only',
      () async {
    final audio = _local(r'C:\Music\a.mp3');
    final lyricBefore = Map<String, LyricSource>.from(LYRIC_SOURCES);
    await store.setIndependent(audio, _online('netease', '123'));

    expect(store.identityFor(audio)?.identity, 'netease:123');
    expect(SongCommentsService.targetFor(audio)?.identity, 'netease:123');
    expect(store.associationFor(audio)?.composer, '候选作曲者');
    expect(LYRIC_SOURCES, lyricBefore,
        reason: 'choosing comments must not change lyric selection');

    store.resetForTesting();
    await store.initialize(directory: root);
    expect(store.identityFor(audio)?.identity, 'netease:123');
    final decoded = jsonDecode(await File(
            '${root.path}${Platform.pathSeparator}${SongCommentAssociationStore.fileName}')
        .readAsString()) as Map;
    expect(decoded['version'], 1);
    expect(jsonEncode(decoded), isNot(contains(audio.title)));
  });

  test('follow-lyric binding follows platform IDs but not lyric-only sources',
      () async {
    final audio = _local(r'C:\Music\follow.mp3');
    LYRIC_SOURCES[audio.path] = LyricSource(LyricSourceType.qq, qqSongId: 456);
    await store.followLyric(audio);
    expect(store.identityFor(audio)?.identity, 'qq:456');

    LYRIC_SOURCES[audio.path] =
        LyricSource(LyricSourceType.netease, neteaseSongId: '789');
    expect(store.identityFor(audio)?.identity, 'netease:789');

    LYRIC_SOURCES[audio.path] =
        LyricSource(LyricSourceType.kugou, kugouSongHash: 'hash');
    expect(store.identityFor(audio), isNull);

    LYRIC_SOURCES[audio.path] =
        LyricSource(LyricSourceType.lrclib, lrclibId: 38005804);
    expect(store.identityFor(audio), isNull,
        reason: 'LRCLIB has no supported comments identity');
    expect(SongCommentsService.unavailableReason(audio), contains('跟随联网歌词'));
  });

  test('independent binding remains stable when lyric source changes',
      () async {
    final audio = _local(r'C:\Music\independent.mp3');
    LYRIC_SOURCES[audio.path] = LyricSource(LyricSourceType.qq, qqSongId: 111);
    await store.setIndependent(audio, _online('netease', '222'));
    LYRIC_SOURCES[audio.path] = LyricSource(LyricSourceType.qq, qqSongId: 333);
    expect(store.identityFor(audio)?.identity, 'netease:222');
  });

  test('custom source keeps profile identity and opaque song ID', () async {
    final audio = _local(r'C:\Music\custom.mp3');
    final candidate = _online('custom:living-room', 'Track_42-v2');

    await store.setIndependent(audio, candidate);

    expect(store.identityFor(audio)?.provider, 'custom:living-room');
    expect(store.identityFor(audio)?.songId, 'Track_42-v2');
    expect(store.identityFor(audio)?.sourceLabel, '自定义歌源');

    store.resetForTesting();
    await store.initialize(directory: root);
    expect(
        store.identityFor(audio)?.identity, 'custom:living-room:Track_42-v2');
  });

  test('custom source rejects unsafe profile and song identifiers', () {
    expect(
      CommentSourceIdentity.tryCreate('custom:valid-profile', 'hash_123'),
      isNotNull,
    );
    expect(
      CommentSourceIdentity.tryCreate('custom:../profile', 'hash_123'),
      isNull,
    );
    expect(
      CommentSourceIdentity.tryCreate(
          'custom:valid-profile', r'C:\Music\song.mp3'),
      isNull,
    );
    expect(
      CommentSourceIdentity.tryCreate('custom:valid-profile', 'search words'),
      isNull,
    );
    expect(
      CommentSourceIdentity.tryCreate('custom:valid-profile', 'id?token=x'),
      isNull,
    );
  });

  test('app-created rename moves association without title guessing', () async {
    final audio = _local(r'C:\Music\old.mp3');
    await store.setIndependent(audio, _online('qq', 'mid', numericId: 987));
    await store.movePath(audio.path, r'C:\Music\new.mp3');
    final moved = _local(r'C:\Music\new.mp3');
    expect(store.associationFor(audio), isNull);
    expect(store.identityFor(moved)?.identity, 'qq:987');
  });

  test('bad rows are skipped and a valid backup is recovered', () async {
    final target = File(
        '${root.path}${Platform.pathSeparator}${SongCommentAssociationStore.fileName}');
    await target.writeAsString('{bad json');
    await File('${target.path}.bak').writeAsString(jsonEncode({
      'version': 1,
      'items': {
        r'c:\music\valid.mp3': {
          'mode': 'independent',
          'provider': 'netease',
          'songId': '42',
        },
        r'c:\music\invalid.mp3': {
          'mode': 'independent',
          'provider': 'qq',
          'songId': 'not-a-number',
        },
      },
    }));

    await store.initialize(directory: root);
    expect(store.identityFor(_local(r'C:\Music\valid.mp3'))?.identity,
        'netease:42');
    expect(store.identityFor(_local(r'C:\Music\invalid.mp3')), isNull);
  });

  test('rapid writes are serialized and leave parseable latest state',
      () async {
    final audio = _local(r'C:\Music\rapid.mp3');
    final first = store.setIndependent(audio, _online('netease', '1'));
    final second = store.setIndependent(audio, _online('netease', '2'));
    await Future.wait([first, second]);
    expect(store.identityFor(audio)?.identity, 'netease:2');
    final target = File(
        '${root.path}${Platform.pathSeparator}${SongCommentAssociationStore.fileName}');
    expect(jsonDecode(await target.readAsString()), isA<Map>());
  });
}
