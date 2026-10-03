import 'dart:convert';

import 'package:dan_player/page/settings_page/desktop_integration_settings.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/search/settings_search_index.dart';
import 'package:dan_player/taskbar_lyrics_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_desktop_integration.dart';
import 'support/listening_status_fixture.dart';
import 'support/playlist_feature_fixture.dart';

const _nextLyric = ValueKey('taskbar-lyrics-next-lyric');
const _advanced = ValueKey('taskbar-lyrics-advanced');
const _color = ValueKey('taskbar-lyrics-color-scheme');

Future<void> _mount(WidgetTester tester, DesktopTestRig rig,
    {double width = 1080,
    double scale = 1,
    GlobalKey? boundary,
    Future<void> Function()? persist}) async {
  sizePlaylistFeature(tester, width: width, height: 1400);
  await tester.pumpWidget(listeningStatusHost(
    Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: DesktopIntegrationSettings(
                preferences: rig.preferences,
                integration: rig.integration,
                persist: persist ?? () async {}),
          ),
        ),
      ),
    ),
    scale: scale,
    seed: width < 500 ? Colors.orange : Colors.teal,
    brightness: width < 500 ? Brightness.dark : Brightness.light,
    boundary: boundary,
  ));
  await tester.pumpAndSettle();
}

Future<void> _expand(WidgetTester tester) async {
  final title = find.text(ui('更多任务栏歌词选项'));
  await tester.ensureVisible(title);
  await tester.tap(title);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  test('next lyric defaults and persistence preserve independent choices', () {
    for (final raw in [null, {}, 'false', 1]) {
      expect(TaskbarLyricsPreferences.fromMap(raw).showNextLyric, isTrue);
    }
    for (final invalid in [null, 'false', 0, [], {}]) {
      final parsed = TaskbarLyricsPreferences.fromMap(
          {'showNextLyric': invalid, 'strokeEnabled': true});
      expect(parsed.showNextLyric, isTrue);
      expect(parsed.strokeEnabled, isTrue);
    }
    const base = TaskbarLyricsPreferences(
        position: TaskbarLyricPosition.end,
        areaSelection: 65535,
        colorScheme: TaskbarLyricColorScheme.system,
        strokeEnabled: true,
        showNextButton: true,
        showNextTrack: false,
        showPauseIndicator: false);
    final oneLine = base.copyWith(showNextLyric: false);
    expect(oneLine, isNot(base));
    expect(oneLine.copyWith(showNextLyric: true), base);
    expect(oneLine.nextArea(), oneLine.copyWith(areaSelection: 0));
    final experience = const PlayerExperiencePreferences(
            closeToTray: true, playbackRate: .75, taskbarLyrics: true)
        .copyWith(taskbarAppearance: oneLine);
    final restored = PlayerExperiencePreferences.fromMap(
        jsonDecode(jsonEncode(experience.toMap())));
    expect(restored, experience);
    expect(restored.hashCode, experience.hashCode);
    expect(restored.taskbarAppearance.showNextLyric, isFalse);
    for (final language in UiLanguage.values) {
      final label = translateUi('显示下一句歌词', language);
      expect(searchSettings(label).where((e) => e.id == 'integration'),
          hasLength(1));
      if (language != UiLanguage.zh) expect(label, isNot('显示下一句歌词'));
    }
  });

  testWidgets('next lyric is direct and survives advanced edits and collapse',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    final saves = <PlayerExperiencePreferences>[];
    await _mount(tester, rig,
        persist: () async => saves.add(rig.preferences.value));
    expect(find.byKey(_color), findsNothing);
    expect(tester.widget<SwitchListTile>(find.byKey(_nextLyric)).value, isTrue);
    await tester.ensureVisible(find.byKey(_nextLyric));
    await tester.tap(find.byKey(_nextLyric));
    await tester.pumpAndSettle();
    expect(rig.preferences.value.taskbarAppearance.showNextLyric, isFalse);
    await _expand(tester);
    final expansion = tester.widget<ExpansionTile>(find.byKey(_advanced));
    expect(expansion.expansionAnimationStyle, AnimationStyle.noAnimation);
    final stroke = find.byKey(const ValueKey('taskbar-lyrics-stroke'));
    await tester.ensureVisible(stroke);
    await tester.tap(stroke);
    await tester.pumpAndSettle();
    expect(rig.preferences.value.taskbarAppearance.strokeEnabled, isTrue);
    expect(rig.preferences.value.taskbarAppearance.showNextLyric, isFalse);
    await _expand(tester);
    expect(find.byKey(_color), findsNothing);
    rig.preferences.value = PlayerExperiencePreferences.fromMap(
        jsonDecode(jsonEncode(rig.preferences.value.toMap())));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(_nextLyric));
    expect(
        tester.widget<SwitchListTile>(find.byKey(_nextLyric)).value, isFalse);
    await tester.tap(find.byKey(_nextLyric));
    await tester.pumpAndSettle();
    expect(saves, hasLength(3));
    expect(rig.preferences.value.taskbarAppearance.strokeEnabled, isTrue);
    expect(rig.preferences.value.taskbarAppearance.showNextLyric, isTrue);
    expect(rig.native.calls, isEmpty);
    expect(rig.playback.starts, 0);
    expect(PlayService.isInitialized, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('regrouped taskbar settings render real fonts in four languages',
      (tester) async {
    for (final language in UiLanguage.values) {
      for (final narrow in [false, true]) {
        uiLanguage.value = language;
        final rig = DesktopTestRig();
        final boundary = GlobalKey();
        final width = narrow ? 360.0 : 1080.0;
        final prefix = '${language.code}-${narrow ? 'narrow-large' : 'wide'}';
        await _mount(tester, rig,
            width: width, scale: narrow ? 2 : 1, boundary: boundary);
        expect(find.byKey(_color), findsNothing);
        await Scrollable.ensureVisible(
            tester.element(find.text(ui('更多任务栏歌词选项'))),
            alignment: 1);
        await tester.pumpAndSettle();
        await capturePlaylistFeature(tester, boundary, '$prefix-main');
        await _expand(tester);
        final appearance = find.text(ui('外观'));
        final content = find.text(ui('显示内容'));
        final appearanceRect = tester.getRect(appearance);
        final contentRect = tester.getRect(content);
        // The compact arrangement keeps appearance/content together, with
        // interaction beside them only when two natural-width columns fit.
        expect(contentRect.top, greaterThan(appearanceRect.bottom));
        expect(contentRect.left, appearanceRect.left);
        for (final key in [
          'taskbar-lyrics-color-scheme',
          'taskbar-lyrics-stroke',
          'taskbar-lyrics-next-track',
          'taskbar-lyrics-pause-indicator',
          'taskbar-lyrics-next-button',
        ]) {
          final control = find.byKey(ValueKey(key));
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          final rect = tester.getRect(control);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(1400));
        }
        await Scrollable.ensureVisible(
            tester.element(
                find.byKey(const ValueKey('taskbar-lyrics-next-button'))),
            alignment: 1);
        await tester.pumpAndSettle();
        await capturePlaylistFeature(tester, boundary, '$prefix-advanced');
        expect(find.text(ui('字体沿用播放器。')), findsOneWidget);
        expect(rig.native.calls, isEmpty);
        expect(rig.playback.starts, 0);
        expect(PlayService.isInitialized, isFalse);
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await rig.dispose();
      }
    }
  });
}
