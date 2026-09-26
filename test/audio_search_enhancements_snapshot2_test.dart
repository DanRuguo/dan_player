import 'dart:async';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/search/audio_search_index.dart';
import 'package:dan_player/search/audio_search_query.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:flutter_test/flutter_test.dart';

Audio fixture(String id,
        {String? composer,
        String? albumArtist,
        String? language,
        int track = 1,
        int duration = 240,
        int? bitrate,
        int? sampleRate,
        int? size,
        bool pending = false,
        int classification = 1,
        CueTrackReference? cue}) =>
    Audio('Tagged $id', 'Artist', 'Album', track, duration, bitrate, sampleRate,
        'C:/Search/$id.flac', 1, 1, 'fixture',
        composer: composer,
        albumArtist: albumArtist,
        language: language,
        fileSizeBytes: size,
        metadataReadPending: pending,
        classificationVersion: classification,
        cueTrack: cue);

void main() {
  late Audio alpha, beta, unknown;
  late PlaybackStatistics statistics;
  late Map<String, PersonalTrack> personal;
  late AudioSearchIndex index;
  late Map<String, PersonalTrack> oldPersonal;
  void publish(List<Audio> audios) {
    AudioLibrary.instance.audioCollection
      ..clear()
      ..addAll(audios);
    AudioLibrary.instance.artistCollection.clear();
    AudioLibrary.instance.albumCollection.clear();
    AudioLibrary.searchRevision++;
    AudioLibrary.revision++;
  }

  Future<List<Audio>> search(String query,
          {int limit = 200, void Function()? check}) async =>
      (await index.searchAll(query,
              audioLimit: limit,
              statistics: statistics,
              loadPersonal: () async => personal,
              checkCancelled: check))
          .audios;
  setUp(() {
    alpha = fixture('alpha-live',
        composer: '莫扎特',
        albumArtist: 'Various Artists',
        language: 'ja',
        bitrate: 320,
        sampleRate: 96000,
        size: 30 * 1048576,
        track: 2);
    beta = fixture('beta',
        composer: 'Beethoven',
        albumArtist: 'Solo',
        language: 'en',
        bitrate: 128,
        sampleRate: 44100,
        size: 1000000,
        track: 5);
    unknown = fixture('unknown', language: 'UNKNOWN', track: 0, duration: 0);
    publish([alpha, beta, unknown]);
    index = AudioSearchIndex.instance;
    statistics = PlaybackStatistics.inMemory();
    statistics.tracks[alpha.stableTrackId] = TrackPlaybackStatistics(
        id: alpha.stableTrackId,
        title: alpha.title,
        artist: alpha.artist,
        album: alpha.album,
        online: false,
        playCount: 10,
        completedCount: 8,
        skippedCount: 2,
        listenMilliseconds: 600001,
        lastPlayedAt: DateTime(2026, 9, 26, 13).millisecondsSinceEpoch);
    personal = {
      alpha.stableTrackId: PersonalTrack(
          rating: 5,
          tags: ['现场', 'Café'],
          firstAddedAtUtc: DateTime(2026, 9, 25, 23).toUtc()),
      beta.stableTrackId: PersonalTrack(
          rating: 2,
          tags: ['Study'],
          firstAddedAtUtc: DateTime(2026, 9, 1, 5).toUtc()),
    };
    oldPersonal = PersonalLibrary.latest;
    PersonalLibrary.latest = personal;
  });
  tearDown(() {
    PersonalLibrary.latest = oldPersonal;
    statistics.dispose();
    publish([]);
  });

  test('filename searches physical source names independent of loaded title',
      () async {
    expect(await search('filename:"alpha-live.flac"'), [alpha]);
    expect(await search('filename:Tagged'), isEmpty);
    expect(await search('title:Tagged -filename:live'),
        containsAll([beta, unknown]));
  });
  test('composer and albumartist search real tags with existing pinyin',
      () async {
    expect(await search('composer:mozhate albumartist:"various artists"'),
        [alpha]);
    expect(await search('composer:beethoven'), [beta]);
    expect(await search('-composer:mozhate'), [beta]);
    expect(await search('albumartist:artist'), [alpha]);
  });
  test('language is an exact original tag with no filename inference',
      () async {
    expect(await search('language:ja'), [alpha]);
    expect(await search('language:j'), isEmpty);
    expect(await search('language:UNKNOWN'), isEmpty);
    expect(await search('-language:ja'), [beta]);
  });
  test('track supports intervals and CUE uses its explicit subtrack number',
      () async {
    final cue = fixture('cue',
        track: 0,
        cue: const CueTrackReference(
            cuePath: 'C:/Search/disc.cue',
            sourcePath: 'C:/Search/disc.flac',
            number: 3,
            startFrame: 0));
    publish([alpha, beta, unknown, cue]);
    expect(await search('track:2..3'), containsAll([alpha, cue]));
    expect(await search('track:>3'), [beta]);
    expect(await search('track:0'), isEmpty);
  });
  test('bitrate and sample rate include exact bounds and unit conversions',
      () async {
    expect(await search('bitrate:>=320kbps samplerate:>44.1kHz'), [alpha]);
    expect(await search('bitrate:<320 samplerate:44100'), [beta]);
    expect(await search('bitrate:128..320 samplerate:>=44100'),
        containsAll([alpha, beta]));
    expect(await search('-bitrate:>=320'), [beta]);
    expect(await search('-samplerate:<=44100'), [alpha]);
  });
  test('file size converts decimal and binary units without file IO', () async {
    expect(await search('filesize:30MiB'), [alpha]);
    expect(await search('filesize:>=30MB'), [alpha]);
    expect(await search('filesize:1MB..2MB'), [beta]);
    expect(await search('filesize:<=1000KB'), [beta]);
    expect(await search('-filesize:>=2MB'), [beta]);
  });
  test('rating intervals and explicit unrated preserve unknown exclusions',
      () async {
    expect(await search('rating:4..5'), [alpha]);
    expect(await search('rating:<=2'), [beta]);
    expect(await search('rating:unrated'), [unknown]);
    expect(await search('-rating:>=4'), [beta]);
  });
  test('personal tags match whole normalized values and support untagged has',
      () async {
    expect(await search('tag:"现场"'), [alpha]);
    expect(await search('tag:cafe'), [alpha]);
    expect(await search('tag:stu'), isEmpty);
    expect(await search('-has:tag'), [unknown]);
  });
  test('added uses persisted personal dates and inclusive local calendar days',
      () async {
    expect(await search('added:2026-09-25'), [alpha]);
    expect(await search('added:>2026-09-01'), [alpha]);
    expect(await search('added:<=2026-09-01'), [beta]);
    expect(await search('added:2026-09-01..2026-09-25'),
        containsAll([alpha, beta]));
    expect(await search('-added:>=2026-09-20'), [beta]);
  });
  test('playcount completion and skip counts use exact track identities',
      () async {
    expect(await search('playcount:>=10 completed:8 skipped:2'), [alpha]);
    expect(await search('playcount:<10 completed:0 skipped:0'),
        containsAll([beta, unknown]));
    expect(await search('completed:>=9 OR skipped:>1'), [alpha]);
  });
  test('listened counts wall listening time and retains subsecond comparison',
      () async {
    expect(await search('listened:>10:00'), [alpha]);
    expect(await search('listened:<=10:00'), containsAll([beta, unknown]));
    expect(await search('listened:5:00..11:00'), [alpha]);
  });
  test('last played supports dates and explicit never played', () async {
    expect(await search('lastplayed:2026-09-26'), [alpha]);
    expect(await search('lastplayed:<2026-09-26'), isEmpty);
    expect(await search('lastplayed:never'), containsAll([beta, unknown]));
    expect(await search('has:history'), [alpha]);
  });
  test('ambiguous legacy statistics never pretend to be zero or never played',
      () async {
    statistics.tracks['legacy'] = TrackPlaybackStatistics(
        id: 'legacy',
        title: 'Shared',
        artist: '',
        album: '',
        online: false,
        legacyUnassigned: true,
        candidateTrackIds: [unknown.stableTrackId],
        playCount: 20);
    for (final query in [
      'playcount:0',
      'completed:0',
      'skipped:0',
      'listened:0',
      'lastplayed:never',
      '-has:history'
    ]) {
      expect(await search(query), isNot(contains(unknown)), reason: query);
    }
    expect(await search('playcount:0 OR filename:unknown'), contains(unknown));
  });
  test(
      'has distinguishes read missing values from pending or unread classification',
      () async {
    final pending = fixture('pending',
        pending: true,
        classification: 0,
        composer: 'Known-looking',
        bitrate: 320,
        language: 'ja');
    publish([alpha, beta, unknown, pending]);
    expect(await search('-has:language'), [unknown]);
    expect(await search('-has:composer'), [unknown]);
    expect(await search('has:bitrate'), containsAll([alpha, beta]));
    expect(await search('-bitrate:>=320'), [beta]);
    expect(await search('composer:"known-looking"'), isEmpty);
    expect(await search('filename:pending OR has:language'), contains(pending));
  });
  test('OR branches are deduplicated and AND binds before OR', () async {
    expect(await search('filename:alpha | bitrate:320'), [alpha]);
    expect(await search('bitrate:128 OR bitrate:320 samplerate:48000'), [beta]);
    expect(await search('(bitrate:128 OR bitrate:320) samplerate:>=48kHz'),
        [alpha]);
    expect(await search('bitrate:128 AND samplerate:44100'), [beta]);
  });
  test('nested groups and group exclusion retain three-valued logic', () async {
    expect(
        await search('(language:ja | (language:en rating:<=2)) -filename:live'),
        [beta]);
    expect(await search('-(bitrate:>=320 | language:ja)'), [beta]);
    expect(await search('-(bitrate:>=320 language:en)'),
        containsAll([alpha, beta]));
    expect(await search('-(-filename:alpha)'), [alpha]);
  });
  test('plain parentheses and quoted operators retain literal behavior',
      () async {
    expect(
        AudioSearchQuery.parse('A Song (Live)').hasStructuredSyntax, isFalse);
    expect(AudioSearchQuery.parse('or').hasStructuredSyntax, isFalse);
    expect(AudioSearchQuery.parse('"OR"').terms.single.value, 'or');
    expect(
        AudioSearchQuery.parse('filename:"A (live) | B.flac"')
            .terms
            .single
            .value,
        'a (live) | b.flac');
  });
  test('numeric date group limits reject malformed expressions before search',
      () {
    for (final query in [
      'filesize:-1',
      'filesize:1e20',
      'samplerate:0.001Hz',
      'rating:6',
      'playcount:1000000001',
      'filesize:9000000000000001',
      'bitrate:320Hz',
      'added:2026-02-30',
      'added:2026-10-01..2026-01-01',
      'has:channels',
      'bitrate:320 OR',
      '| format:flac',
      '() format:flac',
      '(format:flac',
      'format:flac)',
      '${'(' * 10}filename:alpha${')' * 10}',
      List.filled(65, 'format:flac').join(' ')
    ]) {
      expect(() => AudioSearchQuery.parse(query),
          throwsA(isA<AudioSearchQueryException>()),
          reason: query);
    }
  });
  test('unrelated metadata queries never open personal storage', () async {
    var reads = 0;
    await index.searchAll('(filename:alpha | bitrate:128) -has:language',
        statistics: statistics, loadPersonal: () async {
      reads++;
      throw StateError('unused store');
    });
    expect(reads, 0);
  });
  test(
      'personal publication during initial storage read retries before scoring',
      () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final original = Map<String, PersonalTrack>.of(personal);
    var reads = 0;
    final pending = index.searchAll('rating:>=4', statistics: statistics,
        loadPersonal: () async {
      if (++reads == 1) {
        entered.complete();
        await release.future;
        return original;
      }
      return personal;
    });
    await entered.future;
    personal[beta.stableTrackId] = const PersonalTrack(rating: 5);
    PersonalLibrary.changes.value++;
    release.complete();
    expect((await pending).audios, containsAll([alpha, beta]));
    expect(reads, 2);
  });
  test('cancellation after a held personal read detaches the history listener',
      () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var cancelled = false;
    final pending = index.searchAll('rating:>=4 OR playcount:>=1',
        statistics: statistics, loadPersonal: () async {
      entered.complete();
      await release.future;
      return personal;
    }, checkCancelled: () {
      if (cancelled) throw StateError('cancelled');
    });
    await entered.future;
    // Check that the temporary subscription itself is released on cancellation.
    // ignore: invalid_use_of_protected_member
    expect(statistics.hasListeners, isTrue);
    cancelled = true;
    release.complete();
    await expectLater(pending, throwsStateError);
    // ignore: invalid_use_of_protected_member
    expect(statistics.hasListeners, isFalse);
  });
  test('history publication during a yielding query retries a scalar snapshot',
      () async {
    publish([
      alpha,
      beta,
      unknown,
      for (var i = 0; i < 600; i++) fixture('extra-$i')
    ]);
    var checks = 0;
    final results = await search('playcount:>=1', limit: 1000, check: () {
      if (++checks == 5) statistics.start(beta);
    });
    expect(results, containsAll([alpha, beta]));
    expect(results, hasLength(2));
  });
  test(
      'personal publication retries and an unpublished edit cannot mix one query',
      () async {
    publish([
      alpha,
      beta,
      unknown,
      for (var i = 0; i < 600; i++) fixture('extra-$i')
    ]);
    var checks = 0;
    final old = await search('rating:>=4', check: () {
      if (++checks == 5) {
        personal[beta.stableTrackId] = const PersonalTrack(rating: 5);
      }
    });
    expect(old, [alpha]);
    personal[beta.stableTrackId] = const PersonalTrack(rating: 2);
    checks = 0;
    final fresh = await search('rating:>=4', check: () {
      if (++checks == 5) {
        personal[beta.stableTrackId] = const PersonalTrack(rating: 5);
        PersonalLibrary.changes.value++;
      }
    });
    expect(fresh, containsAll([alpha, beta]));
  });
  test('live numeric snapshots refresh without rebuilding text projections',
      () async {
    publish([
      alpha,
      beta,
      unknown,
      for (var i = 0; i < 600; i++) fixture('extra-$i')
    ]);
    var checks = 0;
    final original = await search('bitrate:>=320', check: () {
      if (++checks == 5) beta.bitrate = 320;
    });
    expect(original, [alpha]);
    AudioLibrary.instance.publishDurationChanges();
    expect(await search('bitrate:>=320'), containsAll([alpha, beta]));
  });
}
