import 'dart:async';
import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/playback_bookmarks.dart';
import 'package:dan_player/page/now_playing_page/component/detail_progress_slider.dart';
import 'package:dan_player/page/now_playing_page/component/detail_timeline_annotations.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _marks = [
  PlaybackBookmark(
      id: 'a', track: 'fixture', label: '前奏 / Introduction', positionMs: 20000),
  PlaybackBookmark(
      id: 'b',
      track: 'fixture',
      label: '喜欢的段落 / Favourite section',
      positionMs: 90000,
      endMs: 110000),
  PlaybackBookmark(
      id: 'c', track: 'fixture', label: '很近的第二个书签', positionMs: 91000),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StreamController<double> positions;
  late double actual;
  late List<double> seeks;
  setUp(() {
    positions = StreamController<double>.broadcast(sync: true);
    actual = 20;
    seeks = [];
  });
  tearDown(() async {
    await positions.close();
    uiLanguage.value = UiLanguage.zh;
  });

  Widget host(
          {double width = 420,
          double duration = 200,
          Object identity = 'track',
          bool reject = false,
          ValueNotifier<bool>? hidden,
          TextDirection direction = TextDirection.ltr,
          List<PlaybackBookmark> bookmarks = const [],
          double? start,
          double? end,
          double textScale = 1,
          GlobalKey? boundary,
          bool waveform = false,
          bool reduced = true}) =>
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: Entry(welcome: false).fromSchemeAndFontFamily(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(textScale),
                  disableAnimations: reduced),
              child: child!),
          home: Directionality(
              textDirection: direction,
              child: Scaffold(
                  body: Center(
                      child: SizedBox(
                width: width,
                child: DetailProgressSlider(
                  positions: positions.stream,
                  readPosition: () => actual,
                  duration: duration,
                  trackIdentity: identity,
                  hidden: hidden,
                  waveform: waveform
                      ? List.generate(512, (i) => (i % 37) / 36)
                      : null,
                  bookmarks: bookmarks,
                  loopStart: start,
                  loopEnd: end,
                  loopEnabled: true,
                  onSeek: (value) {
                    seeks.add(value);
                    if (!reject) actual = value;
                  },
                ),
              )))),
        ),
      );

  Future<void> openTimeMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('detail-progress-time-menu')));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'hover previews actual track geometry without changing playback or dragging',
      (tester) async {
    await tester.pumpWidget(host());
    final rect = tester.getRect(find.byType(Slider));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset(rect.left, rect.top - 10));
    await mouse.moveTo(rect.center);
    await tester.pumpAndSettle();
    expect(find.text('1:40'), findsOneWidget);
    expect(seeks, isEmpty);
    expect(actual, 20);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 20);
    await mouse.moveTo(const Offset(0, 0));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('detail-progress-hover-time')), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    await mouse.removePointer();
  });

  for (final reduced in [false, true]) {
    testWidgets(
        'drag preview animates and stays at the released pointer reduced=$reduced',
        (tester) async {
      await tester.pumpWidget(host(reduced: reduced));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(Slider));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(0, 0));
      await mouse.moveTo(Offset(rect.left + 70, rect.center.dy));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      final bubble =
          find.byKey(const ValueKey('detail-progress-preview-bubble'));
      final fade = find
          .ancestor(of: bubble, matching: find.byType(FadeTransition))
          .first;
      expect(tester.widget<FadeTransition>(fade).opacity.value,
          reduced ? 1 : inExclusiveRange(0.0, 1.0));
      await tester.pumpAndSettle();
      await mouse.down(Offset(rect.left + 70, rect.center.dy));
      await mouse.moveTo(Offset(rect.left + 260, rect.center.dy));
      await tester.pumpAndSettle();
      final before = tester.getCenter(bubble).dx;
      final time = tester.widget<Slider>(find.byType(Slider)).value;
      final expected = rect.left + 24 + (rect.width - 48) * time / 200;
      expect(before, closeTo(expected, .5));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getCenter(bubble).dx, closeTo(before, .1));
      await mouse.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.getCenter(bubble).dx, closeTo(before, .5));
      await tester.pumpAndSettle();
      expect(tester.getCenter(bubble).dx, closeTo(before, .5));
      expect(seeks, hasLength(1));
      expect(actual, closeTo(time, .01));
      await mouse.moveTo(const Offset(0, 0));
      await tester.pumpAndSettle();
      expect(bubble, findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      await mouse.removePointer();
    });
  }

  testWidgets(
      'remaining time follows real second samples and drag cancellation',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.byKey(const ValueKey('detail-progress-time-mode')));
    await tester.pumpAndSettle();
    expect(find.text('−3:00'), findsOneWidget);
    actual = 27;
    positions.add(actual);
    await tester.pumpAndSettle();
    expect(find.text('−2:53'), findsOneWidget);
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Slider)));
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).label, contains('(+'));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(find.text('−2:53'), findsOneWidget);
    expect(seeks, isEmpty);
  });

  testWidgets(
      'focused keyboard uses fixed seconds fine seek percentages and boundaries',
      (tester) async {
    await tester.pumpWidget(host());
    tester.widget<Slider>(find.byType(Slider)).focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(actual, 25);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(actual, 24);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit7);
    expect(actual, 140);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    expect(actual, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    expect(actual, 200);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(actual, 200,
        reason: 'Ctrl navigation stays owned by the global shortcuts');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('RTL hover and arrow keys agree with the rendered track',
      (tester) async {
    await tester.pumpWidget(host(direction: TextDirection.rtl));
    tester.widget<Slider>(find.byType(Slider)).focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(actual, 15);
    final rect = tester.getRect(find.byType(Slider));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(0, 0));
    await mouse
        .moveTo(Offset(rect.left + 24 + (rect.width - 48) / 4, rect.center.dy));
    await tester.pumpAndSettle();
    expect(find.text('2:30'), findsOneWidget);
    await mouse.removePointer();
  });

  testWidgets('seek undo returns to the actual previous position once',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.tapAt(tester.getCenter(find.byType(Slider)));
    await tester.pumpAndSettle();
    expect(actual, closeTo(100, 1));
    await openTimeMenu(tester);
    await tester.tap(find.byKey(const ValueKey('detail-progress-undo-seek')));
    await tester.pumpAndSettle();
    expect(actual, 20);
    await openTimeMenu(tester);
    expect(
        tester
            .widget<MenuItemButton>(
                find.byKey(const ValueKey('detail-progress-undo-seek')))
            .onPressed,
        isNull);
  });

  testWidgets(
      'rejected seek and a changed playback session cannot leave an old undo',
      (tester) async {
    await tester.pumpWidget(host(reject: true));
    await tester.tapAt(tester.getCenter(find.byType(Slider)));
    await tester.pumpAndSettle();
    await openTimeMenu(tester);
    expect(
        tester
            .widget<MenuItemButton>(
                find.byKey(const ValueKey('detail-progress-undo-seek')))
            .onPressed,
        isNull);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host());
    await tester.tapAt(tester.getCenter(find.byType(Slider)));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(identity: 'reopened same track'));
    await openTimeMenu(tester);
    expect(
        tester
            .widget<MenuItemButton>(
                find.byKey(const ValueKey('detail-progress-undo-seek')))
            .onPressed,
        isNull);
  });

  testWidgets('copy uses current media time and no playback command',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(host());
    actual = 74.8;
    await openTimeMenu(tester);
    await tester.tap(find.byKey(const ValueKey('detail-progress-copy-time')));
    await tester.pumpAndSettle();
    expect(copied, '1:14');
    expect(seeks, isEmpty);
  });

  testWidgets(
      'bookmark marks locate independently and range mark never commits a seek',
      (tester) async {
    await tester.pumpWidget(host(bookmarks: _marks, start: 40, end: 80));
    expect(find.byKey(const ValueKey('detail-progress-loop-range')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('detail-progress-bookmark-b')));
    await tester.pumpAndSettle();
    expect(seeks, [90]);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 90);
    final range = tester
        .getRect(find.byKey(const ValueKey('detail-progress-loop-range')));
    await tester.tapAt(Offset(range.left + range.width * .3, range.bottom - 2));
    await tester.pumpAndSettle();
    expect(seeks, [90]);
    await openTimeMenu(tester);
    await tester.tap(find.widgetWithText(SubmenuButton, '播放书签'));
    await tester.pumpAndSettle();
    expect(find.text('1:31 · 很近的第二个书签'), findsOneWidget,
        reason: 'overlapping physical marks stay accessible in the menu');
  });

  testWidgets('hidden timeline ignores keyboard and removes hover preview',
      (tester) async {
    final hidden = ValueNotifier(false);
    addTearDown(hidden.dispose);
    await tester.pumpWidget(host(hidden: hidden));
    tester.widget<Slider>(find.byType(Slider)).focusNode!.requestFocus();
    await tester.pump();
    hidden.value = true;
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit8);
    await tester.pumpAndSettle();
    expect(seeks, isEmpty);
    expect(positions.hasListener, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
  });

  test('long audio scale chooses readable media-time divisions', () {
    expect(detailTimelineTicks(200, 600), isEmpty);
    expect(detailTimelineTicks(double.nan, 600), isEmpty);
    expect(detailTimelineTicks(3600, 130), isEmpty);
    expect(detailTimelineTicks(3600, 600), [600, 1200, 1800, 2400, 3000]);
    expect(detailTimelineTicks(3600, 600, textScale: 2), [1800]);
    expect(detailTimelineTime(7321), '2:02:01');
  });

  testWidgets(
      'unknown duration disables timeline commands and discards invalid annotations',
      (tester) async {
    await tester
        .pumpWidget(host(duration: 0, bookmarks: _marks, start: 10, end: 20));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    expect(
        find.byKey(const ValueKey('detail-progress-loop-range')), findsNothing);
    expect(
        find.byKey(const ValueKey('detail-progress-bookmark-a')), findsNothing);
    await openTimeMenu(tester);
    expect(
        tester
            .widget<MenuItemButton>(
                find.byKey(const ValueKey('detail-progress-copy-time')))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<MenuItemButton>(
                find.byKey(const ValueKey('detail-progress-undo-seek')))
            .onPressed,
        isNull);
    expect(seeks, isEmpty);
  });

  testWidgets(
      'time preview numeral ink is vertically centred at both text scales',
      (tester) async {
    await tester.runAsync(() async {
      await (FontLoader(danEmbeddedFontFamily)
            ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
          .load();
      final numerals = File('C:/Windows/Fonts/segoeui.ttf');
      if (await numerals.exists()) {
        await (FontLoader('Segoe UI')
              ..addFont(Future.value(
                  ByteData.sublistView(await numerals.readAsBytes()))))
            .load();
      }
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final scale in [1.0, 1.8]) {
      final boundary = GlobalKey();
      await tester.pumpWidget(host(boundary: boundary, textScale: scale));
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      await mouse.moveTo(tester.getCenter(find.byType(Slider)));
      await tester.pumpAndSettle();
      final bubble = tester.getRect(
          find.byKey(const ValueKey('detail-progress-preview-bubble')));
      final text = tester
          .getRect(find.byKey(const ValueKey('detail-progress-hover-time')));
      final inkCentre = await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final data =
            (await image.toByteData(format: drawing.ImageByteFormat.rawRgba))!
                .buffer
                .asUint8List();
        var top = image.height, bottom = -1;
        // Compare with the bubble's flat fill, excluding the shadow and corners.
        final background = ((bubble.top + 3).round() * image.width +
                bubble.center.dx.round()) *
            4;
        for (var y = text.top.floor(); y < text.bottom.ceil(); y++) {
          for (var x = text.left.floor(); x < text.right.ceil(); x++) {
            final p = (y * image.width + x) * 4;
            final distance = (data[p] - data[background]).abs() +
                (data[p + 1] - data[background + 1]).abs() +
                (data[p + 2] - data[background + 2]).abs();
            if (distance > 180) {
              if (y < top) top = y;
              if (y > bottom) bottom = y;
            }
          }
        }
        image.dispose();
        expect(bottom, greaterThan(top),
            reason: 'Must detect real numeral ink');
        return (top + bottom + 1) / 2;
      });
      expect(inkCentre, closeTo(bubble.center.dy, .75),
          reason:
              'Numeral ink, not the font line box, must be centred ($scale)');
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('real-font wide narrow large-text preview and time menus render',
      (tester) async {
    const output = String.fromEnvironment('DAN_TIMELINE_RENDER');
    if (output.isEmpty) return;
    await tester.runAsync(() async {
      await (FontLoader(danEmbeddedFontFamily)
            ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
          .load();
      final iconPath = File(
          '../tool/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (await iconPath.exists()) {
        await (FontLoader('MaterialIcons')
              ..addFont(Future.value(
                  ByteData.sublistView(await iconPath.readAsBytes()))))
            .load();
      }
      for (final pair in [
        ('Segoe UI', 'C:/Windows/Fonts/segoeui.ttf'),
        ('Malgun Gothic', 'C:/Windows/Fonts/malgun.ttf')
      ]) {
        final font = File(pair.$2);
        if (await font.exists()) {
          await (FontLoader(pair.$1)
                ..addFont(Future.value(
                    ByteData.sublistView(await font.readAsBytes()))))
              .load();
        }
      }
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      for (final width in [840.0, 320.0]) {
        tester.view.physicalSize = Size(width, 420);
        final boundary = GlobalKey();
        actual = 1480;
        await tester.pumpWidget(host(
            width: width - 32,
            duration: 7200,
            textScale: width > 400 ? 1 : 1.8,
            boundary: boundary,
            waveform: true,
            bookmarks: _marks,
            start: 1200,
            end: 2200));
        await tester.pumpAndSettle();
        Future<void> capture(String suffix) async {
          expect(tester.takeException(), isNull);
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            try {
              final bytes = (await image.toByteData(
                  format: drawing.ImageByteFormat.png))!;
              final file =
                  File('$output/${language.name}-${width.toInt()}-$suffix.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }

        await capture('timeline');
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset(width - 2, 400));
        final rect = tester.getRect(find.byType(Slider));
        await mouse.moveTo(
            Offset(rect.left + 24 + (rect.width - 48) * .6, rect.center.dy));
        await tester.pumpAndSettle();
        await capture('hover');
        await mouse.removePointer();
        await tester.pumpAndSettle();
        final drag = await tester.startGesture(rect.center);
        await drag.moveBy(Offset(rect.width * .15, 0));
        await tester.pump(const Duration(milliseconds: 250));
        await capture('drag');
        await drag.cancel();
        await tester.pumpAndSettle();
        await openTimeMenu(tester);
        await capture('menu');
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      }
    }
  });
}
