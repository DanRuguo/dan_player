import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/category_labels.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

void main() {
  test('empty libraries expose seven browsable classification kinds', () {
    final categories = MusicCategories([]);
    expect(MusicCategoryKind.browsableValues, hasLength(7));
    expect(MusicCategoryKind.browsableValues,
        isNot(contains(MusicCategoryKind.composer)));
    for (final kind in MusicCategoryKind.values) {
      expect(categories.groups(kind), isEmpty);
    }
  });

  test('legacy composer category names remain resolvable but are not browsable',
      () {
    expect(MusicCategoryKind.fromName('composer'), MusicCategoryKind.composer);
    expect(MusicCategoryKind.browsableValues,
        isNot(contains(MusicCategoryKind.fromName('composer'))));
  });

  test('artist and composer splitting uses the configured separator equally',
      () {
    final audio =
        CategoryTestAudio('a', artist: '甲、乙 / 甲', composer: 'A、B / A');
    final categories = MusicCategories([audio], artistSplitPattern: r'、|/');
    expect(
        categories.groups(MusicCategoryKind.artist).map((group) => group.title),
        ['乙', '甲']);
    expect(
        categories
            .groups(MusicCategoryKind.composer)
            .map((group) => group.title),
        ['A', 'B']);
    for (final group in categories.groups(MusicCategoryKind.artist)) {
      expect(group.audios, [same(audio)]);
    }
  });

  test('a comma is not silently treated as an extra artist separator', () {
    final audio =
        CategoryTestAudio('a', artist: 'Sakamoto, R', composer: '山田, 太郎');
    final categories = MusicCategories([audio], artistSplitPattern: r'/');
    expect(categories.groups(MusicCategoryKind.artist).single.title,
        'Sakamoto, R');
    expect(
        categories.groups(MusicCategoryKind.composer).single.title, '山田, 太郎');
  });

  test('broad composer category includes contributing artist fallback', () {
    final named = CategoryTestAudio('known', artist: 'Singer');
    final missing =
        CategoryTestAudio('missing', artist: ' UNKNOWN ', composer: ' ');
    final categories = MusicCategories([named, missing]);
    final composers = categories.groups(MusicCategoryKind.composer);
    expect(composers.first.title, 'Singer');
    expect(
        composers.first.evidenceCounts, {ClassificationEvidence.fallback: 1});
    expect(composers.first.audios, [same(named)]);
    expect(composers.last.title, '未知作曲家');
    expect(composers.last.isUnknown, isTrue);
    expect(composers.last.audios, [same(missing)]);
    expect(categories.groups(MusicCategoryKind.artist).last.title, '未知艺术家');
  });

  test('contributing artists split with configured artist separators', () {
    final track = CategoryTestAudio('contributing', artist: 'Alice；Bob；Alice');
    final groups = MusicCategories([track], artistSplitPattern: r'；')
        .groups(MusicCategoryKind.composer);
    expect(groups.map((group) => group.title), ['Alice', 'Bob']);
    expect(
        groups.map((group) => group.evidenceSummary), everyElement('艺术家回退 1'));
    expect(track.composer, isNull);
  });

  test('same album title with different album artists creates different groups',
      () {
    final a = CategoryTestAudio('a', album: 'Best', albumArtist: 'Band A');
    final b = CategoryTestAudio('b', album: 'Best', albumArtist: 'Band B');
    final groups = MusicCategories([a, b]).groups(MusicCategoryKind.album);
    expect(groups, hasLength(2));
    expect(groups.map((group) => group.subtitle).toSet(), {'Band A', 'Band B'});
    expect(groups.map((group) => group.id).toSet(), hasLength(2));
  });

  test('album artist holds keep guest performers in the same release', () {
    final a = CategoryTestAudio('a',
        artist: 'Vocal A', albumArtist: 'Various Artists');
    final b = CategoryTestAudio('b',
        artist: 'Vocal B', albumArtist: 'Various Artists');
    final group =
        MusicCategories([a, b]).groups(MusicCategoryKind.album).single;
    expect(group.subtitle, 'Various Artists');
    expect(group.audios, [same(a), same(b)]);
  });

  test('missing album artist falls back to performer without merging releases',
      () {
    final a = CategoryTestAudio('a', artist: 'A');
    final b = CategoryTestAudio('b', artist: 'B', albumArtist: '  ');
    expect(
        MusicCategories([a, b]).groups(MusicCategoryKind.album), hasLength(2));
  });

  test('unknown album and album artist are clearly named', () {
    final group =
        MusicCategories([CategoryTestAudio('a', artist: '', album: 'UNKNOWN')])
            .groups(MusicCategoryKind.album)
            .single;
    expect(group.title, '未知专辑');
    expect(group.subtitle, '未知专辑艺术家');
    expect(group.isUnknown, isTrue);
  });

  test('compound identity safely round-trips Unicode and URL punctuation', () {
    final group = MusicCategories([
      CategoryTestAudio('a', album: 'A / B ? # & [春]', albumArtist: '藝人 "一"')
    ]).groups(MusicCategoryKind.album).single;
    final uri = Uri.parse(group.location);
    expect(uri.path, '/categories/detail');
    expect(uri.queryParameters['by'], 'album');
    expect(uri.queryParameters['group'], group.id);
  });

  test('album menu helper keeps the selected original reference and release',
      () {
    final selected = CategoryTestAudio('selected', albumArtist: 'A');
    final unrelated = CategoryTestAudio('other', albumArtist: 'B');
    final group = MusicCategories.albumGroupFor(selected, [unrelated]);
    expect(group.audios.single, same(selected));
    expect(group.subtitle, 'A');
  });

  test('projections preserve references and never mutate the source order', () {
    final a = CategoryTestAudio('b', composer: 'C');
    final b = CategoryTestAudio('a', composer: 'C');
    final original = [a, b];
    final before = original.map((audio) => audio.toMap()).toList();
    final group =
        MusicCategories(original).groups(MusicCategoryKind.composer).single;
    expect(group.audios, [same(a), same(b)]);
    expect(() => group.audios.add(a), throwsUnsupportedError);
    expect(original, [same(a), same(b)]);
    expect(original.map((audio) => audio.toMap()).toList(), before);
  });

  test('mixed local and online songs keep provenance and distinct references',
      () {
    final local = CategoryTestAudio('same');
    final remote = CategoryTestAudio('same', online: true);
    final group =
        MusicCategories([local, remote]).groups(MusicCategoryKind.album).single;
    expect(group.localCount, 1);
    expect(group.onlineCount, 1);
    expect(group.sourceSummary, '本地 1 · 联网 1');
    expect(group.audios, [same(local), same(remote)]);
  });

  test('group search includes album artist and ignores name casing', () {
    final group =
        MusicCategories([CategoryTestAudio('a', albumArtist: 'Band A')])
            .groups(MusicCategoryKind.album)
            .single;
    expect(group.matches(' band a '), isTrue);
    expect(group.matches('album'), isTrue);
    expect(group.matches('no match'), isFalse);
  });

  test('language categories use explicit reliable tags only', () {
    final chinese = CategoryTestAudio('Chinese', language: 'zh-Hant');
    final english = CategoryTestAudio('English', language: 'en-JP');
    final japanese = CategoryTestAudio('Japanese', language: 'jpn');
    final korean = CategoryTestAudio('Korean', language: 'ko-KR');
    final other = CategoryTestAudio('French', language: 'fr');
    final groups = MusicCategories([chinese, english, japanese, korean, other])
        .groups(MusicCategoryKind.language);
    expect(
      groups.map((group) => group.title).toSet(),
      {'中文', '英文', '日文', '韩文', '其他语言'},
    );
    expect(groups.firstWhere((group) => group.title == '中文').audios,
        [same(chinese)]);
    expect(groups.firstWhere((group) => group.title == '英文').audios,
        [same(english)]);
    expect(groups.every((group) => !group.isUnknown), isTrue);
  });

  test('language fallback is shared and visibly distinguished from tags', () {
    final kana = CategoryTestAudio('さくらの唄', artist: '日本語');
    final han = CategoryTestAudio('春风', language: 'not-a-language');
    final latin = CategoryTestAudio('This is a song', language: ' ');
    final groups =
        MusicCategories([kana, han, latin]).groups(MusicCategoryKind.language);
    expect(
        groups.firstWhere((group) => group.title == '日文').audios, [same(kana)]);
    expect(groups.firstWhere((group) => group.title == '英文').audios,
        [same(latin)]);
    expect(
        groups.firstWhere((group) => group.title == '中文').audios, [same(han)]);
    expect(groups.firstWhere((group) => group.title == '日文').evidenceCounts,
        {ClassificationEvidence.inferred: 1});
  });

  test('mixed reliable tags are other but partly invalid tags remain unknown',
      () {
    final mixed = CategoryTestAudio('mixed', language: 'zh/ja');
    final invalid = CategoryTestAudio('invalid',
        artist: '', album: '', language: 'zh/invalid');
    final groups =
        MusicCategories([mixed, invalid]).groups(MusicCategoryKind.language);
    expect(groups.first.title, '其他语言');
    expect(groups.first.audios, [same(mixed)]);
    expect(groups.last.title, '未识别');
    expect(groups.last.audios, [same(invalid)]);
  });

  test('local formats use Windows file extensions case-insensitively', () {
    final a = CategoryTestAudio('a', path: r'D:\music.flac\A.Mp3');
    final b = CategoryTestAudio('b', path: 'D:/音乐/B.mp3');
    final c = CategoryTestAudio('c', path: 'D:/音乐/C.flac');
    final groups = MusicCategories([a, b, c]).groups(MusicCategoryKind.format);
    expect(groups.map((group) => group.title), ['FLAC', 'MP3']);
    expect(groups.last.audios, [same(a), same(b)]);
  });

  test('unknown formats do not infer from online URLs or extensionless paths',
      () {
    final remote = CategoryTestAudio('remote',
        online: true,
        path: 'https://provider.invalid/song.flac?token=not-a-real-token');
    final missing = CategoryTestAudio('missing', path: 'D:/music/NoExtension');
    final invalid = CategoryTestAudio('invalid', path: 'D:/music/Audio.?');
    final group = MusicCategories([remote, missing, invalid])
        .groups(MusicCategoryKind.format)
        .single;
    expect(group.title, '未知格式');
    expect(group.isUnknown, isTrue);
    expect(group.audios, [same(remote), same(missing), same(invalid)]);
  });

  test('bitrate ranges are ordered, mutually exclusive and cover boundaries',
      () {
    final values = <int?>[
      null,
      -1,
      0,
      1,
      128,
      129,
      192,
      193,
      256,
      257,
      320,
      321
    ];
    final songs = [
      for (var index = 0; index < values.length; index++)
        CategoryTestAudio('bitrate-$index', bitrate: values[index]),
    ];
    final groups = MusicCategories(songs).groups(MusicCategoryKind.bitrate);
    expect(groups.map((group) => group.title), [
      '128 kbps 及以下',
      '129–192 kbps',
      '193–256 kbps',
      '257–320 kbps',
      '高于 320 kbps',
      '未知码率',
    ]);
    expect(groups.expand((group) => group.audios).toSet(), songs.toSet());
    expect(groups.fold<int>(0, (sum, group) => sum + group.audios.length),
        songs.length);
    expect(groups.last.isUnknown, isTrue);
    expect(
        groups.last.audios, [same(songs[0]), same(songs[1]), same(songs[2])]);
  });

  test('duration ranges are ordered, mutually exclusive and cover boundaries',
      () {
    final values = [-1, 0, 1, 119, 120, 299, 300, 599, 600, 1799, 1800];
    final songs = [
      for (var index = 0; index < values.length; index++)
        CategoryTestAudio('duration-$index', duration: values[index]),
    ];
    final groups = MusicCategories(songs).groups(MusicCategoryKind.duration);
    expect(groups.map((group) => group.title), [
      '少于 2 分钟',
      '2–4 分钟',
      '5–9 分钟',
      '10–29 分钟',
      '30 分钟及以上',
      '未知时长',
    ]);
    expect(groups.expand((group) => group.audios).toSet(), songs.toSet());
    expect(groups.fold<int>(0, (sum, group) => sum + group.audios.length),
        songs.length);
    expect(groups.last.isUnknown, isTrue);
    expect(groups.last.audios, [same(songs[0]), same(songs[1])]);
  });

  test('bitrate and duration category identities survive index round trips',
      () {
    final original = CategoryTestAudio('indexed', duration: 601, bitrate: 193);
    final restored = Audio.fromMap(original.toMap());
    expect(restored.duration, 601);
    expect(restored.bitrate, 193);
    final before = MusicCategories([original]);
    final after = MusicCategories([restored]);
    for (final kind in [
      MusicCategoryKind.bitrate,
      MusicCategoryKind.duration
    ]) {
      final originalGroup = before.groups(kind).single;
      final restoredGroup = after.groups(kind).single;
      expect(restoredGroup.id, originalGroup.id);
      expect(restoredGroup.title, originalGroup.title);
    }
  });

  test('legacy indexes without bitrate or duration remain safely browsable',
      () {
    final map = CategoryTestAudio('legacy-quantitative').toMap()
      ..remove('bitrate')
      ..remove('duration');
    final restored = Audio.fromMap(map);
    expect(restored.bitrate, isNull);
    expect(restored.duration, 0);
    final categories = MusicCategories([restored]);
    expect(categories.groups(MusicCategoryKind.bitrate).single.title, '未知码率');
    expect(categories.groups(MusicCategoryKind.duration).single.title, '未知时长');
  });

  test('quantitative category labels are translated without changing IDs', () {
    final audio = CategoryTestAudio('localized', duration: 60, bitrate: 128);
    final categories = MusicCategories([audio]);
    final bitrate = categories.groups(MusicCategoryKind.bitrate).single;
    final duration = categories.groups(MusicCategoryKind.duration).single;
    final bitrateId = bitrate.id;
    final durationId = duration.id;
    try {
      for (final language in UiLanguage.values.skip(1)) {
        uiLanguage.value = language;
        expect(categoryDisplayTitle(bitrate), isNot(bitrate.title));
        expect(categoryDisplayTitle(duration), isNot(duration.title));
        expect(ui(MusicCategoryKind.bitrate.countLabel), isNotEmpty);
        expect(ui(MusicCategoryKind.duration.countLabel), isNotEmpty);
        expect(bitrate.id, bitrateId);
        expect(duration.id, durationId);
      }
    } finally {
      uiLanguage.value = UiLanguage.zh;
    }
  });

  test('source groups distinguish local and online without merging identities',
      () {
    final local = CategoryTestAudio('local');
    final online = CategoryTestAudio('online', online: true);
    final groups =
        MusicCategories([local, online]).groups(MusicCategoryKind.source);
    expect(groups.map((group) => group.title).toSet(), {'本地', '联网'});
    expect(groups.firstWhere((group) => group.title == '本地').audios,
        [same(local)]);
    expect(groups.firstWhere((group) => group.title == '联网').audios,
        [same(online)]);
  });

  test('local index metadata round-trips independent composer and album artist',
      () {
    final original = CategoryTestAudio('a',
        artist: 'Singer', composer: 'Writer', albumArtist: 'Release');
    final loaded = Audio.fromMap(original.toMap());
    expect(loaded.artist, 'Singer');
    expect(loaded.composer, 'Writer');
    expect(loaded.albumArtist, 'Release');
    expect(loaded.classificationTagsRead, isTrue);
    expect(loaded.toMap(), original.toMap());
  });

  test('legacy index marker is not accidentally promoted when saved by Dart',
      () {
    final original = CategoryTestAudio('a').toMap()
      ..remove('composer')
      ..remove('album_artist')
      ..remove('classification_version');
    final legacy = Audio.fromMap(original);
    expect(legacy.classificationTagsRead, isFalse);
    expect(legacy.toMap()['classification_version'], 0);
    expect(legacy.composer, isNull);
    expect(legacy.albumArtist, isNull);
  });

  test('malformed optional metadata and version values are safe unknowns', () {
    for (final marker in [null, true, false, '1', -1, 1.5]) {
      final value = CategoryTestAudio('a').toMap()
        ..['composer'] = 12
        ..['album_artist'] = false
        ..['classification_version'] = marker;
      final loaded = Audio.fromMap(value);
      expect(loaded.composer, isNull);
      expect(loaded.albumArtist, isNull);
      expect(loaded.classificationTagsRead, isFalse);
    }
  });

  test('online metadata round-trips without modifying remote identity', () {
    final original = CategoryTestAudio('remote',
        online: true, composer: 'Composer', albumArtist: 'Album Artist');
    final loaded = Audio.fromOnlineMap(original.toOnlineMap());
    expect(loaded.path, original.path);
    expect(loaded.composer, original.composer);
    expect(loaded.albumArtist, original.albumArtist);
    expect(loaded.classificationTagsRead, isTrue);
  });

  test(
      'existing metadata edits preserve both classification tags and pending marker',
      () {
    final audio = CategoryTestAudio('a',
        composer: 'Writer', albumArtist: 'Owner', classificationVersion: 0);
    audio.applyEditedMetadata(
        newPath: 'D:/category-test-fixtures/renamed.mp3',
        newTitle: 'New title',
        newArtist: 'New artist',
        newAlbum: 'New album',
        newModified: 20);
    expect(audio.composer, 'Writer');
    expect(audio.albumArtist, 'Owner');
    expect(audio.classificationVersion, 0);
  });

  test('derived-library changes notify once after all collections are complete',
      () {
    final library = AudioLibrary.instance;
    final folders = library.folders;
    final online = library.onlineAudioCollection;
    final audio = CategoryTestAudio('published', composer: 'Writer');
    var notifications = 0;
    void changed() {
      notifications++;
      expect(library.audioCollection, [same(audio)]);
      expect(library.artistCollection, isNotEmpty);
      expect(library.albumCollection, isNotEmpty);
      expect(AudioLibrary.changes.value, AudioLibrary.revision);
    }

    try {
      library.folders = [
        AudioFolder([audio], 'D:/category-test-fixtures', 0, 0)
      ];
      library.onlineAudioCollection = [];
      final before = AudioLibrary.revision;
      final searchBefore = AudioLibrary.searchRevision;
      final classificationBefore = AudioLibrary.classificationRevision;
      AudioLibrary.changes.addListener(changed);
      library.rebuildDerivedCollections();
      expect(notifications, 1);
      expect(AudioLibrary.revision, before + 1);
      expect(AudioLibrary.searchRevision, searchBefore + 1);
      expect(AudioLibrary.classificationRevision, classificationBefore + 1);
    } finally {
      AudioLibrary.changes.removeListener(changed);
      library.folders = folders;
      library.onlineAudioCollection = online;
      library.rebuildDerivedCollections();
    }
  });

  test('duration publication does not invalidate search or classification', () {
    final revisionBefore = AudioLibrary.revision;
    final searchBefore = AudioLibrary.searchRevision;
    final classificationBefore = AudioLibrary.classificationRevision;

    AudioLibrary.instance.publishDurationChanges();

    expect(AudioLibrary.revision, revisionBefore + 1);
    expect(AudioLibrary.searchRevision, searchBefore);
    expect(AudioLibrary.classificationRevision, classificationBefore);
  });

  test('removing an indexed song advances structural revisions', () {
    final library = AudioLibrary.instance;
    final folders = library.folders;
    final online = library.onlineAudioCollection;
    final audio = CategoryTestAudio('deleted');
    try {
      library.folders = [
        AudioFolder([audio], 'D:/category-test-fixtures', 0, 0),
      ];
      library.onlineAudioCollection = [];
      library.rebuildDerivedCollections();
      final searchBefore = AudioLibrary.searchRevision;
      final classificationBefore = AudioLibrary.classificationRevision;

      expect(library.removeLocalAudio(audio.path), 1);

      expect(AudioLibrary.searchRevision, searchBefore + 1);
      expect(AudioLibrary.classificationRevision, classificationBefore + 1);
      expect(library.audioCollection, isEmpty);
    } finally {
      library.folders = folders;
      library.onlineAudioCollection = online;
      library.rebuildDerivedCollections();
    }
  });

  test('default separator follows existing artist settings for composers too',
      () {
    final old = AppSettings.instance.artistSplitPattern;
    try {
      AppSettings.instance.artistSplitPattern = r'；';
      final categories = MusicCategories(
          [CategoryTestAudio('a', artist: 'A；B', composer: 'C；D')]);
      expect(categories.groups(MusicCategoryKind.artist), hasLength(2));
      expect(categories.groups(MusicCategoryKind.composer), hasLength(2));
    } finally {
      AppSettings.instance.artistSplitPattern = old;
    }
  });
}
