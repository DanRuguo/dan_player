import 'dart:async';
import 'dart:io';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/audio_selection_toolbar.dart';
import 'package:dan_player/component/multi_selection_lifecycle.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/folders_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/page/uni_page_components.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

/// The real FoldersPage, real song/context menus and native delayed menu
/// dispatch are mounted together. Only artwork, clipboard and OS paths are
/// injected; no music file, native player, network or user profile is opened.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final qa = Directory(path.join(Directory.current.parent.path, 'tool',
      'qa-local', 'selection-folders-oct11', 'interaction', 'linkage'));
  final data = Directory(path.join(qa.path, 'data'));
  final music = path.join(qa.path, 'Music');
  final alpha = path.join(music, 'Alpha');
  final beta = path.join(music, 'Beta');
  final roots = [
    for (final title in ['D', 'E', 'F'])
      CategoryTestAudio(title, path: path.join(music, '$title.mp3')),
  ];
  final alphas = [
    for (final title in ['A', 'B', 'C'])
      CategoryTestAudio(title, path: path.join(alpha, '$title.mp3')),
  ];
  final betas = [
    for (final title in ['G', 'H'])
      CategoryTestAudio(title, path: path.join(beta, '$title.mp3')),
  ];
  const provider = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final copied = <String>[];
  Future<void> Function(String)? clipboardWrite;
  late List<AudioFolder> previousFolders;
  late PagePreference previousFolderPreference, previousSongPreference;
  late int previousRevision, previousNotification;
  late PlaylistFeaturePlayback playback;
  late GlobalKey<NavigatorState> navigator;

  setUpAll(() async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR'], isNull,
        reason: 'The path_provider fixture must own application data.');
    expect(Directory.systemTemp.absolute.path.replaceAll('\\', '/'),
        contains('/tool/qa-local/'));
    await data.create(recursive: true);
    messenger.setMockMethodCallHandler(provider, (_) async => data.path);
    expect(path.isWithin(data.path, (await getAppDataDir()).path), isTrue);
    await loadPlaylistFeatureFonts();
  });
  tearDownAll(() {
    messenger.setMockMethodCallHandler(provider, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });
  setUp(() {
    uiLanguage.value = UiLanguage.zh;
    previousFolders = AudioLibrary.instance.folders;
    previousRevision = AudioLibrary.revision;
    previousNotification = AudioLibrary.changes.value;
    previousFolderPreference = AppPreference.instance.foldersPagePref;
    previousSongPreference = AppPreference.instance.folderDetailPagePref;
    AppPreference.instance.foldersPagePref =
        PagePreference(0, SortOrder.ascending, ContentView.table);
    AppPreference.instance.folderDetailPagePref =
        PagePreference(0, SortOrder.ascending, ContentView.table);
    AudioLibrary.instance.folders = [
      AudioFolder([roots[1], roots[0], roots[2]], music, 1, 1),
      AudioFolder([alphas[1], alphas[2], alphas[0]], alpha, 2, 2),
      AudioFolder(betas.reversed.toList(), beta, 3, 3),
    ];
    playback = PlaylistFeaturePlayback([]);
    navigator = GlobalKey<NavigatorState>();
    copied.clear();
    clipboardWrite = null;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final text = (call.arguments as Map)['text'] as String;
        copied.add(text);
        await clipboardWrite?.call(text);
      }
      return null;
    });
  });
  tearDown(() {
    playback.dispose();
    AudioLibrary.instance.folders = previousFolders;
    AudioLibrary.revision = previousRevision;
    AudioLibrary.changes.value = previousNotification;
    AppPreference.instance.foldersPagePref = previousFolderPreference;
    AppPreference.instance.folderDetailPagePref = previousSongPreference;
    uiLanguage.value = UiLanguage.zh;
  });

  Future<void> mount(WidgetTester tester,
      {double width = 1000, double scale = 1, GlobalKey? boundary}) async {
    sizePlaylistFeature(tester, width: width, height: 1100);
    final host = playlistFeatureHost(
        AppEntranceScope(
            child: FoldersPage(
                dataDirectory: data,
                initialFolderPath: music,
                playbackService: playback,
                loadArtwork: (_, __) async => null)),
        textScale: scale,
        boundary: boundary) as MaterialApp;
    await tester.pumpWidget(UiLanguageScope(
        child: MaterialApp(
      navigatorKey: navigator,
      navigatorObservers: [MultiSelectionRouteObserver()],
      theme: host.theme,
      builder: host.builder,
      home: host.home,
    )));
    await tester.pumpAndSettle();
  }

  Finder cover(Audio audio) => _key('folder-tree-cover-${audio.path}');
  MultiSelectController<Audio> selection(WidgetTester tester) => tester
      .widget<AudioMultiSelectionActions>(
          find.byType(AudioMultiSelectionActions))
      .controller;
  List<Audio> visible(WidgetTester tester) => tester
      .widget<AudioMultiSelectionActions>(
          find.byType(AudioMultiSelectionActions))
      .contentList;

  Future<void> toggleFolder(WidgetTester tester, String folder) async {
    final row = _key('folder-open-$folder');
    await tester.ensureVisible(row);
    await tester.tapAt(tester.getTopLeft(row) + const Offset(70, 35));
    await tester.pumpAndSettle();
  }

  Future<void> descendSort<T>(WidgetTester tester) async {
    final button = find.descendant(
        of: find.byType(SortMethodComboBox<T>),
        matching: find.byType(OutlinedButton));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(_key('app-sort-direction-descending'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape,
        physicalKey: PhysicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  Future<void> startSelection(WidgetTester tester, Audio audio) async {
    await tester.ensureVisible(cover(audio));
    await tester.longPress(cover(audio));
    await tester.pumpAndSettle();
    final action = find.widgetWithText(MenuItemButton, ui('多选'));
    await tester.ensureVisible(action);
    await tester.tap(action.hitTestable());
    await tester.pumpAndSettle();
    expect(selection(tester).selected, {audio});
  }

  Future<void> select(WidgetTester tester, Audio audio) async {
    await tester.ensureVisible(cover(audio));
    await tester.tap(cover(audio));
    await tester.pumpAndSettle();
  }

  Future<void> openMore(WidgetTester tester) async {
    await tester.ensureVisible(_key('audio-selection-more'));
    await tester.tap(_key('audio-selection-more'));
    await tester.pumpAndSettle();
  }

  Future<void> menu(WidgetTester tester, String id) async {
    await openMore(tester);
    final action = _key(id);
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    await tester.tap(action.hitTestable());
    await tester.pumpAndSettle();
  }

  testWidgets(
      'folder sort range collapse and clipboard commit share one session',
      (tester) async {
    final boundary = GlobalKey();
    await mount(tester, boundary: boundary);
    await descendSort<AudioFolder>(tester);
    await descendSort<Audio>(tester);
    await toggleFolder(tester, alpha);
    await toggleFolder(tester, beta);
    expect(tester.getTopLeft(_key('folder-open-$beta')).dy,
        lessThan(tester.getTopLeft(_key('folder-open-$alpha')).dy));
    await startSelection(tester, roots.first);
    await select(tester, alphas.first);
    final controller = selection(tester);
    final session = controller.session;
    expect(visible(tester), [
      ...roots.reversed,
      ...betas.reversed,
      ...alphas.reversed,
    ]);
    await menu(tester, 'multi-selection-range-between');
    expect(controller.selectedInOrder(visible(tester)), [
      roots.first,
      ...betas.reversed,
      ...alphas.reversed,
    ]);
    await capturePlaylistFeature(tester, boundary, 'folder-linkage-wide-range');
    await toggleFolder(tester, alpha);
    expect(controller.session, session);
    expect(controller.selected, hasLength(6));
    final toolbar = tester
        .widget<AudioSelectionToolbar>(find.byType(AudioSelectionToolbar));
    expect(toolbar.hiddenSelectionCount, 3);
    expect(toolbar.selected, [roots.first, ...betas.reversed]);
    await menu(tester, 'audio-selection-copy-paths');
    expect(copied, [
      [roots.first.path, ...betas.reversed.map((audio) => audio.path)]
          .join('\r\n')
    ]);
    expect(controller.enableMultiSelectView, isFalse);
    expect(controller.selected, isEmpty);
    expect(_key('folder-tree-song-${alphas.first.path}'), findsNothing);
    expect(
        AppPreference.instance.foldersPagePref.sortOrder, SortOrder.decending);
    expect(AppPreference.instance.folderDetailPagePref.sortOrder,
        SortOrder.decending);
    expect(AudioLibrary.instance.folders.first.audios,
        [roots[1], roots[0], roots[2]]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'narrow folder menu retries clipboard with full labels and keyboard',
      (tester) async {
    uiLanguage.value = UiLanguage.en;
    final boundary = GlobalKey();
    await mount(tester, width: 360, scale: 2, boundary: boundary);
    await startSelection(tester, roots.first);
    await select(tester, roots.last);
    final controller = selection(tester);
    clipboardWrite = (_) async => throw StateError('fixture clipboard failure');
    await openMore(tester);
    final rangeItems = [
      for (final kind in ['between', 'above', 'below'])
        tester.widget<MenuItemButton>(_key('multi-selection-range-$kind'))
    ];
    expect(rangeItems.map((item) => (item.leadingIcon! as Icon).icon).toSet(),
        hasLength(3));
    final keys = find
        .byType(MenuItemButton)
        .evaluate()
        .map((element) => element.widget.key!)
        .toList();
    for (final key in keys) {
      final item = find.byKey(key);
      await tester.ensureVisible(item);
      await tester.pumpAndSettle();
      _expectGlyphsInItem(tester, item, 360);
    }
    final copy = _key('audio-selection-copy-info');
    await tester.ensureVisible(copy);
    await tester.pumpAndSettle();
    await capturePlaylistFeature(
        tester, boundary, 'folder-linkage-en-360-2-menu');
    await tester.tap(copy.hitTestable());
    await tester.pumpAndSettle();
    expect(controller.enableMultiSelectView, isTrue);
    expect(controller.selected, {roots.first, roots.last});
    expect(copied, ['D — Artist\r\nF — Artist']);
    clipboardWrite = null;
    await openMore(tester);
    await tester.ensureVisible(copy);
    await tester.pumpAndSettle();
    final text = find.descendant(of: copy, matching: find.byType(Text)).last;
    Focus.of(tester.element(text)).requestFocus();
    await tester.pump();
    expect(Focus.of(tester.element(text)).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter,
        physicalKey: PhysicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(copied, ['D — Artist\r\nF — Artist', 'D — Artist\r\nF — Artist']);
    expect(controller.enableMultiSelectView, isFalse);
    expect(controller.selected, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a library replacement retires a folder menu before delayed range dispatch',
      (tester) async {
    await mount(tester);
    await startSelection(tester, roots.first);
    await select(tester, roots.last);
    final controller = selection(tester);
    await openMore(tester);
    final range = _key('multi-selection-range-between');
    await tester.ensureVisible(range);
    await tester.pumpAndSettle();
    await tester.tap(range.hitTestable());
    expect(controller.selected, {roots.first, roots.last},
        reason: 'The real MenuItem dispatch is pending until the next frame.');
    final current = [
      for (final original in roots.take(2))
        CategoryTestAudio(original.title, path: original.path),
    ];
    AudioLibrary.instance.folders = [
      AudioFolder(current.reversed.toList(), music, 1, 1),
      ...AudioLibrary.instance.folders.skip(1),
    ];
    AudioLibrary.changes.value = ++AudioLibrary.revision;
    await tester.pumpAndSettle();
    expect(controller.enableMultiSelectView, isTrue);
    expect(controller.selected.single, same(current.first));
    expect(visible(tester), current);
    expect(controller.selected.contains(current.last), isFalse,
        reason: 'The stale interval must not select a surviving middle row.');
    await menu(tester, 'multi-selection-range-below');
    expect(controller.selected, current.toSet());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'folder route return and popup do not revive a pending old commit',
      (tester) async {
    await mount(tester);
    await startSelection(tester, roots[1]);
    final controller = selection(tester);
    final pageState = tester.state(find.byType(FoldersPage));
    final oldSession = controller.session;
    final pending = Completer<void>();
    clipboardWrite = (_) => pending.future;
    await menu(tester, 'audio-selection-copy-paths');
    expect(copied, [roots[1].path]);
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other page')))));
    await tester.pumpAndSettle();
    expect(controller.enableMultiSelectView, isFalse);
    expect(controller.selected, isEmpty);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(FoldersPage)), same(pageState));
    await startSelection(tester, roots.last);
    expect(controller.session, greaterThan(oldSession));
    final newSession = controller.session;
    unawaited(showDialog<void>(
        context: tester.element(find.byType(FoldersPage)),
        builder: (context) => AlertDialog(
              content: const Text('Temporary popup'),
              actions: [
                TextButton(
                    key: const ValueKey('linkage-dismiss-popup'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'))
              ],
            )));
    await tester.pumpAndSettle();
    expect(controller.selected, {roots.last});
    pending.complete();
    await tester.pumpAndSettle();
    expect(controller.session, newSession);
    expect(controller.enableMultiSelectView, isTrue);
    expect(controller.selected, {roots.last});
    await tester.tap(_key('linkage-dismiss-popup'));
    await tester.pumpAndSettle();
    expect(controller.selected, {roots.last});
    expect(tester.takeException(), isNull);
  });
}

void _expectGlyphsInItem(WidgetTester tester, Finder item, double width) {
  final bounds = tester.getRect(item);
  expect(bounds.left, greaterThanOrEqualTo(-.5));
  expect(bounds.right, lessThanOrEqualTo(width + .5));
  final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: item, matching: find.byType(RichText)).last);
  expect(paragraph.didExceedMaxLines, isFalse);
  final label = paragraph.text.toPlainText();
  for (var index = 0; index < label.length; index++) {
    if (label[index].trim().isEmpty) continue;
    final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: index, extentOffset: index + 1));
    expect(boxes, isNotEmpty, reason: label);
    for (final box in boxes) {
      final topLeft = paragraph.localToGlobal(Offset(box.left, box.top));
      final bottomRight =
          paragraph.localToGlobal(Offset(box.right, box.bottom));
      expect(topLeft.dx, greaterThanOrEqualTo(bounds.left - .5), reason: label);
      expect(bottomRight.dx, lessThanOrEqualTo(bounds.right + .5),
          reason: label);
      expect(topLeft.dy, greaterThanOrEqualTo(bounds.top - .5), reason: label);
      expect(bottomRight.dy, lessThanOrEqualTo(bounds.bottom + .5),
          reason: label);
    }
  }
}
