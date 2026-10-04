import 'dart:io';

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/player_feature_guide.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/search/settings_search_index.dart';
import 'package:desktop_lyric/l10n/catalog_player_feature_guide.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/playlist_feature_fixture.dart';

const _topics = [
  ('batch-edit', '多选与批量整理', 'guide-batch-music-page', 'batch'),
  ('offline-lyrics', '本地歌词与离线准备', 'guide-offline-lyric-settings', null),
  ('relink', '音乐目录重定位', 'guide-library-health-settings', 'relink'),
  ('sources-comments', '歌词来源与评论关联', 'guide-lyric-source-settings', null),
];

Widget _app(Widget child, {GlobalKey? boundary, double scale = 1}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: applyAppControlTheme(ThemeData(
          platform: TargetPlatform.windows,
          useMaterial3: true,
          fontFamily: danEmbeddedFontFamily,
          fontFamilyFallback: danFontFamilyFallback,
          colorScheme: ColorScheme.fromSeed(
              seedColor: scale > 1 ? Colors.deepOrange : Colors.teal,
              brightness: scale > 1 ? Brightness.dark : Brightness.light))),
      builder: (context, child) => RepaintBoundary(
          key: boundary,
          child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: TextScaler.linear(scale)),
              child: child!)),
      home: Scaffold(body: child),
    );

Finder _header(String id) => find
    .descendant(
        of: find.byKey(ValueKey('guide-section-$id')),
        matching: find.byType(ListTile))
    .first;

Future<void> _showHeader(WidgetTester tester, String id) async {
  await Scrollable.ensureVisible(tester.element(_header(id)), alignment: 0);
  await tester.pumpAndSettle();
}

Future<void> _toggle(WidgetTester tester, String id) async {
  await _showHeader(tester, id);
  await tester.tap(_header(id));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() {
    final output = Platform.environment['DAN_PLAYLIST_FEATURE_RENDER_DIR'];
    if (output == null) return;
    final allowed = path.normalize(path.join(Directory.current.parent.path,
        'tool', 'qa-local', 'resource-surfaces-2606-oct4', 'guide'));
    expect(
        path.isWithin(allowed, path.normalize(path.absolute(output))), isTrue,
        reason: 'Workflow screenshots must stay in isolated guide QA');
  });

  test('new workflows and monitor instructions have four complete languages',
      () {
    final keys = [
      ...catalogPlayerFeatureGuide.keys.skipWhile((key) => key != '多选与批量整理'),
      ...catalogPlayerFeatureGuide.keys.where(
          (key) => key.startsWith('资源监控先由总开关启用') || key.startsWith('只采样播放器自身')),
    ];
    expect(keys.length, greaterThanOrEqualTo(21));
    for (final key in keys) {
      expect(catalogPlayerFeatureGuide[key], hasLength(3));
      for (final language in UiLanguage.values) {
        expect(translateUi(key, language).trim(), isNotEmpty);
        if (language != UiLanguage.zh) {
          expect(translateUi(key, language), isNot(key), reason: key);
        }
      }
    }
    for (final language in UiLanguage.values) {
      final text = translateUi('操作顺序：{0}', language, ['1 → 2 → 3']);
      expect(text, contains('1 → 2 → 3'));
      expect(text, isNot(contains('{0}')));
    }
  });

  testWidgets('workflow links use real page and setting destinations',
      (tester) async {
    sizePlaylistFeature(tester);
    final previous = uiLanguage.value;
    addTearDown(() => uiLanguage.value = previous);
    uiLanguage.value = UiLanguage.zh;
    final destinations = <String>[];
    await tester.pumpWidget(
        _app(PlayerFeatureGuideDialog(onNavigate: destinations.add)));
    await _toggle(tester, 'playlists');
    String? current;
    for (final item in [
      ('batch-edit', 'guide-batch-music-page', '/audios'),
      ('offline-lyrics', 'guide-offline-lyric-settings', 'lyrics/batch'),
      ('relink', 'guide-library-health-settings', 'library/health'),
      (
        'sources-comments',
        'guide-automatic-online-settings',
        'lyrics/automatic'
      ),
      ('sources-comments', 'guide-lyric-source-settings', 'lyrics/source'),
      ('statistics', 'guide-resource-settings', 'backup/process-resources'),
    ]) {
      if (current != item.$1) {
        if (current != null) await _toggle(tester, current);
        await _toggle(tester, item.$1);
        current = item.$1;
      }
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
    testWidgets('workflow ${language.name} narrow large real glyphs',
        (tester) async {
      sizePlaylistFeature(tester, width: 360, height: 1200);
      final previous = uiLanguage.value;
      addTearDown(() => uiLanguage.value = previous);
      uiLanguage.value = language;
      final boundary = GlobalKey();
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(_app(const PlayerFeatureGuideDialog(),
            boundary: boundary, scale: 1.5));
        await _toggle(tester, 'playlists');
        for (final topic in _topics) {
          await _toggle(tester, topic.$1);
          final section = find.byKey(ValueKey('guide-section-${topic.$1}'));
          expect(
              find.descendant(of: section, matching: find.text(ui(topic.$2))),
              findsOneWidget);
          final flowId = topic.$4;
          if (flowId != null) {
            final flow = find.byKey(ValueKey('guide-flow-$flowId'));
            await tester.ensureVisible(flow);
            await tester.pumpAndSettle();
            final labels = (flowId == 'batch'
                    ? ['选择歌曲', '预览修改', '应用预览']
                    : ['预览映射', '确认并退出', '重新启动'])
                .map((step) => ui(step))
                .toList();
            expect(find.bySemanticsLabel(ui('操作顺序：{0}', [labels.join(' → ')])),
                findsOneWidget);
            final color =
                Theme.of(tester.element(flow)).colorScheme.secondaryContainer;
            for (final box in tester.widgetList<DecoratedBox>(find.descendant(
                of: flow, matching: find.byType(DecoratedBox)))) {
              expect((box.decoration as ShapeDecoration).color, color);
            }
            final rect = tester.getRect(flow);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(360));
            expect(tester.takeException(), isNull);
            await capturePlaylistFeature(
                tester, boundary, 'workflow-${language.name}-$flowId-narrow');
          }
          final link = find.byKey(ValueKey(topic.$3));
          await tester.ensureVisible(link);
          await tester.pumpAndSettle();
          expect(link.hitTestable(), findsOneWidget);
          final linkRect = tester.getRect(link);
          expect(linkRect.left, greaterThanOrEqualTo(0));
          expect(linkRect.right, lessThanOrEqualTo(360));
          expect(tester.takeException(), isNull);
          await _toggle(tester, topic.$1);
        }
        await _toggle(tester, 'statistics');
        final monitorText = find.text(ui(catalogPlayerFeatureGuide.keys
            .singleWhere((key) => key.startsWith('资源监控先由总开关启用'))));
        await tester.ensureVisible(monitorText);
        await tester.pumpAndSettle();
        await capturePlaylistFeature(
            tester, boundary, 'workflow-${language.name}-monitor-narrow');
        expect(tester.takeException(), isNull);
        expect(PlayService.isInitialized, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(tester.binding.transientCallbackCount, 0);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('workflow diagram stays compact in a wide light theme',
      (tester) async {
    sizePlaylistFeature(tester, width: 1080, height: 850);
    final previous = uiLanguage.value;
    addTearDown(() => uiLanguage.value = previous);
    uiLanguage.value = UiLanguage.en;
    final boundary = GlobalKey();
    await tester
        .pumpWidget(_app(const PlayerFeatureGuideDialog(), boundary: boundary));
    await _toggle(tester, 'playlists');
    await _toggle(tester, 'batch-edit');
    final flow = find.byKey(const ValueKey('guide-flow-batch'));
    await tester.ensureVisible(flow);
    await tester.pumpAndSettle();
    expect(tester.getSize(flow).height, lessThan(50));
    expect(tester.takeException(), isNull);
    await capturePlaylistFeature(tester, boundary, 'workflow-en-batch-wide');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
