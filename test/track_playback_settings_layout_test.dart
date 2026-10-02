import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_dialog_resize.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/track_playback_settings_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/play_service/playback_rate.dart';
import 'package:dan_player/play_service/track_playback_settings.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/listening_status_fixture.dart';
import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

class _Store extends PersonalLibrary {
  _Store() : super(File('unused-layout-store.json'));
  TrackPlaybackSettings? saved =
      const TrackPlaybackSettings(rate: .875, pitch: -2.5);
  final writes = <TrackPlaybackSettings?>[];
  @override
  Future<TrackPlaybackSettings?> playbackFor(String track) async => saved;
  @override
  Future<void> setPlayback(Audio audio, TrackPlaybackSettings? settings) async {
    writes.add(settings);
    saved = settings;
  }
}

Finder key(String value) => find.byKey(ValueKey(value));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);
  final audio = CategoryTestAudio('夜曲 — The midnight melody 마지막 선율 🎵');
  const defaults = TrackPlaybackSettings(rate: 1, pitch: 0);

  Future<void> mount(WidgetTester tester, _Store store,
      {double width = 1000,
      double scale = 1,
      bool animated = false,
      GlobalKey? boundary,
      Future<bool> Function(TrackPlaybackSettings?)? onSaved}) async {
    sizePlaylistFeature(tester, width: width, height: 1100);
    await tester.pumpWidget(listeningStatusHost(
        Builder(
            builder: (context) => FilledButton(
                key: const ValueKey('open-track-layout'),
                onPressed: () => showAppDialog<void>(
                    context: context,
                    builder: (dialogContext) => MediaQuery(
                        data: MediaQuery.of(dialogContext)
                            .copyWith(disableAnimations: !animated),
                        child: MotionPreferencesScope(
                            preferences: const MotionPreferences(),
                            child: TrackPlaybackSettingsDialog(
                                audio: audio,
                                defaults: defaults,
                                effective: defaults,
                                store: store,
                                onSaved: onSaved)))),
                child: const Text('Open'))),
        scale: scale,
        boundary: boundary,
        brightness: width < 500 ? Brightness.dark : Brightness.light));
    await tester.tap(key('open-track-layout'));
    await tester.pumpAndSettle();
    expect(find.byType(AppDialogResize), findsOneWidget);
  }

  testWidgets('wide controls share full equal columns and aligned baselines',
      (tester) async {
    await mount(tester, _Store());
    final rate = tester.getRect(key('track-rate'));
    final pitch = tester.getRect(key('track-pitch'));
    final group = tester.getRect(key('track-parameters-columns'));
    expect(rate.top, closeTo(pitch.top, .01));
    expect(rate.height, closeTo(pitch.height, .01));
    expect(rate.width, closeTo(pitch.width, .01));
    expect(rate.left, closeTo(group.left, .01));
    expect(pitch.right, closeTo(group.right, .01));
    expect(pitch.left - rate.right, closeTo(16, .01));
    expect(rate.width * 2 + 16, closeTo(group.width, .01));
    expect(rate.height, greaterThanOrEqualTo(44));
    for (final id in ['track-rate', 'track-pitch']) {
      expect(tester.widget<OutlinedButton>(key(id)).style!.shape!.resolve({}),
          AppShape.control);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'narrow large text stacks equal full-width controls without dead side',
      (tester) async {
    uiLanguage.value = UiLanguage.en;
    await mount(tester, _Store(), width: 360, scale: 2);
    final rate = tester.getRect(key('track-rate'));
    final pitch = tester.getRect(key('track-pitch'));
    final group = tester.getRect(key('track-parameters-rows'));
    expect(pitch.top, greaterThan(rate.bottom));
    expect(rate.left, closeTo(pitch.left, .01));
    expect(rate.right, closeTo(pitch.right, .01));
    expect(rate.width, closeTo(group.width, .01));
    expect(pitch.width, closeTo(group.width, .01));
    expect(find.text('0.88×'), findsOneWidget);
    expect(find.text('-2.5'), findsOneWidget);
    expect(find.text(ui('本曲播放速度')), findsOneWidget);
    expect(find.text(ui('本曲音调（半音）')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('width reflow retains draft selection and saves current values',
      (tester) async {
    final store = _Store();
    final global = AppSettings.instance.experience.value;
    final applied = <TrackPlaybackSettings?>[];
    await mount(tester, store, onSaved: (value) async {
      applied.add(value);
      return true;
    });
    await tester.tap(key('track-rate'));
    await tester.pumpAndSettle();
    await tester.tap(key('track-rate-option-1.25'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(360, 1100);
    await tester.pumpAndSettle();
    expect(key('track-parameters-rows'), findsOneWidget);
    expect(find.text(PlaybackRate.label(1.25)), findsOneWidget);
    await tester.ensureVisible(key('track-pitch'));
    await tester.tap(key('track-pitch'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(key('track-pitch-option-5.0'));
    await tester.tap(key('track-pitch-option-5.0'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1000, 1100);
    await tester.pumpAndSettle();
    expect(key('track-parameters-columns'), findsOneWidget);
    final button =
        find.descendant(of: key('track-pitch'), matching: find.text('+5'));
    expect(button, findsOneWidget);
    await tester.ensureVisible(key('track-settings-save'));
    await tester.tap(key('track-settings-save'));
    await tester.pumpAndSettle();
    expect(store.writes.single!.toMap(), {'rate': 1.25, 'pitch': 5.0});
    expect(applied, store.writes);
    expect(AppSettings.instance.experience.value, same(global));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'saved feedback grows real dialog content through intermediate height',
      (tester) async {
    await mount(tester, _Store(), animated: true);
    final content = find
        .descendant(
            of: find.byType(AlertDialog), matching: find.byType(Material))
        .first;
    final before = tester.getSize(content).height;
    await tester.tap(key('track-settings-save'));
    await tester.pump();
    await tester.pump();
    await tester.pump(AppMotion.standard ~/ 2);
    final middle = tester.getSize(content).height;
    await tester.pumpAndSettle();
    final after = tester.getSize(content).height;
    expect(find.text(ui('已记住本曲设置，下次播放时生效')), findsOneWidget);
    expect(middle, greaterThan(before),
        reason: 'dialog heights before=$before middle=$middle after=$after');
    expect(middle, lessThan(after));
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets(
          'track layout ${language.code} ${narrow ? 'narrow large' : 'wide'}',
          (tester) async {
        uiLanguage.value = language;
        final boundary = GlobalKey();
        await mount(tester, _Store(),
            width: narrow ? 360 : 1000,
            scale: narrow ? 2 : 1,
            boundary: boundary);
        final rate = tester.getRect(key('track-rate'));
        final pitch = tester.getRect(key('track-pitch'));
        expect(rate.width, closeTo(pitch.width, .01));
        if (narrow) {
          expect(key('track-parameters-rows'), findsOneWidget);
          expect(rate.left, closeTo(pitch.left, .01));
        } else {
          expect(key('track-parameters-columns'), findsOneWidget);
          expect(rate.top, closeTo(pitch.top, .01));
        }
        expect(find.text(ui('本曲播放速度')), findsOneWidget);
        expect(find.text(ui('本曲音调（半音）')), findsOneWidget);
        await captureListeningStatus(tester, boundary,
            'track-layout-${language.code}-${narrow ? 'narrow' : 'wide'}');
        for (final id in ['track-rate', 'track-pitch']) {
          await tester.ensureVisible(key(id));
          await tester.tap(key(id));
          await tester.pumpAndSettle();
          final selectedValue = id == 'track-rate' ? .875 : -2.5;
          final selected = key('$id-option-$selectedValue');
          await tester.ensureVisible(selected);
          expect(
              find.descendant(of: selected, matching: find.byIcon(Icons.check)),
              findsOneWidget);
          await captureListeningStatus(tester, boundary,
              'track-layout-${language.code}-${narrow ? 'narrow' : 'wide'}-$id');
          await tester.tap(selected);
          await tester.pumpAndSettle();
        }
        for (final action in ['track-settings-clear', 'track-settings-save']) {
          await tester.ensureVisible(key(action));
          expect(key(action).hitTestable(), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
