import 'dart:ui' as raster;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/entry.dart';
import 'dart:async';
import 'dart:io';

import 'package:dan_player/component/smart_playlist_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/smart_playlist.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

class _Store extends SmartPlaylistStore {
  _Store([this.items = const []])
      : super(File('unused-smart-playlist-fixture'));
  List<SmartPlaylist> items;
  int loadFailures = 0;
  int saveFailures = 0;
  int saves = 0;
  int removals = 0;
  int removeFailures = 0;
  Future<void>? saveGate;
  @override
  Future<List<SmartPlaylist>> list() async {
    if (loadFailures-- > 0) throw const FileSystemException('fixture read');
    return List.of(items);
  }

  @override
  Future<void> upsert(SmartPlaylist rule) async {
    saves++;
    if (saveFailures-- > 0) throw const FileSystemException('fixture save');
    if (saveGate != null) await saveGate;
    items = [...items.where((item) => item.id != rule.id), rule];
  }

  @override
  Future<void> remove(String id) async {
    removals++;
    if (removeFailures-- > 0) throw const FileSystemException('fixture delete');
    items = items.where((item) => item.id != id).toList();
  }
}

Widget _host(Widget dialog, {double scale = 1}) => MaterialApp(
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale), disableAnimations: true),
        child: UiLanguageScope(child: child!)),
    home: Scaffold(body: dialog));

Future<void> _new(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('smart-new')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('smart-new')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => uiLanguage.value = UiLanguage.zh);

  testWidgets(
      'read error can retry; save failure retains edits until successful retry',
      (tester) async {
    final store = _Store()
      ..loadFailures = 1
      ..saveFailures = 1;
    final changes = ValueNotifier(0);
    addTearDown(changes.dispose);
    await tester.pumpWidget(_host(SmartPlaylistsDialog(
        loadStore: () async => store,
        library: () => [],
        libraryChanges: changes,
        evaluate: (_, __) async => [])));
    await tester.pumpAndSettle();
    expect(find.text('无法读取智能歌单，请检查数据目录后重试。'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    await _new(tester);
    await tester.enterText(find.byKey(const ValueKey('smart-name')), '静谧');
    await tester.enterText(find.byKey(const ValueKey('smart-query')), '卡农');
    await tester.enterText(
        find.byKey(const ValueKey('smart-formats')), 'flac, mp3');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byKey(const ValueKey('smart-save')));
    await tester.pumpAndSettle();
    expect(store.items, isEmpty);
    expect(find.byKey(const ValueKey('smart-storage-error')), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('smart-name')))
            .controller!
            .text,
        '静谧');
    final gate = Completer<void>();
    store.saveGate = gate.future;
    await tester.tap(find.byKey(const ValueKey('smart-save')));
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('smart-save')))
            .onPressed,
        isNull);
    expect(tester.widget<PopScope>(find.byType(PopScope).last).canPop, isFalse);
    expect(store.items, isEmpty);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('smart-name')))
            .enabled,
        isFalse);
    gate.complete();
    await tester.pumpAndSettle();
    expect(store.items.single.name, '静谧');
    expect(store.items.single.query, '卡农');
    expect(store.items.single.formats, 'flac, mp3');
    expect(find.byKey(const ValueKey('smart-save')), findsNothing);
    expect(find.text('静谧'), findsOneWidget);
    expect(store.saves, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'only opened rule evaluates and stale preview cannot overwrite newer library results',
      (tester) async {
    final store = _Store([
      const SmartPlaylist(id: 'a', name: 'First'),
      const SmartPlaylist(id: 'b', name: 'Second')
    ]);
    final calls = <Completer<List<Audio>>>[];
    final changes = ValueNotifier(0);
    addTearDown(changes.dispose);
    List<Audio> library = [CategoryTestAudio('old')];
    List<Audio>? played;
    await tester.pumpWidget(_host(SmartPlaylistsDialog(
        loadStore: () async => store,
        library: () => library,
        libraryChanges: changes,
        evaluate: (_, __) {
          final value = Completer<List<Audio>>();
          calls.add(value);
          return value.future;
        },
        onPlay: (audios) => played = audios)));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.tap(find.byKey(const ValueKey('smart-rule-a')));
    await tester.pump();
    expect(calls.length, 1);
    changes.value++;
    await tester.pump();
    expect(calls.length, 2);
    final current = [
      CategoryTestAudio('Canon'),
      CategoryTestAudio('Good Time')
    ];
    calls[1].complete(current);
    await tester.pumpAndSettle();
    calls[0].complete(library);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('smart-result-count')))
            .data,
        '匹配 2 首本地歌曲');
    await tester.ensureVisible(find.byKey(const ValueKey('smart-select')));
    await tester.tap(find.byKey(const ValueKey('smart-select')));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('audio-selection-play')));
    await tester.tap(find.byKey(const ValueKey('audio-selection-play')));
    await tester.pumpAndSettle();
    expect(played, current);
    expect(identical(played, current), isFalse);
    library = [CategoryTestAudio('new')];
    changes.value++;
    await tester.pump();
    calls[2].complete(library);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('smart-result-count')))
            .data,
        '匹配 1 首本地歌曲');
    expect(played, current,
        reason: 'an already-started queue is a click-time snapshot');
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    changes.value++;
    await tester.pump();
    expect(calls.length, 3, reason: 'manager never evaluates every saved rule');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'invalid numeric duration cannot silently become an unlimited rule',
      (tester) async {
    final store = _Store();
    var evaluated = 0;
    await tester.pumpWidget(_host(SmartPlaylistsDialog(
        loadStore: () async => store,
        library: () => [],
        evaluate: (_, __) async {
          evaluated++;
          return [];
        })));
    await tester.pumpAndSettle();
    await _new(tester);
    await tester.enterText(
        find.byKey(const ValueKey('smart-name')), 'Duration');
    await tester.enterText(find.byKey(const ValueKey('smart-minimum')), '1.5');
    await tester.pump(const Duration(milliseconds: 250));
    expect(evaluated, 1);
    await tester.tap(find.byKey(const ValueKey('smart-save')));
    await tester.pumpAndSettle();
    expect(store.saves, 0);
    expect(find.text('时长须为 0–86400 秒，最短时长不能超过最长时长。'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'selected export and ordinary playlist actions use the visible selected snapshot',
      (tester) async {
    final tracks = [CategoryTestAudio('Canon'), CategoryTestAudio('Good Time')];
    final store = _Store([const SmartPlaylist(id: 'a', name: 'Music')]);
    List<Audio>? exported;
    List<Audio>? saved;
    await tester.pumpWidget(_host(SmartPlaylistsDialog(
        loadStore: () async => store,
        library: () => tracks,
        evaluate: (_, __) async => tracks,
        onExport: (items) => exported = items,
        onAddToPlaylist: (items) => saved = items)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('smart-rule-a')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('smart-select')));
    await tester.tap(find.byKey(const ValueKey('smart-select')));
    await tester.pumpAndSettle();
    final row = find.byKey(ValueKey('smart-result-${tracks.last.path}'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('smart-ordinary')));
    await tester.tap(find.byKey(const ValueKey('smart-ordinary')));
    await tester.pumpAndSettle();
    expect(saved, [tracks.first]);
    await tester
        .ensureVisible(find.byKey(const ValueKey('audio-selection-more')));
    await tester.tap(find.byKey(const ValueKey('audio-selection-more')));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('audio-selection-export')));
    await tester.tap(find.byKey(const ValueKey('audio-selection-export')));
    await tester.pumpAndSettle();
    expect(exported, [tracks.first]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'delete confirmation is single-flight and failed deletion can retry',
      (tester) async {
    final store = _Store([const SmartPlaylist(id: 'a', name: 'Preserved')])
      ..removeFailures = 1;
    await tester.pumpWidget(_host(SmartPlaylistsDialog(
        loadStore: () async => store,
        library: () => [],
        evaluate: (_, __) async => [])));
    await tester.pumpAndSettle();
    final remove = tester
        .widget<IconButton>(find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == '删除智能歌单规则'))
        .onPressed!;
    remove();
    remove(); // Repeated invocation before the first confirmation is dismissed.
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(store.removals, 0);
    await tester.tap(find.byTooltip('删除智能歌单规则'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除规则失败，请重试。'), findsOneWidget);
    expect(store.items.single.id, 'a');
    await tester.tap(find.byTooltip('删除智能歌单规则'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(store.items, isEmpty);
    expect(store.removals, 2);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('narrow large-text editor stays scrollable at scale $scale',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      uiLanguage.value = UiLanguage.en;
      await tester.pumpWidget(_host(
          SmartPlaylistsDialog(
              loadStore: () async => _Store(),
              library: () => [],
              evaluate: (_, __) async => []),
          scale: scale));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('smart-new')));
      await _new(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('smart-maximum')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('smart-ordinary')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('smart-save')), findsOneWidget);
    });
  }
  testWidgets(
      'production editor keeps floating labels clear and toolbar heights aligned',
      (tester) async {
    tester.view.physicalSize = const Size(1146, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final font in [
      (danEmbeddedFontFamily, 'assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      ),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    final boundary = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: Entry(welcome: false).fromSchemeAndFontFamily(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
              fontFamily: danEmbeddedFontFamily),
          home: Scaffold(
              body: SmartPlaylistsDialog(
                  loadStore: () async => _Store(),
                  library: () => [],
                  evaluate: (_, __) async => [])),
        )));
    await tester.pumpAndSettle();
    await _new(tester);
    await tester.enterText(find.byKey(const ValueKey('smart-name')), '近期收藏');
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('smart-name'));
    final title = find.text(ui('筛选规则'));
    final label = find.text(ui('智能歌单名称'));
    expect(
        tester.getRect(label).top, greaterThan(tester.getRect(title).bottom));
    expect(tester.getRect(field).top - tester.getRect(title).bottom,
        greaterThan(12));
    const export = String.fromEnvironment('SMART_EDITOR_RENDER_DIR');
    Future<void> render(String name) async {
      if (export.isEmpty) return;
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final bytes =
            await image.toByteData(format: raster.ImageByteFormat.png);
        final file = File('$export/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await render('smart-fields');
    await tester.ensureVisible(find.byKey(const ValueKey('smart-ordinary')));
    await tester.pumpAndSettle();
    final refresh =
        tester.getSize(find.byKey(const ValueKey('smart-refresh'))).height;
    for (final key in ['smart-select', 'smart-ordinary']) {
      expect(tester.getSize(find.byKey(ValueKey(key))).height, refresh);
    }
    expect(tester.takeException(), isNull);
    await render('smart-actions');
    await tester.pumpWidget(const SizedBox());
  });
}
