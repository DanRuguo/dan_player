import 'dart:async';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/lyric/japanese_lyric_readings.dart';
import 'package:dan_player/lyric/japanese_reading_preferences.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_reading_tools.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/settings_page/japanese_reading_batch_settings.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/japanese_reading_ui_fixture.dart';

const _bubble = ValueKey('app-notice-bubble');
const _readingOpen = ValueKey('lyric-reading-tools');
const _showReading = ValueKey('lyric-show-japanese-reading');

// This is feedback-component linkage with an injected completed result. The
// singleton production callback's source/visibility guards are reviewed at
// its call site; these tests do not stand in for service/cache/protocol tests.
class _FeedbackRig {
  final appearance = ValueNotifier(
      DesktopLyricAppearance.defaults.copyWith(showJapaneseReading: false));
  final result = Completer<JapaneseReadingResult>();
  late final controller = LyricViewController(
      preferences: NowPlayingPagePreference.fromMap({}),
      appearance: appearance,
      persistAppearance: () async {});
  int calls = 0;

  Widget menu() => LyricReadingMenu(
      controller: controller,
      readLyric: () => null,
      onToggleJapaneseReading: (navigator) async {
        calls++;
        controller.toggleJapaneseReading();
        final completed = await result.future;
        if (navigator.mounted) {
          showJapaneseReadingResultNotice(navigator.context, completed);
        }
      });

  void dispose() {
    controller.dispose();
    appearance.dispose();
  }
}

Future<void> _mount(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
      builder: (context, content) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: AppPresentationHost(child: content!)),
      home: Scaffold(
          body: Align(
              alignment: Alignment.topLeft,
              child:
                  Padding(padding: const EdgeInsets.all(24), child: child)))));
  await tester.pumpAndSettle();
}

Future<_FeedbackRig> _completeReadingAction(
    WidgetTester tester, JapaneseReadingResult result) async {
  final rig = _FeedbackRig();
  addTearDown(rig.dispose);
  await _mount(tester, rig.menu());
  await tester.tap(find.byKey(_readingOpen));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(_showReading));
  await tester.pumpAndSettle();
  expect(rig.calls, 1, reason: 'The actual menu action ran once');
  expect(rig.controller.showJapaneseReading, isTrue);
  expect(find.byKey(_bubble), findsNothing);
  rig.result.complete(result);
  await tester.pumpAndSettle();
  expect(rig.calls, 1);
  expect(rig.controller.showJapaneseReading, isTrue,
      reason: 'Silencing a notice does not undo the requested display state');
  return rig;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // This fixture owns plugins.flutter.io/path_provider and requires DANDIR
  // unset. Its files and the runner's TEMP/TMP are inside workspace QA.
  setUpAll(setUpJapaneseUiFixture);
  tearDownAll(tearDownJapaneseUiFixture);
  final previousLanguage = uiLanguage.value;
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = previousLanguage);

  testWidgets(
      'Japanese applied menu feedback is silent and keeps display state',
      (tester) async {
    await _completeReadingAction(tester, JapaneseReadingResult.applied);
    expect(find.byKey(_bubble), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text(ui('已补充日语假名')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Japanese unchanged menu feedback is silent and keeps display state',
      (tester) async {
    await _completeReadingAction(tester, JapaneseReadingResult.unchanged);
    expect(find.byKey(_bubble), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text(ui('已有读音，或没有可补充的日语歌词')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('Japanese problem menu feedback retains the actual notice bubble',
      (tester) async {
    for (final problem in [
      (JapaneseReadingResult.unavailable, '当前无法生成日语假名，请稍后重试'),
      (JapaneseReadingResult.dictionaryMissing, '请在设置中安装日语假名字典组件'),
      (JapaneseReadingResult.tooLarge, '歌词过长，无法一次生成日语假名'),
    ]) {
      await _completeReadingAction(tester, problem.$1);
      expect(find.byKey(_bubble), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(_bubble), matching: find.text(ui(problem.$2))),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'Japanese normal batch completion keeps progress without a bubble',
      (tester) async {
    for (final generated in [0, 2]) {
      final task = UiBatch();
      final automaticallyOnline = ValueNotifier(false);
      final preferences = ValueNotifier(const JapaneseReadingPreferences());
      addTearDown(task.dispose);
      addTearDown(automaticallyOnline.dispose);
      addTearDown(preferences.dispose);
      await _mount(
          tester,
          JapaneseReadingBatchSettings(
              task: task,
              automaticallyOnline: automaticallyOnline,
              preferences: preferences,
              persist: () async {}));
      await tester
          .tap(find.byKey(const ValueKey('japanese-reading-batch-open')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('japanese-reading-batch-start')));
      await tester.pump();
      expect(task.starts, 1);
      task.finish();
      task.generated = generated;
      task.skipped = task.total - generated;
      task.failed = 0;
      task.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byKey(_bubble), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('japanese-reading-batch-dialog')),
              matching: find.text(ui('批量生成日语假名完成'))),
          findsOneWidget);
      expect(
          find.text(ui('已处理 {0}/{1} · 生成 {2} · 跳过 {3} · 失败 {4}',
              [task.total, task.total, generated, task.total - generated, 0])),
          findsOneWidget);
      await tester
          .tap(find.byKey(const ValueKey('japanese-reading-batch-close')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
