import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/search/audio_search_index.dart';
import 'package:dan_player/utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pinyin sort-key cache stays bounded', () {
    for (var index = 0; index < debugSortKeyCacheLimit + 64; index++) {
      'track-$index'.localeCompareTo('track-${index + 1}');
    }

    expect(debugSortKeyCacheSize, lessThanOrEqualTo(debugSortKeyCacheLimit));
  });

  test('search build releases its temporary key interning pool', () {
    final library = AudioLibrary.instance;
    library.audioCollection
      ..clear()
      ..addAll(List.generate(
        96,
        (index) => Audio.online(
          provider: 'test',
          id: '$index',
          title: 'Track $index',
          artist: 'Artist ${index % 8}',
          album: 'Album ${index % 12}',
          duration: 180,
        ),
      ));
    AudioLibrary.searchRevision++;

    AudioSearchIndex.instance.ensureBuiltSync();

    expect(AudioSearchIndex.instance.debugCachedSearchKeyCount, 0);
    expect(AudioSearchIndex.instance.debugSearchKeyCacheLimit, greaterThan(0));
  });
}
