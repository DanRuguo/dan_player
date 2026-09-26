import 'dart:convert';
import 'dart:io';

import 'package:dan_player/data/snapshot3_upgrade.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/library/cue_sheet.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/library/smart_condition.dart';
import 'package:dan_player/library/smart_playlist.dart';
import 'package:flutter_test/flutter_test.dart';

Audio song(String path,
        {String artist = 'Alice',
        String album = 'Piano',
        int track = 5,
        String? composer = 'Mozart',
        String? albumArtist = 'Orchestra',
        String? language = 'JA',
        bool pending = false,
        int classification = 1,
        int? bitrate = 320,
        int? rate = 48000,
        int? size = 10485760,
        CueTrackReference? cue}) =>
    Audio('Tag title', artist, album, track, 180, bitrate, rate,
        cue?.identity ?? path, 0, 0, null,
        composer: composer,
        albumArtist: albumArtist,
        language: language,
        fileSizeBytes: size,
        classificationVersion: classification,
        metadataReadPending: pending,
        cueTrack: cue);

RuleTruth match(SmartCondition condition, Audio audio, {PersonalTrack? data}) =>
    condition.prepare().evaluate('fixture', data, const {}, audio: audio);

void main() {
  test('real CUE resolution retains source language and metadata read evidence',
      () async {
    final sandbox = await Directory.systemTemp.createTemp('dan-cue-evidence-');
    addTearDown(() => sandbox.delete(recursive: true));
    final source = File('${sandbox.path}/source.flac');
    await source.writeAsBytes([1, 2, 3]);
    final document = parseCue('''TITLE "Album"
FILE "source.flac" WAVE
TRACK 01 AUDIO
TITLE "Slice"
INDEX 01 00:00:00
''', cuePath: '${sandbox.path}/album.cue');
    final known = song(source.path, language: 'ja');
    final slice = (await resolveCueEntries(document, [known])).single;
    expect(slice.language, 'ja');
    expect(slice.classificationTagsRead, isTrue);
    expect(slice.metadataReadPending, isFalse);
    expect(slice.fileSizeBytes, 3);
    expect(match(const SmartCondition.term(SmartField.languageIs, 'ja'), slice),
        RuleTruth.yes);
    known.metadataReadPending = true;
    known.classificationVersion = 0;
    final pending = (await resolveCueEntries(document, [known])).single;
    expect(
        match(const SmartCondition.term(SmartField.metadataPending, 'true'),
            pending),
        RuleTruth.yes);
    final unindexed = (await resolveCueEntries(document, [])).single;
    expect(unindexed.metadataReadPending, isTrue);
    expect(unindexed.classificationTagsRead, isFalse);
    expect(
        match(const SmartCondition.term(SmartField.missingComposer, 'true'),
            unindexed),
        RuleTruth.unknown);
  });
  final textAndNumbers = <SmartField, String>{
    SmartField.composerContains: 'MozART',
    SmartField.albumArtistContains: 'orches',
    SmartField.languageIs: 'ja',
    SmartField.fileNameContains: 'original.flac',
    SmartField.fileSizeAtLeast: '10485760',
    SmartField.fileSizeAtMost: '10485760',
    SmartField.bitrateAtMost: '320',
    SmartField.sampleRateAtMost: '48000',
    SmartField.trackAtLeast: '5',
    SmartField.trackAtMost: '5',
  };
  for (final entry in textAndNumbers.entries) {
    test(
        '${entry.key.name} validates, matches and preserves literal round trip',
        () {
      final audio = song(r'C:\synthetic\Original.FLAC');
      final condition = SmartCondition.term(entry.key, entry.value);
      expect(
          SmartCondition.fromJson(jsonDecode(jsonEncode(condition.toJson())))
              .toJson(),
          condition.toJson());
      expect(match(condition, audio), RuleTruth.yes);
      expect(
          match(SmartCondition.term(entry.key, entry.value, exclude: true),
              audio),
          RuleTruth.no);
    });
  }
  final missingFields = <SmartField>[
    SmartField.missingComposer,
    SmartField.missingAlbumArtist,
    SmartField.missingLanguage,
    SmartField.missingAlbum,
    SmartField.missingArtist,
  ];
  for (final field in missingFields) {
    test('${field.name} selects confirmed empty tags and excludes pending data',
        () {
      final condition = SmartCondition.term(field, 'true');
      final missing = song(r'C:\synthetic\missing.flac',
          artist: 'UNKNOWN',
          album: ' ',
          composer: null,
          albumArtist: null,
          language: 'unknown');
      expect(match(condition, missing), RuleTruth.yes);
      expect(match(condition, song(r'C:\synthetic\known.flac')), RuleTruth.no);
      expect(
          match(
              condition,
              song(r'C:\synthetic\pending.flac',
                  pending: true,
                  artist: '',
                  album: '',
                  composer: null,
                  albumArtist: null,
                  language: null)),
          RuleTruth.unknown);
      expect(
          match(SmartCondition.term(field, 'true', exclude: true),
              song(r'C:\synthetic\pending.flac', pending: true)),
          RuleTruth.unknown);
      expect(SmartCondition.fromJson(condition.toJson()).field, field);
    });
  }
  test(
      'classification pending is unknown for newly backfilled composer and album artist',
      () {
    final audio = song(r'C:\synthetic\legacy.flac',
        composer: null, albumArtist: null, classification: 0);
    for (final field in [
      SmartField.missingComposer,
      SmartField.missingAlbumArtist
    ]) {
      expect(
          match(SmartCondition.term(field, 'true'), audio), RuleTruth.unknown);
    }
    expect(
        match(const SmartCondition.term(SmartField.metadataPending, 'true'),
            audio),
        RuleTruth.yes);
  });
  test(
      'untagged is an explicit personal predicate and tags are not synthesized',
      () {
    const condition = SmartCondition.term(SmartField.untagged, 'true');
    final audio = song(r'C:\synthetic\a.flac');
    expect(condition.usesPersonalData, isTrue);
    expect(match(condition, audio), RuleTruth.yes);
    expect(match(condition, audio, data: const PersonalTrack(tags: ['Chill'])),
        RuleTruth.no);
    expect(
        SmartCondition.fromJson(condition.toJson()).field, SmartField.untagged);
  });
  test(
      'CUE predicate, track bounds and size use the slice identity and source descriptor',
      () {
    const cue = CueTrackReference(
        cuePath: r'C:\synthetic\album.cue',
        sourcePath: r'C:\synthetic\album.flac',
        number: 2,
        startFrame: 0,
        endFrame: 750);
    final audio = song(cue.sourcePath, cue: cue, track: 0);
    for (final condition in [
      const SmartCondition.term(SmartField.cueTrack, 'true'),
      const SmartCondition.term(SmartField.trackAtLeast, '2'),
      const SmartCondition.term(SmartField.trackAtMost, '2'),
      const SmartCondition.term(SmartField.fileNameContains, 'album.flac'),
      const SmartCondition.term(SmartField.fileSizeAtMost, '10485760'),
    ]) {
      expect(match(condition, audio), RuleTruth.yes);
    }
    expect(
        match(const SmartCondition.term(SmartField.cueTrack, 'true'),
            song(r'C:\synthetic\normal.flac')),
        RuleTruth.no);
    expect(audio.path, cue.identity);
  });
  test('metadata pending reflects reader state without probing files', () {
    const condition = SmartCondition.term(SmartField.metadataPending, 'true');
    expect(match(condition, song(r'C:\does-not-exist\a.flac')), RuleTruth.no);
    expect(match(condition, song(r'C:\does-not-exist\b.flac', pending: true)),
        RuleTruth.yes);
    expect(SmartCondition.fromJson(condition.toJson()).field,
        SmartField.metadataPending);
  });
  test('unknown quality size and track values stay unknown under exclusion',
      () {
    final unknown = song(r'C:\synthetic\unknown.flac',
        size: null, bitrate: null, rate: null, track: 0);
    for (final field in [
      SmartField.fileSizeAtLeast,
      SmartField.fileSizeAtMost,
      SmartField.bitrateAtMost,
      SmartField.sampleRateAtMost,
      SmartField.trackAtLeast,
      SmartField.trackAtMost
    ]) {
      expect(match(SmartCondition.term(field, '0', exclude: true), unknown),
          RuleTruth.unknown);
    }
  });
  test('prepared nested groups retain complete three-value truth semantics',
      () {
    final audio = song(r'C:\synthetic\a.flac', bitrate: null);
    const yes = SmartCondition.term(SmartField.languageIs, 'JA');
    const no = SmartCondition.term(SmartField.languageIs, 'en');
    const unknown = SmartCondition.term(SmartField.bitrateAtMost, '320');
    for (final any in [true, false]) {
      for (final left in [yes, no, unknown]) {
        for (final right in [yes, no, unknown]) {
          final truths = [match(left, audio), match(right, audio)];
          final expected = any && truths.contains(RuleTruth.yes)
              ? RuleTruth.yes
              : !any && truths.contains(RuleTruth.no)
                  ? RuleTruth.no
                  : truths.contains(RuleTruth.unknown)
                      ? RuleTruth.unknown
                      : any
                          ? RuleTruth.no
                          : RuleTruth.yes;
          expect(match(SmartCondition.group([left, right], any: any), audio),
              expected);
        }
      }
    }
    const negatedUnknown =
        SmartCondition.term(SmartField.bitrateAtMost, '320', exclude: true);
    expect(match(negatedUnknown, audio), RuleTruth.unknown);
  });
  test('short circuit cannot bypass invalid right branch validation', () async {
    const rule = SmartPlaylist(
        id: 'bad',
        name: 'Bad',
        condition: SmartCondition.group([
          SmartCondition.term(SmartField.languageIs, 'JA'),
          SmartCondition.term(SmartField.fileSizeAtMost, '-1'),
        ], any: true));
    expect(rule.validate(), isNotNull);
    await expectLater(
        rule.evaluate([song(r'C:\synthetic\a.flac')]), throwsFormatException);
    for (final field in smartBooleanFields) {
      expect(
          () => SmartCondition.fromJson(
              SmartCondition.term(field, 'false').toJson()),
          throwsFormatException);
    }
  });
  test(
      'album-track sort separates same title owners, unknown track last, then limits',
      () async {
    final a2 = song(r'C:\synthetic\a2.flac', track: 2, albumArtist: 'A');
    final a1 = song(r'C:\synthetic\a1.flac', track: 1, albumArtist: 'A');
    final unknown = song(r'C:\synthetic\a0.flac', track: 0, albumArtist: 'A');
    final b = song(r'C:\synthetic\b.flac', track: 1, albumArtist: 'B');
    const rule = SmartPlaylist(
        id: 'album', name: 'Album', sort: SmartPlaylistSort.albumTrack);
    expect(await rule.evaluate([b, unknown, a2, a1]), [a1, a2, unknown, b]);
    final limited = SmartPlaylist.fromJson({...rule.toJson(), 'maxResults': 2});
    expect(await limited.evaluate([b, unknown, a2, a1]), [a1, a2]);
  });
  test(
      'schema three migrates on save, four survives startup and future five is never overwritten',
      () async {
    final sandbox =
        await Directory.systemTemp.createTemp('dan-smart-expansion-');
    addTearDown(() => sandbox.delete(recursive: true));
    final file = File('${sandbox.path}/smart_playlists.json');
    const legacy = SmartPlaylist(id: 'legacy', name: 'Legacy');
    await file.writeAsString(jsonEncode({
      'version': 3,
      'playlists': [legacy.toJson()]
    }));
    final store = SmartPlaylistStore(file);
    expect((await store.list()).single.id, legacy.id);
    const fresh = SmartPlaylist(
        id: 'quality',
        name: 'Quality',
        sort: SmartPlaylistSort.albumTrack,
        condition: SmartCondition.term(SmartField.sampleRateAtMost, '48000'));
    await store.upsert(fresh);
    final raw = jsonDecode(await file.readAsString());
    expect(raw['version'], 4);
    Snapshot3Upgrade.validateDocument('smart_playlists.json', raw);
    expect(
        (await SmartPlaylistStore(file).list()).last.toJson(), fresh.toJson());
    final future = jsonEncode({'version': 5, 'playlists': []});
    await file.writeAsString(future);
    await expectLater(
        SmartPlaylistStore(file).upsert(fresh), throwsUnsupportedError);
    expect(await file.readAsString(), future);
  });
}
