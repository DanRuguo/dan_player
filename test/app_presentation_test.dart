import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/audio_metadata_dialog.dart';
import 'package:dan_player/component/playlist_name_dialog.dart';
import 'package:dan_player/page/settings_page/shortcut_settings.dart';
import 'package:dan_player/player_shortcut_preferences.dart';
import 'package:dan_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

void main() {
  late BuildContext pageContext;
  late StateSetter resize;
  double sidebar = 240;
  const panelKey = ValueKey('test-content-panel');
  const editorKey = ValueKey('test-editor-content');
  final bubble = find.byKey(const ValueKey('app-notice-bubble'));

  Future<void> mount(WidgetTester tester,
      {Size size = const Size(1200, 800),
      double textScale = 1,
      Brightness brightness = Brightness.light}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    sidebar = size.width < 600 ? 0 : 240;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal, brightness: brightness)),
      scaffoldMessengerKey: SCAFFOLD_MESSAGER,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: AppPresentationHost(child: child!),
      ),
      home: Scaffold(
          body: Padding(
        padding: const EdgeInsets.only(top: 48, bottom: 12, right: 12),
        child: StatefulBuilder(builder: (context, setState) {
          resize = setState;
          return Row(children: [
            SizedBox(width: sidebar),
            Expanded(
                child: AppContentRegion(
                    key: ValueKey(
                        sidebar == 0 ? 'compact-region' : 'wide-region'),
                    child: ColoredBox(
                      key: panelKey,
                      color: Theme.of(context).colorScheme.surface,
                      child: Builder(builder: (context) {
                        pageContext = context;
                        return const SizedBox.expand();
                      }),
                    ))),
          ]);
        }),
      )),
    ));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
    });
  }

  void showEditor() {
    showAppDialog<void>(
        context: pageContext,
        builder: (context) => Dialog(
              child: SizedBox(
                  key: editorKey,
                  width: 400,
                  height: 240,
                  child: Column(children: [
                    const Text('编辑歌曲信息'),
                    const TextField(),
                    TextButton(
                        onPressed: () => showAppDialog<void>(
                            context: context,
                            builder: (_) => const Dialog(
                                child: SizedBox(
                                    key: ValueKey('nested-editor'),
                                    width: 200,
                                    height: 120))),
                        child: const Text('联网查找')),
                  ])),
            ));
  }

  testWidgets(
      'dialog is centered in content, tracks sidebar and nested dialogs',
      (tester) async {
    await mount(tester);
    showEditor();
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.byKey(editorKey)),
        tester.getCenter(find.byKey(panelKey)));
    expect(tester.getCenter(find.byKey(editorKey)).dx, isNot(600));
    resize(() => sidebar = 340);
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.byKey(editorKey)),
        tester.getCenter(find.byKey(panelKey)));
    // Crossing the responsive threshold replaces the content region while
    // the root modal survives. Its captured old handle must not stay in use.
    for (final width in [0.0, 240.0]) {
      resize(() => sidebar = width);
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.byKey(editorKey)),
          tester.getCenter(find.byKey(panelKey)));
    }
    await tester.tap(find.text('联网查找'));
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.byKey(const ValueKey('nested-editor'))),
        tester.getCenter(find.byKey(panelKey)));
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        '$brightness notice is topmost, compact, closable and avoids editor',
        (tester) async {
      await mount(tester, brightness: brightness);
      showEditor();
      await tester.pumpAndSettle();
      showAppNotice('已填入候选信息，请核对后保存', kind: AppNoticeKind.success);
      await tester.pumpAndSettle();
      final panel = tester.getRect(find.byKey(panelKey));
      final notice = tester.getRect(bubble);
      expect(notice.center.dx, panel.center.dx);
      expect(notice.width, lessThanOrEqualTo(panel.width * .6));
      expect(notice.bottom, lessThanOrEqualTo(panel.bottom));
      expect(
          tester.getRect(find.byKey(editorKey)).bottom, lessThan(notice.top));
      final scheme = Theme.of(tester.element(bubble)).colorScheme;
      expect(tester.widget<Material>(bubble).color, scheme.primaryContainer);
      // This button sits outside the navigator's modal barrier but above it.
      await tester.tap(find.byKey(const ValueKey('app-notice-close')));
      await tester.pumpAndSettle();
      expect(bubble, findsNothing);
      expect(find.byKey(editorKey), findsOneWidget);
      expect(tester.getCenter(find.byKey(editorKey)), panel.center);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'notice follows text width, wraps at 60%, and ellipsizes bounded lines',
      (tester) async {
    await mount(tester);
    showAppNotice('已保存');
    await tester.pumpAndSettle();
    final shortSize = tester.getSize(bubble);
    final longText = List.filled(40, '歌曲信息更新失败，请检查文件访问权限。').join();
    showAppNotice(longText, kind: AppNoticeKind.error);
    await tester.pumpAndSettle();
    final longSize = tester.getSize(bubble);
    expect(longSize.width,
        closeTo(tester.getSize(find.byKey(panelKey)).width * .6, .01));
    expect(longSize.width, greaterThan(shortSize.width));
    expect(longSize.height, greaterThan(shortSize.height));
    final text = tester.widget<Text>(find.text(longText));
    expect(text.maxLines, lessThanOrEqualTo(3));
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new notice cancels old expiration and keeps accessible action',
      (tester) async {
    await mount(tester);
    showAppNotice('旧消息', duration: const Duration(milliseconds: 50));
    await tester.pump();
    var retries = 0;
    showAppNotice('新消息', actionLabel: '重试', onAction: () => retries++);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('旧消息'), findsNothing);
    expect(find.text('新消息'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(retries, 1);
    expect(bubble, findsNothing);
  });

  testWidgets(
      'short narrow window with large text leaves scrollable editor usable',
      (tester) async {
    await mount(tester, size: const Size(507, 320), textScale: 2);
    showAppDialog<void>(
        context: pageContext,
        builder: (_) => AlertDialog(
              scrollable: true,
              title: const Text('编辑歌曲信息'),
              content: Text(List.filled(20, '歌曲名、艺术家与专辑信息').join('\n')),
              actions: [TextButton(onPressed: () {}, child: const Text('保存'))],
            ));
    await tester.pumpAndSettle();
    showAppNotice('更新歌曲信息失败，请检查访问权限并重试。' * 20, kind: AppNoticeKind.error);
    // Check the very first layout and intermediate fade frames, not only the
    // settled result: the notification must never cover the save action.
    for (final milliseconds in [0, 16, 48, 100]) {
      await tester.pump(Duration(milliseconds: milliseconds));
      expect(tester.getRect(find.text('保存')).bottom,
          lessThan(tester.getRect(bubble).top));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    final panel = tester.getRect(find.byKey(panelKey));
    final notice = tester.getRect(bubble);
    expect(notice.width, lessThanOrEqualTo(panel.width * .6));
    expect(notice.bottom, lessThanOrEqualTo(panel.bottom));
    expect(tester.getRect(find.text('保存')).bottom, lessThan(notice.top));
    await tester.tap(find.byKey(const ValueKey('app-notice-close')));
    await tester.pumpAndSettle();
    expect(bubble, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('real metadata editor remains usable above a narrow notification',
      (tester) async {
    await mount(tester, size: const Size(507, 320), textScale: 2);
    showEditAudioMetadataDialog(pageContext, CategoryTestAudio('Fixture'));
    await tester.pumpAndSettle();
    showAppNotice('已填入候选信息，尚未写入文件。请核对后保存。');
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('保存')).bottom,
        lessThan(tester.getRect(bubble).top));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shortcut recorder can save above notice at minimum window size',
      (tester) async {
    await mount(tester, size: const Size(507, 320), textScale: 2);
    final result = showAppDialog<ShortcutChord>(
        context: pageContext,
        builder: (_) => ShortcutRecorderDialog(
            definition: playerShortcutDefinitions.first,
            preferences: ShortcutPreferences.defaults()));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    showAppNotice('快捷键仅在播放器窗口内生效。');
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('save-shortcut-recording'));
    expect(tester.getRect(save).bottom, lessThan(tester.getRect(bubble).top));
    expect(tester.takeException(), isNull);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect((await result)?.keyId, LogicalKeyboardKey.keyB.keyId);
  });

  testWidgets('playlist name remains editable above notice in a short window',
      (tester) async {
    await mount(tester, size: const Size(507, 320), textScale: 2);
    final result = showPlaylistNameDialog(pageContext, title: '新建歌单');
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('playlist-name-input'));
    await tester.enterText(input, '我的歌单');
    showAppNotice('测试通知：可以继续编辑歌单名称。');
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('创建')).bottom,
        lessThan(tester.getRect(bubble).top));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(await result, '我的歌单');
  });

  testWidgets('offstage normal content does not anchor mini feedback',
      (tester) async {
    tester.view.physicalSize = const Size(520, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        builder: (_, child) => AppPresentationHost(child: child!),
        home: const Stack(children: [
          Offstage(
              offstage: true,
              child: TickerMode(
                  enabled: false,
                  child: AppContentRegion(
                      child: SizedBox(width: 1200, height: 800)))),
          Positioned.fill(child: AppContentRegion(child: SizedBox.expand())),
        ])));
    await tester.pumpAndSettle();
    showAppNotice('迷你窗口通知');
    await tester.pumpAndSettle();
    final rect = tester.getRect(bubble);
    expect(rect.center.dx, 260);
    expect(rect.bottom, lessThanOrEqualTo(300));
    expect(rect.width, lessThanOrEqualTo(312));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
