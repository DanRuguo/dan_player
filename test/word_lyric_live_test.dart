import 'dart:convert';
import 'dart:io';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/online_lyric_parser.dart';
import 'package:dan_player/online/kugou_music_api.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final samples = [
    ('君が好きだと叫びたい', 'BAAD', '君が好きだと叫びたい', 231.497143),
    ('結想は花となる', '堀江晶太', 'as:9-nine- ARTEISIA ORIGINAL SOUND TRACK', 195.578776),
    (
      'Kizuna No Kiseki',
      'MAN WITH A MISSION;MAN WITH A MISSION;MAN WITH A MISSION',
      'Kizuna No Kiseki',
      223.32
    ),
    ('紅蓮華', 'LiSA;LiSA', '紅蓮華', 238.586667),
  ];
  final samplePath = Platform.environment['DAN_LYRIC_LIVE_SAMPLES'];
  if (samplePath != null) {
    final entries = jsonDecode(
        File(samplePath).readAsStringSync().replaceFirst('\uFEFF', '')) as List;
    samples
      ..clear()
      ..addAll(entries.map((entry) => (
            entry['title'] as String,
            entry['artist'] as String,
            entry['album'] as String,
            (entry['duration'] as num).toDouble()
          )));
  }
  for (final sample in samples) {
    test('live previous sample ${sample.$1}', () async {
      final audio = Audio(sample.$1, sample.$2, sample.$3, 0, sample.$4.round(),
          null, null, 'readonly-fixture.mp3', 0, 0, null);
      final api = KugouMusicApi(CustomMusicSourceProfile.kugouPreset());
      final response = await searchLyricCandidates(audio,
          sources: ResultSource.values.toSet(),
          perSourceLimit: 5,
          maxAttempts: 1, kugouSearch: (query, limit) async {
        final result = await api.search(query, limit: limit);
        return [
          for (final track in result.tracks)
            SongSearchResult(
                ResultSource.kugou,
                track.title,
                track.artist,
                track.album,
                computeSongMatchScore(
                    audio, track.title, track.artist, track.album),
                kugouSongHash: track.onlineId,
                customAudio: track,
                durationSeconds: track.duration.toDouble())
        ];
      });
      final rows = <Map<String, Object?>>[];
      final loaded = <String, Lyric?>{};
      Future<Lyric?> load(SongSearchResult candidate) async {
        if (loaded.containsKey(candidate.identity)) {
          return loaded[candidate.identity];
        }
        final result = candidate.source == ResultSource.kugou
            ? parseOnlineLyricPayload(
                (await api.lyrics(candidate.customAudio!)).rawBody)
            : await getLyricForCandidate(candidate);
        loaded[candidate.identity] = result;
        return result;
      }

      for (final source in ResultSource.values) {
        final candidates =
            response.candidates.where((c) => c.source == source).take(2);
        for (final candidate in candidates) {
          Lyric? lyric;
          String? error;
          try {
            lyric = await load(candidate).timeout(const Duration(seconds: 16));
          } catch (e) {
            error = e.toString();
          }
          rows.add({
            'source': source.name,
            'title': candidate.title,
            'artist': candidate.artists,
            'duration': candidate.durationSeconds,
            'score': candidate.score,
            'versionCompatible':
                isAutomaticLyricCandidateCompatible(audio, candidate),
            'lines': lyric?.lines.length,
            'wordTiming': hasWordTiming(lyric),
            'error': error
          });
        }
      }
      final selected = await getMostMatchedLyric(audio,
          candidateSearch: (_) async => response, candidateLyricLoader: load);
      final report = {
        'sample': sample.$1,
        'localArtist': sample.$2,
        'localDuration': sample.$4,
        'failures': response.failures.map((k, v) => MapEntry(k.name, v)),
        'candidates': rows,
        'selectedLines': selected?.lines.length,
        'selectedWordTiming': hasWordTiming(selected)
      };
      final renderDirectory = Platform.environment['DAN_LYRIC_RENDER_SAMPLES'];
      if (renderDirectory != null && selected != null) {
        final file = File('$renderDirectory/${samples.indexOf(sample)}.json');
        await file.parent.create(recursive: true);
        await file.writeAsString(jsonEncode({
          'sample': sample.$1,
          'snapshot': LyricSnapshot.capture(selected).toJson(),
        }));
      }
      stdout.writeln('LIVE_RESULT ${jsonEncode(report)}');
      expect(response.candidates, isNotEmpty, reason: sample.$1);
    },
        skip: Platform.environment['DAN_LYRIC_LIVE'] != '1',
        timeout: const Timeout(Duration(minutes: 4)));
  }
}
