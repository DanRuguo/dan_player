import 'dart:io';
import 'dart:ui' as raster;
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_text_search.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_find_dialog.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_reading_result_list.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_segment_practice_dialog.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as path;
import 'support/listening_status_fixture.dart';
import 'support/lyric_share_fixture.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

class _Playback extends PlaylistFeaturePlayback {
  _Playback() : super([]);
  @override
  bool get canUseSegmentLoop => true;
  @override
  double get length => 2000000;
  @override
  int get playbackSessionToken => 7;
}

Lrc _sample([int count = 40]) => Lrc([
      for (var i = 0; i < count; i++)
        LrcLine(
            Duration(seconds: i * 4),
            i == 0
                ? 'Short'
                : i == 2
                    ? '${'Long verse 雨が降る 번역 ' * 28}最後の文字 끝'
                    : 'Line $i 夜の雨┃第 $i 行译文',
            isBlank: false,
            length: const Duration(seconds: 2))
          ..romanization = i == 0 || i == 2 ? null : 'ame $i ga furu',
    ], LrcSource.local);

class _Pixels {
  _Pixels(this.width, this.height, this.bytes);
  final int width, height;
  final Uint8List bytes;
  int changedIn(_Pixels other, Rect area) {
    var changed = 0;
    for (var y = area.top.ceil().clamp(0, height);
        y < area.bottom.floor().clamp(0, height);
        y++) {
      for (var x = area.left.ceil().clamp(0, width);
          x < area.right.floor().clamp(0, width);
          x++) {
        final p = (y * width + x) * 4;
        if (bytes[p] != other.bytes[p] ||
            bytes[p + 1] != other.bytes[p + 1] ||
            bytes[p + 2] != other.bytes[p + 2]) {
          changed++;
        }
      }
    }
    return changed;
  }
}

void main({String? onlyCase, bool nativeWheelOnly = false}) {
  void register(String name, WidgetTesterCallback callback) {
    if (nativeWheelOnly &&
        name != 'wheel clips selected and hover ink to find result viewport' &&
        name !=
            'wheel clips selected and hover ink to practice result viewport') {
      return;
    }
    if (onlyCase == null || name == onlyCase) testWidgets(name, callback);
  }

  TestWidgetsFlutterBinding.ensureInitialized();
  final output = Platform.environment['DAN_LYRIC_RESULT_RENDER_DIR'];
  setUpAll(() async {
    if (output != null &&
        !path.isWithin(
            path.join(Directory.current.parent.path, 'tool', 'qa-local'),
            output)) {
      throw StateError('Render output must stay in workspace QA');
    }
    await loadLyricShareFonts();
  });
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);
  LyricReadingTarget? result;
  Future<GlobalKey> mount(WidgetTester tester,
      {bool practice = false,
      Lyric? lyric,
      double width = 900,
      double scale = 1}) async {
    sizePlaylistFeature(tester, width: width, height: 1000);
    final boundary = GlobalKey(), playback = _Playback();
    addTearDown(playback.dispose);
    result = null;
    final document = lyric ?? _sample();
    await tester.pumpWidget(listeningStatusHost(
        Builder(
            builder: (context) => Center(
                child: FilledButton(
                    child: const Text('Open'),
                    onPressed: () async {
                      if (practice) {
                        await showLyricSegmentPracticeDialog(context,
                            playback: playback,
                            lyric: document,
                            playbackSession: 7,
                            isCurrentLyric: () => true,
                            songTitle: 'Night 夜の雨 밤의 비');
                      } else {
                        result = await showLyricFindDialog(context,
                            lyric: document,
                            isCurrentLyric: () => true,
                            songTitle: 'Night 夜の雨 밤의 비');
                      }
                    }))),
        boundary: boundary,
        scale: scale,
        brightness: width < 500 ? Brightness.dark : Brightness.light));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return boundary;
  }

  Finder row(int i, {bool practice = false}) =>
      _key(practice ? 'lyric-segment-line-$i' : 'lyric-find-result-$i--1');
  Finder timestamp(int i, {bool practice = false}) => find.descendant(
      of: row(i, practice: practice),
      matching: find.byWidgetPredicate((w) =>
          w is Text &&
          RegExp(r'^\d+:\d\d(?::\d\d|\.\d\d\d)$').hasMatch(w.data ?? '')));
  Rect timestampGlyphs(WidgetTester tester, Finder finder) {
    final paragraph = tester.renderObject<RenderParagraph>(finder);
    final text = tester.widget<Text>(finder).data!;
    final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: text.length));
    final bounds =
        boxes.map((box) => box.toRect()).reduce((a, b) => a.expandToInclude(b));
    return paragraph.localToGlobal(bounds.topLeft) & bounds.size;
  }

  Future<_Pixels> pixels(WidgetTester tester, GlobalKey boundary) async {
    final box =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    return (await tester.runAsync(() async {
      final image = await box.toImage();
      try {
        final bytes =
            await image.toByteData(format: raster.ImageByteFormat.rawRgba);
        return _Pixels(image.width, image.height, bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    }))!;
  }

  Future<void> capture(
      WidgetTester tester, GlobalKey boundary, String name) async {
    if (output == null) return;
    final bytes = await captureLyricShare(tester, boundary);
    await tester.runAsync(() async {
      await Directory(output).create(recursive: true);
      await File(path.join(output, '$name.png')).writeAsBytes(bytes);
    });
  }

  register('compact find rows use content height and keep complete long lyrics',
      (tester) async {
    await mount(tester);
    expect(tester.getSize(row(0)).height, lessThan(75));
    expect(tester.getSize(row(0)).height, greaterThanOrEqualTo(48));
    final text = tester.widget<Text>(find.descendant(
        of: row(2),
        matching: find.byWidgetPredicate(
            (w) => w is Text && (w.data?.contains('最後の文字') ?? false))));
    expect(text.maxLines, isNull);
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    expect(tester.getSize(row(2)).height,
        greaterThan(tester.getSize(row(0)).height * 2));
  });
  register(
      'time sits on the right and narrow large rows preserve it without squeezing lyrics',
      (tester) async {
    await mount(tester);
    final tile = tester.getRect(row(0)),
        time = timestampGlyphs(tester, timestamp(0));
    expect(time.right, closeTo(tile.right - 12, .5));
    expect(time.center.dy, closeTo(tile.center.dy, 2));
    await tester.tap(find.text(ui('取消')));
    await tester.pumpAndSettle();
    await mount(tester, width: 360, scale: 3);
    await tester.ensureVisible(row(0));
    await tester.pumpAndSettle();
    final narrow = tester.getRect(row(0)),
        narrowTime = timestampGlyphs(tester, timestamp(0));
    expect(narrowTime.right, closeTo(narrow.right - 12, .5));
    expect(narrowTime.bottom, lessThanOrEqualTo(narrow.bottom));
    expect(tester.takeException(), isNull);
  });
  for (final practice in [false, true]) {
    register(
        'wheel clips selected and hover ink to ${practice ? 'practice' : 'find'} result viewport',
        (tester) async {
      final boundary = await mount(tester, practice: practice);
      final list =
          _key(practice ? 'lyric-segment-lines' : 'lyric-find-results');
      final search =
          _key(practice ? 'lyric-segment-search' : 'lyric-find-search');
      final listRect = tester.getRect(list),
          searchRect = tester.getRect(search);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: listRect.center);
      await tester.pumpAndSettle();
      final scroll = tester.widget<CustomScrollView>(list).controller!;
      final offsetBefore = scroll.offset;
      final firstTopBefore = tester.getRect(row(0, practice: practice)).top;
      final before = await pixels(tester, boundary);
      await tester.sendEventToBinding(PointerScrollEvent(
          position: listRect.center,
          scrollDelta: Offset(0, listRect.top - searchRect.center.dy)));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(offsetBefore),
          reason: 'The actual result viewport must receive the wheel event');
      if (row(0, practice: practice).evaluate().isNotEmpty) {
        expect(tester.getRect(row(0, practice: practice)).top,
            lessThan(firstTopBefore),
            reason: 'The selected row must move upward when the list scrolls');
      }
      final after = await pixels(tester, boundary);
      final header = Rect.fromLTRB(listRect.left + 4, searchRect.top,
          listRect.right - 8, listRect.top - 4);
      expect(after.changedIn(before, header), 0,
          reason:
              'A scroll must not paint row selection/hover into header controls');
      await capture(
          tester, boundary, '${practice ? 'practice' : 'find'}-wheel');
      await mouse.removePointer();
    });
  }
  Future<(GlobalKey<LyricReadingResultListState>, ScrollController)> mountList(
      WidgetTester tester) async {
    sizePlaylistFeature(tester, width: 600, height: 700);
    final state = GlobalKey<LyricReadingResultListState>(),
        scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(listeningStatusHost(Center(
        child: SizedBox(
            width: 520,
            height: 260,
            child: LyricReadingResultList(
                key: state,
                controller: scroll,
                scrollViewKey: const ValueKey('probe-results'),
                itemCount: 2000,
                resetToken: 'all',
                itemBuilder: (context, i) => LyricReadingResultRow(
                    tileKey: ValueKey('probe-row-$i'),
                    text: i.isEven ? 'Row $i' : 'Row $i\n訳文\n번역',
                    selected: i == 1500,
                    icon: Symbols.radio_button_unchecked,
                    timestamp: '00:04.000',
                    onTap: () {}))))));
    await tester.pumpAndSettle();
    return (state, scroll);
  }

  register(
      'variable height index reveal stays lazy and preserves global semantic indices',
      (tester) async {
    final (state, _) = await mountList(tester);
    state.currentState!.revealIndex(1500);
    await tester.pumpAndSettle();
    expect(_key('probe-row-1500'), findsOneWidget);
    final list = tester.getRect(_key('probe-results')),
        target = tester.getRect(_key('probe-row-1500'));
    expect(target.top, greaterThanOrEqualTo(list.top - .5));
    expect(target.bottom, lessThanOrEqualTo(list.bottom + .5));
    expect(find.byType(LyricReadingResultRow).evaluate().length, lessThan(40));
    expect(
        find.ancestor(
            of: _key('probe-row-1500'),
            matching: find.byWidgetPredicate(
                (w) => w is IndexedSemantics && w.index == 1500)),
        findsOneWidget);
  });
  register('rapid requests retain the last index and visible rows never jump',
      (tester) async {
    final (state, scroll) = await mountList(tester);
    state.currentState!.revealIndex(1999);
    state.currentState!.revealIndex(0);
    state.currentState!.revealIndex(1500);
    await tester.pumpAndSettle();
    expect(_key('probe-row-1500'), findsOneWidget);
    final before = scroll.offset;
    state.currentState!.revealIndex(1501);
    await tester.pumpAndSettle();
    expect(scroll.offset, before);
    final listRect = tester.getRect(_key('probe-results'));
    tester.binding.handlePointerEvent(PointerScrollEvent(
        position: listRect.center, scrollDelta: const Offset(0, -100)));
    await tester.pumpAndSettle();
    final visible = <(int, double)>[];
    for (var i = 1495; i <= 1505; i++) {
      if (_key('probe-row-$i').evaluate().isNotEmpty) {
        final rect = tester.getRect(_key('probe-row-$i'));
        if (rect.overlaps(listRect)) visible.add((i, rect.top));
      }
    }
    expect(visible.length, greaterThan(2));
    expect(visible.map((r) => r.$2),
        orderedEquals([...visible.map((r) => r.$2)]..sort()));
    expect(tester.takeException(), isNull);
  });
  register(
      'F3 wraps natural rows and filtering resets to the original matching index',
      (tester) async {
    await mount(tester, lyric: _sample(100));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft,
        physicalKey: PhysicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f3,
        physicalKey: PhysicalKeyboardKey.f3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft,
        physicalKey: PhysicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(row(99), findsOneWidget);
    expect(
        tester
            .getRect(row(99))
            .overlaps(tester.getRect(_key('lyric-find-results'))),
        isTrue);
    await tester.ensureVisible(_key('lyric-find-search'));
    await tester.enterText(_key('lyric-find-search'), 'Line 17');
    await tester.pumpAndSettle();
    expect(row(17), findsOneWidget);
    expect(tester.widget<Text>(_key('lyric-find-count')).data, '匹配：1 / 1');
    await tester.ensureVisible(_key('lyric-find-locate'));
    await tester.tap(_key('lyric-find-locate'));
    await tester.pumpAndSettle();
    expect(result?.index, 17);
    expect(tester.takeException(), isNull);
  });
  for (final language in UiLanguage.values) {
    for (final practice in [false, true]) {
      register(
          '${language.name} ${practice ? 'practice' : 'find'} natural rows wide narrow and large',
          (tester) async {
        uiLanguage.value = language;
        for (final frame in [
          ('wide', 900.0, 1.0),
          ('narrow', 420.0, 1.3),
          ('large', 360.0, 3.0)
        ]) {
          final boundary = await mount(tester,
              practice: practice, width: frame.$2, scale: frame.$3);
          await tester.ensureVisible(
              _key(practice ? 'lyric-segment-lines' : 'lyric-find-results'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await capture(tester, boundary,
              '${language.name}-${practice ? 'practice' : 'find'}-${frame.$1}');
          expect(tester.getSize(row(0, practice: practice)).height,
              greaterThanOrEqualTo(48));
          tester
              .state<LyricReadingResultListState>(
                  find.byType(LyricReadingResultList))
              .revealIndex(1);
          await tester.pumpAndSettle();
          final list =
              _key(practice ? 'lyric-segment-lines' : 'lyric-find-results');
          await tester.ensureVisible(list);
          await tester.pumpAndSettle();
          final visibleRow = tester
              .getRect(row(1, practice: practice))
              .intersect(tester.getRect(list));
          expect(visibleRow.width, greaterThan(0));
          expect(visibleRow.height, greaterThan(0));
          expect(tester.widget<ListTile>(row(1, practice: practice)).selected,
              isFalse);
          // Large natural rows can exceed the viewport. Their geometric
          // centers may sit behind dialog actions, so click the actual visible
          // portion and verify the production row receives the pointer.
          await tester.tapAt(visibleRow.center);
          await tester.pumpAndSettle();
          expect(tester.widget<ListTile>(row(1, practice: practice)).selected,
              isTrue);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text(ui('取消')));
          await tester.tap(find.text(ui('取消')));
          await tester.pumpAndSettle();
        }
      });
    }
  }
  register(
      'large narrow navigation stacks full labels and keeps both buttons tappable',
      (tester) async {
    uiLanguage.value = UiLanguage.en;
    final wideBoundary = await mount(tester);
    final widePrevious = tester.getRect(_key('lyric-find-previous'));
    final wideNext = tester.getRect(_key('lyric-find-next'));
    expect(wideNext.top, widePrevious.top);
    expect(wideNext.left, greaterThanOrEqualTo(widePrevious.right + 8));
    expect(wideNext.width, widePrevious.width);
    await capture(tester, wideBoundary, 'en-find-wide');
    await tester.tap(find.text(ui('取消')));
    await tester.pumpAndSettle();
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      final boundary = await mount(tester, width: 360, scale: 3);
      final previous = _key('lyric-find-previous');
      final next = _key('lyric-find-next');
      final previousBounds = tester.getRect(previous);
      final nextBounds = tester.getRect(next);
      expect(nextBounds.top, greaterThanOrEqualTo(previousBounds.bottom + 8));
      expect(nextBounds.left, previousBounds.left);
      expect(nextBounds.width, previousBounds.width);
      for (final name in ['previous', 'next']) {
        final label = _key('lyric-find-$name-label');
        final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: label, matching: find.byType(RichText)));
        final text = tester.widget<Text>(label).data!;
        final first = paragraph.getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 1));
        final last = paragraph.getBoxesForSelection(TextSelection(
            baseOffset: text.length - 1, extentOffset: text.length));
        expect(first, isNotEmpty);
        expect(last, isNotEmpty,
            reason:
                'The full localized label must be painted, without ellipsis');
        expect(last.first.top, first.first.top);
        expect(last.first.bottom, first.first.bottom);
      }
      await tester.ensureVisible(previous);
      await tester.pumpAndSettle();
      await tester.tap(previous);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(_key('lyric-find-count')).data,
          ui('匹配：{0} / {1}', [40, 40]));
      await tester.ensureVisible(next);
      await tester.pumpAndSettle();
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(_key('lyric-find-count')).data,
          ui('匹配：{0} / {1}', [1, 40]));
      await tester.ensureVisible(_key('lyric-find-results'));
      await tester.pumpAndSettle();
      await capture(tester, boundary, '${language.name}-find-large');
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text(ui('取消')));
      await tester.tap(find.text(ui('取消')));
      await tester.pumpAndSettle();
    }
  });
  register('untimed long text preserves every character and omits time',
      (tester) async {
    final plain = PlainLyric('${'無時刻 가사 🌧 ' * 70}END');
    await mount(tester, lyric: plain, width: 360, scale: 3);
    await tester.ensureVisible(_key('lyric-find-search'));
    await tester.enterText(_key('lyric-find-search'), 'END');
    await tester.pumpAndSettle();
    await tester.ensureVisible(_key('lyric-find-results'));
    await tester.pumpAndSettle();
    final text = tester.widget<Text>(find.byWidgetPredicate(
        (w) => w is Text && (w.data?.contains('END') ?? false)));
    expect(text.semanticsLabel, plain.text);
    expect(text.maxLines, isNull);
    expect(
        find.descendant(
            of: _key('lyric-find-results'),
            matching: find.byWidgetPredicate(
                (w) => w is Text && RegExp(r'^\d+:').hasMatch(w.data ?? ''))),
        findsNothing);
    expect(tester.takeException(), isNull);
  });
}
