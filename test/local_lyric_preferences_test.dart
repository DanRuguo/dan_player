import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final settings = AppSettings.instance;
  final originalOrder = settings.localLyricLineOrder;
  final originalStyle = settings.nowPlayingProgressStyle.value;
  final originalDensity = settings.waveformBarDensity.value;
  late File settingsFile;
  setUpAll(() async {
    final root = Platform.environment['DAN_PLAYER_DATA_DIR'];
    if (root == null ||
        !path.isWithin(
            path.join(Directory.current.parent.path, 'tool', 'qa-local'),
            root)) {
      throw StateError('Use independent workspace QA data');
    }
    await Directory(root).create(recursive: true);
    settingsFile = File(path.join(root, 'settings.json'));
  });
  tearDown(() {
    settings.localLyricLineOrder = originalOrder;
    settings.nowPlayingProgressStyle.value = originalStyle;
    settings.waveformBarDensity.value = originalDensity;
  });
  test('legacy missing and unknown preferences choose conservative defaults',
      () async {
    for (final value in [null, 'future-value', 2]) {
      settings.localLyricLineOrder =
          LocalLyricLineOrder.romanizationOriginalTranslation;
      settings.nowPlayingProgressStyle.value = NowPlayingProgressStyle.waveform;
      settings.waveformBarDensity.value = WaveformBarDensity.dense;
      await settingsFile.writeAsString(jsonEncode({
        'ArtistSeparator': ['/', '、'],
        if (value != null) 'LocalLyricLineOrder': value,
        if (value != null) 'NowPlayingProgressStyle': value,
        if (value != null) 'WaveformBarDensity': value,
      }));
      await AppSettings.readFromJson();
      expect(settings.localLyricLineOrder, LocalLyricLineOrder.automatic);
      expect(settings.nowPlayingProgressStyle.value,
          NowPlayingProgressStyle.standard);
      expect(settings.waveformBarDensity.value, WaveformBarDensity.automatic);
    }
  });
  test('explicit new preferences round trip without translated storage keys',
      () async {
    settings.localLyricLineOrder =
        LocalLyricLineOrder.originalTranslationRomanization;
    settings.nowPlayingProgressStyle.value = NowPlayingProgressStyle.waveform;
    settings.waveformBarDensity.value = WaveformBarDensity.medium;
    await settings.saveSettings(captureWindowSize: false, throwOnError: true);
    final data = jsonDecode(await settingsFile.readAsString());
    expect(data['LocalLyricLineOrder'], 'originalTranslationRomanization');
    expect(data['NowPlayingProgressStyle'], 'waveform');
    expect(data['WaveformBarDensity'], 'medium');
    settings.localLyricLineOrder = LocalLyricLineOrder.automatic;
    settings.nowPlayingProgressStyle.value = NowPlayingProgressStyle.standard;
    settings.waveformBarDensity.value = WaveformBarDensity.automatic;
    await AppSettings.readFromJson();
    expect(settings.localLyricLineOrder,
        LocalLyricLineOrder.originalTranslationRomanization);
    expect(settings.nowPlayingProgressStyle.value,
        NowPlayingProgressStyle.waveform);
    expect(settings.waveformBarDensity.value, WaveformBarDensity.medium);
  });
}
