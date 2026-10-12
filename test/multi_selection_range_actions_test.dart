import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/audio_selection_toolbar.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/uni_detail_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/page/uni_page_components.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

Widget _host(Widget child, {double scale = 1}) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: applyAppControlTheme(ThemeData(
        fontFamily: danEmbeddedFontFamily,
        fontFamilyFallback: danFontFamilyFallback,
        colorSchemeSeed: Colors.teal)),
    builder: (context, child) => UiLanguageScope(
        child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
                disableAnimations: true, textScaler: TextScaler.linear(scale)),
            child: child!)),
    home: Scaffold(body: child));

Future<void> _range(WidgetTester tester, String kind,
    {bool generic = false}) async {
  await tester.tap(
      _key(generic ? 'multi-selection-range-menu' : 'audio-selection-more'));
  await tester.pumpAndSettle();
  final icons = {
    for (final name in ['between', 'above', 'below'])
      (tester
              .widget<MenuItemButton>(_key('multi-selection-range-$name'))
              .leadingIcon as Icon)
          .icon,
  };
  expect(icons.length, 3);
  final item = _key('multi-selection-range-$kind');
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
  await tester.tap(item.hitTestable());
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPlaylistFeatureFonts);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  test(
      'two endpoints expand only after an explicit operation, preserving hidden choices',
      () {
    final controller = MultiSelectController<String>();
    addTearDown(controller.dispose);
    controller.selectAll(['a', 'd', 'hidden']);
    expect(controller.selected, {'a', 'd', 'hidden'});
    expect(
        controller
            .canSelectRange(['a', 'b', 'c', 'd'], MultiSelectRange.between),
        isTrue);
    controller.selectRange(['a', 'b', 'c', 'd'], MultiSelectRange.between);
    expect(controller.selected, {'a', 'b', 'c', 'd', 'hidden'});
  });

  test('one endpoint includes itself above or below the supplied display order',
      () {
    final controller = MultiSelectController<String>();
    addTearDown(controller.dispose);
    controller.selectAll(['c', 'hidden']);
    controller.selectRange(['d', 'c', 'b', 'a'], MultiSelectRange.above);
    expect(controller.selected, {'d', 'c', 'hidden'});
    controller.replaceSelection(['c', 'hidden']);
    controller.selectRange(['d', 'c', 'b', 'a'], MultiSelectRange.below);
    expect(controller.selected, {'c', 'b', 'a', 'hidden'});
  });

  test('invalid, adjacent and already-at-edge selections never create a range',
      () {
    final controller = MultiSelectController<String>();
    addTearDown(controller.dispose);
    for (final selection in [
      <String>[],
      ['a'],
      ['a', 'b'],
      ['a', 'b', 'd']
    ]) {
      controller.replaceSelection(selection);
      controller.selectRange(['a', 'b', 'c', 'd'], MultiSelectRange.between);
      expect(controller.selected, selection.toSet());
    }
    controller.replaceSelection(['a']);
    expect(
        controller.canSelectRange(['a', 'b'], MultiSelectRange.above), isFalse);
    controller.replaceSelection(['b']);
    expect(
        controller.canSelectRange(['a', 'b'], MultiSelectRange.below), isFalse);
    controller.selectRange([], MultiSelectRange.below);
    expect(controller.selected, {'b'});
  });

  test(
      'an old successful action cannot end a newer selection session or notify disposal',
      () {
    final controller = MultiSelectController<String>()
      ..useMultiSelectView(true)
      ..select('a');
    final oldSession = controller.session;
    controller.exitMultiSelect();
    controller.useMultiSelectView(true);
    controller.select('b');
    controller.exitMultiSelect(expectedSession: oldSession);
    expect(controller.enableMultiSelectView, isTrue);
    expect(controller.selected, {'b'});
    controller.dispose();
    controller.exitMultiSelect();
    expect(controller.isSessionCurrent(controller.session), isFalse);
  });

  for (final order in SortOrder.values) {
    testWidgets(
        'detail range follows actual sorted search results order=${order.name}',
        (tester) async {
      final tracks = <Audio>[
        for (final title in ['Keep D', 'Hidden', 'Keep B', 'Keep C', 'Keep A'])
          CategoryTestAudio(title),
      ];
      final selection = MultiSelectController<Audio>()
        ..useMultiSelectView(true)
        ..selectAll([tracks[0], tracks[4], tracks[1]]);
      addTearDown(selection.dispose);
      await tester.pumpWidget(_host(UniDetailPage<String, Audio, String>(
          pref: PagePreference(0, order, ContentView.list),
          primaryContent: 'album',
          primaryPic: Future.value(),
          backgroundPic: Future.value(),
          picShape: PicShape.rrect,
          title: 'Album',
          subtitle: '',
          secondaryContent: tracks,
          secondaryContentBuilder: (_, audio, __, ___, ____) =>
              Text(audio.title),
          tertiaryContentTitle: '',
          tertiaryContent: const [],
          tertiaryContentBuilder: (_, item, __, ___) => Text(item),
          secondaryContentSearchText: (audio) => audio.title,
          enableShufflePlay: false,
          enableSortMethod: true,
          enableSortOrder: true,
          enableSecondaryContentViewSwitch: false,
          sortMethods: [
            SortMethodDesc<Audio>(
                icon: Icons.sort,
                name: 'Title',
                method: (items, order) => items.sort((a, b) =>
                    order == SortOrder.ascending
                        ? a.title.compareTo(b.title)
                        : b.title.compareTo(a.title)))
          ],
          multiSelectController: selection,
          enableMultiSelectAddToPlaylist: true)));
      await tester.pumpAndSettle();
      await tester.enterText(_key('uni-detail-search'), 'Keep');
      await tester.pumpAndSettle();
      await _range(tester, 'between');
      expect(selection.selected.map((audio) => audio.title).toSet(),
          {'Keep A', 'Keep B', 'Keep C', 'Keep D', 'Hidden'});
      final selected = tester
          .widget<AudioSelectionToolbar>(find.byType(AudioSelectionToolbar))
          .selected;
      expect(
          selected.map((audio) => audio.title).toList(),
          order == SortOrder.ascending
              ? ['Keep A', 'Keep B', 'Keep C', 'Keep D']
              : ['Keep D', 'Keep C', 'Keep B', 'Keep A']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('generic UniPage range applies to its sorted artist-like items',
      (tester) async {
    final selection = MultiSelectController<String>()
      ..useMultiSelectView(true)
      ..select('B');
    addTearDown(selection.dispose);
    await tester.pumpWidget(_host(UniPage<String>(
        pref: PagePreference(0, SortOrder.decending, ContentView.list),
        title: 'Artists',
        contentList: List<String>.of(const ['A', 'B', 'C', 'D']),
        contentBuilder: (_, item, __, ___) => Text(item),
        enableShufflePlay: false,
        enableSortMethod: true,
        enableSortOrder: false,
        enableContentViewSwitch: false,
        sortMethods: [
          SortMethodDesc<String>(
              icon: Icons.sort,
              name: 'Name',
              method: (items, _) => items.sort((a, b) => b.compareTo(a)))
        ],
        multiSelectController: selection,
        multiSelectViewActions: [
          MultiSelectExit(multiSelectController: selection)
        ])));
    await tester.pumpAndSettle();
    expect(find.text(ui('范围选择')), findsOneWidget);
    await _range(tester, 'above', generic: true);
    expect(selection.selected, {'D', 'C', 'B'});
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    testWidgets(
        'range menu ${language.name} wide and narrow large text remains fully reachable',
        (tester) async {
      uiLanguage.value = language;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final a = CategoryTestAudio('A'),
          b = CategoryTestAudio('B'),
          c = CategoryTestAudio('C');
      final selection = MultiSelectController<Audio>()
        ..useMultiSelectView(true)
        ..select(b);
      addTearDown(selection.dispose);
      for (final size in [(1100.0, 1.0), (360.0, 2.0)]) {
        final boundary = GlobalKey();
        tester.view.physicalSize = Size(size.$1, 800);
        selection.replaceSelection([b]);
        await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: _host(
                SingleChildScrollView(
                    child: AudioMultiSelectionActions(
                        controller: selection, contentList: [a, b, c])),
                scale: size.$2)));
        await tester.pumpAndSettle();
        await tester.tap(_key('audio-selection-more'));
        await tester.pumpAndSettle();
        final above = _key('multi-selection-range-above');
        await tester.ensureVisible(above);
        await tester.pumpAndSettle();
        final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: above, matching: find.byType(RichText)).last);
        expect(paragraph.didExceedMaxLines, isFalse);
        final text = paragraph.text.toPlainText();
        for (var at = 0; at < text.length; at++) {
          if (text[at].trim().isEmpty) continue;
          final boxes = paragraph.getBoxesForSelection(
              TextSelection(baseOffset: at, extentOffset: at + 1));
          expect(boxes, isNotEmpty, reason: text);
          for (final box in boxes) {
            expect(box.left, greaterThanOrEqualTo(-.5));
            expect(box.right, lessThanOrEqualTo(paragraph.size.width + .5));
            final right = paragraph.localToGlobal(Offset(box.right, 0)).dx;
            expect(right, lessThanOrEqualTo(size.$1 + .5),
                reason: 'every glyph must also fit the actual window');
          }
        }
        await capturePlaylistFeature(tester, boundary,
            'selection-range-${language.name}-${size.$1.toInt()}');
        await tester.tap(above.hitTestable());
        await tester.pumpAndSettle();
        expect(selection.selected, {a, b});
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('all shared selection menu labels fit narrow large-text windows',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final audio = CategoryTestAudio('A');
    final boundary = GlobalKey();
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: _host(AudioSelectionMenu(selected: [audio]), scale: 2)));
      await tester.pumpAndSettle();
      await tester.tap(_key('audio-selection-more'));
      await tester.pumpAndSettle();
      final items = find
          .byType(MenuItemButton)
          .evaluate()
          .map((element) => element.widget.key!)
          .toList();
      for (final key in items) {
        final item = find.byKey(key);
        await tester.ensureVisible(item);
        await tester.pumpAndSettle();
        expect(tester.getRect(item).left, greaterThanOrEqualTo(-.5));
        expect(tester.getRect(item).right, lessThanOrEqualTo(360.5));
        final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: item, matching: find.byType(RichText)).last);
        expect(paragraph.didExceedMaxLines, isFalse);
        final label = paragraph.text.toPlainText();
        for (var at = 0; at < label.length; at++) {
          if (label[at].trim().isEmpty) continue;
          final boxes = paragraph.getBoxesForSelection(
              TextSelection(baseOffset: at, extentOffset: at + 1));
          expect(boxes, isNotEmpty);
          for (final box in boxes) {
            expect(paragraph.localToGlobal(Offset(box.left, 0)).dx,
                greaterThanOrEqualTo(0),
                reason: label);
            expect(paragraph.localToGlobal(Offset(box.right, 0)).dx,
                lessThanOrEqualTo(360.5),
                reason: label);
          }
        }
      }
      await capturePlaylistFeature(
          tester, boundary, 'selection-full-menu-${language.name}-360');
      // The menu was opened by a touch tap with no focused item. Dismiss it
      // through its real outside-tap region rather than assuming key focus.
      await tester.tapAt(const Offset(358, 798));
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'the labelled range entry and enabled choices remain reachable by keyboard',
      (tester) async {
    var above = 0;
    await tester.pumpWidget(_host(Center(
        child:
            SelectionRangeMenuButton(onAbove: () => above++, onBelow: () {}))));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final entryText = tester.element(find.text(ui('范围选择')));
    expect(Focus.of(entryText).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final item = _key('multi-selection-range-above');
    expect(item, findsOneWidget);
    final itemText = tester
        .element(find.descendant(of: item, matching: find.byType(Text)).last);
    expect(Focus.of(itemText).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    final belowText = tester.element(find
        .descendant(
            of: _key('multi-selection-range-below'),
            matching: find.byType(Text))
        .last);
    expect(Focus.of(belowText).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(Focus.of(itemText).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(above, 1);
    expect(find.byType(MenuItemButton), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
