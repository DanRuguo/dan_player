import 'package:dan_player/component/app_menu_anchor.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/playback_diagnostics_panel.dart';
import 'package:dan_player/page/settings_page/replay_gain_settings.dart';
import 'package:dan_player/play_service/replay_gain.dart';
import 'package:dan_player/search/settings_search_index.dart';
import 'package:desktop_lyric/l10n/catalog_replaygain_gain.dart';
import 'package:desktop_lyric/l10n/ui_catalog.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/listening_status_fixture.dart';
import 'support/playlist_feature_fixture.dart';

Finder key(String name) => find.byKey(ValueKey(name));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  Future<void> mount(WidgetTester tester, Widget panel,
      {double width = 900, double scale = 1, GlobalKey? boundary}) async {
    sizePlaylistFeature(tester,
        width: width, height: width < 500 ? 1800 : 1000);
    await tester.pumpWidget(listeningStatusHost(
        SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(12), child: panel)),
        boundary: boundary,
        scale: scale,
        brightness: width < 500 ? Brightness.dark : Brightness.light));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String id, double value) async {
    await tester.ensureVisible(key(id));
    await tester.tap(key(id));
    await tester.pumpAndSettle();
    final item = key('$id-option-$value');
    await tester.ensureVisible(item);
    await tester.tap(item);
    await tester.pumpAndSettle();
  }

  Future<void> custom(WidgetTester tester, String id) async {
    await tester.ensureVisible(key(id));
    await tester.tap(key(id));
    await tester.pumpAndSettle();
    final item = key('$id-custom');
    await tester.ensureVisible(item);
    await tester.tap(item);
    await tester.pumpAndSettle();
  }

  test('catalog exact placeholders and localized ReplayGain search entry', () {
    final arguments = RegExp(r'\{\d+\}');
    for (final entry in catalogReplaygainGain.entries) {
      expect(entry.value, hasLength(3), reason: entry.key);
      final placeholders =
          arguments.allMatches(entry.key).map((m) => m[0]).toSet();
      for (var index = 0; index < 3; index++) {
        final value = entry.value[index];
        expect(value.trim(), isNotEmpty, reason: entry.key);
        expect(
            arguments.allMatches(value).map((m) => m[0]).toSet(), placeholders);
        expect(uiCatalog[entry.key]![index], value);
        uiLanguage.value = UiLanguage.values[index + 1];
        expect(ui(entry.key), value);
      }
    }
    final entry = settingsSearchEntries.singleWhere((e) => e.id == 'gain');
    expect(entry.terms, containsAll(['ReplayGain 预增益', '无标签补偿']));
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      expect(searchSettings(ui('无标签补偿')), contains(entry));
      expect(searchSettings(ui('ReplayGain 预增益')), contains(entry));
    }
  });

  testWidgets('gain selections merge with latest mode clipping and each other',
      (tester) async {
    var prefs = const ReplayGainPreferences(
        mode: ReplayGainMode.album, preventClipping: false);
    await mount(
        tester,
        StatefulBuilder(
            builder: (context, setState) => ReplayGainSettingsPanel(
                preferences: prefs,
                onChanged: (update) => setState(() => prefs = update(prefs)))));
    await choose(tester, 'replay-gain-preamp', 3);
    await choose(tester, 'replay-gain-fallback', -6);
    expect(prefs.preampDb, 3);
    expect(prefs.fallbackGainDb, -6);
    expect(prefs.mode, ReplayGainMode.album);
    expect(prefs.preventClipping, isFalse);
    final button = tester.widget<OutlinedButton>(key('replay-gain-preamp'));
    expect(button.style!.shape!.resolve({}), AppShape.control);
    expect(tester.getSize(key('replay-gain-preamp')).height,
        greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'custom entry rejects invalid gains and retains decimal precision',
      (tester) async {
    var prefs = const ReplayGainPreferences(mode: ReplayGainMode.track);
    await mount(
        tester,
        StatefulBuilder(
            builder: (context, setState) => ReplayGainSettingsPanel(
                preferences: prefs,
                onChanged: (update) => setState(() => prefs = update(prefs)))));
    await custom(tester, 'replay-gain-preamp');
    for (final text in ['NaN', 'Infinity', '1e400', '25', '-25', '']) {
      await tester.enterText(key('replay-gain-number-input'), text);
      await tester.tap(find.text(ui('确定')));
      await tester.pumpAndSettle();
      expect(key('replay-gain-number-input'), findsOneWidget);
      expect(prefs.preampDb, 0);
      expect(
          find.text(ui('请输入 {0} 到 {1} 之间的增益（dB）', [-24, 24])), findsOneWidget);
    }
    await tester.enterText(key('replay-gain-number-input'), '-4.25');
    await tester.tap(find.text(ui('确定')));
    await tester.pumpAndSettle();
    expect(prefs.preampDb, -4.25);
    expect(prefs.fallbackGainDb, 0);
    expect(find.text('-4.25 dB'), findsOneWidget);
    await custom(tester, 'replay-gain-fallback');
    await tester.enterText(key('replay-gain-number-input'), '6.5');
    await tester.tap(find.text(ui('取消')));
    await tester.pumpAndSettle();
    expect(prefs.fallbackGainDb, 0);
    expect(prefs.preampDb, -4.25);
  });

  testWidgets('turning ReplayGain off during custom dialog rejects late entry',
      (tester) async {
    var prefs = const ReplayGainPreferences(mode: ReplayGainMode.track);
    await mount(
        tester,
        StatefulBuilder(
            builder: (context, setState) => ReplayGainSettingsPanel(
                preferences: prefs,
                onChanged: (update) => setState(() => prefs = update(prefs)))));
    await custom(tester, 'replay-gain-fallback');
    final mode = tester
        .widget<AppSegmentedControl<ReplayGainMode>>(key('replay-gain-mode'));
    mode.onChanged!(ReplayGainMode.off);
    await tester.pump();
    await tester.enterText(key('replay-gain-number-input'), '-6');
    await tester.tap(find.text(ui('确定')));
    await tester.pumpAndSettle();
    expect(prefs.mode, ReplayGainMode.off);
    expect(prefs.fallbackGainDb, 0);
    expect(tester.widget<OutlinedButton>(key('replay-gain-preamp')).onPressed,
        isNull);
    expect(tester.widget<OutlinedButton>(key('replay-gain-fallback')).onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('diagnostics distinguishes applied fallback from absent tag mode',
      (tester) async {
    await mount(
        tester,
        PlaybackDiagnosticsContent(snapshot: const {
          'phase': 'paused',
          'output': {
            'replayGainRequested': 'album',
            'replayGainApplied': null,
            'replayGainSource': 'fallback',
            'replayGainEffectiveDb': -6.0,
            'replayGainPreampDb': 3.0,
            'replayGainFallbackDb': -9.0,
            'effectiveDspMultiplier': .5,
          }
        }, onExport: (_) async {}, onRefresh: () {}));
    expect(find.text('${ui('专辑')} / ${ui('无标签补偿')}'), findsOneWidget);
    expect(find.text('-6.00 dB'), findsOneWidget);
    expect(find.text('3.00 dB'), findsOneWidget);
    expect(find.text('-9.00 dB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets(
          'render ${language.code} ${narrow ? 'narrow dark large' : 'wide light'}',
          (tester) async {
        uiLanguage.value = language;
        final boundary = GlobalKey();
        var prefs = const ReplayGainPreferences(
            mode: ReplayGainMode.album, preampDb: 2.25, fallbackGainDb: -4.75);
        await mount(
            tester,
            StatefulBuilder(
                builder: (context, setState) => ReplayGainSettingsPanel(
                    preferences: prefs,
                    onChanged: (update) =>
                        setState(() => prefs = update(prefs)))),
            width: narrow ? 380 : 1000,
            scale: narrow ? 1.8 : 1,
            boundary: boundary);
        final semantic = tester.ensureSemantics();
        try {
          expect(find.text(ui('ReplayGain 预增益')), findsOneWidget);
          expect(find.text(ui('无标签补偿')), findsOneWidget);
          expect(
              tester.getSemantics(find.text('+2.25 dB')),
              matchesSemantics(
                  label: '${ui('ReplayGain 预增益')}: +2.25 dB',
                  isButton: true,
                  hasEnabledState: true,
                  isEnabled: true,
                  isFocusable: true,
                  hasTapAction: true,
                  hasFocusAction: true,
                  textDirection: TextDirection.ltr));
          await captureListeningStatus(tester, boundary,
              'replaygain-${language.code}-${narrow ? 'narrow' : 'wide'}');
          await tester.ensureVisible(key('replay-gain-preamp'));
          await tester.tap(key('replay-gain-preamp'));
          await tester.pumpAndSettle();
          expect(find.byType(AppMenuAnchor), findsNWidgets(2));
          final selected = key('replay-gain-preamp-option-2.25');
          await tester.ensureVisible(selected);
          expect(
              find.descendant(of: selected, matching: find.byIcon(Icons.check)),
              findsOneWidget);
          await captureListeningStatus(tester, boundary,
              'replaygain-${language.code}-${narrow ? 'narrow' : 'wide'}-menu');
          expect(tester.takeException(), isNull);
        } finally {
          semantic.dispose();
        }
      });
    }
  }
}
