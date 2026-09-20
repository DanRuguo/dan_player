import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:dan_player/page/settings_page/animation_settings.dart';
import 'package:dan_player/performance_preset.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

class _Word extends SyncLyricWord {
  _Word(int start, String text)
      : super(Duration(seconds: start), const Duration(seconds: 4), text);
}

class _Line extends SyncLyricLine {
  _Line(int index)
      : super(Duration(seconds: index * 4), const Duration(seconds: 4),
            [_Word(index * 4, 'Melody $index')], 'A translated line');
}

class _Lyrics extends Lyric {
  _Lyrics() : super([for (var i = 0; i < 30; i++) _Line(i)]);
}

class _Fixture {
  final settings = AppSettings.instance;
  final style = LyricViewController()
    ..lyricFontSize = 24
    ..translationFontSize = 18;
  final positions = StreamController<double>.broadcast(sync: true);
  final hidden = ValueNotifier(false);
  final lyric = _Lyrics();
  double position = 20.9;

  void emit(double value) {
    position = value;
    positions.add(value);
  }

  Widget app() => MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        builder: (_, child) => RenderingPreferencesScope(
            preferences: settings.rendering, child: child!),
        home: Scaffold(
          body: Row(children: [
            SizedBox(
              width: 400,
              height: 480,
              child: ChangeNotifierProvider.value(
                value: style,
                child: ValueListenableBuilder(
                  valueListenable: settings.experience,
                  builder: (context, value, child) => VerticalLyricScrollView(
                    lyric: lyric,
                    positionStream: positions.stream,
                    readPosition: () => position,
                    onSeek: emit,
                    hidden: hidden,
                    springLyrics: value.springLyrics,
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: AnimationSettings(persist: () async {}),
              ),
            ),
          ]),
        ),
      );

  Future<void> dispose() async {
    await positions.close();
    hidden.dispose();
    style.dispose();
  }
}

LyricWordHighlightPainter _word(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<LyricWordHighlightPainter>()
    .firstWhere((painter) => painter.active);

void _expectStopped(WidgetTester tester) {
  expect(_word(tester).reducedMotion, isTrue);
  expect(_word(tester).movingWordCount, 0);
  expect(
      tester
          .widgetList<LyricFollowEffects>(find.byType(LyricFollowEffects))
          .every((effect) => effect.transition == null),
      isTrue);
  expect(
      tester
          .widgetList<ImageFiltered>(find.byType(ImageFiltered))
          .where((filter) => filter.enabled),
      isEmpty);
  expect(
      tester.widget<LyricViewportFade>(find.byType(LyricViewportFade)).enabled,
      isFalse);
  expect(tester.binding.transientCallbackCount, 0);
}

void _expectWordSampling(WidgetTester tester, _Fixture fixture, bool enabled) {
  final painter = _word(tester);
  var repaints = 0;
  void repaint() => repaints++;
  painter.addListener(repaint);
  fixture.emit(fixture.position + .05);
  painter.removeListener(repaint);
  expect(repaints > 0, enabled,
      reason:
          'The actual painter must detach from the playback repaint source.');
}

Future<void> _expectNewFollow(WidgetTester tester, _Fixture fixture) async {
  fixture.emit(((fixture.position / 4).floor() + 1) * 4 + .9);
  await tester.pump();
  await tester.pump();
  expect(
      tester
          .widgetList<LyricFollowEffects>(find.byType(LyricFollowEffects))
          .any((effect) => effect.transition != null),
      isTrue);
  expect(_word(tester).reducedMotion, isFalse);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const provider = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory fixtureRoot;
  late PerformanceSnapshot original;
  late PerformancePresetState originalPreset;
  late PlayerExperiencePreferences originalExperience;

  setUp(() async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
    final testRoot =
        await Directory(path.join(Directory.current.path, 'build', 'test-data'))
            .create(recursive: true);
    fixtureRoot = await testRoot.createTemp('lyric-preset-integration-');
    messenger.setMockMethodCallHandler(provider, (_) async => fixtureRoot.path);
    expect(
        path.isWithin(fixtureRoot.path, (await getAppDataDir()).path), isTrue);
    final settings = AppSettings.instance;
    original = settings.performancePresets.capture();
    originalPreset = settings.performancePresets.value;
    originalExperience = settings.experience.value;
    settings.performancePresets.value = const PerformancePresetState();
    settings.rendering.value = const RenderingPreferences(
      animations: MotionPreferences(disabled: {MotionKind.tracking}),
    );
    settings.backgrounds.value = const BackgroundPreferences(
      main:
          BackgroundAppearance(source: BackgroundSource.artwork, motion: true),
      nowPlaying:
          BackgroundAppearance(source: BackgroundSource.artwork, motion: true),
      mini:
          BackgroundAppearance(source: BackgroundSource.artwork, motion: false),
    );
    settings.experience.value =
        const PlayerExperiencePreferences(springLyrics: false);
    settings.dynamicTheme = false;
  });

  tearDown(() async {
    final settings = AppSettings.instance;
    settings.performancePresets.apply(original);
    settings.performancePresets.value = originalPreset;
    settings.experience.value = originalExperience;
    messenger.setMockMethodCallHandler(provider, null);
    final resolved = await fixtureRoot.resolveSymbolicLinks();
    final testRoot = path.join(Directory.current.path, 'build', 'test-data');
    if (!path.isWithin(testRoot, resolved) ||
        !path.basename(resolved).startsWith('lyric-preset-integration-')) {
      throw StateError('Refusing to delete an unverified fixture');
    }
    await Directory(resolved).delete(recursive: true);
  });

  testWidgets(
      'real performance presets stop and restore the mounted lyric effects and snapshot',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    final settings = fixture.settings;
    final before = settings.performancePresets.capture().toMap();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    _expectWordSampling(tester, fixture, true);
    await _expectNewFollow(tester, fixture);
    await tester.runAsync(
        () => settings.performancePresets.select(PerformanceMode.economy));
    await tester.pumpAndSettle();
    _expectStopped(tester);
    _expectWordSampling(tester, fixture, false);
    for (final scene in BackgroundScene.values) {
      expect(settings.backgrounds.value.forScene(scene).motion, isFalse);
    }
    await tester.runAsync(
        () => settings.performancePresets.select(PerformanceMode.performance));
    await tester.pumpAndSettle();
    _expectWordSampling(tester, fixture, true);
    await _expectNewFollow(tester, fixture);
    expect(settings.rendering.value.animations.allEnabled, isTrue);
    for (final scene in BackgroundScene.values) {
      expect(settings.backgrounds.value.forScene(scene).motion, isTrue);
    }
    await tester.runAsync(
        () => settings.performancePresets.select(PerformanceMode.custom));
    await tester.pumpAndSettle();
    expect(settings.performancePresets.capture().toMap(), before);
    expect(settings.performancePresets.value.before, isNull);
    _expectWordSampling(tester, fixture, true);
    final saved = await tester.runAsync(() async => jsonDecode(
        await File(path.join((await getAppDataDir()).path, 'settings.json'))
            .readAsString()));
    expect(saved['PerformancePreset'], {'mode': 'custom'});
    expect(saved['Rendering'], before['rendering']);
  });

  testWidgets(
      'actual animation management buttons gate new word and line effects together',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _expectNewFollow(tester, fixture);
    await tester.tap(find.byKey(const ValueKey('animations-all-off')));
    await tester.pumpAndSettle();
    _expectStopped(tester);
    _expectWordSampling(tester, fixture, false);
    for (final scene in BackgroundScene.values) {
      expect(
          fixture.settings.backgrounds.value.forScene(scene).motion, isFalse);
    }
    await tester.tap(find.byKey(const ValueKey('animations-all-on')));
    await tester.pumpAndSettle();
    _expectWordSampling(tester, fixture, true);
    await _expectNewFollow(tester, fixture);
    for (final scene in BackgroundScene.values) {
      expect(fixture.settings.backgrounds.value.forScene(scene).motion, isTrue);
    }
    final lyricsSwitch = tester
        .widget<SwitchListTile>(find.byKey(const ValueKey('animation-lyrics')));
    lyricsSwitch.onChanged!(false);
    await tester.pumpAndSettle();
    _expectStopped(tester);
    _expectWordSampling(tester, fixture, false);
    expect(fixture.settings.backgrounds.value.nowPlaying.motion, isTrue);
  });

  testWidgets(
      'hidden preference cancels a live follow and preset changes cannot restart it',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _expectNewFollow(tester, fixture);
    await tester.pump(const Duration(milliseconds: 90));
    fixture.hidden.value = true;
    await tester.pumpAndSettle();
    _expectStopped(tester);
    final lastPosition = _word(tester).position;
    fixture.emit(64.9);
    await tester.runAsync(() => fixture.settings.performancePresets
        .select(PerformanceMode.performance));
    await tester.pumpAndSettle();
    _expectStopped(tester);
    expect(_word(tester).position, lastPosition);
    fixture.hidden.value = false;
    await tester.pumpAndSettle();
    expect(_word(tester).position, const Duration(milliseconds: 64900));
    _expectWordSampling(tester, fixture, true);
    final scroll =
        tester.getRect(find.byKey(const ValueKey('vertical-lyric-scroll')));
    final row = tester.getRect(find.byType(LyricViewTile).at(16));
    expect(
        row.top, closeTo(scroll.top + (scroll.height - row.height) * .25, .1));
    expect(
        tester
            .widgetList<LyricFollowEffects>(find.byType(LyricFollowEffects))
            .every((effect) => effect.transition == null),
        isTrue);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
