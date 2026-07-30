import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/search/audio_search_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Audio qingHuaCi;
  late Audio englishSong;

  setUp(() {
    qingHuaCi = Audio(
      "青花瓷",
      "周杰伦",
      "我很忙",
      1,
      240,
      320,
      44100,
      r"C:\Music\青花瓷.mp3",
      1,
      1,
      "test",
    );
    englishSong = Audio(
      "A Place Called You",
      "Taylor Swift",
      "Demo",
      2,
      210,
      320,
      44100,
      r"C:\Music\A Place Called You.mp3",
      1,
      1,
      "test",
    );

    final library = AudioLibrary.instance;
    library.audioCollection
      ..clear()
      ..addAll([qingHuaCi, englishSong]);
    library.artistCollection
      ..clear()
      ..addAll({
        "周杰伦": Artist(name: "周杰伦")..works.add(qingHuaCi),
        "Taylor Swift": Artist(name: "Taylor Swift")..works.add(englishSong),
      });
    library.albumCollection
      ..clear()
      ..addAll({
        "我很忙": Album(name: "我很忙")..works.add(qingHuaCi),
        "Demo": Album(name: "Demo")..works.add(englishSong),
      });
    AudioLibrary.revision++;
  });

  test("searches Chinese songs by full pinyin", () {
    final index = AudioSearchIndex.instance..ensureBuiltSync();
    expect(index.searchAudios("qinghuaci").first, same(qingHuaCi));
  });

  test("searches artists by pinyin initials", () {
    final index = AudioSearchIndex.instance..ensureBuiltSync();
    expect(index.searchArtists("zjl").first.name, "周杰伦");
  });

  test("keeps direct Latin search behavior", () {
    final index = AudioSearchIndex.instance..ensureBuiltSync();
    expect(index.searchAudios("place called").first, same(englishSong));
    expect(index.searchArtists("ts").first.name, "Taylor Swift");
  });
}
