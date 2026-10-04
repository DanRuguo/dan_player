import 'dart:io';

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/player_feature_guide.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/playlist_feature_fixture.dart';

const _statisticsHeadings = [
  '1. 打开统计与更新展示',
  '2. 最近一天：时长、次数与时段',
  '3. 日历与听歌习惯洞察',
  '4. 趋势：比较两个完整区间',
  '5. 排行：播放最多与收听最久',
  '6. 曲库构成与语言判定',
  '7. 音乐文件、文件夹与缓存空间',
  '8. 按需查看播放器资源',
];

final _qaRoot = path.normalize(path.join(Directory.current.parent.path, 'tool',
    'qa-local', 'sidebar-monitor-manual-2606-oct4', 'manual'));

Widget _host(Widget child,
        {GlobalKey? boundary, double scale = 1, bool dark = false}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: applyAppControlTheme(ThemeData(
          platform: TargetPlatform.windows,
          useMaterial3: true,
          fontFamily: danEmbeddedFontFamily,
          fontFamilyFallback: danFontFamilyFallback,
          colorScheme: ColorScheme.fromSeed(
              seedColor: dark ? Colors.deepOrange : Colors.teal,
              brightness: dark ? Brightness.dark : Brightness.light))),
      builder: (context, child) => UiLanguageScope(
          child: RepaintBoundary(
              key: boundary,
              child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      disableAnimations: true,
                      textScaler: TextScaler.linear(scale)),
                  child: child!))),
      home: Scaffold(body: child),
    );

Finder _header(String id) => find
    .descendant(
        of: find.byKey(ValueKey('guide-section-$id')),
        matching: find.byType(ListTile))
    .first;

Future<void> _toggle(WidgetTester tester, String id) async {
  await tester.ensureVisible(_header(id));
  await tester.pumpAndSettle();
  await tester.tap(_header(id));
  await tester.pumpAndSettle();
}

void _withinWidth(WidgetTester tester, Finder item, double width) {
  final rect = tester.getRect(item);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(width));
  expect(tester.takeException(), isNull);
}

List<String> _changedUiLiterals() {
  final source =
      File('lib/component/player_feature_guide.dart').readAsStringSync();
  final statistics = source.substring(
      source.indexOf("_section(context, 'statistics'"),
      source.indexOf("_section(context, 'backup-workflow'"));
  final personal = source.substring(
      source.indexOf("_paragraph(context, '给喜欢的歌曲评分"),
      source.indexOf("_section(context, 'batch-edit'"));
  return RegExp(r"'((?:\\.|[^'\\])*)'")
      .allMatches('$statistics\n$personal')
      .map((match) => match.group(1)!.replaceAll(r'\n', '\n'))
      .where((text) => RegExp(r'[\u4e00-\u9fff]').hasMatch(text))
      .toSet()
      .toList();
}

Future<void> _loadStatisticsGuideFonts() async {
  await loadPlaylistFeatureFonts();
  final windows = Platform.environment['WINDIR'];
  if (windows == null) return;
  // The bundled Chinese font omits the Japanese middle dot. Widget tests
  // must register the player's real Windows fallback instead of rendering
  // that punctuation as blank and mistaking the result for production.
  final japanese = File(path.join(windows, 'Fonts', 'YuGothR.ttc'));
  if (await japanese.exists()) {
    await (FontLoader('Yu Gothic UI')
          ..addFont(
              Future.value(ByteData.sublistView(await japanese.readAsBytes()))))
        .load();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const provider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory fixture;
  late UiLanguage previousLanguage;
  setUpAll(_loadStatisticsGuideFonts);
  setUp(() async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR'], isNull,
        reason: 'This fixture injects path_provider; do not bypass it');
    final temp = Directory(path.join(_qaRoot, 'temp'));
    await temp.create(recursive: true);
    fixture = await temp.createTemp('statistics-guide-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(provider, (_) async => fixture.path);
    previousLanguage = uiLanguage.value;
    final output = Platform.environment['DAN_PLAYLIST_FEATURE_RENDER_DIR'];
    if (output != null) {
      expect(path.isWithin(_qaRoot, path.normalize(path.absolute(output))),
          isTrue);
    }
  });
  tearDown(() async {
    uiLanguage.value = previousLanguage;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(provider, null);
    expect(
        path.isWithin(_qaRoot, path.normalize(fixture.absolute.path)), isTrue);
    await fixture.delete(recursive: true);
  });

  test('statistics manual source labels and explanations have four languages',
      () {
    final literals = _changedUiLiterals();
    expect(literals.length, greaterThan(25));
    for (final text in literals) {
      for (final language in UiLanguage.values) {
        final translated = translateUi(text, language);
        expect(translated.trim(), isNotEmpty, reason: text);
        if (language != UiLanguage.zh) {
          expect(translated, isNot(text), reason: '${language.name}: $text');
        }
        expect(
            RegExp(r'\{\d+\}').allMatches(translated).map((m) => m[0]).toList(),
            RegExp(r'\{\d+\}').allMatches(text).map((m) => m[0]).toList(),
            reason: '${language.name}: $text');
      }
    }
  });

  testWidgets('statistics guide preserves tools and links to the complete page',
      (tester) async {
    sizePlaylistFeature(tester, width: 1080, height: 950);
    uiLanguage.value = UiLanguage.zh;
    final hidden = ValueNotifier(false);
    addTearDown(hidden.dispose);
    final destinations = <String>[];
    await tester.pumpWidget(_host(PlayerFeatureGuideDialog(
        onNavigate: destinations.add, demoIsHidden: hidden)));
    await _toggle(tester, 'statistics');
    for (final item in [
      ('guide-listening-statistics', '/statistics'),
      ('guide-cache-statistics', '/statistics?section=cache'),
      (
        'guide-resource-settings',
        '/settings?section=backup&setting=process-resources'
      ),
    ]) {
      final link = find.byKey(ValueKey(item.$1));
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      await tester.tap(link);
      expect(destinations.last, item.$2);
    }
    expect(find.byKey(const ValueKey('guide-flow-statistics')), findsOneWidget);
    expect(PlayService.isInitialized, isFalse);
    expect(fixture.listSync(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('statistics workflow is readable and scrollable in a wide guide',
      (tester) async {
    sizePlaylistFeature(tester, width: 1080, height: 1100);
    uiLanguage.value = UiLanguage.zh;
    final hidden = ValueNotifier(false);
    addTearDown(hidden.dispose);
    final boundary = GlobalKey();
    await tester.pumpWidget(_host(
        PlayerFeatureGuideDialog(demoIsHidden: hidden),
        boundary: boundary));
    await _toggle(tester, 'statistics');
    for (final item in [
      (0, 'statistics-guide-zh-overview-wide'),
      (3, 'statistics-guide-zh-trends-ranking-wide'),
      (6, 'statistics-guide-zh-storage-wide'),
    ]) {
      final heading = find.text(ui(_statisticsHeadings[item.$1]));
      await Scrollable.ensureVisible(tester.element(heading), alignment: 0);
      await tester.pumpAndSettle();
      expect(heading.hitTestable(), findsOneWidget);
      _withinWidth(tester, heading, 1080);
      await capturePlaylistFeature(tester, boundary, item.$2);
    }
    final resources = find.text(ui(_statisticsHeadings.last));
    await tester.ensureVisible(resources);
    await tester.pumpAndSettle();
    expect(resources.hitTestable(), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    expect(PlayService.isInitialized, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final language in UiLanguage.values) {
    testWidgets('statistics guide ${language.name} narrow enlarged rendering',
        (tester) async {
      sizePlaylistFeature(tester, width: 360, height: 1200);
      uiLanguage.value = language;
      final hidden = ValueNotifier(false);
      addTearDown(hidden.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(_host(
          PlayerFeatureGuideDialog(demoIsHidden: hidden),
          boundary: boundary,
          scale: 1.5,
          dark: language == UiLanguage.en || language == UiLanguage.ko));
      await _toggle(tester, 'statistics');
      final section = find.byKey(const ValueKey('guide-section-statistics'));
      final texts = find
          .descendant(of: section, matching: find.byType(Text))
          .evaluate()
          .map((element) => element.widget as Text)
          .where((text) => text.data != null && text.data!.length > 50)
          .map((text) => text.data!)
          .toSet();
      // Every added long paragraph is naturally laid out, not merely the titles.
      expect(texts.length, greaterThan(12));
      for (final text in texts) {
        _withinWidth(tester, find.text(text), 360);
      }
      for (var index = 0; index < _statisticsHeadings.length; index++) {
        final heading = find.text(ui(_statisticsHeadings[index]));
        await Scrollable.ensureVisible(tester.element(heading), alignment: 0);
        await tester.pumpAndSettle();
        expect(heading.hitTestable(), findsOneWidget);
        _withinWidth(tester, heading, 360);
        if (index == 1 || index == 3 || index == 6) {
          await capturePlaylistFeature(tester, boundary,
              'statistics-guide-${language.name}-section-${index + 1}-narrow');
        }
      }
      final link = find.byKey(const ValueKey('guide-listening-statistics'));
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      expect(link.hitTestable(), findsOneWidget);
      _withinWidth(tester, link, 360);
      await _toggle(tester, 'statistics');
      await _toggle(tester, 'smart');
      final personal = find.text(ui('给喜欢的歌曲评分，再按标签找回'));
      await Scrollable.ensureVisible(tester.element(personal), alignment: 0);
      await tester.pumpAndSettle();
      _withinWidth(tester, personal, 360);
      await capturePlaylistFeature(tester, boundary,
          'statistics-guide-${language.name}-personal-narrow');
      expect(PlayService.isInitialized, isFalse);
      expect(fixture.listSync(), isEmpty);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
