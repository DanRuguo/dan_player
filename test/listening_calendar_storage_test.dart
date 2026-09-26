import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/statistics/listening_calendar.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final recorder = PlaybackStatistics.instance;
  late File primary;
  late File backup;
  setUp(() async {
    final override = Platform.environment['DAN_PLAYER_DATA_DIR'];
    if (override == null ||
        !p.isAbsolute(override) ||
        !override.replaceAll('\\', '/').contains('/tool/qa-local/')) {
      throw StateError(
          'Persistent tests require a dedicated workspace QA data directory');
    }
    final directory = await getAppDataDir();
    primary = File(p.join(directory.path, 'playback_statistics.json'));
    backup = File('${primary.path}.bak');
    await recorder.flush(finishSession: true);
  });
  tearDown(() async => recorder.flush(finishSession: true));

  test(
      'startup enables day counts at zero and preserves old time/all-time counts',
      () async {
    await primary.writeAsString(jsonEncode({
      'version': 2,
      'tracks': [
        {'id': 'online:netease:historical', 'playCount': 99}
      ],
      'days': {'2026-09-21': 5000}
    }));
    await recorder.initialize();
    await recorder.flush();
    expect(recorder.totalPlayCount, 99);
    expect(recorder.dailyPlayCounts, isEmpty);
    final today = listeningDayKey(localCalendarDate(DateTime.now()));
    expect(recorder.playCountTrackingStartedOn, today);
    expect(recorder.dailyMilliseconds, {'2026-09-21': 5000});
    final saved = jsonDecode(await primary.readAsString()) as Map;
    expect(saved['version'], 3);
    expect(saved['dailyPlayCounts'], isEmpty);
    expect(saved['playCountTrackingStartedOn'], today);
  });

  test(
      'real stored play counts survive flush/reload without counting a resume twice',
      () async {
    await primary.writeAsString('{"version":3,"tracks":[]}');
    await recorder.initialize();
    final audio = Audio.online(
        provider: 'netease',
        id: 'storage',
        title: 'Stored',
        artist: 'Artist',
        album: 'Album',
        duration: 180);
    recorder.start(audio);
    recorder.pause();
    recorder.start(audio);
    await recorder.flush(finishSession: true);
    final counts = Map<String, int>.of(recorder.dailyPlayCounts);
    final marker = recorder.playCountTrackingStartedOn;
    await recorder.initialize();
    expect(recorder.dailyPlayCounts, counts);
    expect(counts.values.single, 1);
    expect(recorder.totalPlayCount, 1);
    expect(recorder.playCountTrackingStartedOn, marker);
  });

  test(
      'future primary survives initialization and new playback despite an older valid backup',
      () async {
    const future = '{"version":4,"futurePrivateCounter":987654321}';
    const older = '{"version":2,"tracks":[],"days":{"2026-09-21":1}}';
    await primary.writeAsString(future);
    await backup.writeAsString(older);
    await recorder.initialize();
    expect(recorder.storageWarning, isNotNull);
    expect(recorder.tracks, isEmpty);
    final audio = Audio.online(
        provider: 'netease',
        id: 'future',
        title: 'Future',
        artist: 'Artist',
        album: 'Album',
        duration: 180);
    recorder.start(audio);
    await recorder.flush(finishSession: true);
    expect(await primary.readAsString(), future);
    expect(await backup.readAsString(), older);
  });
}
