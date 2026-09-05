import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/smart_playlist.dart';
import 'package:flutter_test/flutter_test.dart';

Audio track(String path,
        {String title = 'Canon',
        String artist = 'Artist',
        String album = 'Album',
        int duration = 180,
        int created = 1}) =>
    Audio.fromMap({
      'path': path,
      'title': title,
      'artist': artist,
      'album': album,
      'duration': duration,
      'created': created,
    });

void main() {
  test(
      'saved conditions combine metadata, formats and duration; refresh is live',
      () async {
    const rule = SmartPlaylist(
        id: 'one',
        name: 'Short FLAC',
        query: 'canon artist',
        artist: 'ARTIST',
        album: 'album',
        formats: '.flac, wav',
        minSeconds: 60,
        maxSeconds: 200);
    final a = track(r'C:\Music\First.FLAC');
    final b = track(r'C:\Music\Second.wav', duration: 300);
    final c = track(r'C:\Music\Third.mp3');
    expect(await rule.evaluate([a, b, c]), [same(a)]);
    final d = track(r'C:\Music\New.wav', duration: 120);
    expect(await rule.evaluate([a, b, c, d]), [same(a), same(d)]);
    expect((await rule.evaluate([d])).single, same(d));
  });

  test(
      'online entries are excluded; scalar sort preserves original Audio references',
      () async {
    final a = track(r'C:\A.wav', created: 20, duration: 60);
    final b = track(r'C:\B.wav', created: 40, duration: 30);
    final online = Audio.online(
        provider: 'qq',
        id: '123',
        title: 'Song',
        artist: 'A',
        album: 'B',
        duration: 10);
    expect(
        await const SmartPlaylist(
                id: 'x', name: 'Recent', sort: SmartPlaylistSort.newest)
            .evaluate([a, b, online]),
        [same(b), same(a)]);
    expect(
        await const SmartPlaylist(
                id: 'x', name: 'Length', sort: SmartPlaylistSort.duration)
            .evaluate([a, b]),
        [same(b), same(a)]);
  });

  test('large evaluations yield and obsolete previews can cancel', () async {
    final library =
        List.generate(10000, (index) => track('C:\\Music\\$index.wav'));
    var cancelled = false;
    final future = const SmartPlaylist(id: 'x', name: 'All')
        .evaluate(library, shouldCancel: () => cancelled);
    cancelled = true;
    expect(await future, isEmpty);
  });

  test('serialized edits survive restart and recover the last good backup',
      () async {
    final directory = await Directory.systemTemp.createTemp('dan-smart-store-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/smart_playlists.json');
    final store = SmartPlaylistStore(file);
    await Future.wait([
      store.upsert(const SmartPlaylist(id: 'a', name: 'First')),
      store.upsert(const SmartPlaylist(id: 'b', name: 'Second')),
    ]);
    expect(
        (await SmartPlaylistStore(file).list()).map((p) => p.id), ['a', 'b']);
    await file.writeAsString('{damaged');
    final recovered = SmartPlaylistStore(file);
    expect((await recovered.list()).map((p) => p.id), ['a']);
    await recovered.upsert(const SmartPlaylist(id: 'c', name: 'Recovered'));
    expect(
        (await SmartPlaylistStore(file).list()).map((p) => p.id), ['a', 'c']);
  });

  test('write failure preserves memory and disk, then permits retry', () async {
    final directory = await Directory.systemTemp.createTemp('dan-smart-retry-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/smart_playlists.json');
    final store = SmartPlaylistStore(file);
    await store.upsert(const SmartPlaylist(id: 'a', name: 'Old'));
    final obstruction = Directory('${file.path}.tmp');
    await obstruction.create();
    await expectLater(
        store.upsert(const SmartPlaylist(id: 'a', name: 'Changed')),
        throwsA(isA<FileSystemException>()));
    expect((await store.list()).single.name, 'Old');
    expect((await SmartPlaylistStore(file).list()).single.name, 'Old');
    await obstruction.delete();
    await store.upsert(const SmartPlaylist(id: 'a', name: 'Changed'));
    expect((await SmartPlaylistStore(file).list()).single.name, 'Changed');
  });

  test('invalid rules and oversized corrupt files cannot replace stored data',
      () async {
    expect(
        const SmartPlaylist(
                id: 'x', name: 'Bad', minSeconds: 200, maxSeconds: 20)
            .validate(),
        isNotNull);
    final directory =
        await Directory.systemTemp.createTemp('dan-smart-bounds-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/smart_playlists.json');
    await file.writeAsString('x' * (SmartPlaylistStore.maxBytes + 1));
    await expectLater(
        SmartPlaylistStore(file)
            .upsert(const SmartPlaylist(id: 'a', name: 'New')),
        throwsFormatException);
    expect(await file.length(), SmartPlaylistStore.maxBytes + 1);
    expect(() => SmartPlaylist.fromJson(jsonDecode('{"id":"x"}')),
        throwsFormatException);
  });
}
