import 'package:dan_player/component/playback_diagnostics_panel.dart';
import 'package:dan_player/page/now_playing_page/component/equalizer_dialog.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/src/bass/bass_equalizer.dart';
import 'package:desktop_lyric/l10n/catalog_equalizer_source.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/listening_status_fixture.dart';
import 'support/playlist_feature_fixture.dart';

class _Playback extends Fake implements PlaybackService {
  @override
  int eqEditRevision = 0;
  @override
  final eqEnabled = ValueNotifier(true);
  final gains = List<double>.filled(10, 0)..[9] = 6;
  @override
  List<double> get eqGains => List.of(gains);
  @override
  bool setEqEnabled(bool enabled) {
    eqEditRevision++;
    eqEnabled.value = enabled;
    return true;
  }

  @override
  void setEqBandGain(int band, double gain) {
    eqEditRevision++;
    gains[band] = gain;
  }

  @override
  void applyEqGains(List<double> values) {
    eqEditRevision++;
    gains.setAll(0, values);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPlaylistFeatureFonts);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  Future<void> mount(WidgetTester tester, _Playback playback,
      {int rate = 8000,
      double width = 1000,
      double height = 860,
      double scale = 1,
      Brightness brightness = Brightness.light,
      GlobalKey? boundary}) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(listeningStatusHost(
        EqualizerDialog(
            playbackService: playback,
            availableBands:
                BassEqualizer.supportFor(rate, peakingAvailable: true)),
        scale: scale,
        brightness: brightness,
        boundary: boundary));
    await tester.pumpAndSettle();
  }

  testWidgets('unsupported source bands are disabled without rewriting gains',
      (tester) async {
    final playback = _Playback();
    addTearDown(playback.eqEnabled.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, playback);
    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders.length, 10);
    expect(sliders.take(6).every((slider) => slider.onChanged != null), true);
    expect(sliders.skip(6).every((slider) => slider.onChanged == null), true);
    expect(playback.gains.last, 6);
    expect(find.byKey(const ValueKey('equalizer-unavailable-bands')),
        findsOneWidget);
    expect(find.byTooltip(ui('此音源不应用 {0} Hz；设置会在支持的音源上恢复。', ['16k'])),
        findsOneWidget);
    sliders[4].onChanged!(3);
    await tester.pump();
    expect(playback.gains[4], 3);
    expect(playback.gains.last, 6);
    expect(tester.takeException(), null);
  });

  testWidgets('source 8k to 44.1k recovers saved high bands in the same dialog',
      (tester) async {
    final playback = _Playback();
    addTearDown(playback.eqEnabled.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, playback);
    final state = tester.state(find.byType(EqualizerDialog));
    await mount(tester, playback, rate: 44100);
    expect(tester.state(find.byType(EqualizerDialog)), same(state));
    expect(
        tester
            .widgetList<Slider>(find.byType(Slider))
            .every((slider) => slider.onChanged != null),
        true);
    expect(tester.widgetList<Slider>(find.byType(Slider)).last.value, 6);
    expect(find.byKey(const ValueKey('equalizer-unavailable-bands')),
        findsNothing);
    expect(playback.gains.last, 6);
    expect(tester.takeException(), null);
  });

  testWidgets('EQ off and on keeps source limits and stored unavailable values',
      (tester) async {
    final playback = _Playback();
    addTearDown(playback.eqEnabled.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, playback, rate: 32000);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<Slider>(find.byType(Slider))
            .every((slider) => slider.onChanged == null),
        true);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders.take(9).every((slider) => slider.onChanged != null), true);
    expect(sliders.last.onChanged, null);
    expect(playback.gains.last, 6);
  });

  testWidgets(
      'diagnostics distinguish unavailable frequency from an FX failure',
      (tester) async {
    await tester.pumpWidget(listeningStatusHost(PlaybackDiagnosticsContent(
      snapshot: const {
        'phase': 'paused',
        'output': {
          'eqRequested': true,
          'eqAppliedBands': 6,
          'eqSettingsApplied': false,
          'eqImplementation': 'peaking',
          'eqUnavailableFrequencies': [4000, 8000, 12000, 16000],
        },
      },
      onExport: (_) async {},
      onRefresh: () {},
    )));
    await tester.pumpAndSettle();
    expect(find.text(ui('EQ 暂未应用频段')), findsOneWidget);
    expect(find.text('4000, 8000, 12000, 16000 Hz'), findsOneWidget);
    expect(find.text('BASS_FX PEAKEQ'), findsOneWidget);
    expect(tester.takeException(), null);
  });

  test('new EQ catalog has complete translations and integrated placeholders',
      () {
    for (final entry in catalogEqualizerSource.entries) {
      expect(entry.value.length, 3);
      final expectedParameters = RegExp(r'\{\d+\}')
          .allMatches(entry.key)
          .map((match) => match.group(0))
          .toSet();
      for (var language = 0; language < UiLanguage.values.length; language++) {
        uiLanguage.value = UiLanguage.values[language];
        final translated =
            language == 0 ? entry.key : entry.value[language - 1];
        expect(translated.trim(), isNotEmpty);
        expect(
            RegExp(r'\{\d+\}')
                .allMatches(translated)
                .map((match) => match.group(0))
                .toSet(),
            expectedParameters);
        expect(ui(entry.key), translated);
      }
    }
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets('EQ source capability ${language.code} narrow=$narrow',
          (tester) async {
        final playback = _Playback();
        addTearDown(playback.eqEnabled.dispose);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        uiLanguage.value = language;
        final boundary = GlobalKey();
        await mount(tester, playback,
            width: narrow ? 507 : 1000,
            height: narrow ? 360 : 860,
            scale: narrow ? 2 : 1,
            brightness: narrow ? Brightness.dark : Brightness.light,
            boundary: boundary);
        expect(find.text(ui('完成')).hitTestable(), findsOneWidget);
        // Reach the source limit notice through the real dialog scroll region.
        await tester.ensureVisible(
            find.byKey(const ValueKey('equalizer-unavailable-bands')));
        await tester.pumpAndSettle();
        expect(
            find
                .byKey(const ValueKey('equalizer-unavailable-bands'))
                .hitTestable(),
            findsOneWidget);
        expect(tester.takeException(), null);
        await captureListeningStatus(tester, boundary,
            'equalizer-${language.code}-${narrow ? 'narrow-dark-200' : 'wide-light'}');
      });
    }
  }
}
