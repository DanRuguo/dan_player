import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/smart_condition_editor.dart';
import 'package:dan_player/component/smart_playlist_dialog.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/smart_condition.dart';
import 'package:dan_player/library/smart_playlist.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryRules extends SmartPlaylistStore {
  MemoryRules(this.items) : super(File('unused-smart-workflow-fixture'));
  List<SmartPlaylist> items;
  @override
  Future<List<SmartPlaylist>> list() async => List.of(items);
  @override
  Future<void> upsert(SmartPlaylist rule) async =>
      items = [...items.where((item) => item.id != rule.id), rule];
}

Widget host(Widget child, {bool dark = false, double scale = 1}) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: Entry(welcome: false).fromSchemeAndFontFamily(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: dark ? Brightness.dark : Brightness.light),
        fontFamily: danEmbeddedFontFamily),
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale), disableAnimations: true),
        child: UiLanguageScope(child: child!)),
    home: Scaffold(body: child));

const original = SmartPlaylist(
    id: 'original',
    name: 'Classical',
    sort: SmartPlaylistSort.albumTrack,
    history: SmartPlaylistHistory.played,
    condition: SmartCondition.group([
      SmartCondition.term(SmartField.composerContains, 'Mozart'),
    ]));

void main() {
  setUpAll(() async {
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
    final korean = File('C:/Windows/Fonts/malgun.ttf');
    if (await korean.exists()) {
      await (FontLoader('Malgun Gothic')
            ..addFont(
                Future.value(ByteData.sublistView(await korean.readAsBytes()))))
          .load();
    }
  });
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  testWidgets(
      'duplicate is a separate unsaved rule and Save preserves the original',
      (tester) async {
    final store = MemoryRules([original]);
    final stats = PlaybackStatistics.inMemory();
    addTearDown(stats.dispose);
    final drafts = <SmartPlaylist>[];
    await tester.pumpWidget(host(SmartPlaylistsDialog(
        loadStore: () async => store,
        library: () => <Audio>[],
        statistics: stats,
        evaluate: (draft, _) async {
          drafts.add(draft);
          return [];
        })));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('smart-copy-original')));
    await tester.pumpAndSettle();
    expect(store.items, [original]);
    final copy = drafts.last;
    expect(copy.id, isNot(original.id));
    expect(copy.condition!.toJson(), original.condition!.toJson());
    expect(copy.sort, original.sort);
    expect(copy.history, original.history);
    expect(find.byKey(const ValueKey('smart-restore-saved')), findsNothing);
    await tester.enterText(
        find.byKey(const ValueKey('smart-name')), 'For study');
    await tester.tap(find.byKey(const ValueKey('smart-save')));
    await tester.pumpAndSettle();
    expect(store.items.length, 2);
    expect(store.items.first.toJson(), original.toJson());
    expect(store.items.last.id, copy.id);
    expect(store.items.last.name, 'For study');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'restore confirms, cancels safely, then resets text and dropdown state together',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryRules([original]);
    final stats = PlaybackStatistics.inMemory();
    addTearDown(stats.dispose);
    final drafts = <SmartPlaylist>[];
    await tester.pumpWidget(host(SmartPlaylistsDialog(
        loadStore: () async => store,
        library: () => <Audio>[],
        statistics: stats,
        evaluate: (draft, _) async {
          drafts.add(draft);
          return [];
        })));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('smart-rule-original')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('筛选规则'));
    await tester.pumpAndSettle();
    final field = find.byType(TextFormField);
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Haydn');
    await tester.enterText(find.byKey(const ValueKey('smart-name')), 'Draft');
    final sortFinder = find.byType(DropdownButtonFormField<SmartPlaylistSort>);
    await tester.ensureVisible(sortFinder);
    await tester.tap(sortFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.text('歌曲名称').last);
    await tester.pumpAndSettle();
    final historyFinder =
        find.byType(DropdownButtonFormField<SmartPlaylistHistory>);
    await tester.ensureVisible(historyFinder);
    await tester.tap(historyFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.text('从未播放').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('smart-restore-saved')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '取消').last);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<EditableText>(
                find.descendant(of: field, matching: find.byType(EditableText)))
            .controller
            .text,
        'Haydn');
    await tester.tap(find.byKey(const ValueKey('smart-restore-saved')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '恢复'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<EditableText>(
                find.descendant(of: field, matching: find.byType(EditableText)))
            .controller
            .text,
        'Mozart');
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('smart-name')))
            .controller!
            .text,
        'Classical');
    final sort = tester.state<FormFieldState<SmartPlaylistSort>>(
        find.byType(DropdownButtonFormField<SmartPlaylistSort>));
    final history = tester.state<FormFieldState<SmartPlaylistHistory>>(
        find.byType(DropdownButtonFormField<SmartPlaylistHistory>));
    expect(sort.value, SmartPlaylistSort.albumTrack);
    expect(history.value, SmartPlaylistHistory.played);
    expect(drafts.last.toJson(), original.toJson());
    expect(store.items.single.toJson(), original.toJson());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'rule capacity disables duplication without changing original data',
      (tester) async {
    final store = MemoryRules(List.generate(SmartPlaylistStore.maxPlaylists,
        (index) => SmartPlaylist(id: '$index', name: 'Rule $index')));
    final stats = PlaybackStatistics.inMemory();
    addTearDown(stats.dispose);
    await tester.pumpWidget(host(SmartPlaylistsDialog(
        loadStore: () async => store,
        library: () => [],
        statistics: stats,
        evaluate: (_, __) async => [])));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('smart-copy-0')))
            .onPressed,
        isNull);
    expect(store.items.length, 100);
    expect(tester.takeException(), isNull);
  });

  testWidgets('boolean rules keep one label and preserve exclusion values',
      (tester) async {
    var condition = const SmartCondition.group([
      SmartCondition.term(SmartField.missingComposer, 'true'),
      SmartCondition.term(SmartField.cueTrack, 'true'),
    ]);
    await tester.pumpWidget(host(SingleChildScrollView(
        child: StatefulBuilder(
            builder: (context, update) => SmartConditionEditor(
                value: condition,
                onChanged: (next) => update(() => condition = next))))));
    await tester.pumpAndSettle();
    expect(find.text(ui('缺少作曲家标签')), findsOneWidget);
    expect(find.text(ui('是 CUE 分轨')), findsOneWidget);
    final checkbox = find.byType(Checkbox).first;
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(condition.children.first.field, SmartField.missingComposer);
    expect(condition.children.first.value, 'true');
    expect(condition.children.first.exclude, isTrue);
    expect(condition.children.last.field, SmartField.cueTrack);
    expect(condition.children.last.value, 'true');
    expect(condition.children.last.exclude, isFalse);
    expect(find.byType(TextFormField), findsNothing,
        reason: 'boolean rules require no duplicate value input');
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets(
          'expanded fields and workflow ${language.name} ${narrow ? 'narrow' : 'wide'}',
          (tester) async {
        uiLanguage.value = language;
        tester.view.physicalSize =
            narrow ? const Size(380, 780) : const Size(900, 980);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final capture = GlobalKey();
        const renderRoot = String.fromEnvironment('DAN_SMART_EXPANSION_RENDER');
        Future<void> render(String stage) async {
          if (renderRoot.isEmpty) return;
          await tester.runAsync(() async {
            final image = await (capture.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: raster.ImageByteFormat.png);
            final file = File(
                '$renderRoot/smart-${language.name}-${narrow ? 'narrow' : 'wide'}-$stage.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await tester.pumpWidget(RepaintBoundary(
            key: capture,
            child: host(
                AlertDialog(
                    title: AppDialogTitle(ui('筛选规则')),
                    content: SizedBox(
                        width: 720,
                        child: SingleChildScrollView(
                            child: SmartConditionEditor(
                                value: const SmartCondition.group([
                                  SmartCondition.term(
                                      SmartField.albumArtistContains,
                                      'Orchestra'),
                                  SmartCondition.term(
                                      SmartField.fileSizeAtMost, '104857600'),
                                  SmartCondition.term(
                                      SmartField.missingComposer, 'true'),
                                  SmartCondition.term(
                                      SmartField.cueTrack, 'true'),
                                ]),
                                onChanged: (_) {}))),
                    actions: [
                      FilledButton(onPressed: () {}, child: Text(ui('保存规则')))
                    ]),
                dark: narrow,
                scale: narrow ? 1.6 : 1)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await render('fields');
        await tester.drag(
            find.byType(SingleChildScrollView).first, const Offset(0, -420));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await render('flags');
        final stats = PlaybackStatistics.inMemory();
        addTearDown(stats.dispose);
        final store = MemoryRules([original]);
        await tester.pumpWidget(RepaintBoundary(
            key: capture,
            child: host(
                SmartPlaylistsDialog(
                    loadStore: () async => store,
                    library: () => [],
                    statistics: stats,
                    evaluate: (_, __) async => []),
                dark: narrow,
                scale: narrow ? 1.6 : 1)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await render('copy');
        await tester.tap(find.byKey(const ValueKey('smart-rule-original')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('smart-restore-saved')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await render('restore');
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
