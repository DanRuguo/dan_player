import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:desktop_lyric/appearance_palette_app.dart';
import 'package:desktop_lyric/appearance_palette_bridge.dart';
import 'package:desktop_lyric/component/desktop_lyric_text.dart';
import 'package:desktop_lyric/component/foreground.dart';
import 'package:desktop_lyric/component/lyric_line_display_area.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:desktop_lyric/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/desktop_lyric_test_support.dart';
import 'support/palette_test_bridge.dart';

DesktopLyricTextPainter _painter(WidgetTester tester,
        {bool translation = false}) =>
    tester
        .widget<CustomPaint>(find.descendant(
          of: find.byKey(ValueKey(translation
              ? 'desktop-translation-lyric'
              : 'desktop-primary-lyric')),
          matching: find.byType(CustomPaint),
        ))
        .painter! as DesktopLyricTextPainter;

void main() {
  test('fractional valid font sizes reach bounds without throwing', () {
    final texts = TextDisplayController();
    addTearDown(texts.dispose);
    texts.value = DesktopLyricAppearance.defaults
        .copyWith(lyricFontSize: 63.5, translationFontSize: 59.5);
    texts.increaseLyricFontSize();
    expect(texts.lyricFontSize, 64);
    expect(texts.translationFontSize, 60);
    texts.value = DesktopLyricAppearance.defaults
        .copyWith(lyricFontSize: 18.5, translationFontSize: 14.5);
    texts.decreaseLyricFontSize();
    expect(texts.lyricFontSize, 18);
    expect(texts.translationFontSize, 14);
  });
  test(
      'legacy appearance retains the old size/theme/background/shadow defaults',
      () {
    for (final input in [null, 1, '', <String, dynamic>{}]) {
      expect(DesktopLyricAppearance.fromJson(input),
          DesktopLyricAppearance.defaults);
    }
    const value = DesktopLyricAppearance.defaults;
    expect(value.lyricFontSize, 22);
    expect(value.translationFontSize, 18);
    expect(value.customColor, null);
    expect(value.backgroundOpacity, 0);
    expect(value.textOpacity, 1);
    expect(value.strokeEnabled, false);
  });

  test(
      'all appearance fields round trip and following theme clears custom color',
      () {
    final value = DesktopLyricAppearance.defaults.copyWith(
        lyricFontSize: 40,
        translationFontSize: 36,
        customColor: 0xffffcc00,
        backgroundOpacity: .3,
        textOpacity: .7,
        strokeEnabled: true);
    expect(
        DesktopLyricAppearance.fromJson(jsonDecode(jsonEncode(value.toJson()))),
        value);
    expect(value.copyWith(followTheme: true).customColor, null);
    final envelope = jsonDecode(
        DesktopLyricAppearanceChangedMessage(value, revision: 12)
            .buildMessageJson());
    final message =
        DesktopLyricAppearanceChangedMessage.fromJson(envelope['message']);
    expect(message.appearance, value);
    expect(message.revision, 12);
  });

  test('nonfinite/out-of-range fields cannot reach renderers or disk', () {
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
      -.01,
      1.01,
      '1'
    ]) {
      final map = {
        ...DesktopLyricAppearance.defaults.toJson(),
        'backgroundOpacity': value
      };
      expect(DesktopLyricAppearance.tryFromJson(map), null);
      expect(DesktopLyricAppearance.fromJson(map).backgroundOpacity, 0);
    }
    for (final entry in {
      'textOpacity': .19,
      'lyricFontSize': 65,
      'translationFontSize': 13,
      'customColor': -1,
      'strokeEnabled': 1
    }.entries) {
      expect(
          DesktopLyricAppearance.tryFromJson({
            ...DesktopLyricAppearance.defaults.toJson(),
            entry.key: entry.value
          }),
          null);
    }
    expect(
        () => DesktopLyricAppearance.defaults.copyWith(textOpacity: double.nan),
        throwsArgumentError);
    expect(() => DesktopLyricAppearance.defaults.copyWith(textOpacity: 0),
        throwsArgumentError);
    expect(DesktopLyricAppearance.tryFromJson({'textOpacity': .5}), null);
  });

  test('helper initialization and canonical updates never echo or reset clock',
      () {
    final sent = <String>[];
    final source = DesktopLyricController.detached(
        sendMessage: sent.add, clock: PlaybackClock(automaticTicks: false));
    addTearDown(source.dispose);
    final appearance = DesktopLyricAppearance.defaults
        .copyWith(textOpacity: .4, strokeEnabled: true);
    source.applyInitialState(InitArgsMessage(
        false, 'title', '', '', false, 0xff000000, 0xffffffff, 0xff000000,
        appearance: appearance));
    expect(source.appearance.value, appearance);
    source.handleMessage(
        const PlaybackTimelineMessage(3, 1234, false, playbackRate: 2)
            .buildMessageJson());
    source.handleMessage(DesktopLyricAppearanceMessage(
            appearance.copyWith(backgroundOpacity: .6))
        .buildMessageJson());
    expect(sent, isEmpty);
    expect(source.playbackClock.positionMilliseconds, 1234);
    expect(source.playbackClock.playbackRate, 2);
  });

  test(
      'helper revisions reject stale echo, report failure and retry latest choice',
      () {
    final sent = <String>[];
    final source = DesktopLyricController.detached(
        sendMessage: sent.add, clock: PlaybackClock(automaticTicks: false));
    addTearDown(source.dispose);
    source.appearance.setTextOpacity(.8);
    source.appearance.setTextOpacity(.4);
    source.handleMessage(const DesktopLyricAppearanceMessage(
            DesktopLyricAppearance.defaults,
            revision: 1)
        .buildMessageJson());
    expect(source.appearance.value.textOpacity, .4);
    source.handleMessage(
        const DesktopLyricAppearanceSavedMessage(revision: 1, saved: false)
            .buildMessageJson());
    expect(source.appearanceSaveError.value, null);
    source.handleMessage(
        const DesktopLyricAppearanceSavedMessage(revision: 2, saved: false)
            .buildMessageJson());
    expect(source.appearanceSaveError.value, contains('保存失败'));
    source.retryAppearanceSave();
    final retry = jsonDecode(sent.last)['message'];
    expect(retry['revision'], 3);
    expect(retry['appearance']['textOpacity'], .4);
    expect(source.appearanceSaveError.value, null);
    source.handleMessage(
        const DesktopLyricAppearanceSavedMessage(revision: 3, saved: true)
            .buildMessageJson());
    expect(sent, hasLength(3));
  });

  test('helper pipe closure and write failure are safe without writing files',
      () async {
    final input = StreamController<List<int>>();
    var sends = 0;
    final source = DesktopLyricController.detached(
        input: input.stream,
        closeWindow: () async {},
        clock: PlaybackClock(automaticTicks: false),
        sendMessage: (_) {
          sends++;
          throw StateError('closed pipe');
        });
    source.appearance.setTextOpacity(.5);
    expect(source.appearanceSaveError.value, contains('无法连接'));
    await input.close();
    source.retryAppearanceSave();
    expect(sends, 1);
    source.dispose();
    source.handleMessage(
        const DesktopLyricAppearanceMessage(DesktopLyricAppearance.defaults)
            .buildMessageJson());
  });

  for (final vertical in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets(
          'cached real glyph stroke with timed words: vertical=$vertical dark=$dark',
          (tester) async {
        var now = 0;
        final clock =
            PlaybackClock(nowMilliseconds: () => now, automaticTicks: false);
        addTearDown(clock.dispose);
        const words = [
          DesktopLyricWord(0, 1000, 'Hello'),
          DesktopLyricWord(1000, 1000, ' 世界')
        ];
        const line = LyricLineTimelineMessage(
            sequence: 1,
            lineIndex: 0,
            startMilliseconds: 0,
            lengthMilliseconds: 2000,
            content: 'Hello 世界',
            translation: '你好 world',
            words: words);
        Widget app(bool stroke) => MaterialApp(
            theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light),
            home: Center(
                child: SizedBox(
                    width: 240,
                    height: 350,
                    child: DesktopLyricLineContent(
                        detailedLine: line,
                        legacyLine:
                            const LyricLineChangedMessage('', Duration.zero),
                        clock: clock,
                        vertical: vertical,
                        color:
                            dark ? Colors.amber.shade200 : Colors.blue.shade900,
                        textOpacity: .5,
                        strokeEnabled: stroke))));
        clock
            .sync(const PlaybackTimelineMessage(1, 500, true, playbackRate: 2));
        await tester.pumpWidget(app(true));
        await tester.pumpAndSettle();
        final first = _painter(tester);
        expect(first.cachedStrokePainterCount, vertical ? 3 : 1);
        expect(_painter(tester, translation: true).cachedStrokePainterCount,
            vertical ? 3 : 1);
        if (vertical) {
          expect(first.glyphs.map((glyph) => glyph.text), ['Hello', '世', '界']);
        }
        final bounds =
            tester.getSize(find.byKey(const ValueKey('desktop-primary-lyric')));
        final firstFill = first.highlightRectsForWord(0).single;
        now = 100;
        clock.sync(
            const PlaybackTimelineMessage(1, 700, false, playbackRate: 2));
        await tester.pump();
        expect(
            identical(first.layoutCacheIdentity,
                _painter(tester).layoutCacheIdentity),
            true);
        expect(first.highlightRectsForWord(0).single.width,
            greaterThan(firstFill.width));
        final recorder = ui.PictureRecorder();
        first.paint(Canvas(recorder), bounds);
        final picture = recorder.endRecording();
        final withStroke = await tester.runAsync(() async {
          final image =
              await picture.toImage(bounds.width.ceil(), bounds.height.ceil());
          final bytes = await image.toByteData();
          image.dispose();
          picture.dispose();
          return bytes;
        });
        await tester.pumpWidget(app(false));
        await tester.pumpAndSettle();
        expect(_painter(tester).cachedStrokePainterCount, 0);
        expect(
            tester.getSize(find.byKey(const ValueKey('desktop-primary-lyric'))),
            bounds);
        final plainRecorder = ui.PictureRecorder();
        _painter(tester).paint(Canvas(plainRecorder), bounds);
        final plainPicture = plainRecorder.endRecording();
        final withoutStroke = await tester.runAsync(() async {
          final image = await plainPicture.toImage(
              bounds.width.ceil(), bounds.height.ceil());
          final bytes = await image.toByteData();
          image.dispose();
          plainPicture.dispose();
          return bytes;
        });
        expect(withStroke!.buffer.asUint8List(),
            isNot(orderedEquals(withoutStroke!.buffer.asUint8List())),
            reason:
                'The switch must change real glyph pixels, not only metadata.');
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets(
      'cover theme updates new controls, lyric and contrast outline live',
      (tester) async {
    final source = DesktopLyricController.detached(
        sendMessage: (_) {}, clock: PlaybackClock(automaticTicks: false));
    addTearDown(source.dispose);
    final layout = DesktopLyricWindowLayout(adapter: FakeDesktopLyricWindow());
    await layout.initialize(vertical: false);
    addTearDown(layout.dispose);
    final bridge = PaletteTestBridge(source: source, layout: layout);
    addTearDown(bridge.dispose);
    source.appearance.setStrokeEnabled(true);
    Widget lyrics() => MaterialApp(
        home: Scaffold(
            body: DesktopLyricPaletteScope(
                host: bridge.host,
                child: ValueListenableProvider<ThemeChangedMessage>.value(
                  value: source.theme,
                  child: DesktopLyricForeground(
                      isHovering: true,
                      controller: source,
                      windowLayout: layout,
                      sendMessage: (_) {}),
                ))));
    await tester.pumpWidget(lyrics());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('歌词外观'));
    await tester.pumpAndSettle();
    final client = await bridge.connectClient();
    // Two independent app roots, as with the two native engines. Keeping the
    // lyric pane mounted lets the same test compare controls and glyph colors.
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Row(children: [
          Expanded(child: lyrics()),
          Expanded(child: DesktopLyricAppearanceApp(client: client))
        ])));
    await tester.pumpAndSettle();
    DesktopLyricText lyric() => tester.widget<DesktopLyricText>(
        find.byKey(const ValueKey('desktop-primary-lyric')));
    for (final color in [0xff175321, 0xffffe090]) {
      source.handleMessage(ThemeChangedMessage(color, 0xff202020, 0xffe5e5e5)
          .buildMessageJson());
      await tester.pumpAndSettle();
      expect(lyric().playedColor, Color(color));
      expect(
          lyric().strokeColor,
          (Color(color).computeLuminance() > .45 ? Colors.black : Colors.white)
              .withValues(alpha: .9));
      final toggle = tester.widget<SwitchListTile>(
          find.byKey(const ValueKey('desktop-lyric-stroke')));
      expect(toggle.activeThumbColor, Color(color));
      final palette = tester.widget<IconButton>(find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == '歌词外观'));
      expect(palette.color, Color(color));
      final title = tester.widget<Text>(find.text('文字描边'));
      expect(title.style!.color, const Color(0xffe5e5e5));
    }
    source.appearance.spcifiyColor(Colors.pink);
    source.handleMessage(
        const ThemeChangedMessage(0xff000099, 0xffffffff, 0xff222222)
            .buildMessageJson());
    await tester.pumpAndSettle();
    expect(lyric().playedColor.toARGB32(), Colors.pink.toARGB32(),
        reason:
            'Only explicit custom lyric color stops following cover color.');
    source.appearance.usePlayerTheme();
    await tester.pumpAndSettle();
    expect(lyric().playedColor, const Color(0xff000099));
    expect(tester.takeException(), null);
    await tester
        .ensureVisible(find.byKey(const ValueKey('desktop-appearance-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('desktop-appearance-close')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    ALWAYS_SHOW_ACTION_ROW = false;
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'appearance palette edits are scrollable and controls stay opaque at $scale',
        (tester) async {
      tester.view.physicalSize = const Size(507, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final messages = <String>[];
      final source = DesktopLyricController.detached(
          sendMessage: messages.add,
          clock: PlaybackClock(automaticTicks: false));
      final native = FakeDesktopLyricWindow();
      final layout = DesktopLyricWindowLayout(adapter: native);
      await layout.initialize(vertical: false);
      addTearDown(source.dispose);
      addTearDown(layout.dispose);
      final bridge = PaletteTestBridge(source: source, layout: layout);
      addTearDown(bridge.dispose);
      final theme = ThemeData(colorSchemeSeed: Colors.blue);
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(
              body: MediaQuery(
            data: MediaQueryData(
                size: const Size(507, 500),
                textScaler: TextScaler.linear(scale)),
            child: DesktopLyricPaletteScope(
                host: bridge.host,
                child: Provider<ThemeChangedMessage>.value(
                    value: ThemeChangedMessage(
                        theme.colorScheme.primary.toARGB32(),
                        theme.colorScheme.surfaceContainer.toARGB32(),
                        theme.colorScheme.onSurface.toARGB32()),
                    child: DesktopLyricForeground(
                        isHovering: true,
                        controller: source,
                        windowLayout: layout,
                        sendMessage: messages.add))),
          ))));
      await tester.pumpAndSettle();
      source.appearance.setTextOpacity(.2);
      await tester.pump();
      expect(
          tester
              .widget<Opacity>(
                  find.byKey(const ValueKey('desktop-lyric-text-opacity')))
              .opacity,
          .2);
      final controls = find.byKey(const ValueKey('desktop-actions'));
      expect(
          find.ancestor(
              of: controls,
              matching:
                  find.byKey(const ValueKey('desktop-lyric-text-opacity'))),
          findsNothing);
      await tester.tap(find.byTooltip('歌词外观'));
      await tester.pumpAndSettle();
      final client = await bridge.connectClient();
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(DesktopLyricAppearanceApp(client: client));
      await tester.pumpAndSettle();
      final slider = find.byKey(const ValueKey('desktop-text-opacity'));
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      final widget = tester.widget<Slider>(slider);
      expect(widget.min, .2);
      widget.onChanged!(.6);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pumpAndSettle();
      expect(source.appearance.value.textOpacity, .6);
      final stroke = find.byKey(const ValueKey('desktop-lyric-stroke'));
      await tester.ensureVisible(stroke);
      await tester.pumpAndSettle();
      await tester.tap(stroke);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pumpAndSettle();
      expect(source.appearance.value.strokeEnabled, true);
      final revision = jsonDecode(messages.last)['message']['revision'] as int;
      source.handleMessage(
          DesktopLyricAppearanceSavedMessage(revision: revision, saved: false)
              .buildMessageJson());
      expect(source.appearanceSaveError.value, isNotNull);
      // The independent engine receives an asynchronous snapshot before it
      // renders its retry action; one owner frame is not a channel barrier.
      await tester.pumpAndSettle();
      expect(client.saveError.value, isNotNull);
      await tester.ensureVisible(find.text('重试保存'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重试保存'));
      await tester.pump();
      expect(source.appearanceSaveError.value, null);
      expect(tester.takeException(), null);
      await tester.ensureVisible(
          find.byKey(const ValueKey('desktop-appearance-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('desktop-appearance-close')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      ALWAYS_SHOW_ACTION_ROW = false;
    });
  }
}
