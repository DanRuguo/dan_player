import 'dart:async';
import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_checkbox_menu_button.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/japanese_reading_analyzer.dart';
import 'package:dan_player/lyric/japanese_reading_preferences.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_reading_tools.dart';
import 'package:dan_player/page/settings_page/japanese_reading_batch_settings.dart';
import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/japanese_reading_ui_fixture.dart';

const _mode = ValueKey('japanese-reading-generation-mode');
const _batchMode = ValueKey('japanese-reading-batch-mode');
const _provider = MethodChannel('plugins.flutter.io/path_provider');
final _qa = p.join(Directory.current.parent.path, 'tool', 'qa-local',
    'kana-layout-feedback-oct11', 'ui');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late UiLanguage previousLanguage;
  setUpAll(() async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
    expect(Directory.systemTemp.absolute.path.replaceAll('\\', '/'),
        contains('/tool/qa-local/'));
    final data = Directory(p.join(_qa, 'data'));
    await data.create(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_provider, (_) async => data.path);
    expect(p.isWithin(data.path, (await getAppDataDir()).path), isTrue);
    for (final language in UiLanguage.values) {
      await ensureAppFontsLoaded(AppFontPolicy.defaults(language: language));
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    await (FontLoader('packages/material_symbols_icons/MaterialSymbolsOutlined')
          ..addFont(rootBundle.load(
              'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf')))
        .load();
  });
  tearDownAll(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_provider, null));
  setUp(() => previousLanguage = uiLanguage.value);
  tearDown(() => uiLanguage.value = previousLanguage);

  for (final language in UiLanguage.values) {
    for (final size in [(1000.0, 1.0), (360.0, 2.0)]) {
      testWidgets(
          'Japanese mode ${language.code} ${size.$1} ${size.$2} centers actual choices',
          (tester) async {
        final boundary = GlobalKey();
        JapaneseReadingRequestMode? returned;
        var returns = 0;
        await mountJapaneseUi(
            tester,
            Builder(
                builder: (context) => FilledButton(
                    key: const ValueKey('open-mode'),
                    onPressed: () => unawaited(
                            showJapaneseReadingModeDialog(context)
                                .then((value) {
                          returned = value;
                          returns++;
                        })),
                    child: const Text('Open'))),
            language: language,
            width: size.$1,
            scale: size.$2,
            boundary: boundary);
        final automatic = AppSettings.instance.automaticOnlineLyrics.value;
        final preferences = AppSettings.instance.japaneseReadings.value;
        await tester.tap(find.byKey(const ValueKey('open-mode')));
        await tester.pumpAndSettle();
        expect(returns, 0);
        expect(find.byType(Dialog), findsOneWidget);
        await _capture(tester, boundary,
            'mode-${language.code}-${size.$1.toInt()}-${size.$2.toInt()}');
        // Literal expectations catch a missing catalog key instead of agreeing
        // with the same ui() fallback that the production title uses.
        final expectedTitle = switch (language) {
          UiLanguage.zh => '生成日语假名',
          UiLanguage.en => 'Generate Japanese readings',
          UiLanguage.ja => '日本語の読み仮名を生成',
          UiLanguage.ko => '일본어 가나 생성',
        };
        expect(
            find.descendant(
                of: find.byType(AppDialogTitle),
                matching: find.text(expectedTitle)),
            findsOneWidget);
        if (language != UiLanguage.zh) {
          expect(
              find.descendant(
                  of: find.byType(Dialog), matching: find.text('生成日语假名')),
              findsNothing);
        }
        _expectCenteredChoices(tester, _mode);
        await expectJapaneseUiText(tester, find.byType(Dialog));

        final compact = find.descendant(
            of: find.byKey(_mode), matching: find.byType(OutlinedButton));
        if (compact.evaluate().isNotEmpty) {
          await tester.tap(compact);
          await tester.pumpAndSettle();
          await tester
              .tap(find.byKey(const ValueKey('japanese-reading-mode-online')));
        } else {
          await tester
              .tap(find.byKey(const ValueKey('japanese-reading-mode-online')));
        }
        await tester.pumpAndSettle();
        _expectCenteredChoices(tester, _mode);
        final control =
            tester.widget<AppSegmentedControl<JapaneseReadingRequestMode>>(
                find.byKey(_mode));
        expect(control.value, JapaneseReadingRequestMode.online);
        expect(returns, 0, reason: 'Choosing a mode is not generating.');
        await tester
            .tap(find.byKey(const ValueKey('japanese-reading-mode-generate')));
        await tester.pumpAndSettle();
        expect(returned, JapaneseReadingRequestMode.online);
        expect(returns, 1);
        expect(AppSettings.instance.automaticOnlineLyrics.value, automatic);
        expect(AppSettings.instance.japaneseReadings.value, same(preferences));
        expect(tester.takeException(), isNull);
        expect(tester.binding.transientCallbackCount, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }

    testWidgets('Japanese batch ${language.code} centers actual mode choices',
        (tester) async {
      final boundary = GlobalKey();
      final task = UiBatch();
      final preferences = ValueNotifier(const JapaneseReadingPreferences());
      final automaticallyOnline = ValueNotifier(false);
      addTearDown(task.dispose);
      addTearDown(preferences.dispose);
      addTearDown(automaticallyOnline.dispose);
      await mountJapaneseUi(
          tester,
          JapaneseReadingBatchSettings(
              task: task,
              preferences: preferences,
              automaticallyOnline: automaticallyOnline,
              persist: () async {}),
          language: language,
          boundary: boundary);
      await tester
          .tap(find.byKey(const ValueKey('japanese-reading-batch-open')));
      await tester.pumpAndSettle();
      await _capture(tester, boundary, 'batch-mode-${language.code}-1000-1');
      _expectCenteredChoices(tester, _batchMode);
      await expectJapaneseUiText(tester, find.byType(Dialog));
      expect(task.starts, 0);
      await tester
          .tap(find.byKey(const ValueKey('japanese-reading-batch-close')));
      await tester.pumpAndSettle();
      expect(task.starts, 0);
      expect(task.cancels, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  testWidgets(
      'Japanese visibility checkbox follows romanization and can hide while busy',
      (tester) async {
    final appearance = ValueNotifier(DesktopLyricAppearance.defaults);
    final controller = LyricViewController(
        preferences: NowPlayingPagePreference.fromMap({}),
        appearance: appearance);
    final busy = ValueNotifier(true);
    addTearDown(controller.dispose);
    addTearDown(appearance.dispose);
    addTearDown(busy.dispose);
    await mountJapaneseUi(
        tester,
        LyricReadingMenu(
            controller: controller,
            readLyric: () => null,
            japaneseReadingsBusy: busy));
    await tester.tap(find.byKey(const ValueKey('lyric-reading-tools')));
    await tester.pumpAndSettle();
    final choices = tester
        .widgetList<AppCheckboxMenuButton>(find.byType(AppCheckboxMenuButton))
        .toList();
    expect(
        choices.take(4).map((button) =>
            (((button.child as ConstrainedBox).child) as Text).data),
        [ui('显示歌词译文'), ui('显示歌词注音'), ui('显示日语假名'), ui('显示歌词时间')]);
    final japanese = find.byKey(const ValueKey('lyric-show-japanese-reading'));
    expect(tester.widget<AppCheckboxMenuButton>(japanese).value, isTrue);
    expect(tester.widget<AppCheckboxMenuButton>(japanese).onChanged, isNotNull);
    final romanization = find.ancestor(
        of: find.text(ui('显示歌词注音')),
        matching: find.byType(AppCheckboxMenuButton));
    expect(tester.getRect(japanese).top,
        greaterThan(tester.getRect(romanization).top));
    expect(tester.getRect(japanese).left, tester.getRect(romanization).left);
    expect(find.byKey(const ValueKey('lyric-generate-japanese-readings')),
        findsNothing);
    await tester.tap(japanese);
    await tester.pumpAndSettle();
    expect(controller.showJapaneseReading, isFalse);
    expect(controller.showTranslation, isTrue);
    expect(controller.showRomanization, isTrue);
    expect(busy.value, isTrue);
    expect(find.byType(Dialog), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'displayed lyric copy menus and shortcut omit hidden Japanese reading',
      (tester) async {
    final copies = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copies.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final appearance = ValueNotifier(DesktopLyricAppearance.defaults);
    final controller = LyricViewController(
        preferences: NowPlayingPagePreference.fromMap({}),
        appearance: appearance);
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(appearance.dispose);
    addTearDown(focus.dispose);
    final line = LrcLine(Duration.zero, '夜空を読む┃Reading translation',
        isBlank: false, length: const Duration(seconds: 5))
      ..romanization = 'Authored romanization'
      ..japaneseReading = 'よぞらをよむ';
    final future = Future<Lyric?>.value(_CopyLyric([line]));
    const rowKey = ValueKey('copy-current-line');
    await mountJapaneseUi(
        tester,
        Column(children: [
          LyricReadingMenu(controller: controller, readLyric: () => future),
          LyricLineReadingActions(
              line: line,
              controller: controller,
              timed: true,
              child: Focus(
                  focusNode: focus,
                  child: const SizedBox(
                      key: rowKey,
                      width: 300,
                      height: 100,
                      child: Text('夜空を読む'))))
        ]));

    Future<void> copyAll() async {
      await tester.tap(find.byKey(const ValueKey('lyric-reading-tools')));
      await tester.pumpAndSettle();
      final copy = find.widgetWithText(MenuItemButton, ui('复制完整显示歌词'));
      await tester.ensureVisible(copy);
      await tester.pumpAndSettle();
      await tester.tap(copy);
      await tester.pumpAndSettle();
    }

    await copyAll();
    expect(copies.last, contains('よぞらをよむ'));
    controller.toggleJapaneseReading();
    await tester.pumpAndSettle();
    await copyAll();
    const displayed = 'Authored romanization\n夜空を読む\nReading translation';
    expect(copies.last, displayed);
    for (final timestamp in [false, true]) {
      await tester.tap(find.byKey(rowKey), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(
          MenuItemButton, ui(timestamp ? '复制歌词与时间' : '复制这一句歌词')));
      await tester.pumpAndSettle();
      expect(
          copies.last,
          timestamp
              ? 'Authored romanization\n[00:00.000] 夜空を読む\nReading translation'
              : displayed);
    }
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC,
        physicalKey: PhysicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(copies.length, 5);
    expect(copies.last, displayed);
    expect(line.content, '夜空を読む┃Reading translation');
    expect(line.romanization, 'Authored romanization');
    expect(line.japaneseReading, 'よぞらをよむ');
    expect(line.start, Duration.zero);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _CopyLyric extends Lyric {
  _CopyLyric(super.lines);
}

/// The LayoutBuilder/control wrapper can be wider than its painted segments.
/// Compare the actual native button surfaces with the actual dialog surface.
void _expectCenteredChoices(WidgetTester tester, Key key) {
  final control = find.byKey(key);
  final compact =
      find.descendant(of: control, matching: find.byType(OutlinedButton));
  final buttons = compact.evaluate().isNotEmpty
      ? compact
      : find.descendant(of: control, matching: find.byType(TextButton));
  final rects = buttons
      .evaluate()
      .map((element) => tester.getRect(find.byWidget(element.widget)))
      .toList();
  expect(rects, isNotEmpty);
  final group = rects.reduce((first, next) => first.expandToInclude(next));
  // Dialog's route padding fills the screen; its first Material is the actual
  // rounded surface, unlike the transparent Material inside SegmentedButton.
  final dialog = tester.getRect(find
      .descendant(of: find.byType(Dialog), matching: find.byType(Material))
      .first);
  expect(group.center.dx, closeTo(dialog.center.dx, .5),
      reason: 'The visible choices must share the heading/dialog center.');
  expect(group.left, greaterThanOrEqualTo(dialog.left + 16));
  expect(group.right, lessThanOrEqualTo(dialog.right - 16));
  for (final rect in rects) {
    expect(rect.height, greaterThanOrEqualTo(44));
  }
}

Future<void> _capture(
    WidgetTester tester, GlobalKey boundary, String name) async {
  final output = Platform.environment['DAN_KANA_LAYOUT_RENDER_DIR'];
  if (output == null || output.isEmpty) return;
  final directory = p.normalize(p.absolute(output));
  expect(p.isWithin(p.normalize(_qa), directory), isTrue);
  await tester.runAsync(() async {
    await Directory(directory).create(recursive: true);
    final render =
        boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: raster.ImageByteFormat.png);
      await File(p.join(directory, '$name.png'))
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
