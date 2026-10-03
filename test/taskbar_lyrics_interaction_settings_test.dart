import 'dart:async';
import 'dart:convert';

import 'package:dan_player/component/app_menu_anchor.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/page/settings_page/desktop_integration_settings.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/search/settings_search_index.dart';
import 'package:dan_player/taskbar_lyrics_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_desktop_integration.dart';
import 'support/listening_status_fixture.dart';
import 'support/playlist_feature_fixture.dart';

const _color = ValueKey('taskbar-lyrics-color-scheme');
const _stroke = ValueKey('taskbar-lyrics-stroke');
const _next = ValueKey('taskbar-lyrics-next-button');

Future<void> _mount(WidgetTester tester, DesktopTestRig rig,
    {double width = 1080,
    double scale = 1,
    GlobalKey? boundary,
    bool expandAdvanced = true,
    Future<void> Function()? persist}) async {
  sizePlaylistFeature(tester, width: width, height: 1000);
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
              persist: persist ?? () async {},
            ),
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
  if (expandAdvanced) {
    final title = find.text(ui('更多任务栏歌词选项'));
    await tester.ensureVisible(title);
    await tester.tap(title);
    await tester.pumpAndSettle();
  }
}

MenuItemButton _colorOption(
        WidgetTester tester, TaskbarLyricColorScheme color) =>
    tester
        .widget<AppMenuAnchor>(find.ancestor(
            of: find.byKey(_color), matching: find.byType(AppMenuAnchor)))
        .menuChildren
        .cast<MenuItemButton>()[color.index];

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  test('legacy taskbar appearance restores independent defaults', () {
    for (final raw in [
      null,
      'system',
      1,
      [],
      const {'position': 'end', 'showNextTrack': false, 'areaSelection': 17},
    ]) {
      final model = TaskbarLyricsPreferences.fromMap(raw);
      expect(model.strokeEnabled, isFalse);
      expect(model.showNextButton, isFalse);
      expect(model.colorScheme, TaskbarLyricColorScheme.player);
      if (raw is Map) {
        expect(model.position, TaskbarLyricPosition.end);
        expect(model.showNextTrack, isFalse);
        expect(model.areaSelection, 17);
      }
    }
    expect(
        PlayerExperiencePreferences.fromMap(const {'taskbarLyrics': true})
            .taskbarAppearance
            .strokeEnabled,
        isFalse);
  });

  test('new taskbar fields reject coercion without losing valid old fields',
      () {
    for (final invalid in [null, 1, 'true', [], <String, Object>{}]) {
      final model = TaskbarLyricsPreferences.fromMap({
        'strokeEnabled': invalid,
        'showNextButton': invalid,
        'colorScheme': 'system',
        'position': 'start',
        'showPauseIndicator': false,
      });
      expect(model.strokeEnabled, isFalse);
      expect(model.showNextButton, isFalse);
      expect(model.colorScheme, TaskbarLyricColorScheme.system);
      expect(model.position, TaskbarLyricPosition.start);
      expect(model.showPauseIndicator, isFalse);
    }
    for (final invalid in [null, 'System', 'windows', true, 1, [], {}]) {
      final model = TaskbarLyricsPreferences.fromMap({
        'colorScheme': invalid,
        'strokeEnabled': true,
        'showNextButton': true,
      });
      expect(model.colorScheme, TaskbarLyricColorScheme.player);
      expect(model.strokeEnabled, isTrue);
      expect(model.showNextButton, isTrue);
    }
  });

  test('new appearance fields round trip in existing experience map', () {
    const experience = PlayerExperiencePreferences(
        closeToTray: true, playbackRate: .75, taskbarLyrics: true);
    for (final color in TaskbarLyricColorScheme.values) {
      for (final stroke in [false, true]) {
        for (final next in [false, true]) {
          final appearance = TaskbarLyricsPreferences(
            position: TaskbarLyricPosition.end,
            areaSelection: 65535,
            colorScheme: color,
            strokeEnabled: stroke,
            showNextButton: next,
          );
          final original = experience.copyWith(taskbarAppearance: appearance);
          final restored = PlayerExperiencePreferences.fromMap(
              jsonDecode(jsonEncode(original.toMap())));
          expect(restored, original);
          expect(restored.hashCode, original.hashCode);
          expect(restored.taskbarAppearance.toMap()['colorScheme'], color.name);
          expect(restored.closeToTray, isTrue);
          expect(restored.playbackRate, .75);
        }
      }
    }
  });

  test('copy and area cycling retain all independent appearance choices', () {
    const original = TaskbarLyricsPreferences(
        strokeEnabled: true,
        showNextButton: true,
        colorScheme: TaskbarLyricColorScheme.system,
        showNextTrack: false,
        showPauseIndicator: false,
        position: TaskbarLyricPosition.center,
        areaSelection: 65535);
    expect(original.copyWith(), original);
    expect(original.nextArea(), original.copyWith(areaSelection: 0));
    expect(original.copyWith(strokeEnabled: false), isNot(original));
    expect(original.copyWith(showNextButton: false), isNot(original));
    expect(original.copyWith(colorScheme: TaskbarLyricColorScheme.player),
        isNot(original));
    expect(TaskbarLyricsPreferences.fromMap(original.toMap()), original);
  });

  test('new taskbar settings search and hints are localized in all languages',
      () {
    for (final language in UiLanguage.values) {
      for (final key in [
        '任务栏歌词配色',
        '播放器配色',
        '跟随 Windows 任务栏',
        '任务栏歌词描边',
        '下一首按钮',
      ]) {
        expect(
            searchSettings(translateUi(key, language))
                .where((entry) => entry.id == 'integration'),
            hasLength(1));
      }
      for (final key in [
        '独立设置，不影响桌面歌词。',
        '仅按钮可点击，歌词文字仍可点击穿透。',
        '字体沿用播放器。',
      ]) {
        final translated = translateUi(key, language);
        expect(translated.trim(), isNotEmpty);
        if (language != UiLanguage.zh) expect(translated, isNot(key));
      }
    }
  });

  testWidgets('real color menu selects stable values with no duplicate save',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    var saves = 0;
    await _mount(tester, rig, persist: () async => saves++);
    final button = find.byKey(_color);
    expect(
        tester
            .widget<OutlinedButton>(button)
            .style!
            .shape!
            .resolve(const <WidgetState>{}),
        AppShape.control);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(
        (_colorOption(tester, TaskbarLyricColorScheme.player).child
                as Semantics)
            .properties
            .selected,
        isTrue);
    await tester
        .tap(find.byKey(const ValueKey('taskbar-lyrics-color-scheme-system')));
    await tester.pumpAndSettle();
    expect(rig.preferences.value.taskbarAppearance.colorScheme,
        TaskbarLyricColorScheme.system);
    expect(saves, 1);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('taskbar-lyrics-color-scheme-system')));
    await tester.pumpAndSettle();
    expect(saves, 1);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('taskbar-lyrics-color-scheme-player')));
    await tester.pumpAndSettle();
    expect(rig.preferences.value.taskbarAppearance.colorScheme,
        TaskbarLyricColorScheme.player);
    expect(saves, 2);
    expect(rig.native.calls, isEmpty);
    expect(rig.playback.starts, 0);
    expect(PlayService.isInitialized, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('color menu supports keyboard selection and escape',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    await _mount(tester, rig);
    final button = find.byKey(_color);
    await tester.ensureVisible(button);
    Focus.of(tester
            .element(find.descendant(of: button, matching: find.byType(Text))))
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(rig.preferences.value.taskbarAppearance.colorScheme,
        TaskbarLyricColorScheme.system);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('taskbar-lyrics-color-scheme-player')),
        findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cold toggles preserve same-frame unrelated settings',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    final snapshots = <PlayerExperiencePreferences>[];
    await _mount(tester, rig,
        persist: () async => snapshots.add(rig.preferences.value));
    expect(tester.widget<SwitchListTile>(find.byKey(_stroke)).value, isFalse);
    expect(tester.widget<SwitchListTile>(find.byKey(_next)).value, isFalse);
    tester.widget<SwitchListTile>(find.byKey(_stroke)).onChanged!(true);
    tester.widget<SwitchListTile>(find.byKey(_next)).onChanged!(true);
    _colorOption(tester, TaskbarLyricColorScheme.system).onPressed!();
    rig.preferences.value = rig.preferences.value.copyWith(closeToTray: true);
    tester
        .widget<SwitchListTile>(
            find.byKey(const ValueKey('taskbar-lyrics-next-track')))
        .onChanged!(false);
    await tester.pumpAndSettle();
    expect(rig.preferences.value.closeToTray, isTrue);
    expect(rig.preferences.value.taskbarLyrics, isFalse);
    expect(
        rig.preferences.value.taskbarAppearance,
        const TaskbarLyricsPreferences(
            strokeEnabled: true,
            showNextButton: true,
            colorScheme: TaskbarLyricColorScheme.system,
            showNextTrack: false));
    expect(snapshots, hasLength(4));
    expect(rig.native.calls, isEmpty);
    expect(rig.playback.starts, 0);
    expect(PlayService.isInitialized, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('old appearance save failure cannot replace newer choices',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    final first = Completer<void>();
    var saves = 0;
    await _mount(tester, rig,
        persist: () => ++saves == 1 ? first.future : Future.value());
    tester.widget<SwitchListTile>(find.byKey(_stroke)).onChanged!(true);
    _colorOption(tester, TaskbarLyricColorScheme.system).onPressed!();
    tester.widget<SwitchListTile>(find.byKey(_next)).onChanged!(true);
    await tester.pump();
    first.completeError(StateError('old save failed'));
    await tester.pumpAndSettle();
    expect(
        rig.preferences.value.taskbarAppearance,
        const TaskbarLyricsPreferences(
            strokeEnabled: true,
            showNextButton: true,
            colorScheme: TaskbarLyricColorScheme.system));
    expect(find.textContaining('保存桌面设置失败'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets(
          'new interaction settings render ${language.code} ${narrow ? 'narrow-large' : 'wide'}',
          (tester) async {
        uiLanguage.value = language;
        final rig = DesktopTestRig();
        addTearDown(rig.dispose);
        final boundary = GlobalKey();
        final width = narrow ? 360.0 : 1080.0;
        final prefix = '${language.code}-${narrow ? 'narrow-large' : 'wide'}';
        await _mount(tester, rig,
            width: width, scale: narrow ? 2 : 1, boundary: boundary);
        expect(rig.preferences.value.taskbarLyrics, isFalse);
        expect(
            tester.widget<SwitchListTile>(find.byKey(_stroke)).value, isFalse);
        expect(tester.widget<SwitchListTile>(find.byKey(_next)).value, isFalse);
        expect(
            tester
                .widget<OutlinedButton>(
                    find.byKey(const ValueKey('taskbar-lyrics-next-area')))
                .onPressed,
            isNull);
        await tester.ensureVisible(find.byKey(_stroke));
        await tester.pumpAndSettle();
        await capturePlaylistFeature(tester, boundary, '$prefix-controls-off');
        await tester.ensureVisible(find.byKey(_color));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_color));
        await tester.pumpAndSettle();
        for (final key in ['播放器配色', '跟随 Windows 任务栏']) {
          final rect = tester.getRect(find.text(ui(key)).last);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
        }
        await capturePlaylistFeature(tester, boundary, '$prefix-color-menu');
        await tester.tap(
            find.byKey(const ValueKey('taskbar-lyrics-color-scheme-system')));
        await tester.pumpAndSettle();
        await capturePlaylistFeature(tester, boundary, '$prefix-color-system');
        tester.widget<SwitchListTile>(find.byKey(_stroke)).onChanged!(true);
        tester.widget<SwitchListTile>(find.byKey(_next)).onChanged!(true);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(_next));
        await tester.pumpAndSettle();
        final buttonRect = tester.getRect(find.byKey(_next));
        expect(buttonRect.left, greaterThanOrEqualTo(0));
        expect(buttonRect.right, lessThanOrEqualTo(width));
        expect(buttonRect.top, greaterThanOrEqualTo(0));
        expect(buttonRect.bottom, lessThanOrEqualTo(1000));
        await capturePlaylistFeature(tester, boundary, '$prefix-controls-on');
        expect(find.text(ui('字体沿用播放器。')), findsOneWidget);
        expect(rig.preferences.value.taskbarAppearance.colorScheme,
            TaskbarLyricColorScheme.system);
        expect(
            tester.widget<SwitchListTile>(find.byKey(_stroke)).value, isTrue);
        expect(tester.widget<SwitchListTile>(find.byKey(_next)).value, isTrue);
        expect(rig.native.calls, isEmpty);
        expect(rig.playback.starts, 0);
        expect(PlayService.isInitialized, isFalse);
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
