import 'dart:ui' as drawing;
import 'dart:io';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:desktop_lyric/app_motion.dart';
import 'package:desktop_lyric/component/desktop_lyric_text.dart';
import 'package:desktop_lyric/component/lyric_letter_spacing_control.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'lyric_letter_spacing_render_test.dart' show loadLetterSpacingFonts;
import 'lyric_letter_spacing_visible_feedback_test.dart'
    show expectMainSpacingGroup;
import 'support/playlist_feature_fixture.dart' show capturePlaylistFeature;

const _parts = ['晨光かな ', 'Moonlight e\u0301 ', '👩🏽‍🚀 한글 ', 'שלום 終点'];
final _text = _parts.join();

class _Word extends SyncLyricWord {
  _Word(int index, String text)
      : super(Duration(milliseconds: index * 400),
            const Duration(milliseconds: 800), text);
}

class _Line extends SyncLyricLine {
  _Line()
      : super(Duration.zero, const Duration(seconds: 5), [
          for (final (index, text) in _parts.indexed) _Word(index, text),
        ]);
}

List<({TextPainter text, CustomPainter painter})> _mainPainters(GlobalKey key) {
  final result = <({TextPainter text, CustomPainter painter})>[];
  void visit(Element element) {
    if (element.widget case CustomPaint(painter: final painter)) {
      final text = switch (painter) {
        PlainLyricWordFollowPainter() => painter.text,
        LyricWordHighlightPainter() => painter.text,
        _ => null,
      };
      if (text?.text?.toPlainText() == _text) {
        result.add((text: text!, painter: painter!));
      }
    }
    element.visitChildren(visit);
  }

  visit(key.currentContext! as Element);
  return result;
}

Future<List<int>> _rgba(WidgetTester tester, GlobalKey key) async {
  return (await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    try {
      return (await image.toByteData(format: drawing.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List()
          .toList(growable: false);
    } finally {
      image.dispose();
    }
  }))!;
}

void _expectGlyphInk(List<int> rgba) {
  var inkPixels = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (rgba[i + 3] > 0 &&
        (rgba[i] < 220 || rgba[i + 1] < 220 || rgba[i + 2] < 220)) {
      inkPixels += 1;
    }
  }
  expect(inkPixels, greaterThan(100),
      reason: 'A geometry frame must retain actual foreground glyph ink');
}

DesktopLyricTextPainter _desktop(WidgetTester tester) => tester
    .widget<CustomPaint>(find.byWidgetPredicate((widget) =>
        widget is CustomPaint && widget.painter is DesktopLyricTextPainter))
    .painter! as DesktopLyricTextPainter;

void _semanticChange(WidgetTester tester, Finder finder) {
  SemanticsNode? target;
  void visit(SemanticsNode node) {
    if (node.getSemanticsData().hasAction(SemanticsAction.increase)) {
      target = node;
      return;
    }
    node.visitChildren((child) {
      visit(child);
      return target == null;
    });
  }

  visit(tester.getSemantics(finder));
  expect(target, isNotNull);
  target!.owner!.performAction(target!.id, SemanticsAction.increase);
}

Future<Duration> _pumpFrameStamp(
    WidgetTester tester, Future<void> Function() pump) async {
  Duration? frame;
  tester.binding.addPostFrameCallback((stamp) => frame = stamp);
  await pump();
  expect(frame, isNotNull);
  return frame!;
}

void main({bool onlyRender = false}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  final nativeCase = onlyRender
      ? Platform.environment['DAN_LYRIC_SPACING_MOTION_NATIVE_CASE'] ?? ''
      : '';
  if (nativeCase.isNotEmpty && nativeCase != 'desktop') {
    throw ArgumentError.value(nativeCase,
        'DAN_LYRIC_SPACING_MOTION_NATIVE_CASE', 'Expected empty or desktop');
  }
  setUpAll(() async {
    await loadLetterSpacingFonts();
    // The Windows renderer resolves these production policy fallbacks itself.
    // The software test engine needs their real files registered explicitly.
    final windows = Platform.environment['WINDIR'];
    if (windows != null) {
      for (final (family, filename) in [
        ('Segoe UI', 'segoeui.ttf'),
        ('Segoe UI Symbol', 'seguisym.ttf'),
        ('Segoe UI Emoji', 'seguiemj.ttf')
      ]) {
        final font = File('$windows/Fonts/$filename');
        if (await font.exists()) {
          await (FontLoader(family)
                ..addFont(Future.value(
                    ByteData.sublistView(await font.readAsBytes()))))
              .load();
        }
      }
    }
  });
  if (!onlyRender) {
    testWidgets('spacing held pointer retires before control disposal',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Material(
              child: Center(
                  child: SizedBox(
                      width: 400,
                      child: LyricLetterSpacingControl(
                          value: 6, onChanged: (_) {}, id: 'raw-spacing'))))));
      final slider = find.byKey(const ValueKey('raw-spacing-slider'));
      final gesture = await tester.startGesture(tester.getCenter(slider));
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await gesture.cancel();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    });
    testWidgets('spacing external replacement retains its held raw owner',
        (tester) async {
      final value = ValueNotifier(6.0);
      addTearDown(value.dispose);
      final commits = <double>[];
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(MaterialApp(
            home: Material(
                child: Center(
                    child: SizedBox(
                        width: 400,
                        child: ValueListenableBuilder(
                            valueListenable: value,
                            builder: (_, current, __) =>
                                LyricLetterSpacingControl(
                                    value: current,
                                    id: 'raw-spacing',
                                    onChanged: (next) {
                                      commits.add(next);
                                      value.value = next;
                                    })))))));
        final slider = find.byKey(const ValueKey('raw-spacing-slider'));
        final gesture = await tester.startGesture(tester.getCenter(slider));
        await gesture.moveBy(const Offset(60, 0));
        await tester.pump();
        expect(tester.widget<Slider>(slider).value, greaterThan(6));
        value.value = 2;
        await tester.pump();
        _semanticChange(tester, slider);
        await tester.pump();
        expect(commits, isEmpty);
        expect(value.value, 2);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(commits, isEmpty);
        _semanticChange(tester, slider);
        await tester.pumpAndSettle();
        expect(commits, [2.5]);
      } finally {
        semantics.dispose();
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
    for (final early in [false, true]) {
      testWidgets(
          'spacing raw owner rejects ${early ? 'pre-start semantics' : 'parent scroll cancellation'}',
          (tester) async {
        final value = ValueNotifier(6.0);
        addTearDown(value.dispose);
        final commits = <double>[];
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(MaterialApp(
              home: Scaffold(
                  body: SizedBox(
                      height: 400,
                      child: SingleChildScrollView(
                          child: Column(children: [
                        const SizedBox(height: 40),
                        ValueListenableBuilder(
                            valueListenable: value,
                            builder: (_, current, __) =>
                                LyricLetterSpacingControl(
                                    value: current,
                                    id: 'raw-spacing',
                                    onChanged: (next) {
                                      commits.add(next);
                                      value.value = next;
                                    })),
                        const SizedBox(height: 1000),
                      ]))))));
          final slider = find.byKey(const ValueKey('raw-spacing-slider'));
          final gesture = await tester.startGesture(tester.getCenter(slider));
          if (early) {
            _semanticChange(tester, slider);
            await tester.pump();
            expect(commits, isEmpty);
            expect(value.value, 6);
            await gesture.moveBy(const Offset(60, 0));
            await tester.pump();
            final draft = tester.widget<Slider>(slider).value;
            expect(draft, greaterThan(6));
            await gesture.up();
            await tester.pumpAndSettle();
            expect(commits, [draft]);
          } else {
            await tester.pump(const Duration(milliseconds: 150));
            await gesture.moveBy(const Offset(0, -70));
            await tester.pump();
            expect(commits, isEmpty);
            expect(value.value, 6);
            await gesture.up();
            await tester.pumpAndSettle();
            expect(commits, isEmpty);
          }
          _semanticChange(tester, slider);
          await tester.pumpAndSettle();
          expect(commits.length, early ? 2 : 1);
        } finally {
          semantics.dispose();
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  for (final timed in nativeCase.isEmpty ? [false, true] : const <bool>[]) {
    for (final rtl in [false, true]) {
      testWidgets(
          'spacing main ${timed ? 'timed' : 'plain'} target stays shaped through wrap rtl=$rtl',
          (tester) async {
        final appearance = ValueNotifier(DesktopLyricAppearance.defaults);
        final controller = LyricViewController(
            preferences: NowPlayingPagePreference.fromMap({}),
            appearance: appearance);
        final position = ValueNotifier(const Duration(milliseconds: 1550));
        final render =
            ValueNotifier(const RenderingPreferences(surfaceBlur: false));
        addTearDown(render.dispose);
        addTearDown(controller.dispose);
        addTearDown(appearance.dispose);
        addTearDown(position.dispose);
        final LyricLine line = timed ? _Line() : PlainLyric(_text).lines.single;
        final root = GlobalKey(), tile = GlobalKey();
        Widget host({bool enabled = true, bool ticker = true}) => MaterialApp(
            home: AppFontScope(
                policy: AppFontPolicy.defaults(),
                child: RenderingPreferencesScope(
                    preferences: render,
                    child: MotionPreferencesScope(
                        preferences: MotionPreferences(
                            disabled: enabled ? const {} : {MotionKind.layout}),
                        child: ChangeNotifierProvider.value(
                            value: controller,
                            child: Directionality(
                                textDirection:
                                    rtl ? TextDirection.rtl : TextDirection.ltr,
                                child: Center(
                                    child: TickerMode(
                                        enabled: ticker,
                                        child: RepaintBoundary(
                                            key: root,
                                            child: Material(
                                                color: Colors.white,
                                                textStyle: const TextStyle(
                                                    fontSize: 20,
                                                    letterSpacing: .5),
                                                child: SizedBox(
                                                    width: rtl ? 300 : 260,
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        LyricViewTile(
                                                            key: tile,
                                                            line: line,
                                                            position: position,
                                                            opacity: 1,
                                                            distance: 0,
                                                            reducedMotion:
                                                                false)
                                                      ],
                                                    ))))))))))));
        await tester.pumpWidget(host());
        await tester.pumpAndSettle();
        final oldHeight = tester.getSize(find.byKey(tile)).height;
        final initial = await _rgba(tester, root);
        _expectGlyphInk(initial);
        if (!timed && !rtl) {
          await capturePlaylistFeature(
              tester, root, 'spacing-motion-main-start');
        }
        controller.setLyricLetterSpacing(8);
        await tester.pump();
        final targetHeight = tester.getSize(find.byKey(tile)).height;
        expect(targetHeight, greaterThan(oldHeight),
            reason: 'Wrapping uses the complete target spacing on frame zero');
        final endpoints = _mainPainters(tile);
        expect(endpoints, hasLength(1));
        expect(endpoints.map((entry) => entry.text.text!.style!.letterSpacing),
            [8.5]);
        final paragraph = find.descendant(
            of: find.byKey(tile),
            matching: find.byWidgetPredicate((widget) =>
                widget is CustomPaint &&
                (widget.painter is PlainLyricWordFollowPainter ||
                    widget.painter is LyricWordHighlightPainter)));
        expectMainSpacingGroup(tester, paragraph, 0);
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          final progress = LyricMotion.curve.transform(
              (frame + 1) * 16 / LyricMotion.spacingDuration.inMilliseconds);
          expectMainSpacingGroup(tester, paragraph, progress);
          expect(_mainPainters(tile).map((entry) => entry.text),
              endpoints.map((entry) => entry.text));
          expect(tester.getSize(find.byKey(tile)).height, targetHeight,
              reason:
                  'Only the target ink moves; wrapping does not grow per frame');
          if (timed) {
            for (final entry in _mainPainters(tile)) {
              expect(
                  (entry.painter as LyricWordHighlightPainter)
                      .progressForWord(1),
                  closeTo(1, .0001));
            }
          }
        }
        final middleHeight = tester.getSize(find.byKey(tile)).height;
        final middle = await _rgba(tester, root);
        _expectGlyphInk(middle);
        expect(middle, isNot(initial));
        expect(middleHeight, targetHeight);
        if (!timed && !rtl) {
          await capturePlaylistFeature(tester, root, 'spacing-motion-main-mid');
        }
        controller.setLyricLetterSpacing(1);
        await tester.pump();
        final reversedHeight = tester.getSize(find.byKey(tile)).height;
        expect(_mainPainters(tile), hasLength(1));
        expect(_mainPainters(tile).single.text.text!.style!.letterSpacing, 1.5);
        expectMainSpacingGroup(tester, paragraph, 0);
        await tester.pump(const Duration(milliseconds: 32));
        expectMainSpacingGroup(
            tester,
            paragraph,
            LyricMotion.curve
                .transform(32 / LyricMotion.spacingDuration.inMilliseconds));
        expect(tester.getSize(find.byKey(tile)).height, reversedHeight);
        _expectGlyphInk(await _rgba(tester, root));
        await tester.pumpAndSettle();
        expectMainSpacingGroup(tester, paragraph, 1);
        expect(tester.getSize(find.byKey(tile)).height, reversedHeight);
        expect(_mainPainters(tile), hasLength(1));
        final finalText = _mainPainters(tile).single.text;
        expect(finalText.text!.toPlainText(), _text);
        expect(finalText.text!.style!.letterSpacing, 1.5);
        expect(
            finalText.getBoxesForSelection(TextSelection(
                baseOffset: _text.length - 2, extentOffset: _text.length)),
            isNotEmpty);
        expect(position.value, const Duration(milliseconds: 1550));
        _expectGlyphInk(await _rgba(tester, root));
        if (!timed && !rtl) {
          await capturePlaylistFeature(tester, root, 'spacing-motion-main-end');
        }
        controller.setLyricLetterSpacing(7);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 32));
        await tester.pumpWidget(host(enabled: false));
        await tester.pump();
        expect(_mainPainters(tile), hasLength(1));
        expect(_mainPainters(tile).single.text.text!.style!.letterSpacing, 7.5);
        expect(tester.binding.transientCallbackCount, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.binding.transientCallbackCount, 0);
      });
    }
  }

  for (final vertical in [false, true]) {
    testWidgets(
        'spacing desktop cached geometry has finite middle frames vertical=$vertical',
        (tester) async {
      final clock = PlaybackClock(automaticTicks: false);
      addTearDown(clock.dispose);
      clock.sync(const PlaybackTimelineMessage(1, 1550, false));
      const text = '晨光👩🏽‍🚀再次照亮終点';
      final words = [const DesktopLyricWord(0, 4000, text)];
      var spacing = 0.0;
      final boundary = GlobalKey(), naturalTarget = GlobalKey();
      Widget textNode(double value, {bool reduced = false, Key? key}) =>
          DesktopLyricText(
            key: key,
            text: text,
            words: words,
            clock: clock,
            vertical: vertical,
            verticalLetterSpacing: value,
            reducedMotion: reduced,
            style: TextStyle(fontSize: 22, letterSpacing: value),
            playedColor: Colors.blue,
            unplayedColor: Colors.red,
            strokeColor: Colors.black,
          );
      Widget host({bool ticker = true}) => MaterialApp(
          home: AppFontScope(
              policy: AppFontPolicy.defaults(),
              child: Center(
                  child: TickerMode(
                      enabled: ticker,
                      child: onlyRender
                          ? Stack(alignment: Alignment.center, children: [
                              RepaintBoundary(
                                  key: boundary, child: textNode(spacing)),
                              if (onlyRender)
                                Offstage(
                                    child: textNode(8,
                                        reduced: true, key: naturalTarget))
                            ])
                          : RepaintBoundary(
                              key: boundary, child: textNode(spacing))))));
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      final before = tester.getSize(find.byKey(boundary));
      final startInk = await _rgba(tester, boundary);
      _expectGlyphInk(startInk);
      if (vertical) {
        await capturePlaylistFeature(
            tester, boundary, 'spacing-motion-desktop-start');
      }
      spacing = 8;
      var spacingStart = Duration.zero;
      if (onlyRender) {
        spacingStart =
            await _pumpFrameStamp(tester, () => tester.pumpWidget(host()));
      } else {
        await tester.pumpWidget(host());
      }
      final identities = _desktop(tester).cachedShapingIdentities;
      expect(_desktop(tester).retainsPreviousLayout, isTrue);
      expect(tester.getSize(find.byKey(boundary)), before);
      final beforeRects = _desktop(tester).highlightRectsForWord(0);
      await tester.pump(const Duration(milliseconds: 90));
      final middle = tester.getSize(find.byKey(boundary));
      expect(vertical ? middle.height : middle.width,
          greaterThan(vertical ? before.height : before.width));
      expect(_desktop(tester).cachedShapingIdentities, identities);
      final middleInk = await _rgba(tester, boundary);
      _expectGlyphInk(middleInk);
      expect(middleInk, isNot(startInk));
      if (vertical) {
        await capturePlaylistFeature(
            tester, boundary, 'spacing-motion-desktop-mid');
      }
      if (vertical) {
        expect(_desktop(tester).highlightRectsForWord(0).last.top,
            greaterThan(beforeRects.last.top));
      }
      spacing = 2;
      if (onlyRender) {
        final frame =
            await _pumpFrameStamp(tester, () => tester.pumpWidget(host()));
        final targetSize =
            tester.getSize(find.byKey(naturalTarget, skipOffstage: false));
        // Desktop spacing retains its 480ms lyric clock and existing curve.
        // Only the main player's target-group entrance uses the shorter tier.
        final elapsed = (frame - spacingStart).inMicroseconds /
            AppMotion.lyricLine.inMicroseconds;
        final expected = Size.lerp(before, targetSize,
            LyricMotion.curve.transform(elapsed.clamp(0.0, 1.0)))!;
        final actual = tester.getSize(find.byKey(boundary));
        expect(actual.width, closeTo(expected.width, .05));
        expect(actual.height, closeTo(expected.height, .05));
      } else {
        await tester.pumpWidget(host());
        expect(tester.getSize(find.byKey(boundary)), middle);
      }
      await tester.pumpAndSettle();
      expect(_desktop(tester).retainsPreviousLayout, isFalse);
      _expectGlyphInk(await _rgba(tester, boundary));
      expect(_desktop(tester).progressForWord(0), closeTo(.3875, .0001));
      if (vertical) {
        await capturePlaylistFeature(
            tester, boundary, 'spacing-motion-desktop-end');
      }
      expect(_desktop(tester).glyphs.map((glyph) => glyph.text).join(),
          vertical ? text : '');
      spacing = 7;
      await tester.pumpWidget(host());
      await tester.pump(const Duration(milliseconds: 32));
      await tester.pumpWidget(host(ticker: false));
      await tester.pump();
      expect(_desktop(tester).retainsPreviousLayout, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  if (!onlyRender) {
    for (final gate in ['lifecycle', 'native reduce']) {
      testWidgets('spacing desktop $gate stops and releases its old endpoint',
          (tester) async {
        final clock = PlaybackClock(automaticTicks: false);
        addTearDown(clock.dispose);
        var spacing = 0.0;
        Widget host() => MaterialApp(
            home: AppFontScope(
                policy: AppFontPolicy.defaults(),
                child: Center(
                    child: DesktopLyricText(
                        text: _text,
                        clock: clock,
                        verticalLetterSpacing: spacing,
                        style: TextStyle(fontSize: 22, letterSpacing: spacing),
                        playedColor: Colors.blue,
                        unplayedColor: Colors.red))));
        await tester.pumpWidget(host());
        spacing = 8;
        await tester.pumpWidget(host());
        await tester.pump(const Duration(milliseconds: 32));
        expect(_desktop(tester).retainsPreviousLayout, isTrue);
        if (gate == 'lifecycle') {
          addTearDown(() => tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        } else {
          addTearDown(
              tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(reduceMotion: true);
        }
        await tester.pump();
        expect(_desktop(tester).retainsPreviousLayout, isFalse);
        expect(_desktop(tester).cachedShapingIdentities, hasLength(2));
        expect(tester.binding.transientCallbackCount, 0);
        await tester.pump(const Duration(seconds: 1));
        expect(tester.binding.transientCallbackCount, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
    testWidgets('spacing-only duration cannot shorten later lyric focus motion',
        (tester) async {
      var spacing = 0.0, activation = 0.0;
      var transition = (
        fromFontSize: 22.0,
        toFontSize: 22.0,
        fromTranslationFontSize: 18.0,
        toTranslationFontSize: 18.0,
        progress: 1.0,
        visualProgress: 1.0,
        fromLetterSpacing: 0.0,
        toLetterSpacing: 0.0
      );
      Widget host() => MaterialApp(
          home: LyricLineMotion(
              opacity: 1,
              scale: 1,
              activation: activation,
              alignment: Alignment.center,
              presentation: (
                fontSize: 22,
                translationFontSize: 18,
                alignment: Alignment.center
              ),
              letterSpacing: spacing,
              reducedMotion: false,
              builder: (_, __, ___, current) {
                transition = current;
                return const SizedBox(width: 20, height: 20);
              }));
      await tester.pumpWidget(host());
      spacing = 6;
      await tester.pumpWidget(host());
      await tester
          .pump(LyricMotion.lineDuration + const Duration(milliseconds: 1));
      expect(transition.visualProgress, 1);
      activation = 1;
      await tester.pumpWidget(host());
      await tester.pump(const Duration(milliseconds: 181));
      expect(transition.visualProgress, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(transition.visualProgress, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.binding.transientCallbackCount, 0);
    });
  }
}
