import 'package:dan_player/component/japanese_dictionary_setup_card.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/settings_section_visibility.dart';
import 'package:dan_player/lyric/japanese_reading_analyzer.dart';
import 'package:dan_player/lyric/japanese_reading_preferences.dart';
import 'package:dan_player/page/settings_page/japanese_reading_batch_settings.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/japanese_reading_ui_fixture.dart';

const _open = ValueKey('japanese-reading-batch-open');
const _dialog = ValueKey('japanese-reading-batch-dialog');
const _start = ValueKey('japanese-reading-batch-start');
const _close = ValueKey('japanese-reading-batch-close');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late UiLanguage previousLanguage;
  late UiBatch task;
  late ValueNotifier<JapaneseReadingPreferences> preferences;
  late ValueNotifier<bool> automaticallyOnline;
  var saves = 0;
  setUpAll(setUpJapaneseUiFixture);
  tearDownAll(tearDownJapaneseUiFixture);
  setUp(() {
    previousLanguage = uiLanguage.value;
    task = UiBatch();
    preferences = ValueNotifier(const JapaneseReadingPreferences());
    automaticallyOnline = ValueNotifier(false);
    saves = 0;
  });
  tearDown(() {
    task.dispose();
    preferences.dispose();
    automaticallyOnline.dispose();
    uiLanguage.value = previousLanguage;
  });

  JapaneseReadingBatchSettings settings({
    UiDictionaryRuntime? runtime,
    JapaneseDictionaryInstallerFactory? installerFactory,
  }) =>
      JapaneseReadingBatchSettings(
          task: task,
          dictionaryRuntime: runtime,
          installerFactory: installerFactory,
          preferences: preferences,
          automaticallyOnline: automaticallyOnline,
          persist: () async {
            saves++;
          });

  Future<void> open(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(_open));
    await tester.tap(find.byKey(_open));
    await tester.pumpAndSettle();
    expect(find.byKey(_dialog), findsOneWidget);
  }

  for (final language in UiLanguage.values) {
    for (final size in [(1000.0, 1.0), (360.0, 2.0)]) {
      testWidgets(
          'Japanese batch ${language.code} ${size.$1} ${size.$2} keeps complete controls',
          (tester) async {
        final boundary = GlobalKey();
        await mountJapaneseUi(tester, settings(),
            language: language,
            width: size.$1,
            scale: size.$2,
            boundary: boundary);
        expect(task.starts, 0);
        await open(tester);
        await captureJapaneseUi(tester, boundary,
            'batch-${language.code}-${size.$1.toInt()}-${size.$2.toInt()}');
        _expectWholeTitleWords(tester);
        await expectJapaneseUiText(tester, find.byKey(_dialog));
        final button = tester.widget<FilledButton>(find.byKey(_start));
        expect(button.onPressed, isNotNull);
        expect(
            find.descendant(
                of: find.byKey(_start), matching: find.byType(Icon)),
            findsOneWidget);
        expect(task.starts, 0);
        expect(task.cancels, 0);
        expect(tester.binding.transientCallbackCount, 0);
        await tester.tap(find.byKey(_close));
        await tester.pumpAndSettle();
        expect(task.disposals, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Japanese batch starts explicitly and cancellation permits retry',
      (tester) async {
    await mountJapaneseUi(tester, settings());
    await open(tester);
    expect(task.starts, 0);
    await tester.tap(find.byKey(_start));
    await tester.pump();
    expect(task.starts, 1);
    expect(task.lastMode, JapaneseReadingRequestMode.offline);
    expect(task.running, isTrue);
    task.scanning = false;
    task.total = 4;
    task.completed = task.generated = 1;
    task.status = '正在批量生成日语假名…';
    task.notifyListeners();
    await tester.pump();
    expect(
        find.text(
            ui('已处理 {0}/{1} · 生成 {2} · 跳过 {3} · 失败 {4}', [1, 4, 1, 0, 0])),
        findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('japanese-reading-batch-cancel')));
    await tester.pumpAndSettle();
    expect(task.cancels, 1);
    expect(task.generated, 1);
    await tester.tap(find.byKey(_start));
    await tester.pump();
    expect(task.starts, 2);
    task.finish();
    await tester.pumpAndSettle();
    expect(
        find.text(
            ui('已处理 {0}/{1} · 生成 {2} · 跳过 {3} · 失败 {4}', [4, 4, 1, 2, 1])),
        findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.tap(find.byKey(_close));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'Japanese batch reverse immediately cancels and rejects late state',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await mountJapaneseUi(tester, settings(),
        navigator: navigator, reduced: false);
    await open(tester);
    await tester.tap(find.byKey(_start));
    await tester.pump();
    navigator.currentState!.pop();
    expect(task.cancels, 1,
        reason: 'Cancellation belongs to reverse start, not dispose.');
    task.finish();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text(ui('批量生成日语假名完成')), findsNothing);
    await tester.pumpAndSettle();
    expect(task.disposals, 0);
    expect(find.byKey(_dialog), findsNothing);
    await open(tester);
    expect(task.starts, 1);
    await tester.tap(find.byKey(_close));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Japanese batch retained section exit cancels only its dialog',
      (tester) async {
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await mountJapaneseUi(
        tester,
        ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, value, __) =>
                SettingsSectionVisibility(visible: value, child: settings())));
    await open(tester);
    await tester.tap(find.byKey(_start));
    await tester.pump();
    visible.value = false;
    await tester.pump();
    expect(task.cancels, 1);
    await tester.pumpAndSettle();
    expect(find.byKey(_dialog), findsNothing);
    visible.value = true;
    await tester.pumpAndSettle();
    await open(tester);
    expect(task.starts, 1);
    await tester.tap(find.byKey(_close));
    await tester.pumpAndSettle();
    expect(task.disposals, 0);
  });

  testWidgets('Japanese batch opened then hidden in the same frame stays idle',
      (tester) async {
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await mountJapaneseUi(
        tester,
        ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, value, __) =>
                SettingsSectionVisibility(visible: value, child: settings())));
    await tester.tap(find.byKey(_open));
    visible.value = false;
    await tester.pumpAndSettle();
    expect(find.byKey(_dialog), findsNothing);
    expect(task.starts, 0);
    expect(task.disposals, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Japanese batch missing dictionary never auto downloads or restarts',
      (tester) async {
    final runtime = UiDictionaryRuntime();
    final installer = UiDictionaryInstaller(runtime);
    var factories = 0;
    await mountJapaneseUi(
        tester,
        settings(
            runtime: runtime,
            installerFactory: (_) {
              factories++;
              return installer;
            }));
    await open(tester);
    await tester.tap(find.byKey(_start));
    await tester.pump();
    task.missingDictionary();
    await tester.pumpAndSettle();
    expect(find.byType(JapaneseDictionarySetupCard), findsOneWidget);
    expect(factories, 0);
    expect(runtime.inspections, 0);
    final download = find.byKey(const ValueKey('japanese-dictionary-download'));
    await tester.ensureVisible(download);
    await tester.tap(download);
    await tester.pump();
    expect(factories, 1);
    expect(installer.starts, 1);
    runtime.ready = true;
    installer.completion.complete();
    await tester.pumpAndSettle();
    expect(find.byType(JapaneseDictionarySetupCard), findsNothing);
    expect(find.text(ui('字典组件已就绪；点击“开始生成”。')), findsOneWidget);
    expect(task.starts, 1);
    await tester.tap(find.byKey(_start));
    await tester.pump();
    expect(task.starts, 2);
    await tester.tap(find.byKey(_close));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Japanese batch auto online does not ask for a manual mode',
      (tester) async {
    automaticallyOnline.value = true;
    await mountJapaneseUi(tester, settings());
    await open(tester);
    expect(find.byKey(const ValueKey('japanese-reading-batch-mode')),
        findsNothing);
    await tester.tap(find.byKey(_start));
    await tester.pump();
    expect(task.lastMode, JapaneseReadingRequestMode.automatic);
    expect(saves, 0);
    await tester.tap(find.byKey(_close));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'Japanese batch manual mode is explicit and remembered without auto start',
      (tester) async {
    await mountJapaneseUi(tester, settings());
    await open(tester);
    expect(task.starts, 0);
    await tester.tap(find.text(ui('联网生成')));
    await tester.pumpAndSettle();
    expect(preferences.value.lastManualMode, 'online');
    expect(saves, 1);
    expect(task.starts, 0);
    await tester.tap(find.byKey(_start));
    await tester.pump();
    expect(task.lastMode, JapaneseReadingRequestMode.online);
    await tester.tap(find.byKey(_close));
    await tester.pumpAndSettle();
    await open(tester);
    expect(
        tester
            .widget<AppSegmentedControl<JapaneseReadingRequestMode>>(
                find.byKey(const ValueKey('japanese-reading-batch-mode')))
            .value,
        JapaneseReadingRequestMode.online);
    expect(task.starts, 1);
    expect(saves, 1);
    await tester.tap(find.byKey(_close));
    await tester.pumpAndSettle();
  });
}

void _expectWholeTitleWords(WidgetTester tester) {
  final heading = find.descendant(
      of: find.byKey(_dialog), matching: find.byType(AppDialogTitle));
  final text =
      find.descendant(of: heading, matching: find.text(ui('批量生成日语假名')));
  final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)));
  // The title retains the user's text scale. Its real shaped word must fit on
  // one line instead of breaking a Latin word around balanced icon slots.
  for (final word in RegExp(r'[A-Za-z]+').allMatches(ui('批量生成日语假名'))) {
    final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: word.start, extentOffset: word.end));
    expect(boxes, isNotEmpty, reason: word.group(0));
    expect(boxes.map((box) => box.top).toSet(), hasLength(1),
        reason: 'Title word must remain whole: ${word.group(0)}');
  }
}
