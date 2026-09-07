import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/library_folders_dialog.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/page/folders_page.dart' show folderDisplayName;
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _longFolder =
    r'J:\Music\ゲーム音楽\2026年・大切にしている音楽コレクション\as9-nine- ARTEISIA オリジナルサウンドトラック\結想は花となる・ハイレゾ音源';
final _windows = TargetPlatformVariant.only(TargetPlatform.windows);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    await (FontLoader('packages/material_symbols_icons/MaterialSymbolsOutlined')
          ..addFont(rootBundle.load(
              'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf')))
        .load();
  });
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  Future<({GlobalKey capture, List<String> draft})> mount(
    WidgetTester tester, {
    List<String> folders = const [_longFolder],
    Size size = const Size(850, 650),
    double scale = 1,
    Brightness brightness = Brightness.light,
    VoidCallback? onConfirm,
    VoidCallback? onCancel,
    VoidCallback? onAdd,
    bool editing = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final capture = GlobalKey();
    final draft = List<String>.of(folders);
    final theme = Entry(welcome: false).fromSchemeAndFontFamily(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xffa95839), brightness: brightness),
        fontFamily: danEmbeddedFontFamily);
    late BuildContext pageContext;
    await tester.pumpWidget(UiLanguageScope(
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(
              key: capture, child: AppPresentationHost(child: child!)),
        ),
        home: Builder(builder: (context) {
          pageContext = context;
          return Scaffold(backgroundColor: theme.colorScheme.surfaceContainer);
        }),
      ),
    ));
    await tester.pump();
    showAppDialog<void>(
        context: pageContext,
        builder: (context) => StatefulBuilder(builder: (context, setState) {
              return LibraryFoldersDialog(
                folders: draft,
                folderName: folderDisplayName,
                editing: editing,
                onAdd:
                    onAdd ?? () => setState(() => draft.add(r'J:\Music\新收录')),
                onRemove: (index) => setState(() => draft.removeAt(index)),
                onCancel: () {
                  onCancel?.call();
                  Navigator.pop(context);
                },
                onConfirm: onConfirm ?? () {},
              );
            }));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
    return (capture: capture, draft: draft);
  }

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    final output = Platform.environment['DAN_PLAYER_QA_OUTPUT'];
    if (output == null) return;
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final bytes =
            await image.toByteData(format: drawing.ImageByteFormat.png);
        final file = File('$output/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
      } finally {
        image.dispose();
      }
    });
  }

  testWidgets(
      'one folder fits its content and exposes the full selectable path',
      (tester) async {
    final state = await mount(tester);
    final card = find.byKey(const ValueKey('library-folder-0'));
    final dialog = tester.getRect(find
        .descendant(of: find.byType(Dialog), matching: find.byType(Material))
        .first);
    expect(dialog.height, lessThan(420));
    final path = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(path.data, _longFolder);
    expect(path.maxLines, isNull,
        reason: 'long paths must wrap without truncation');
    expect(tester.getRect(card).width, greaterThan(400));
    final heading = tester.getRect(find.text(ui('管理文件夹')));
    expect(heading.center.dx, closeTo(dialog.center.dx, 1));
    expect(find.byTooltip(ui('复制路径')), findsOneWidget);
    expect(find.byTooltip(ui('移除文件夹')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, state.capture, 'folders-single-light');
  }, variant: _windows);

  testWidgets('draft add and removal do not save and cancel discards edits',
      (tester) async {
    var saved = 0;
    var cancelled = 0;
    const original = [r'J:\Music\Original'];
    final state = await mount(tester,
        folders: original,
        onConfirm: () => saved++,
        onCancel: () => cancelled++);
    await tester.tap(find.byTooltip(ui('移除文件夹')));
    await tester.pumpAndSettle();
    expect(find.text(ui('还没有音乐文件夹')), findsOneWidget);
    expect(state.draft, isEmpty);
    expect(original, [r'J:\Music\Original']);
    expect(saved, 0);
    await capture(tester, state.capture, 'folders-empty-light');
    await tester.tap(find.text(ui('添加文件夹')));
    await tester.pumpAndSettle();
    expect(state.draft, [r'J:\Music\新收录']);
    expect(saved, 0);
    await tester.tap(find.text(ui('取消')));
    await tester.pumpAndSettle();
    expect(cancelled, 1);
    expect(saved, 0);
    expect(find.byType(LibraryFoldersDialog), findsNothing);
  }, variant: _windows);

  testWidgets('copy uses the original full path and confirm submits explicitly',
      (tester) async {
    String? copied;
    var confirmed = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await mount(tester, onConfirm: () => confirmed++);
    await tester.tap(find.byTooltip(ui('复制路径')));
    await tester.pumpAndSettle();
    expect(copied, _longFolder);
    expect(confirmed, 0);
    await tester.tap(find.text(ui('确定')));
    await tester.pump();
    expect(confirmed, 1);
    expect(tester.takeException(), isNull);
  }, variant: _windows);

  testWidgets('many folders scroll while all save actions remain reachable',
      (tester) async {
    final state = await mount(tester,
        folders: [for (var i = 0; i < 18; i++) 'J:/Music/Collection $i'],
        brightness: Brightness.dark);
    final list = find.byType(ListView);
    final scroll = tester.widget<ListView>(list).controller!;
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    for (final action in ['添加文件夹', '取消', '确定']) {
      expect(find.text(ui(action)).hitTestable(), findsOneWidget);
    }
    await capture(tester, state.capture, 'folders-many-dark');
    await tester.drag(list, const Offset(0, -1700));
    await tester.pumpAndSettle();
    expect(find.text(ui('确定')).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: _windows);

  for (final size in [const Size(320, 640), const Size(507, 320)]) {
    testWidgets('small window with 200 percent text stays usable at $size',
        (tester) async {
      final state = await mount(tester, size: size, scale: 2);
      for (final action in ['添加文件夹', '取消', '确定']) {
        expect(find.text(ui(action)).hitTestable(), findsOneWidget);
      }
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.controller!.position.maxScrollExtent, greaterThan(0));
      expect(tester.takeException(), isNull);
      await capture(tester, state.capture,
          'folders-${size.width.toInt()}x${size.height.toInt()}-200pct');
    }, variant: _windows);
  }

  testWidgets('scanning locks actions until the owner restores editing',
      (tester) async {
    await mount(tester, editing: false);
    expect(find.text(ui('正在准备扫描')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
    expect(find.byTooltip(ui('移除文件夹')), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: _windows);

  testWidgets('English narrow folder dialog supports 200 percent text',
      (tester) async {
    uiLanguage.value = UiLanguage.en;
    final state = await mount(tester, size: const Size(480, 640), scale: 2);
    for (final action in ['添加文件夹', '取消', '确定']) {
      expect(ui(action), isNot(action), reason: 'Use translated controls.');
      expect(find.text(ui(action)).hitTestable(), findsOneWidget);
    }
    for (final text in ['管理文件夹', '添加音乐所在的文件夹，确认后刷新曲库。', '移除仅取消收录，不会删除音乐文件。']) {
      expect(ui(text), isNot(text), reason: 'Use translated folder guidance.');
      expect(find.text(ui(text)), findsOneWidget);
    }
    expect(tester.widget<SelectableText>(find.byType(SelectableText)).data,
        _longFolder,
        reason: 'Changing the UI language must not rewrite media paths.');
    expect(tester.takeException(), isNull);
    await capture(tester, state.capture, 'folders-en-480x640-200pct');
  }, variant: _windows);
}
