import 'dart:async';
import 'dart:convert';

import 'package:dan_player/component/app_menu_anchor.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/page/settings_page/desktop_integration_settings.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/search/settings_search_index.dart';
import 'package:dan_player/taskbar_lyrics_preferences.dart';
import 'package:desktop_lyric/l10n/catalog_taskbar_lyrics.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_desktop_integration.dart';
import 'support/listening_status_fixture.dart';
import 'support/playlist_feature_fixture.dart';

const _position = ValueKey('taskbar-lyrics-position');
const _nextTrack = ValueKey('taskbar-lyrics-next-track');
const _pause = ValueKey('taskbar-lyrics-pause-indicator');
const _area = ValueKey('taskbar-lyrics-next-area');

List<MenuItemButton> positionOptions(WidgetTester tester) => tester
    .widget<AppMenuAnchor>(find.ancestor(
        of: find.byKey(_position), matching: find.byType(AppMenuAnchor)))
    .menuChildren
    .cast<MenuItemButton>();

void choosePositionCallback(
        WidgetTester tester, TaskbarLyricPosition position) =>
    positionOptions(tester)[position.index].onPressed!();

List<String?> positionLabels(WidgetTester tester) => positionOptions(tester)
    .map((item) => ((item.child as Semantics).child as Text).data)
    .toList();

Future<void> mount(WidgetTester tester, DesktopTestRig rig,
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

Future<void> readyLayout(DesktopTestRig rig,
    {bool vertical = false, int count = 2, int index = 0}) async {
  rig.native.intercept = (method, args) async =>
      method == 'getTaskbarLyricsLayout'
          ? {'vertical': vertical, 'areaCount': count, 'areaIndex': index}
          : rig.native.state();
  await rig.initialize();
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  test('taskbar appearance legacy defaults keep auto and optional information',
      () {
    for (final raw in [null, 1, 'start', [], <String, Object?>{}]) {
      final preferences = TaskbarLyricsPreferences.fromMap(raw);
      expect(preferences.position, TaskbarLyricPosition.auto);
      expect(preferences.showNextTrack, isTrue);
      expect(preferences.showPauseIndicator, isTrue);
      expect(preferences.areaSelection, 0);
    }
    expect(
        PlayerExperiencePreferences.fromMap(const {'taskbarLyrics': true})
            .taskbarAppearance,
        const TaskbarLyricsPreferences());
  });

  test('malformed fields fall back independently without coercing types', () {
    for (final invalid in [null, 'true', 1, [], <String, Object>{}]) {
      final preferences = TaskbarLyricsPreferences.fromMap({
        'position': 'end',
        'showNextTrack': invalid,
        'showPauseIndicator': false,
        'areaSelection': 7,
      });
      expect(preferences.position, TaskbarLyricPosition.end);
      expect(preferences.showNextTrack, isTrue);
      expect(preferences.showPauseIndicator, isFalse);
      expect(preferences.areaSelection, 7);
    }
    for (final invalid in [null, 'Start', 'left', 1, true]) {
      final preferences = TaskbarLyricsPreferences.fromMap({
        'position': invalid,
        'showNextTrack': false,
      });
      expect(preferences.position, TaskbarLyricPosition.auto);
      expect(preferences.showNextTrack, isFalse);
    }
  });

  test(
      'area selection accepts bounded integers and wraps without changing alignment',
      () {
    for (final invalid in [-1, 65536, 1.0, double.nan, '1', false, null]) {
      expect(
          TaskbarLyricsPreferences.fromMap({'areaSelection': invalid})
              .areaSelection,
          0);
    }
    const last = TaskbarLyricsPreferences(
        position: TaskbarLyricPosition.start,
        areaSelection: 65535,
        showNextTrack: false);
    expect(
        last.nextArea(),
        const TaskbarLyricsPreferences(
            position: TaskbarLyricPosition.start, showNextTrack: false));
    expect(last.copyWith(areaSelection: -1), last);
    expect(TaskbarLyricsPreferences.safeAreaSelection(null, fallback: -1), 0);
  });

  test(
      'nested appearance round trip preserves all other experience preferences',
      () {
    const old = PlayerExperiencePreferences(
        closeToTray: true,
        taskbarControls: false,
        taskbarLyrics: true,
        playbackRate: .75,
        trayMenuBlurRadius: 13);
    for (final position in TaskbarLyricPosition.values) {
      final appearance = TaskbarLyricsPreferences(
          position: position,
          showNextTrack: false,
          showPauseIndicator: false,
          areaSelection: 9);
      final next = old.copyWith(taskbarAppearance: appearance);
      final roundTrip = PlayerExperiencePreferences.fromMap(
          jsonDecode(jsonEncode(next.toMap())));
      expect(roundTrip, next);
      expect(roundTrip.hashCode, next.hashCode);
      expect(roundTrip.taskbarAppearance.toMap()['position'], position.name);
      expect(roundTrip.copyWith(taskbarAppearance: old.taskbarAppearance), old);
      expect(next.copyWith(), next);
    }
  });

  test('appearance search and parameterized catalog cover every language', () {
    for (final language in UiLanguage.values) {
      for (final label in ['任务栏歌词位置', '下一首歌曲信息', '暂停状态提示', '切换空区']) {
        final entry = searchSettings(translateUi(label, language))
            .where((entry) => entry.id == 'integration')
            .single;
        expect(Uri.parse(entry.location).queryParameters['section'], 'desktop');
      }
      for (final entry in catalogTaskbarLyrics.entries) {
        expect(entry.value, hasLength(3));
        expect(translateUi(entry.key, language).trim(), isNotEmpty);
        if (language != UiLanguage.zh) {
          expect(translateUi(entry.key, language), isNot(entry.key));
        }
      }
      expect(
          translateUi('下一首：{0}', language, ['Fixture']), contains('Fixture'));
      expect(translateUi('可用空区：{0}；当前：{1}', language, [2, 1]),
          allOf(contains('2'), contains('1'), isNot(contains('{'))));
    }
  });

  testWidgets(
      'cold appearance edits preserve same-frame unrelated settings and start no factory',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    final saves = <PlayerExperiencePreferences>[];
    await mount(tester, rig,
        persist: () async => saves.add(rig.preferences.value));
    expect(find.text('开启后检测任务栏空区。'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(_area)).onPressed, isNull);
    choosePositionCallback(tester, TaskbarLyricPosition.end);
    tester.widget<SwitchListTile>(find.byKey(_nextTrack)).onChanged!(false);
    tester.widget<SwitchListTile>(find.byKey(_pause)).onChanged!(false);
    tester
        .widget<SwitchListTile>(
            find.byKey(const ValueKey('taskbar-controls-setting')))
        .onChanged!(false);
    await tester.pumpAndSettle();
    final result = rig.preferences.value;
    expect(
        result.taskbarAppearance,
        const TaskbarLyricsPreferences(
            position: TaskbarLyricPosition.end,
            showNextTrack: false,
            showPauseIndicator: false));
    expect(result.taskbarControls, isFalse);
    expect(result.taskbarLyrics, isFalse);
    expect(saves, hasLength(4));
    expect(rig.native.calls, isEmpty);
    expect(rig.playback.starts, 0);
    expect(PlayService.isInitialized, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'real rounded position menu persists a stable orientation-independent value',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    var saves = 0;
    await mount(tester, rig, persist: () async => saves++);
    final button = find.byKey(_position);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    final selected = tester.widget<MenuItemButton>(
        find.byKey(const ValueKey('taskbar-lyrics-position-auto')));
    expect((selected.child as Semantics).properties.selected, isTrue);
    expect(find.descendant(of: button, matching: find.byType(InputDecorator)),
        findsNothing);
    await tester
        .tap(find.byKey(const ValueKey('taskbar-lyrics-position-start')));
    await tester.pumpAndSettle();
    expect(rig.preferences.value.taskbarAppearance.position,
        TaskbarLyricPosition.start);
    expect(saves, 1);
    expect(
        tester
            .widget<OutlinedButton>(button)
            .style!
            .shape!
            .resolve(const <WidgetState>{}),
        AppShape.control);
    expect(find.byKey(const ValueKey('taskbar-lyrics-position-start')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('position expand button supports keyboard choice and escape',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    var saves = 0;
    await mount(tester, rig, persist: () async => saves++);
    final button = find.byKey(_position);
    await tester.ensureVisible(button);
    final label = find.descendant(of: button, matching: find.byType(Text));
    Focus.of(tester.element(label)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('taskbar-lyrics-position-auto')),
        findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(rig.preferences.value.taskbarAppearance.position,
        TaskbarLyricPosition.start);
    expect(saves, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('taskbar-lyrics-position-start')),
        findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('taskbar-lyrics-position-start')),
        findsNothing);
    expect(saves, 1);
    expect(rig.native.calls, isEmpty);
    expect(PlayService.isInitialized, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'two safe areas cycle via preferences and native layout events without polling',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    rig.preferences.value = rig.preferences.value.copyWith(taskbarLyrics: true);
    await tester.runAsync(() => readyLayout(rig));
    var saves = 0;
    await mount(tester, rig, persist: () async => saves++);
    expect(find.text('可用空区：2；当前：1'), findsOneWidget);
    final button = find.byKey(_area);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(rig.preferences.value.taskbarAppearance.areaSelection, 1);
    await rig.native.emit('taskbarLyricsLayoutChanged',
        {'vertical': false, 'areaCount': 2, 'areaIndex': 1});
    await tester.pumpAndSettle();
    expect(find.text('可用空区：2；当前：2'), findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(rig.preferences.value.taskbarAppearance.areaSelection, 2);
    await rig.native.emit('taskbarLyricsLayoutChanged',
        {'vertical': false, 'areaCount': 2, 'areaIndex': 0});
    await tester.pumpAndSettle();
    expect(find.text('可用空区：2；当前：1'), findsOneWidget);
    expect(saves, 2);
    expect(
        rig.native.calls.where((call) => call.$1 == 'getTaskbarLyricsLayout'),
        hasLength(1));
    expect(PlayService.isInitialized, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'single and zero areas disable cycling and keep honest status text',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    rig.preferences.value = rig.preferences.value.copyWith(taskbarLyrics: true);
    await tester.runAsync(() => readyLayout(rig, count: 1));
    await mount(tester, rig);
    expect(tester.widget<OutlinedButton>(find.byKey(_area)).onPressed, isNull);
    expect(find.text('可用空区：1；当前：1'), findsOneWidget);
    await rig.native.emit('taskbarLyricsLayoutChanged',
        {'vertical': false, 'areaCount': 0, 'areaIndex': 0});
    await tester.pumpAndSettle();
    expect(find.text('暂未检测到可用任务栏空区。'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(_area)).onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    rig.preferences.value =
        rig.preferences.value.copyWith(taskbarLyrics: false);
    await tester.pumpAndSettle();
    expect(find.text('开启后检测任务栏空区。'), findsOneWidget);
    expect(rig.preferences.value.taskbarAppearance.areaSelection, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'taskbar orientation event relabels start and end without rewriting preferences',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    rig.preferences.value = rig.preferences.value.copyWith(
        taskbarAppearance: const TaskbarLyricsPreferences(
            position: TaskbarLyricPosition.start));
    await tester.runAsync(() => readyLayout(rig));
    var saves = 0;
    await mount(tester, rig, persist: () async => saves++);
    expect(positionLabels(tester), ['自动', '靠左', '居中', '靠右']);
    await rig.native.emit('taskbarLyricsLayoutChanged',
        {'vertical': true, 'areaCount': 2, 'areaIndex': 0});
    await tester.pumpAndSettle();
    expect(positionLabels(tester), ['自动', '靠上', '居中', '靠下']);
    expect(rig.preferences.value.taskbarAppearance.position,
        TaskbarLyricPosition.start);
    expect(saves, 0);
    expect(
        rig.native.calls.where((call) => call.$1 == 'getTaskbarLyricsLayout'),
        hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'unavailable bridge is read once when ready and removes the page listener',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    await mount(tester, rig);
    expect(rig.native.calls, isEmpty);
    await tester.runAsync(() => readyLayout(rig, vertical: true));
    await tester.pumpAndSettle();
    expect(positionLabels(tester), ['自动', '靠上', '居中', '靠下']);
    expect(
        rig.native.calls.where((call) => call.$1 == 'getTaskbarLyricsLayout'),
        hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await rig.native.emit('taskbarLyricsLayoutChanged',
        {'vertical': false, 'areaCount': 1, 'areaIndex': 0});
    await tester.pumpAndSettle();
    expect(
        rig.native.calls.where((call) => call.$1 == 'getTaskbarLyricsLayout'),
        hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'late save failure cannot undo a newer appearance or replace its feedback',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    final first = Completer<void>();
    var saves = 0;
    await mount(tester, rig,
        persist: () => ++saves == 1 ? first.future : Future.value());
    choosePositionCallback(tester, TaskbarLyricPosition.center);
    tester.widget<SwitchListTile>(find.byKey(_pause)).onChanged!(false);
    await tester.pump();
    first.completeError(StateError('old failed save'));
    await tester.pumpAndSettle();
    expect(
        rig.preferences.value.taskbarAppearance,
        const TaskbarLyricsPreferences(
            position: TaskbarLyricPosition.center, showPauseIndicator: false));
    expect(find.textContaining('保存桌面设置失败'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets(
          'appearance controls render ${language.code} ${narrow ? 'narrow-large' : 'wide'}',
          (tester) async {
        uiLanguage.value = language;
        final rig = DesktopTestRig();
        addTearDown(rig.dispose);
        rig.preferences.value =
            rig.preferences.value.copyWith(taskbarLyrics: true);
        await tester.runAsync(() => readyLayout(rig, vertical: narrow));
        final boundary = GlobalKey();
        final width = narrow ? 360.0 : 1080.0;
        await mount(tester, rig,
            width: width, scale: narrow ? 2 : 1, boundary: boundary);
        final group =
            find.byKey(const ValueKey('taskbar-lyrics-options-group'));
        expect(
            find.descendant(of: group, matching: find.byType(SettingsSurface)),
            findsNothing);
        await tester.ensureVisible(find.byKey(_position));
        await tester.pumpAndSettle();
        final positionRect = tester.getRect(find.byKey(_position));
        expect(positionRect.left, greaterThanOrEqualTo(0));
        expect(positionRect.right, lessThanOrEqualTo(width));
        await capturePlaylistFeature(tester, boundary,
            'appearance-${language.code}-${narrow ? 'narrow-large' : 'wide'}-position');
        await tester.tap(find.byKey(_position));
        await tester.pumpAndSettle();
        for (final position in TaskbarLyricPosition.values) {
          final label = switch (position) {
            TaskbarLyricPosition.auto => '自动',
            TaskbarLyricPosition.start => narrow ? '靠上' : '靠左',
            TaskbarLyricPosition.center => '居中',
            TaskbarLyricPosition.end => narrow ? '靠下' : '靠右',
          };
          final item = find.text(ui(label)).last;
          expect(item, findsOneWidget);
          final rect = tester.getRect(item);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
        }
        await capturePlaylistFeature(tester, boundary,
            'appearance-${language.code}-${narrow ? 'narrow-large' : 'wide'}-menu');
        await tester.tap(find.text(ui(narrow ? '靠下' : '靠右')).last);
        await tester.pumpAndSettle();
        expect(rig.preferences.value.taskbarAppearance.position,
            TaskbarLyricPosition.end);
        await tester.ensureVisible(find.byKey(_area));
        await tester.pumpAndSettle();
        final areaButton = tester.widget<OutlinedButton>(find.byKey(_area));
        expect(areaButton.onPressed, isNotNull);
        expect(areaButton.style!.side!.resolve(const <WidgetState>{})!.width,
            greaterThan(0));
        expect(find.text(ui('切换空区')), findsOneWidget);
        final areaRect = tester.getRect(find.byKey(_area));
        expect(areaRect.left, greaterThanOrEqualTo(0));
        expect(areaRect.right, lessThanOrEqualTo(width));
        await capturePlaylistFeature(tester, boundary,
            'appearance-${language.code}-${narrow ? 'narrow-large' : 'wide'}-area');
        await tester.ensureVisible(find.byKey(_pause));
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(find.byKey(_nextTrack)).value,
            isTrue);
        expect(tester.widget<SwitchListTile>(find.byKey(_pause)).value, isTrue);
        expect(find.text(translateUi('字体沿用播放器。', language)), findsOneWidget);
        expect(find.text(translateUi('下一首歌曲信息', language)), findsOneWidget);
        expect(find.text(translateUi('播放/暂停按钮', language)), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(PlayService.isInitialized, isFalse);
        expect(tester.binding.hasScheduledFrame, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
