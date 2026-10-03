import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/page/settings_page/desktop_integration_settings.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/search/settings_search_index.dart';
import 'package:desktop_lyric/l10n/catalog_taskbar_lyrics.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_desktop_integration.dart';
import 'support/listening_status_fixture.dart';
import 'support/playlist_feature_fixture.dart';

const _lyricsKey = ValueKey('taskbar-lyrics-setting');
const _title = '任务栏歌词';
const _detail = '在主屏任务栏的空白区域显示当前歌词；开启后关闭桌面歌词，空间不足时自动隐藏。';
const _controlsDetail = '悬停任务栏图标时显示上一首、播放/暂停和下一首。';

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  test(
      'taskbar lyric preference defaults off and rejects malformed legacy flags',
      () {
    for (final source in [
      null,
      <String, Object?>{},
      for (final invalid in [null, 'true', 1, [], <String, Object>{}])
        {'taskbarLyrics': invalid}
    ]) {
      expect(
          PlayerExperiencePreferences.fromMap(source).taskbarLyrics, isFalse);
    }
    expect(
        PlayerExperiencePreferences.fromMap(const {'taskbarLyrics': true})
            .taskbarLyrics,
        isTrue);
    expect(
        PlayerExperiencePreferences.fromMap(const {'taskbarLyrics': false})
            .taskbarLyrics,
        isFalse);
  });

  test('taskbar lyrics round trip and copy preserve unrelated desktop choices',
      () {
    const original = PlayerExperiencePreferences(
        taskbarControls: false,
        taskbarSongPreview: false,
        taskbarPlaybackProgress: false,
        closeToTray: true,
        trayMenuBlurRadius: 14,
        playbackRate: .75,
        windowSizeLocked: true);
    final enabled = original.copyWith(taskbarLyrics: true);
    expect(enabled.toMap(), {...original.toMap(), 'taskbarLyrics': true});
    expect(enabled, isNot(original));
    expect(enabled.copyWith(), enabled);
    final decoded = jsonDecode(jsonEncode(enabled.toMap()));
    final restored = PlayerExperiencePreferences.fromMap(decoded);
    expect(restored, enabled);
    expect(restored.hashCode, enabled.hashCode);
    expect(jsonEncode(decoded), jsonEncode(enabled.toMap()));
    expect(restored.copyWith(taskbarLyrics: false), original);
  });

  test(
      'taskbar lyric search resolves four languages to the existing desktop card',
      () {
    final originalLanguage = uiLanguage.value;
    for (final language in UiLanguage.values) {
      final match = searchSettings(translateUi(_title, language))
          .where((entry) => entry.id == 'integration')
          .single;
      final destination = Uri.parse(match.location);
      expect(destination.path, '/settings');
      expect(destination.queryParameters['section'], 'desktop');
      expect(destination.queryParameters['setting'], 'integration');
    }
    for (final entry in catalogTaskbarLyrics.entries) {
      expect(entry.value, hasLength(3));
      expect(entry.value.every((value) => value.trim().isNotEmpty), isTrue);
    }
    expect(uiLanguage.value, originalLanguage);
  });

  Future<void> mount(WidgetTester tester, DesktopTestRig rig,
      {double width = 920,
      double scale = 1,
      GlobalKey? boundary,
      Brightness brightness = Brightness.light,
      Future<void> Function()? persist}) async {
    sizePlaylistFeature(tester, width: width, height: 1100);
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
                            persist: persist ?? () async {}))))),
        scale: scale,
        boundary: boundary,
        seed: brightness == Brightness.dark ? Colors.orange : Colors.teal,
        brightness: brightness));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'taskbar lyric row toggles and persists without starting playback',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    final saves = <PlayerExperiencePreferences>[];
    await mount(tester, rig,
        persist: () async => saves.add(rig.preferences.value));
    final tile = find.byKey(_lyricsKey);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(find.text(_detail), findsOneWidget);
    expect(find.text(_controlsDetail), findsOneWidget);
    expect(find.textContaining('不在任务栏显示歌词'), findsNothing);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(saves.single.taskbarLyrics, isTrue);
    expect(rig.preferences.value.taskbarLyrics, isTrue);
    expect(rig.preferences.value.taskbarControls, isTrue);
    expect(rig.preferences.value.taskbarSongPreview, isTrue);
    expect(rig.preferences.value.taskbarPlaybackProgress, isTrue);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(saves, hasLength(2));
    expect(saves.last.taskbarLyrics, isFalse);
    expect(rig.native.calls, isEmpty);
    expect(rig.playback.starts, 0);
    expect(PlayService.isInitialized, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'taskbar lyric and control toggles in one frame retain both changes',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    var saves = 0;
    await mount(tester, rig, persist: () async => saves++);
    tester.widget<SwitchListTile>(find.byKey(_lyricsKey)).onChanged!(true);
    tester
        .widget<SwitchListTile>(
            find.byKey(const ValueKey('taskbar-controls-setting')))
        .onChanged!(false);
    await tester.pumpAndSettle();
    expect(rig.preferences.value.taskbarLyrics, isTrue);
    expect(rig.preferences.value.taskbarControls, isFalse);
    expect(rig.preferences.value.taskbarSongPreview, isTrue);
    expect(saves, 2);
    expect(rig.native.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failed taskbar lyric save keeps its choice and reports persistence',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    await mount(tester, rig,
        persist: () async => throw StateError('fixture disk'));
    await tester.tap(find.byKey(_lyricsKey));
    await tester.pumpAndSettle();
    expect(rig.preferences.value.taskbarLyrics, isTrue);
    final error = find.text('保存桌面设置失败；当前选择仍对本次会话生效。');
    await tester.ensureVisible(error);
    await tester.pumpAndSettle();
    expect(error, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'late failed lyric save cannot replace a newer desktop save result',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    final first = Completer<void>();
    var saves = 0;
    await mount(tester, rig,
        persist: () => ++saves == 1 ? first.future : Future.value());
    tester.widget<SwitchListTile>(find.byKey(_lyricsKey)).onChanged!(true);
    tester
        .widget<SwitchListTile>(
            find.byKey(const ValueKey('taskbar-controls-setting')))
        .onChanged!(false);
    await tester.pump();
    first.completeError(StateError('stale fixture disk'));
    await tester.pumpAndSettle();
    expect(rig.preferences.value.taskbarLyrics, isTrue);
    expect(rig.preferences.value.taskbarControls, isFalse);
    expect(find.textContaining('保存桌面设置失败'), findsNothing);
    expect(saves, 2);
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets(
          'taskbar lyric settings ${language.name} ${narrow ? 'narrow-large' : 'wide'}',
          (tester) async {
        uiLanguage.value = language;
        final rig = DesktopTestRig();
        addTearDown(rig.dispose);
        final boundary = GlobalKey();
        final width = narrow ? 360.0 : 1080.0;
        await mount(tester, rig,
            width: width,
            scale: narrow ? 2 : 1,
            brightness: narrow ? Brightness.dark : Brightness.light,
            boundary: boundary);
        final tile = find.byKey(_lyricsKey);
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        final rect = tester.getRect(tile);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(width));
        expect(tester.widget<SwitchListTile>(tile).value, isFalse);
        expect(tester.widget<SwitchListTile>(tile).visualDensity,
            VisualDensity.standard);
        for (final key in [_title, _detail, _controlsDetail]) {
          expect(find.text(translateUi(key, language)), findsOneWidget);
          if (language != UiLanguage.zh) {
            expect(translateUi(key, language), isNot(key));
          }
        }
        final output = Platform.environment['DAN_TASKBAR_LYRICS_RENDER_DIR'];
        if (output != null) {
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
            try {
              final bytes =
                  await image.toByteData(format: raster.ImageByteFormat.png);
              await Directory(output).create(recursive: true);
              await File(
                      '$output/${language.name}-${narrow ? 'narrow-large' : 'wide'}.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        expect(rig.native.calls, isEmpty);
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
