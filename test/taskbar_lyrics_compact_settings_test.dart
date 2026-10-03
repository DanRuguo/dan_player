import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui_image;

import 'package:dan_player/page/settings_page/desktop_integration_settings.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/search/settings_search_index.dart';
import 'package:dan_player/taskbar_lyrics_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_desktop_integration.dart';
import 'support/listening_status_fixture.dart';
import 'support/playlist_feature_fixture.dart';

const _pause = ValueKey('taskbar-lyrics-pause-indicator');
const _area = ValueKey('taskbar-lyrics-next-area');
const _card = ValueKey('taskbar-lyrics-options-group');

Future<void> _mount(WidgetTester tester, DesktopTestRig rig,
    {double width = 1280,
    double scale = 1,
    GlobalKey? boundary,
    Future<void> Function()? persist}) async {
  sizePlaylistFeature(tester, width: width, height: 1000);
  await tester.pumpWidget(listeningStatusHost(
    Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1160),
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

Future<void> _show(WidgetTester tester, Finder target,
    {double alignment = 0}) async {
  await Scrollable.ensureVisible(tester.element(target), alignment: alignment);
  await tester.pumpAndSettle();
}

Future<void> _expand(WidgetTester tester) async {
  final title = find.text(ui('更多任务栏歌词选项'));
  await _show(tester, title);
  await tester.tap(title);
  await tester.pumpAndSettle();
}

/// Capture only the visible intersection of the actual taskbar card. Long
/// 200% text is sampled in consecutive real viewport sections, not scaled to
/// fit or reconstructed outside its scroll constraints.
Future<void> _captureCard(
    WidgetTester tester, GlobalKey boundary, String name) async {
  final directory = Platform.environment['DAN_TASKBAR_COMPACT_RENDER_DIR'];
  if (directory == null) return;
  final cardRect = tester.getRect(find.byKey(_card));
  final repaint =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final original = await repaint.toImage(pixelRatio: 1);
    final rect = cardRect.intersect(Rect.fromLTWH(
        0, 0, original.width.toDouble(), original.height.toDouble()));
    final recorder = ui_image.PictureRecorder();
    Canvas(recorder).drawImageRect(
        original, rect, Rect.fromLTWH(0, 0, rect.width, rect.height), Paint());
    final picture = recorder.endRecording();
    final image = await picture.toImage(rect.width.ceil(), rect.height.ceil());
    try {
      final bytes =
          await image.toByteData(format: ui_image.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File('$directory/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
      picture.dispose();
      original.dispose();
    }
  });
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  testWidgets('play pause setting reuses the saved field and stays cold',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    rig.preferences.value = rig.preferences.value.copyWith(
        closeToTray: true,
        taskbarAppearance: const TaskbarLyricsPreferences(
            colorScheme: TaskbarLyricColorScheme.system,
            strokeEnabled: true,
            showNextLyric: false,
            showNextButton: true));
    final saved = <PlayerExperiencePreferences>[];
    await _mount(tester, rig,
        persist: () async => saved.add(rig.preferences.value));
    await _expand(tester);
    expect(find.text('播放/暂停按钮'), findsOneWidget);
    expect(find.text('暂停状态提示'), findsNothing);
    expect(tester.widget<SwitchListTile>(find.byKey(_pause)).value, isTrue);
    await _show(tester, find.byKey(_pause));
    await tester.tap(find.byKey(_pause));
    await tester.pumpAndSettle();
    expect(saved, hasLength(1));
    expect(saved.single.taskbarAppearance.showPauseIndicator, isFalse);
    final restored = PlayerExperiencePreferences.fromMap(
        jsonDecode(jsonEncode(saved.single.toMap())));
    expect(restored.taskbarAppearance.toMap()['showPauseIndicator'], isFalse);
    expect(
        restored.taskbarAppearance.toMap().containsKey('showPlayPauseButton'),
        isFalse);
    expect(restored.closeToTray, isTrue);
    expect(restored.taskbarAppearance.strokeEnabled, isTrue);
    expect(restored.taskbarAppearance.showNextLyric, isFalse);
    expect(restored.taskbarAppearance.showNextButton, isTrue);
    rig.preferences.value = restored;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_pause));
    await tester.pumpAndSettle();
    expect(saved, hasLength(2));
    expect(saved.last.taskbarAppearance.showPauseIndicator, isTrue);
    expect(rig.native.calls, isEmpty);
    expect(rig.playback.starts, 0);
    expect(PlayService.isInitialized, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
    for (final language in UiLanguage.values) {
      final label = translateUi('播放/暂停按钮', language);
      expect(searchSettings(label).where((entry) => entry.id == 'integration'),
          hasLength(1));
      if (language != UiLanguage.zh) expect(label, isNot('播放/暂停按钮'));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact taskbar card reflows complete four language sections',
      (tester) async {
    for (final language in UiLanguage.values) {
      for (final layout in ['wide', 'narrow-large', 'wide-large']) {
        final narrow = layout == 'narrow-large';
        final large = layout != 'wide';
        uiLanguage.value = language;
        final rig = DesktopTestRig();
        final boundary = GlobalKey();
        rig.preferences.value = rig.preferences.value.copyWith(
            taskbarLyrics: true,
            taskbarAppearance: const TaskbarLyricsPreferences(
                colorScheme: TaskbarLyricColorScheme.system));
        rig.native.intercept = (method, _) async =>
            method == 'getTaskbarLyricsLayout'
                ? {'vertical': false, 'areaCount': 2, 'areaIndex': 0}
                : rig.native.state();
        await tester.runAsync(rig.initialize);
        final observationStarts = rig.playback.starts;
        final width = narrow
            ? 360.0
            : large
                ? 1080.0
                : 1280.0;
        final prefix = '${language.code}-$layout';
        await _mount(tester, rig,
            width: width, scale: large ? 2 : 1, boundary: boundary);
        final positionLabel = tester.getRect(find.text(ui('任务栏歌词位置')));
        final positionButton = tester
            .getRect(find.byKey(const ValueKey('taskbar-lyrics-position')));
        if (narrow) {
          expect(positionButton.top, greaterThan(positionLabel.bottom));
        } else {
          expect((positionLabel.center.dy - positionButton.center.dy).abs(),
              lessThan(16));
          final status = tester.getRect(
              find.byKey(const ValueKey('taskbar-lyrics-area-status')));
          final area = tester.getRect(find.byKey(_area));
          expect((status.center.dy - area.center.dy).abs(), lessThan(1));
          if (!large) {
            expect(
                tester
                    .getSize(
                        find.byKey(const ValueKey('taskbar-lyrics-next-lyric')))
                    .height,
                lessThanOrEqualTo(76));
          }
        }
        expect(tester.widget<OutlinedButton>(find.byKey(_area)).onPressed,
            isNotNull);
        await _show(
            tester, find.byKey(const ValueKey('taskbar-lyrics-setting')));
        await _captureCard(tester, boundary, '$prefix-main-top');
        if (narrow) {
          await _show(tester, find.text(ui('更多任务栏歌词选项')), alignment: 1);
          await _captureCard(tester, boundary, '$prefix-main-bottom');
        }
        await _expand(tester);
        final appearance = tester.getRect(find.text(ui('外观')));
        final interaction = tester.getRect(find.text(ui('交互')));
        if (large) {
          expect(interaction.top, greaterThan(appearance.bottom));
        } else {
          expect(interaction.top, appearance.top);
          expect(interaction.left, greaterThan(appearance.right));
          final colorLabel = tester.getRect(find.text(ui('任务栏歌词配色')));
          final colorButton = tester.getRect(
              find.byKey(const ValueKey('taskbar-lyrics-color-scheme')));
          expect((colorLabel.center.dy - colorButton.center.dy).abs(),
              lessThan(16));
        }
        await _show(
            tester,
            large
                ? find.text(ui('外观'))
                : find.byKey(const ValueKey('taskbar-lyrics-setting')));
        await _captureCard(tester, boundary, '$prefix-options-top');
        for (final key in [
          'taskbar-lyrics-color-scheme',
          'taskbar-lyrics-stroke',
          'taskbar-lyrics-next-track',
          'taskbar-lyrics-pause-indicator',
          'taskbar-lyrics-next-button',
        ]) {
          final finder = find.byKey(ValueKey(key));
          await _show(tester, finder);
          final rect = tester.getRect(finder);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(1000));
        }
        if (narrow) {
          await _show(
              tester, find.byKey(const ValueKey('taskbar-lyrics-next-button')),
              alignment: 1);
          await _captureCard(tester, boundary, '$prefix-options-bottom');
        }
        expect(find.text(ui('播放/暂停按钮')), findsOneWidget);
        expect(find.text(ui('暂停状态提示')), findsNothing);
        expect(
            rig.preferences.value.taskbarAppearance.showPauseIndicator, isTrue);
        expect(rig.playback.starts, observationStarts);
        expect(PlayService.isInitialized, isFalse);
        expect(
            rig.native.calls
                .where((call) => call.$1 == 'getTaskbarLyricsLayout'),
            hasLength(1));
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(rig.dispose);
      }
    }
  });
}
