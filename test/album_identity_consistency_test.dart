import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/search/audio_search_index.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/music_category_fixtures.dart';

void main() {
  final library = AudioLibrary.instance;
  late List<AudioFolder> folders;
  late List<Audio> online;
  setUp(() {
    folders = library.folders;
    online = library.onlineAudioCollection;
  });
  tearDown(() {
    library.folders = folders;
    library.onlineAudioCollection = online;
    library.rebuildDerivedCollections();
  });
  void load(List<Audio> audios) {
    library.folders = [AudioFolder(audios, 'J:/fixture/music', 0, 0)];
    library.onlineAudioCollection = [];
    library.rebuildDerivedCollections();
    AudioSearchIndex.instance.ensureBuiltSync();
  }

  test(
      'same album title has identical distinct scopes in search category and song lookup',
      () {
    final a =
        CategoryTestAudio('first', artist: 'Artist A', album: 'Same Album');
    final b =
        CategoryTestAudio('second', artist: 'Artist B', album: 'Same Album');
    load([a, b]);
    final categories = LibraryMusicCategories.groups(MusicCategoryKind.album);
    final results = AudioSearchIndex.instance.searchAlbums('Same Album');
    expect(categories.length, 2);
    expect(library.albumCollection.keys.toSet(),
        categories.map((group) => group.id).toSet());
    expect(results.map((album) => album.groupId).toSet(),
        library.albumCollection.keys.toSet());
    expect(results.map((album) => album.albumArtist).toSet(),
        {'Artist A', 'Artist B'});
    expect(library.albumCollection[a.albumIdentity.id]!.works, [a]);
    expect(library.albumCollection[b.albumIdentity.id]!.works, [b]);
    expect(
        AudioSearchIndex.instance.searchAlbums('Artist B').single.works, [b]);
  });
  test(
      'common album artist compilation remains one group and track covers are ordered',
      () {
    final a = CategoryTestAudio('first',
        artist: 'Performer A',
        album: 'Compilation',
        albumArtist: 'Various Artists',
        track: 2);
    final b = CategoryTestAudio('second',
        artist: 'Performer B',
        album: 'Compilation',
        albumArtist: 'Various Artists',
        track: 1);
    load([a, b]);
    expect(library.albumCollection.length, 1);
    expect(AudioSearchIndex.instance.searchAlbums('Compilation').single.works,
        [a, b]);
    final group = LibraryMusicCategories.groups(MusicCategoryKind.album).single;
    expect(group.coverAudio, same(b));
    expect(library.artistCollection['Performer A']!.albumsMap.keys, [group.id]);
    expect(
        MusicCategories.albumGroupFor(b, library.audioCollection).id, group.id);
  });
  test(
      'unknown tags and whitespace keep existing fallback without guessing editions',
      () {
    final a = CategoryTestAudio('first', artist: ' UNKNOWN ', album: '');
    final b = CategoryTestAudio('second', artist: '', album: 'unknown');
    load([a, b]);
    expect(library.albumCollection.length, 1);
    final album = library.albumCollection.values.single;
    expect(album.name, '未知专辑');
    expect(album.albumArtist, '未知专辑艺术家');
    expect(album.groupId,
        LibraryMusicCategories.groups(MusicCategoryKind.album).single.id);
  });
}
