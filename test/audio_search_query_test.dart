import 'dart:async';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/search/audio_search_index.dart';
import 'package:dan_player/search/audio_search_query.dart';
import 'package:flutter_test/flutter_test.dart';

Audio song(
        String title, String artist, String album, String path, int duration) =>
    Audio(title, artist, album, 1, duration, 320, 44100, path, 1, 1, 'test');

void main() {
  late Audio chinese;
  late Audio accent;
  late Audio live;
  late AudioSearchIndex index;
  setUp(() {
    chinese = song('青花瓷', '周杰伦', '我很忙', 'C:/Music/Studio/青花瓷.flac', 240);
    accent = song('Café Love Story', 'Beyoncé', 'Démo',
        'C:/Music/Studio/Café Love Story.mp3', 180);
    live = song('Love Story Live', 'Beyoncé', 'Concert',
        'C:/Music/Live/love.flac', 301);
    final library = AudioLibrary.instance;
    library.audioCollection
      ..clear()
      ..addAll([chinese, accent, live]);
    library.artistCollection
      ..clear()
      ..addAll({
        '周杰伦': Artist(name: '周杰伦')..works.add(chinese),
        'Beyoncé': Artist(name: 'Beyoncé')..works.addAll([accent, live]),
      });
    library.albumCollection
      ..clear()
      ..addAll({
        '我很忙': Album(name: '我很忙')..works.add(chinese),
        'Démo': Album(name: 'Démo')..works.add(accent),
      });
    AudioLibrary.searchRevision++;
    AudioLibrary.revision++;
    index = AudioSearchIndex.instance..ensureBuiltSync();
  });
  tearDown(() {
    AudioLibrary.instance.audioCollection.clear();
    AudioLibrary.instance.artistCollection.clear();
    AudioLibrary.instance.albumCollection.clear();
    AudioLibrary.searchRevision++;
    AudioLibrary.revision++;
  });

  test('plain multiword queries retain phrase and pinyin scoring', () {
    expect(AudioSearchQuery.parse('love story').hasStructuredSyntax, isFalse);
    expect(index.searchAudios('love story'), [live, accent]);
    expect(index.searchAudios('qhc'), [chinese]);
    expect(AudioSearchQuery.parse(r'C:\Music').hasStructuredSyntax, isFalse);
    expect(AudioSearchQuery.parse('AC:DC').hasStructuredSyntax, isFalse);
  });

  test('field filters match only their intended tags and combine with AND', () {
    expect(index.searchAudios('title:qhc artist:zjl album:whm'), [chinese]);
    expect(index.searchAudios('title:beyonce'), isEmpty);
    expect(index.searchAudios('artist:beyonce album:demo'), [accent]);
    expect(index.searchArtists('artist:beyonce').single.name, 'Beyoncé');
    expect(index.searchAlbums('album:demo').single.name, 'Démo');
    expect(index.searchArtists('-title:live'), isEmpty);
    expect(index.searchAlbums('format:mp3'), isEmpty);
  });

  test(
      'folder excludes filename while path includes it and accepts either slash',
      () {
    expect(
        index.searchAudios(r'folder:"C:\Music\Studio" format:flac'), [chinese]);
    expect(index.searchAudios('folder:love'), isEmpty);
    expect(index.searchAudios('path:"cafe love"'), [accent]);
    expect(index.searchAudios('folder:live'), [live]);
  });

  test('format uses exact source extension and comma-separated alternatives',
      () {
    expect(index.searchAudios('format:.MP3'), [accent]);
    expect(index.searchAudios('format:fl'), isEmpty);
    expect(index.searchAudios('format:flac,mp3', limit: 2), hasLength(2));
  });

  test(
      'quoted Windows folders keep trailing separators and CUE filters use source audio',
      () {
    expect(
        index.searchAudios(r'folder:"C:\Music\Studio\" format:mp3'), [accent]);
    final cue = Audio(
        'CUE song', '', '', 1, 210, 800, 44100, 'cue://track/1', 1, 1, 'test',
        cueTrack: const CueTrackReference(
            cuePath: r'C:\Music\disc.cue',
            sourcePath: r'C:\Music\disc.flac',
            number: 1,
            startFrame: 0,
            endFrame: 15750));
    AudioLibrary.instance.audioCollection.add(cue);
    AudioLibrary.searchRevision++;
    index.ensureBuiltSync();
    expect(
        index.searchAudios(
            'title:"cue song" format:flac path:disc.flac duration:210'),
        [cue]);
    expect(index.searchAudios('title:"cue song" format:cue'), isEmpty);
  });

  test('duration handles inclusive ranges, strict bounds and exact seconds',
      () {
    expect(index.searchAudios('duration:3:00..4:00'),
        containsAll([accent, chinese]));
    expect(index.searchAudios('duration:>4:00'), [live]);
    expect(index.searchAudios('duration:>=4:00'), containsAll([chinese, live]));
    expect(index.searchAudios('duration:<180'), isEmpty);
    expect(index.searchAudios('duration:<=180'), [accent]);
    expect(index.searchAudios('duration:0:03:00'), [accent]);
    expect(index.searchAudios('duration:240'), [chinese]);
  });

  test('duration-only publication updates filters without changing cached text',
      () {
    accent
      ..duration = 302
      ..title = 'unpublished rename';
    AudioLibrary.instance.publishDurationChanges();
    expect(index.searchAudios('title:cafe duration:>300'), [accent]);
    expect(index.searchAudios('title:unpublished'), isEmpty);
  });

  test(
      'unknown durations never imply short or long tracks including exclusions',
      () {
    accent.duration = 0;
    AudioLibrary.instance.publishDurationChanges();
    expect(index.searchAudios('duration:<180'), isEmpty);
    expect(index.searchAudios('-duration:<180'), isNot(contains(accent)));
    expect(index.searchAudios('duration:0'), isEmpty);
  });

  test('file filters never interpret provider identities as local files', () {
    final remote = Audio.online(
        provider: 'demo',
        id: 'live.mp3',
        title: 'Remote',
        artist: '',
        album: '',
        duration: 220);
    AudioLibrary.instance.audioCollection.add(remote);
    AudioLibrary.searchRevision++;
    index.ensureBuiltSync();
    for (final query in [
      'path:online',
      'folder:demo',
      'format:mp3',
      '-format:flac',
      '-path:unmatched'
    ]) {
      expect(index.searchAudios(query), isNot(contains(remote)), reason: query);
    }
  });

  test('negation filters metadata and supports exclusion-only queries', () {
    expect(index.searchAudios('artist:beyonce -live'), [accent]);
    expect(index.searchAudios('-format:mp3'), containsAll([chinese, live]));
    expect(index.searchAudios('format:flac -artist:zjl'), [live]);
    expect(index.searchAudios('artist:beyonce -duration:>300'), [accent]);
  });

  test('quoted phrases are literal, not pinyin or compact approximations', () {
    expect(index.searchAudios('title:"love story" -live'), [accent]);
    expect(index.searchAudios('"qhc"'), isEmpty);
    expect(index.searchAudios('"love  story"'), isEmpty);
    expect(() => index.searchAudios('""'),
        throwsA(isA<AudioSearchQueryException>()));
  });

  test(
      'leading quoted minus and field names remain literal while exclusions accept phrases',
      () {
    expect(AudioSearchQuery.parse('"-live"').terms.single.negative, isFalse);
    expect(AudioSearchQuery.parse('"title:live"').terms.single.field, isEmpty);
    expect(index.searchAudios('artist:beyonce -"love story live"'), [accent]);
  });

  test('Latin accents, decomposed accents and fullwidth text match', () {
    expect(index.searchAudios('cafe'), [accent]);
    expect(index.searchAudios('cafe\u0301'), [accent]);
    expect(index.searchAudios('ＣＡＦＥ'), [accent]);
    expect(index.searchAudios('ＡＲＴＩＳＴ：ＢＥＹＯＮＣＥ -title:live'), [accent]);
  });

  test('malformed filters report actionable errors rather than broad matches',
      () {
    for (final query in [
      'title:',
      '"unfinished',
      'format:mp3,',
      'duration:1:60',
      'duration:5:00..3:00',
      'duration:fast',
      'duration:..300',
      'duration:1..2..3',
      'duration:999999999999999999:59',
      'duration:2147483648'
    ]) {
      expect(() => AudioSearchQuery.parse(query),
          throwsA(isA<AudioSearchQueryException>()),
          reason: query);
    }
  });

  test('structured scoring yields and cancels with the existing token',
      () async {
    AudioLibrary.instance.audioCollection.addAll([
      for (var i = 0; i < 800; i++)
        song('extra $i', 'demo', '', 'C:/Music/$i.flac', 220)
    ]);
    AudioLibrary.searchRevision++;
    index.ensureBuiltSync();
    var cancelled = false;
    var checks = 0;
    await expectLater(
        index.searchAll('format:flac duration:>180', checkCancelled: () {
          if (cancelled) throw StateError('cancelled');
          if (++checks == 3) Timer.run(() => cancelled = true);
        }),
        throwsA(isA<StateError>()));
    expect(checks, lessThan(8));
  });

  test('duration publication during chunking retries one coherent query',
      () async {
    AudioLibrary.instance.audioCollection.addAll([
      for (var i = 0; i < 600; i++)
        song('extra $i', '', '', 'C:/Music/$i.flac', 150)
    ]);
    AudioLibrary.searchRevision++;
    index.ensureBuiltSync();
    var checks = 0;
    final result = await index.searchAll('duration:>300', checkCancelled: () {
      if (++checks == 4) {
        accent.duration = 302;
        AudioLibrary.instance.publishDurationChanges();
      }
    });
    expect(result.audios, containsAll([accent, live]));
    expect(result.audios, hasLength(2));
  });
}
