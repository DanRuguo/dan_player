import 'dart:async';
import 'dart:io';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_text_search.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_find_dialog.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_reading_tools.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:desktop_lyric/l10n/catalog_lyric_find.dart';
import 'package:desktop_lyric/l10n/ui_catalog.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'support/listening_status_fixture.dart';
import 'support/lyric_share_fixture.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String text) => find.byKey(ValueKey(text));
Lrc _sample() => Lrc([
      for (var index = 0; index < 24; index++)
        LrcLine(Duration(seconds: index * 4),
            '第 $index 行 夜の雨 night rain┃译文 $index 雨落在窗前',
            isBlank: false, length: const Duration(seconds: 4))
          ..romanization = 'ame $index ga furu',
    ], LrcSource.local);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final output = Platform.environment['DAN_LYRIC_FIND_RENDER_DIR'];
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

  late LyricViewController controller;
  late Future<Lyric?> source;
  late Lyric document;
  late ValueNotifier<int> changes;
  int session = 1;
  int seeks = 0;

  Future<void> mount(WidgetTester tester,
      {Lyric? lyric,
      Future<Lyric?>? pending,
      ValueNotifier<bool>? hidden,
      GlobalKey? capture,
      bool animations = false}) async {
    document = lyric ?? _sample();
    source = pending ?? Future.value(document);
    session = 1;
    seeks = 0;
    changes = ValueNotifier(0);
    controller =
        LyricViewController(preferences: NowPlayingPagePreference.fromMap({}));
    addTearDown(changes.dispose);
    addTearDown(controller.dispose);
    sizePlaylistFeature(tester, width: 640, height: 700);
    Future<void> open(NavigatorState navigator) {
      final captured = source, token = session;
      return findLyricsForReading(navigator, controller,
          lyricFuture: captured,
          isCurrentLyric: () => identical(source, captured) && session == token,
          lyricChanges: changes,
          songTitle: 'Night 夜の雨 밤의 비');
    }

    await tester.pumpWidget(listeningStatusHost(
        ChangeNotifierProvider.value(
            value: controller,
            child: Builder(
                builder: (context) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(disableAnimations: !animations),
                    child: LyricControlsSurface(
                        onFind: () => open(Navigator.of(context)),
                        controls: LyricReadingMenu(
                            controller: controller,
                            readLyric: () => source,
                            onFind: open),
                        child: VerticalLyricScrollView(
                            lyric: document,
                            positionStream: const Stream<double>.empty(),
                            readPosition: () => 0,
                            onSeek: (_) => seeks++,
                            hidden: hidden,
                            playing: false,
                            springLyrics: false))))),
        boundary: capture));
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(600, 650));
    await tester.pump();
    await tester.tap(_key('lyric-reading-tools'));
    await tester.pumpAndSettle();
    await tester.tap(_key('lyric-find-open'));
    await tester.pumpAndSettle();
    await mouse.removePointer();
  }

  Future<void> query(WidgetTester tester, String text) async {
    await tester.ensureVisible(_key('lyric-find-search'));
    await tester.enterText(_key('lyric-find-search'), text);
    await tester.pumpAndSettle();
  }

  ScrollController scroll(WidgetTester tester) => tester
      .widget<CustomScrollView>(_key('vertical-lyric-scroll'))
      .controller!;

  test('find catalog has four languages and unchanged interpolation tokens',
      () {
    final tokens = RegExp(r'\{\d+\}');
    for (final entry in catalogLyricFind.entries) {
      expect(uiCatalog[entry.key], same(entry.value), reason: entry.key);
      expect(entry.value, hasLength(3));
      final expected = tokens.allMatches(entry.key).map((m) => m[0]).toList();
      for (final text in entry.value) {
        expect(text.trim(), isNotEmpty);
        expect(
            tokens.allMatches(text).map((m) => m[0]), orderedEquals(expected));
      }
    }
  });

  testWidgets(
      'reading menu searches hidden auxiliary tracks and reveals without seeking',
      (tester) async {
    final capture = GlobalKey();
    await mount(tester, capture: capture);
    controller.setShowTranslation(false);
    controller.setShowRomanization(false);
    await tester.pumpAndSettle();
    await openMenu(tester);
    await query(tester, '雨落');
    final visiblePreview = tester.widget<Text>(find
        .descendant(
            of: _key('lyric-find-result-0--1'), matching: find.byType(Text))
        .first);
    expect(visiblePreview.data, '译文 0 雨落在窗前');
    expect(visiblePreview.semanticsLabel, contains('ame 0 ga furu'));
    sizePlaylistFeature(tester, width: 420, height: 1000);
    await tester.pumpAndSettle();
    if (output != null) {
      final bytes = await captureLyricShare(tester, capture);
      await tester.runAsync(() async {
        await File(path.join(output, 'zh-narrow-translation.png'))
            .writeAsBytes(bytes);
      });
    }
    await query(tester, 'ame 19 译文');
    expect(_key('lyric-find-result-19--1'), findsOneWidget);
    await tester.tap(_key('lyric-find-locate'));
    await tester.pumpAndSettle();
    expect(controller.readingMode, isTrue);
    expect(controller.readingTarget?.index, 19);
    expect(scroll(tester).offset, greaterThan(200));
    expect(seeks, 0);
    expect(
        tester
            .widget<VerticalLyricScrollView>(
                find.byType(VerticalLyricScrollView))
            .playing,
        isFalse);
  });

  testWidgets(
      'Ctrl F opens find and F3 navigation wraps without changing reading until confirm',
      (tester) async {
    await mount(tester);
    final before = scroll(tester).offset;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF,
        physicalKey: PhysicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(LyricFindDialog), findsOneWidget);
    await query(tester, 'night');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft,
        physicalKey: PhysicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f3,
        physicalKey: PhysicalKeyboardKey.f3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft,
        physicalKey: PhysicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(_key('lyric-find-count')).data, '匹配：24 / 24');
    expect(_key('lyric-find-result-23--1'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.f3,
        physicalKey: PhysicalKeyboardKey.f3);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(_key('lyric-find-count')).data, '匹配：1 / 24');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape,
        physicalKey: PhysicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(controller.readingMode, isFalse);
    expect(controller.readingRequest, 0);
    expect(scroll(tester).offset, before);
    expect(seeks, 0);
  });

  testWidgets(
      'late source completion and repeated shortcut cannot open stale or duplicate dialogs',
      (tester) async {
    final pending = Completer<Lyric?>();
    await mount(tester, pending: pending.future);
    await openMenu(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF,
        physicalKey: PhysicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    source = Future.value(_sample());
    session++;
    changes.value++;
    pending.complete(document);
    await tester.pumpAndSettle();
    expect(find.byType(LyricFindDialog), findsNothing);
    expect(controller.readingRequest, 0);
  });

  testWidgets(
      'song replacement disables stale dialog and confirmation never publishes its target',
      (tester) async {
    await mount(tester);
    await openMenu(tester);
    await query(tester, 'rain');
    await tester.tap(_key('lyric-find-next'));
    await tester.pumpAndSettle();
    session++;
    changes.value++;
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(_key('lyric-find-locate')).onPressed,
        isNull);
    expect(tester.widget<OutlinedButton>(_key('lyric-find-next')).onPressed,
        isNull);
    await tester.tap(find.text(ui('取消')));
    await tester.pumpAndSettle();
    expect(controller.readingRequest, 0);
    expect(seeks, 0);
  });

  testWidgets('no matches cannot locate and clear restores all original rows',
      (tester) async {
    await mount(tester);
    await openMenu(tester);
    await query(tester, 'not-present');
    expect(tester.widget<FilledButton>(_key('lyric-find-locate')).onPressed,
        isNull);
    expect(find.text(ui('当前歌词中没有匹配内容')), findsOneWidget);
    await tester.tap(find.byTooltip(ui('清除')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(_key('lyric-find-count')).data, '匹配：1 / 24');
  });

  testWidgets(
      'plain paragraph reveals shaped glyphs deep inside one untimed line',
      (tester) async {
    final plain = PlainLyric('${'長い歌詞 rain 🌧 ' * 200}Needle 마지막 끝');
    await mount(tester, lyric: plain);
    await openMenu(tester);
    await query(tester, 'needle');
    await tester.tap(_key('lyric-find-locate'));
    await tester.pumpAndSettle();
    final element = tester.element(find.byWidgetPredicate(
        (w) => w is BalancedLyricText && w.text == plain.text));
    final geometry =
        (element as StatefulElement).state as LyricTextReadingGeometry;
    final y = geometry.readingGlobalY(plain.text.indexOf('Needle'))!;
    expect(y, inInclusiveRange(0, 650));
    expect(scroll(tester).offset, greaterThan(1000));
    expect(document.lines, hasLength(1));
    expect(seeks, 0);
  });

  testWidgets(
      'hidden reading request waits and returns at the selected row without animation',
      (tester) async {
    final hidden = ValueNotifier(false);
    addTearDown(hidden.dispose);
    await mount(tester, hidden: hidden);
    final before = scroll(tester).offset;
    hidden.value = true;
    await tester.pump();
    controller
        .revealForReading(LyricReadingTarget(document, 20, document.lines[20]));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(scroll(tester).offset, before);
    hidden.value = false;
    await tester.pump();
    await tester.pump();
    expect(scroll(tester).offset, greaterThan(1000));
    expect(scroll(tester).position.isScrollingNotifier.value, isFalse);
    expect(seeks, 0);
  });

  testWidgets(
      'return current cancels a pending reveal and stale document targets are ignored',
      (tester) async {
    await mount(tester);
    controller
        .revealForReading(LyricReadingTarget(document, 20, document.lines[20]));
    controller.returnToCurrent();
    await tester.pumpAndSettle();
    expect(scroll(tester).offset, lessThan(100));
    final other = _sample();
    controller.revealForReading(LyricReadingTarget(other, 20, other.lines[20]));
    await tester.pumpAndSettle();
    expect(scroll(tester).offset, lessThan(100));
    expect(seeks, 0);
  });

  testWidgets(
      'native reduce motion finishes an interrupted reading reveal without a ticker',
      (tester) async {
    await mount(tester, animations: true);
    final target = LyricReadingTarget(document, 20, document.lines[20]);
    controller.revealForReading(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    final moving = scroll(tester).offset;
    expect(scroll(tester).position.isScrollingNotifier.value, isTrue);
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(
        tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    await tester.pump();
    expect(scroll(tester).position.isScrollingNotifier.value, isFalse);
    expect(scroll(tester).offset, greaterThan(moving));
    expect(controller.readingMode, isTrue);
    expect(seeks, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  test(
      'discarding and disposing a captured reading target retain manual mode safely',
      () {
    final settings =
        LyricViewController(preferences: NowPlayingPagePreference.fromMap({}));
    final lyric = _sample();
    settings.revealForReading(LyricReadingTarget(lyric, 3, lyric.lines[3]));
    settings.discardReadingTarget();
    expect(settings.readingTarget, isNull);
    expect(settings.readingMode, isTrue);
    settings.dispose();
    expect(
        () => settings
            .revealForReading(LyricReadingTarget(lyric, 3, lyric.lines[3])),
        returnsNormally);
  });

  for (final language in UiLanguage.values) {
    testWidgets('${language.name} real-font find dialog wide narrow and large',
        (tester) async {
      uiLanguage.value = language;
      for (final frame in [
        ('wide', 900.0, 1.0),
        ('narrow', 420.0, 1.3),
        ('large', 360.0, 3.0)
      ]) {
        sizePlaylistFeature(tester, width: frame.$2, height: 1000);
        final boundary = GlobalKey();
        final lyric = _sample();
        await tester.pumpWidget(listeningStatusHost(
            Builder(
                builder: (context) => Center(
                    child: FilledButton(
                        onPressed: () => showLyricFindDialog(context,
                            lyric: lyric,
                            isCurrentLyric: () => true,
                            songTitle: 'Night 夜の雨 밤의 비'),
                        child: const Text('Open')))),
            scale: frame.$3,
            brightness: frame.$2 < 500 ? Brightness.dark : Brightness.light,
            boundary: boundary));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (output != null) {
          final bytes = await captureLyricShare(tester, boundary);
          await tester.runAsync(() async {
            await Directory(output).create(recursive: true);
            await File(path.join(output, '${language.name}-${frame.$1}.png'))
                .writeAsBytes(bytes);
          });
        }
        await tester.ensureVisible(_key('lyric-find-next'));
        await tester.tap(_key('lyric-find-next'));
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(_key('lyric-find-count')).data,
            ui('匹配：{0} / {1}', [2, 24]));
        await tester.ensureVisible(_key('lyric-find-locate'));
        await tester.tap(_key('lyric-find-locate'));
        await tester.pumpAndSettle();
        expect(find.byType(LyricFindDialog), findsNothing);
        expect(tester.takeException(), isNull);
      }
    });
  }
}
