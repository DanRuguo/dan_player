import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:dan_player/data/cache_backup_service.dart';
import 'package:dan_player/play_service/waveform_service.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

Map<String, Object?> _statistics() => {
      'version': 3,
      'tracks': [],
      'days': {'2026-09-21': 192345, '2026-09-25': 789012, '2026-09-26': 0},
      'dailyPlayCounts': {'2026-09-21': 2, '2026-09-25': 7, '2026-09-26': 0},
      'playCountTrackingStartedOn': '2026-09-21',
      'hours': List<int>.generate(24, (hour) => hour == 13 ? 981357 : 0),
    };

Future<void> _json(File file, Object value) async {
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode(value));
}

Future<File> _repackStatistics(
    File original, File target, Map<String, Object?> data) async {
  final archive = ZipDecoder().decodeBytes(await original.readAsBytes());
  final payload = utf8.encode(jsonEncode(data));
  final manifest = jsonDecode(utf8.decode(archive.files
      .singleWhere((file) => file.name == 'manifest.json')
      .content as List<int>)) as Map;
  final entry = (manifest['files'] as List)
      .cast<Map>()
      .singleWhere((value) => value['path'] == 'playback_statistics.json');
  entry['size'] = payload.length;
  entry['sha256'] = sha256.convert(payload).toString();
  final rewritten = Archive();
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final bytes = file.name == 'payload/playback_statistics.json'
        ? payload
        : file.name == 'manifest.json'
            ? utf8.encode(jsonEncode(manifest))
            : file.content as List<int>;
    rewritten.addFile(ArchiveFile(file.name, bytes.length, bytes));
  }
  await target.writeAsBytes(ZipEncoder().encode(rewritten)!);
  return target;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory fixture;
  late Directory source;
  late Directory current;
  late File stats;
  late File backup;
  setUp(() async {
    final dataRoot = Platform.environment['DAN_PLAYER_DATA_DIR'];
    if (dataRoot == null ||
        !path.isWithin(
            path.join(Directory.current.parent.path, 'tool', 'qa-local'),
            dataRoot)) {
      throw StateError('Use independent workspace QA data');
    }
    fixture = await Directory(dataRoot).createTemp('followup-data-');
    source = await Directory(path.join(fixture.path, 'source')).create();
    current = await Directory(path.join(fixture.path, 'current')).create();
    stats = File(path.join(source.path, 'playback_statistics.json'));
    backup = File(path.join(fixture.path, 'portable.bak'));
    await _json(stats, _statistics());
    await _json(File(path.join(current.path, 'playback_statistics.json')), {
      ..._statistics(),
      'days': {'2026-09-26': 927001}
    });
    await File(path.join(current.path, 'keep-live-data.bin'))
        .writeAsBytes([9, 2, 7]);
  });

  test(
      'statistics v3 backup restores exact daily counters and tracking boundary',
      () async {
    final expected = _statistics();
    PlaybackStatistics.validateSnapshot(expected);
    await const CacheBackupService()
        .exportBackup(source: source, destination: backup);
    Directory? staged;
    final target = Directory(path.join(fixture.path, 'target'));
    await const CacheBackupService().restoreBackup(
        backup: backup,
        destination: target,
        currentData: current,
        activateLocation: (_, staging) async {
          staged = staging;
        });
    final actual = jsonDecode(
        await File(path.join(staged!.path, 'playback_statistics.json'))
            .readAsString());
    expect(actual, expected);
    final recorder = PlaybackStatistics.inMemory(
        initialData: Map<String, Object?>.from(actual as Map));
    addTearDown(recorder.dispose);
    expect(recorder.dailyMilliseconds, expected['days']);
    expect(recorder.dailyPlayCounts, expected['dailyPlayCounts']);
    expect(recorder.playCountTrackingStartedOn, '2026-09-21');
    expect(await target.exists(), isFalse);
  });

  test(
      'bounded waveform cache round trips without packaging audio or file paths',
      () async {
    final key = sha256
        .convert(utf8.encode('source revision and cue segment'))
        .toString();
    final expected = {
      'version': 1,
      'entries': {
        key: {
          'duration': 123.75,
          'peaks': List<double>.generate(512, (index) => (index % 17) / 16),
        }
      }
    };
    WaveformService.validateCache(expected);
    await _json(File(path.join(source.path, 'waveform_cache.json')), expected);
    await const CacheBackupService()
        .exportBackup(source: source, destination: backup);
    final archive = ZipDecoder().decodeBytes(await backup.readAsBytes());
    final manifest = jsonDecode(utf8.decode(archive.files
        .singleWhere((file) => file.name == 'manifest.json')
        .content as List<int>)) as Map;
    expect(manifest['music'], isEmpty);
    expect(manifest['songs'], isEmpty);
    expect(archive.files.where((file) => file.isFile).map((file) => file.name),
        contains('payload/waveform_cache.json'));
    Directory? staged;
    await const CacheBackupService().restoreBackup(
        backup: backup,
        destination: Directory(path.join(fixture.path, 'waveform-target')),
        currentData: current,
        activateLocation: (_, staging) async {
          staged = staging;
        });
    final actual = jsonDecode(
        await File(path.join(staged!.path, 'waveform_cache.json'))
            .readAsString());
    expect(actual, expected);
    WaveformService.validateCache(Map<String, dynamic>.from(actual as Map));
  });

  test('followup lyric and waveform settings survive real backup restoration',
      () async {
    final expected = {
      'Version': '26.0.6-snapshot.2',
      'ArtistSeparator': ['/', '、'],
      'LocalLyricLineOrder': 'romanizationOriginalTranslation',
      'NowPlayingProgressStyle': 'waveform',
      'WaveformBarDensity': 'dense',
    };
    await _json(File(path.join(source.path, 'settings.json')), expected);
    await const CacheBackupService()
        .exportBackup(source: source, destination: backup);
    Directory? staged;
    await const CacheBackupService().restoreBackup(
        backup: backup,
        destination: Directory(path.join(fixture.path, 'settings-target')),
        currentData: current,
        activateLocation: (_, staging) async {
          staged = staging;
        });
    final actual = jsonDecode(
        await File(path.join(staged!.path, 'settings.json')).readAsString());
    for (final entry in expected.entries) {
      expect(actual[entry.key], entry.value, reason: entry.key);
    }
  });

  test(
      'export rejects future statistics and invalid day counts without replacing existing backup',
      () async {
    final original = [112, 114, 101, 118, 105, 111, 117, 115];
    final invalid = <Map<String, Object?>>[
      {..._statistics(), 'version': 4},
      {
        ..._statistics(),
        'dailyPlayCounts': {'2026-09-26': -1}
      },
      {
        ..._statistics(),
        'dailyPlayCounts': {'2026-09-26': 1.5}
      },
      {
        ..._statistics(),
        'dailyPlayCounts': {'2026-02-30': 1}
      },
      {..._statistics(), 'playCountTrackingStartedOn': '2026-99-99'},
    ];
    for (final value in invalid) {
      await _json(stats, value);
      await backup.writeAsBytes(original);
      await expectLater(
          const CacheBackupService()
              .exportBackup(source: source, destination: backup),
          throwsA(isA<CacheBackupException>()),
          reason: jsonEncode(value));
      expect(await backup.readAsBytes(), original);
      expect(jsonDecode(await stats.readAsString()), value);
    }
  });

  test(
      'restore rejects authenticated future or invalid statistics before activation and preserves live data',
      () async {
    await const CacheBackupService()
        .exportBackup(source: source, destination: backup);
    final live = File(path.join(current.path, 'playback_statistics.json'));
    final liveBefore = await live.readAsBytes();
    final invalid = <Map<String, Object?>>[
      {..._statistics(), 'version': 4},
      {
        ..._statistics(),
        'dailyPlayCounts': {'2026-09-26': -1}
      },
      {
        ..._statistics(),
        'dailyPlayCounts': {'2026-02-30': 1}
      },
      {..._statistics(), 'playCountTrackingStartedOn': '2026-99-99'},
    ];
    var activations = 0;
    for (var index = 0; index < invalid.length; index++) {
      final tampered = await _repackStatistics(backup,
          File(path.join(fixture.path, 'invalid-$index.bak')), invalid[index]);
      final target =
          Directory(path.join(fixture.path, 'invalid-target-$index'));
      await expectLater(
          const CacheBackupService().restoreBackup(
              backup: tampered,
              destination: target,
              currentData: current,
              activateLocation: (_, __) async {
                activations++;
              }),
          throwsA(isA<CacheBackupException>()),
          reason: jsonEncode(invalid[index]));
      expect(activations, 0);
      expect(await target.exists(), isFalse);
      expect(await live.readAsBytes(), liveBefore);
      expect(
          await File(path.join(current.path, 'keep-live-data.bin'))
              .readAsBytes(),
          [9, 2, 7]);
    }
  });
}
