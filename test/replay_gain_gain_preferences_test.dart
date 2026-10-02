import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/play_service/replay_gain.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const track = ReplayGainPreferences(mode: ReplayGainMode.track);
  const empty = ReplayGainTags();
  double factor(double gain) => math.pow(10, gain / 20).toDouble();

  test('legacy zero defaults preserve unapplied and disabled behavior', () {
    final legacy = ReplayGainPreferences.fromJson(
        {'mode': 'track', 'preventClipping': false});
    expect(legacy.preampDb, 0);
    expect(legacy.fallbackGainDb, 0);
    expect(empty.volume(.8, legacy), .8);
    expect(empty.appliedSource(legacy), isNull);
    expect(empty.effectiveGainDb(.8, legacy), isNull);
    final off = legacy.copyWith(
        mode: ReplayGainMode.off, preampDb: 12, fallbackGainDb: -6);
    for (final tags in [empty, const ReplayGainTags(trackGainDb: -12)]) {
      expect(tags.volume(.8, off), .8);
      expect(tags.requestedGainDb(off), isNull);
      expect(tags.appliedSource(off), isNull);
      expect(tags.effectiveGainDb(.8, off), isNull);
    }
  });

  test('gain preferences reject nonfinite JSON and clamp finite bounds', () {
    for (final bad in [
      null,
      '6',
      true,
      double.nan,
      double.infinity,
      double.negativeInfinity
    ]) {
      final value = ReplayGainPreferences.fromJson(
          {'preampDb': bad, 'fallbackGainDb': bad, 'mode': 'album'});
      expect(value.preampDb, 0);
      expect(value.fallbackGainDb, 0);
      expect(value.mode, ReplayGainMode.album);
    }
    final exponent = ReplayGainPreferences.fromJson(
        jsonDecode('{"preampDb":1e400,"fallbackGainDb":-1e400}'));
    expect(exponent.preampDb, 0);
    expect(exponent.fallbackGainDb, 0);
    final finite = ReplayGainPreferences.fromJson(
        {'preampDb': 500, 'fallbackGainDb': -500});
    expect(finite.preampDb, 24);
    expect(finite.fallbackGainDb, -24);
    expect(jsonEncode(finite.toJson()), contains('24.0'));
    const invalidConstructor = ReplayGainPreferences(
        preampDb: double.nan, fallbackGainDb: double.infinity);
    expect(invalidConstructor.toJson()['preampDb'], 0);
    expect(invalidConstructor.toJson()['fallbackGainDb'], 0);
  });

  test('copy and identity include both gains without losing mode protection',
      () {
    final value = track.copyWith(preampDb: 2.25, fallbackGainDb: -4.5);
    expect(value.mode, ReplayGainMode.track);
    expect(value.preventClipping, isTrue);
    expect(ReplayGainPreferences.fromJson(value.toJson()), value);
    expect(ReplayGainPreferences.fromJson(value.toJson()).hashCode,
        value.hashCode);
    expect(value.copyWith(preampDb: 3), isNot(value));
    expect(value.copyWith(fallbackGainDb: -3), isNot(value));
    expect(value.copyWith(preventClipping: false).preampDb, 2.25);
    expect(value.copyWith(mode: ReplayGainMode.album).fallbackGainDb, -4.5);
  });

  test('tag plus preamp ignores fallback and caps only their final sum', () {
    const tags = ReplayGainTags(trackGainDb: 12, trackPeak: 1);
    final value = track.copyWith(preampDb: -12, fallbackGainDb: -24);
    expect(tags.requestedGainDb(value), 0);
    expect(tags.volume(.8, value), closeTo(.8, 1e-12),
        reason:
            'Clipping +12 dB before adding -12 dB would wrongly attenuate.');
    expect(tags.appliedSource(value), 'track');
    expect(tags.effectiveGainDb(.8, value), closeTo(0, 1e-12));
    final boosted = value.copyWith(preampDb: 3);
    expect(tags.volume(.8, boosted), 1);
    expect(tags.volume(1.5, boosted), 1);
  });

  test('album selection and track fallback use their own peak with preamp', () {
    const tags = ReplayGainTags(
        trackGainDb: -6, trackPeak: .5, albumGainDb: -12, albumPeak: 2);
    final value = track.copyWith(
        mode: ReplayGainMode.album, preampDb: 6, fallbackGainDb: 24);
    expect(tags.volume(.8, value), closeTo(.8 * factor(-6), 1e-12));
    expect(tags.appliedSource(value), 'album');
    const withoutAlbum =
        ReplayGainTags(trackGainDb: -6, trackPeak: .5, albumPeak: 2);
    expect(withoutAlbum.volume(.8, value), closeTo(.8, 1e-12));
    expect(withoutAlbum.appliedSource(value), 'track');
  });

  test('missing tags combine preamp fallback and report actual protected gain',
      () {
    final value = track.copyWith(preampDb: 3, fallbackGainDb: -9);
    expect(empty.requestedGainDb(value), -6);
    expect(empty.volume(.8, value), closeTo(.8 * factor(-6), 1e-12));
    expect(empty.appliedMode(value), isNull);
    expect(empty.appliedSource(value), 'fallback');
    expect(empty.effectiveGainDb(.8, value), closeTo(-6, 1e-12));
    final boost = value.copyWith(fallbackGainDb: 3);
    expect(empty.volume(.8, boost), .8);
    expect(empty.effectiveGainDb(.8, boost), closeTo(0, 1e-12));
    expect(empty.volume(.8, boost.copyWith(preventClipping: false)),
        closeTo(.8 * factor(6), 1e-12));
    expect(empty.effectiveGainDb(0, value), isNull);
    expect(empty.volume(0, value), 0);
  });

  test('peak-only metadata protects fallback without borrowing another mode',
      () {
    const peakOnly = ReplayGainTags(trackPeak: .5, albumPeak: 2);
    final value = track.copyWith(fallbackGainDb: 6);
    expect(peakOnly.volume(.8, value), closeTo(.8 * factor(6), 1e-12));
    expect(peakOnly.volume(.8, value.copyWith(mode: ReplayGainMode.album)), .5);
    expect(const ReplayGainTags(albumPeak: .1).volume(.8, value), .8);
  });

  test('invalid tags use fallback while finite preamp cannot corrupt output',
      () {
    const tags = ReplayGainTags(trackGainDb: double.nan, trackPeak: double.nan);
    const value = ReplayGainPreferences(
        mode: ReplayGainMode.track,
        preampDb: double.infinity,
        fallbackGainDb: -6);
    expect(tags.volume(.8, value), closeTo(.8 * factor(-6), 1e-12));
    expect(tags.appliedSource(value), 'fallback');
    final positive = value.copyWith(preampDb: 12, fallbackGainDb: 0);
    expect(const ReplayGainTags(trackGainDb: -6).volume(.8, positive), .8);
  });

  group('real isolated AppSettings persistence', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const data = MethodChannel('plugins.flutter.io/path_provider');
    const window = MethodChannel('window_manager');
    final parent = p.normalize(p.join(Directory.current.path, '..', 'tool',
        'qa-local', 'replaygain-gain-next', 'persistence'));
    late Directory fixture;
    late File file;
    late ReplayGainPreferences previous;
    late UiLanguage language;
    setUp(() async {
      expect(
          Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
      await Directory(parent).create(recursive: true);
      fixture = await Directory(parent).createTemp('settings-');
      messenger.setMockMethodCallHandler(data, (_) async => fixture.path);
      messenger.setMockMethodCallHandler(window,
          (_) async => throw StateError('Unexpected native window query'));
      file = File(p.join((await getAppDataDir()).path, 'settings.json'));
      previous = AppSettings.instance.replayGain.value;
      language = uiLanguage.value;
    });
    tearDown(() async {
      AppSettings.instance.replayGain.value = previous;
      uiLanguage.value = language;
      messenger.setMockMethodCallHandler(data, null);
      messenger.setMockMethodCallHandler(window, null);
      expect(p.isWithin(parent, await fixture.resolveSymbolicLinks()), isTrue);
      await fixture.delete(recursive: true);
    });

    test('fractional gains survive settings save reload with original options',
        () async {
      final prefs = track.copyWith(
          mode: ReplayGainMode.album,
          preventClipping: false,
          preampDb: 2.25,
          fallbackGainDb: -4.75);
      AppSettings.instance.replayGain.value = prefs;
      await AppSettings.instance
          .saveSettings(throwOnError: true, captureWindowSize: false);
      expect(
          jsonDecode(await file.readAsString())['ReplayGain'], prefs.toJson());
      AppSettings.instance.replayGain.value = const ReplayGainPreferences();
      await AppSettings.readFromJson();
      expect(AppSettings.instance.replayGain.value, prefs);
    });

    test('old settings load neutral gains and save compatible original fields',
        () async {
      await file.writeAsString(jsonEncode({
        'Version': '26.0.6',
        'ReplayGain': {'mode': 'album', 'preventClipping': false}
      }));
      AppSettings.instance.replayGain.value = track.copyWith(preampDb: 12);
      await AppSettings.readFromJson();
      final loaded = AppSettings.instance.replayGain.value;
      expect(
          loaded,
          const ReplayGainPreferences(
              mode: ReplayGainMode.album, preventClipping: false));
      await AppSettings.instance
          .saveSettings(throwOnError: true, captureWindowSize: false);
      expect(
          jsonDecode(await file.readAsString())['ReplayGain'], loaded.toJson());
    });

    test(
        'overflow persisted gains recover without discarding mode or protection',
        () async {
      await file.writeAsString('{"Version":"26.0.6","ReplayGain":'
          '{"mode":"track","preventClipping":false,'
          '"preampDb":1e400,"fallbackGainDb":-900}}');
      await AppSettings.readFromJson();
      final loaded = AppSettings.instance.replayGain.value;
      expect(loaded.mode, ReplayGainMode.track);
      expect(loaded.preventClipping, isFalse);
      expect(loaded.preampDb, 0);
      expect(loaded.fallbackGainDb, -24);
      await AppSettings.instance
          .saveSettings(throwOnError: true, captureWindowSize: false);
      expect(
          jsonDecode(await file.readAsString())['ReplayGain'], loaded.toJson());
    });
  });
}
