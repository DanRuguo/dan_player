import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:dan_player/search/audio_search_index.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

// Opt in once at a milestone, not on each routine regression run:
// flutter test --no-pub --dart-define=DAN_RUN_LIBRARY_BASELINE=true
//   test/library_scale_baseline_test.dart --reporter expanded
// Set DAN_PLAYER_DATA_DIR to a disposable workspace QA directory beforehand.
// This test generates metadata only and writes no files, including that folder.
const _enabled = bool.fromEnvironment('DAN_RUN_LIBRARY_BASELINE');

double _milliseconds(Stopwatch watch) => watch.elapsedMicroseconds / 1000;
double _rounded(double number) => double.parse(number.toStringAsFixed(3));

double _percentile(List<double> samples, double percentile) {
  final ordered = [...samples]..sort();
  return _rounded(ordered[max(0, (ordered.length * percentile).ceil() - 1)]);
}

int? _rss() {
  try {
    return ProcessInfo.currentRss;
  } catch (_) {
    return null;
  }
}

int? _maximumRss() {
  try {
    return ProcessInfo.maxRss;
  } catch (_) {
    return null;
  }
}

List<Audio> _metadata(int count, String syntheticRoot) {
  const titles = [
    'Canon study',
    '稻香 合成标签',
    'Good Time demo',
    '結想は花となる short ver. fixture',
    'Night drive',
    '晨光',
    '静かな午後',
    'Instrumental sketch',
  ];
  final artistCount = max(10, count ~/ 100);
  return [
    for (var i = 0; i < count; i++)
      () {
        final cue = i % 100 == 0
            ? CueTrackReference(
                cuePath: path.join(syntheticRoot, 'cue', 'album_$i.cue'),
                sourcePath: path.join(syntheticRoot, 'cue', 'album_$i.flac'),
                number: 1,
                startFrame: 0,
                endFrame: 18000,
              )
            : null;
        return Audio(
          i == count - 1
              ? 'Needle Exact Tail'
              : '${titles[i % titles.length]} #${i.toString().padLeft(6, '0')}',
          'Fixture Artist ${(i % artistCount).toString().padLeft(4, '0')}',
          'Fixture Album ${(i ~/ 10).toString().padLeft(5, '0')}',
          i % 10 + 1,
          120 + i % 240,
          320,
          44100,
          cue?.identity ??
              path.join(syntheticRoot, 'album_${i ~/ 10}',
                  'track_$i.${['flac', 'mp3', 'wav'][i % 3]}'),
          1,
          1,
          'synthetic metadata',
          cueTrack: cue,
        );
      }(),
  ];
}

Future<void> _runScale(int count, String dataRoot) async {
  final library = AudioLibrary.instance;
  final rssBefore = _rss();
  final timer = Stopwatch()..start();
  final songs = _metadata(
      count, path.join(dataRoot, 'synthetic_metadata_only', '$count'));
  final metadataMs = _milliseconds(timer);

  timer.reset();
  library.folders
    ..clear()
    ..add(AudioFolder(songs, dataRoot, 1, 1));
  library.onlineAudioCollection.clear();
  library.rebuildDerivedCollections();
  final collectionsMs = _milliseconds(timer);

  timer.reset();
  final registry = TrackIdentityRegistry.inMemory();
  final ids = [
    for (final audio in songs) registry.idFor(audio.path, cue: audio.cueTrack),
  ];
  final identityBuildMs = _milliseconds(timer);
  expect(ids.toSet(), hasLength(count));

  timer.reset();
  final byPath = library.audioByPath;
  final pathMapBuildMs = _milliseconds(timer);
  expect(byPath, hasLength(count));

  timer.reset();
  await AudioSearchIndex.instance.ensureBuilt();
  final searchBuildMs = _milliseconds(timer);
  final rssAfterBuild = _rss();

  const lookupCount = 10000;
  var identityHits = 0;
  timer.reset();
  for (var i = 0; i < lookupCount; i++) {
    final ordinal = i * 7919 % count;
    final audio = songs[ordinal];
    if (registry.idFor(audio.path, cue: audio.cueTrack) == ids[ordinal]) {
      identityHits++;
    }
  }
  final identityLookupMs = _milliseconds(timer);
  expect(identityHits, lookupCount);

  var pathHits = 0;
  timer.reset();
  for (var i = 0; i < lookupCount; i++) {
    final audio = songs[i * 7919 % count];
    if (identical(library.audioByPath[audio.path], audio)) pathHits++;
  }
  final pathLookupMs = _milliseconds(timer);
  expect(pathHits, lookupCount);

  // The compatibility resolver is distinct from the normal ID/location map.
  // Sample it separately so a slow legacy-alias path cannot hide behind cached
  // O(1) lookups. Nine calls are observations, not a full migration benchmark.
  final aliasSamples = <double>[];
  for (var repeat = 0; repeat < 3; repeat++) {
    for (final ordinal in [0, count ~/ 2, count - 1]) {
      timer.reset();
      final result = registry.resolvePath(songs[ordinal].path);
      aliasSamples.add(_milliseconds(timer));
      expect(result, ids[ordinal]);
    }
  }

  const queries = [
    'fixture',
    '稻香',
    'daoxiang',
    'Good Time',
    '結想は花となる',
    'Needle Exact Tail',
    '__no_such_metadata_987654321__',
  ];
  final querySamples = <double>[];
  final perQuery = <String, List<double>>{};
  for (var repeat = 0; repeat < 3; repeat++) {
    for (final query in queries) {
      timer.reset();
      final result = await AudioSearchIndex.instance.searchAll(query);
      final elapsed = _milliseconds(timer);
      querySamples.add(elapsed);
      perQuery.putIfAbsent(query, () => []).add(elapsed);
      expect(result.audios.length, lessThanOrEqualTo(200));
      if (query == 'Needle Exact Tail') {
        expect(result.audios.first, same(songs.last));
      } else if (query.startsWith('__no_such')) {
        expect(result.audios, isEmpty);
      } else {
        expect(result.audios, isNotEmpty);
      }
    }
  }

  // One structured stdout record per size; no parallel report or profile file.
  // RSS includes the Flutter test engine, JIT and earlier scale runs. No forced
  // GC is used, so these are process observations, not per-track heap costs.
  // ignore: avoid_print
  print('LIBRARY_SCALE_BASELINE ${jsonEncode({
        'tracks': count,
        'syntheticCueSegments': count ~/ 100,
        'artists': library.artistCollection.length,
        'albums': library.albumCollection.length,
        'timingMs': {
          'generateMetadata': _rounded(metadataMs),
          'rebuildDerivedCollections': _rounded(collectionsMs),
          'registerStableIdsCold': _rounded(identityBuildMs),
          'pathMapCold': _rounded(pathMapBuildMs),
          'searchIndexCold': _rounded(searchBuildMs),
          'stableIdLookup10000': _rounded(identityLookupMs),
          'pathLookup10000': _rounded(pathLookupMs),
          'legacyAliasLookupP50': _percentile(aliasSamples, .50),
          'legacyAliasLookupP95': _percentile(aliasSamples, .95),
          'searchP50': _percentile(querySamples, .50),
          'searchP95': _percentile(querySamples, .95),
          'searchMax': _rounded(querySamples.reduce(max)),
        },
        'queryCount': querySamples.length,
        'legacyAliasLookupCount': aliasSamples.length,
        'queryP50Ms': {
          for (final entry in perQuery.entries)
            entry.key: _percentile(entry.value, .50),
        },
        'rssBytes': {
          'beforeMetadata': rssBefore,
          'afterColdBuild': rssAfterBuild,
          'afterQueries': _rss(),
          'processHighWaterMark': _maximumRss(),
        },
      })}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('synthetic metadata scale baseline: 1000 / 10000 / 100000', () async {
    final dataRoot = Platform.environment['DAN_PLAYER_DATA_DIR'];
    if (dataRoot == null || dataRoot.isEmpty || !path.isAbsolute(dataRoot)) {
      throw StateError('Set DAN_PLAYER_DATA_DIR to an absolute isolated QA '
          'directory before explicitly running the scale baseline.');
    }
    // ignore: avoid_print
    print('LIBRARY_SCALE_ENV ${jsonEncode({
          'os': Platform.operatingSystem,
          'osVersion': Platform.operatingSystemVersion,
          'dartRuntime': Platform.version,
          'logicalProcessors': Platform.numberOfProcessors,
          'processor': Platform.environment['PROCESSOR_IDENTIFIER'],
          'mode': 'Flutter test / JIT, sequential scales in one process',
          'fixture':
              'Generated metadata; 1% CUE references; no media/cover files',
          'coldDefinition':
              'Search revision rebuilt at each size; process and JIT remain warm',
          'limits': 'No audio decoding, waveform, disk scanning, native devices, '
              'cover decoding, UI frame timing or listening quality measurement. '
              'Does not demonstrate real-device or whole-application performance.',
        })}');
    try {
      for (final count in [1000, 10000, 100000]) {
        await _runScale(count, dataRoot);
      }
    } finally {
      final library = AudioLibrary.instance;
      library.folders.clear();
      library.onlineAudioCollection.clear();
      library.rebuildDerivedCollections();
      await AudioSearchIndex.instance.ensureBuilt();
    }
  },
      skip: _enabled
          ? false
          : 'Opt-in milestone baseline; see run command above.',
      timeout: const Timeout(Duration(minutes: 5)));
}
