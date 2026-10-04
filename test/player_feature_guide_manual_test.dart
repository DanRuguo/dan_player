import 'dart:io';

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/player_feature_guide.dart';
import 'package:dan_player/lyric/lyric_edit_codec.dart';
import 'package:dan_player/lyric/tap_lyric_session.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/search/settings_search_index.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/playlist_feature_fixture.dart';

const _chapters = [
  ('start', '导入与起步'),
  ('playback', '播放与队列'),
  ('organize', '整理音乐'),
  ('lyric-tools', '歌词工具与制作'),
  ('audio-tools', '声音与音频文件'),
  ('windows', '外观与窗口'),
  ('maintenance', '统计与维护'),
  ('input-tools', '搜索与快捷键'),
];
const _editing = [
  (
    'manual-lyric-edit',
    'manual-edit',
    'manual-lrc',
    'guide-manual-edit-page',
    ['传统码字', '编辑与试听', '保存编辑副本', '使用编辑的本地歌词'],
    [
      '1. 打开编辑器并选择格式',
      '2. 载入内容并分开编辑',
      '3. 用试听位置设置句与字的时间',
      '4. 预览、保存与明确选用',
      '5. 导出、回退与保护',
    ]
  ),
  (
    'tap-lyric-edit',
    'tap-edit',
    'tap-columns',
    'guide-tap-edit-page',
    ['准备歌词文本', '逐句打点', '逐字打点（可选）', '保存并选用'],
    [
      '1. 准备正文、翻译与注音',
      '2. 逐句开始、结束与试听确认',
      '3. 可选：继续逐字打点',
      '4. 保存进度、退出与重新修改',
      '5. 选择格式、保存副本并投入播放',
    ]
  ),
];

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

Future<void> _top(WidgetTester tester) async {
  tester
      .widget<SingleChildScrollView>(
          find.byKey(const ValueKey('player-feature-guide-scroll')))
      .controller!
      .jumpTo(0);
  await tester.pumpAndSettle();
}

void _inViewport(WidgetTester tester, Finder target, double width) {
  final rect = tester.getRect(target);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(width));
  expect(tester.takeException(), isNull);
}

Future<void> _loadManualFonts() async {
  await loadPlaylistFeatureFonts();
  final windows = Platform.environment['WINDIR'];
  if (windows == null) return;
  final font = File(path.join(windows, 'Fonts', 'consola.ttf'));
  if (await font.exists()) {
    await (FontLoader('Consolas')
          ..addFont(
              Future.value(ByteData.sublistView(await font.readAsBytes()))))
        .load();
  }
}

void main() {
  setUpAll(_loadManualFonts);
  setUp(() {
    final output = Platform.environment['DAN_PLAYLIST_FEATURE_RENDER_DIR'];
    if (output == null) return;
    final allowed = path.normalize(path.join(Directory.current.parent.path,
        'tool', 'qa-local', 'resource-guide-edit-2606-oct4', 'guide'));
    expect(
        path.isWithin(allowed, path.normalize(path.absolute(output))), isTrue,
        reason: 'Manual screenshots must stay in isolated guide QA');
  });

  test('all manual UI strings, including workflow labels, have four languages',
      () {
    final source =
        File('lib/component/player_feature_guide.dart').readAsStringSync();
    // Audit every Chinese UI literal, not merely the keys already registered.
    final literals = RegExp(r"'((?:\\.|[^'\\])*)'")
        .allMatches(source)
        .map((match) => match.group(1)!.replaceAll(r'\n', '\n'))
        .where((text) => RegExp(r'[\u4e00-\u9fff]').hasMatch(text))
        .toSet();
    expect(literals.length, greaterThan(100));
    for (final text in literals) {
      for (final language in UiLanguage.values) {
        final translated = translateUi(text, language);
        expect(translated.trim(), isNotEmpty, reason: text);
        if (language != UiLanguage.zh) {
          expect(translated, isNot(text),
              reason: 'Missing ${language.name} manual text: $text');
        }
      }
    }
  });

  testWidgets(
      'manual contents reach eight chapters and survive appearance changes',
      (tester) async {
    sizePlaylistFeature(tester, width: 1080, height: 900);
    final previous = uiLanguage.value;
    addTearDown(() => uiLanguage.value = previous);
    uiLanguage.value = UiLanguage.zh;
    final boundary = GlobalKey();
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
          _host(const PlayerFeatureGuideDialog(), boundary: boundary));
      expect(find.byKey(const ValueKey('guide-flow-first-play')).hitTestable(),
          findsOneWidget);
      expect(find.text(ui('自定义顺序与拖动')), findsOneWidget);
      final contents = find.byKey(const ValueKey('guide-manual-contents'));
      _inViewport(tester, contents, 1080);
      await capturePlaylistFeature(tester, boundary, 'manual-zh-contents-wide');
      final keys = <Key?>[];
      for (final chapter in _chapters) {
        await _top(tester);
        await tester.tap(find.byKey(ValueKey('guide-jump-${chapter.$1}')));
        await tester.pumpAndSettle();
        final heading = find.byKey(ValueKey('guide-chapter-${chapter.$1}'));
        expect(heading.hitTestable(), findsOneWidget);
        expect(tester.widget<Semantics>(heading).properties.header, isTrue);
        keys.add(tester
            .widget<KeyedSubtree>(find
                .ancestor(of: heading, matching: find.byType(KeyedSubtree))
                .first)
            .key);
      }
      await _toggle(tester, 'manual-lyric-edit');
      await _top(tester);
      uiLanguage.value = UiLanguage.en;
      await tester.pumpWidget(_host(const PlayerFeatureGuideDialog(),
          boundary: boundary, dark: true));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('guide-code-manual-lrc')), findsOneWidget);
      for (var index = 0; index < _chapters.length; index++) {
        final chapter = _chapters[index];
        final heading = find.byKey(ValueKey('guide-chapter-${chapter.$1}'));
        expect(
            tester
                .widget<KeyedSubtree>(find
                    .ancestor(of: heading, matching: find.byType(KeyedSubtree))
                    .first)
                .key,
            keys[index]);
        await _top(tester);
        await tester.tap(find.byKey(ValueKey('guide-jump-${chapter.$1}')));
        await tester.pumpAndSettle();
        expect(heading.hitTestable(), findsOneWidget);
        expect(find.text('${index + 1} · ${ui(chapter.$2)}'), findsNWidgets(2));
      }
      expect(PlayService.isInitialized, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('new manual entry links navigate without starting playback',
      (tester) async {
    sizePlaylistFeature(tester);
    final previous = uiLanguage.value;
    addTearDown(() => uiLanguage.value = previous);
    uiLanguage.value = UiLanguage.zh;
    final destinations = <String>[];
    await tester.pumpWidget(
        _host(PlayerFeatureGuideDialog(onNavigate: destinations.add)));
    for (final item in [
      ('getting-started', 'guide-first-import-settings', 'library/folders'),
      ('getting-started', 'guide-first-refresh-settings', 'library/refresh'),
      ('getting-started', 'guide-first-watch-settings', 'library/watch'),
      ('manual-lyric-edit', 'guide-manual-edit-page', '/nowplaying'),
      ('tap-lyric-edit', 'guide-tap-edit-page', '/nowplaying'),
      ('backup-workflow', 'guide-manual-backup-settings', 'backup/backup'),
    ]) {
      if (item.$1 != 'getting-started') await _toggle(tester, item.$1);
      final link = find.byKey(ValueKey(item.$2));
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      await tester.tap(link);
      final expected = item.$3.startsWith('/')
          ? item.$3
          : settingsSearchEntries
              .singleWhere((entry) => '${entry.section}/${entry.id}' == item.$3)
              .location;
      expect(destinations.last, expected);
    }
    expect(destinations, hasLength(6));
    expect(PlayService.isInitialized, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final language in UiLanguage.values) {
    testWidgets(
        'manual ${language.name} full editing paths narrow large glyphs',
        (tester) async {
      sizePlaylistFeature(tester, width: 360, height: 1200);
      final previous = uiLanguage.value;
      addTearDown(() => uiLanguage.value = previous);
      uiLanguage.value = language;
      final boundary = GlobalKey();
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(_host(const PlayerFeatureGuideDialog(),
            boundary: boundary, scale: 1.5, dark: true));
        _inViewport(
            tester, find.byKey(const ValueKey('guide-manual-contents')), 360);
        for (final chapter in _chapters) {
          expect(
              find.byKey(ValueKey('guide-jump-${chapter.$1}')), findsOneWidget);
        }
        await capturePlaylistFeature(
            tester, boundary, 'manual-${language.name}-contents-narrow');
        await _toggle(tester, 'getting-started');
        await _toggle(tester, 'playlists');
        for (final editor in _editing) {
          await _toggle(tester, editor.$1);
          final flow = find.byKey(ValueKey('guide-flow-${editor.$2}'));
          await tester.ensureVisible(flow);
          await tester.pumpAndSettle();
          expect(
              find.bySemanticsLabel(ui(
                  '操作顺序：{0}', [editor.$5.map((step) => ui(step)).join(' → ')])),
              findsOneWidget);
          _inViewport(tester, flow, 360);
          await capturePlaylistFeature(
              tester, boundary, 'manual-${language.name}-${editor.$2}-start');
          for (final step in editor.$6) {
            final heading = find.text(ui(step));
            expect(heading, findsOneWidget);
            await tester.ensureVisible(heading);
            await tester.pumpAndSettle();
            _inViewport(tester, heading, 360);
          }
          final code = find.byKey(ValueKey('guide-code-${editor.$3}'));
          await tester.ensureVisible(code);
          await tester.pumpAndSettle();
          _inViewport(tester, code, 360);
          await capturePlaylistFeature(
              tester, boundary, 'manual-${language.name}-${editor.$2}-example');
          final lastStep = find.text(ui(editor.$6.last));
          await tester.ensureVisible(lastStep);
          await tester.pumpAndSettle();
          await capturePlaylistFeature(
              tester, boundary, 'manual-${language.name}-${editor.$2}-finish');
          final link = find.byKey(ValueKey(editor.$4));
          await tester.ensureVisible(link);
          await tester.pumpAndSettle();
          expect(link.hitTestable(), findsOneWidget);
          _inViewport(tester, link, 360);
          await _toggle(tester, editor.$1);
        }
        expect(PlayService.isInitialized, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(tester.binding.transientCallbackCount, 0);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('wide editing examples are usable by the real lyric parsers',
      (tester) async {
    sizePlaylistFeature(tester, width: 1080, height: 850);
    final previous = uiLanguage.value;
    addTearDown(() => uiLanguage.value = previous);
    uiLanguage.value = UiLanguage.en;
    final boundary = GlobalKey();
    await tester.pumpWidget(
        _host(const PlayerFeatureGuideDialog(), boundary: boundary));
    await _toggle(tester, 'getting-started');
    await _toggle(tester, 'playlists');
    await _toggle(tester, 'manual-lyric-edit');
    final lrc = find.byKey(const ValueKey('guide-code-manual-lrc'));
    await tester.ensureVisible(lrc);
    await tester.pumpAndSettle();
    final text = tester.widget<SelectableText>(lrc).data!;
    final lyrics = LyricEditDraft(LyricEditFormat.lrc, text).parse();
    expect(lyrics.lines.single.start, const Duration(seconds: 1));
    expect(lyricLineText(lyrics.lines.single), 'Hello world');
    await capturePlaylistFeature(tester, boundary, 'manual-en-direct-wide');
    await _toggle(tester, 'manual-lyric-edit');
    await _toggle(tester, 'tap-lyric-edit');
    final tap = find.byKey(const ValueKey('guide-code-tap-columns'));
    await tester.ensureVisible(tap);
    await tester.pumpAndSettle();
    final rows = parseTapText(tester.widget<SelectableText>(tap).data!, 0);
    expect(rows, hasLength(2));
    expect(rows.first.translation, isNotEmpty);
    expect(rows.first.romanization, isNotEmpty);
    expect(rows.last.translation, isEmpty);
    expect(rows.last.romanization, isNotEmpty);
    for (final language in UiLanguage.values) {
      final localized =
          parseTapText(translateUi('正文|翻译|注音\n正文||注音', language), 0);
      expect(localized, hasLength(2));
      expect(localized.last.translation, isEmpty);
      expect(localized.last.romanization, isNotEmpty);
    }
    await capturePlaylistFeature(tester, boundary, 'manual-en-tap-wide');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
