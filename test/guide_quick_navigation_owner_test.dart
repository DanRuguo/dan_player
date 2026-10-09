import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/player_feature_guide.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playlist_feature_fixture.dart';

Finder _key(String key) => find.byKey(ValueKey(key));
Finder _header(String id) => find
    .descendant(of: _key('guide-section-$id'), matching: find.byType(ListTile))
    .first;

class _Scene {
  final hidden = ValueNotifier(false);

  ScrollController scroll(WidgetTester tester) => tester
      .widget<SingleChildScrollView>(_key('player-feature-guide-scroll'))
      .controller!;

  Rect viewport(WidgetTester tester) =>
      tester.getRect(_key('player-feature-guide-scroll'));

  Future<void> mount(WidgetTester tester,
      {double width = 1080, double scale = 1, bool disabled = false}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(hidden.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
            platform: TargetPlatform.windows,
            fontFamily: danEmbeddedFontFamily,
            fontFamilyFallback: danFontFamilyFallback),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                disableAnimations: disabled,
                textScaler: TextScaler.linear(scale)),
            child: child!),
        home: Scaffold(body: PlayerFeatureGuideDialog(demoIsHidden: hidden))));
    await tester.pumpAndSettle();
  }

  Future<void> begin(WidgetTester tester, {int gap = 0}) async {
    final queue = _key('guide-common-queue');
    final lyrics = _key('guide-common-lyrics');
    expect(queue.hitTestable(), findsOneWidget);
    expect(lyrics.hitTestable(), findsOneWidget);
    await tester.tap(queue);
    if (gap > 0) {
      // The first navigation already scrolls the quick controls offscreen.
      // A pointer held on the next real control still delivers its release
      // after that first expansion/layout frame.
      final press = await tester.startGesture(tester.getCenter(lyrics));
      await tester.pump(Duration(milliseconds: gap));
      await press.up();
    } else {
      await tester.tap(lyrics);
    }
    await tester.pump();
    for (final id in ['queue', 'lyrics']) {
      expect(
          tester
              .widget<ExpansionTile>(_key('guide-section-$id'))
              .controller!
              .isExpanded,
          isTrue);
    }
  }

  void expectLatestVisible(WidgetTester tester) {
    final header = tester.getRect(_header('lyrics'));
    final view = viewport(tester);
    expect(header.top, greaterThanOrEqualTo(view.top - .5));
    expect(header.bottom, lessThanOrEqualTo(view.bottom + .5));
    expect(_header('lyrics').hitTestable(), findsOneWidget);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  }
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);

  for (final gap in [0, 18]) {
    testWidgets(
        'latest common topic stays visible after normal expansion gap=$gap',
        (tester) async {
      final scene = _Scene();
      await scene.mount(tester);
      await scene.begin(tester, gap: gap);
      await tester.pumpAndSettle();
      scene.expectLatestVisible(tester);
      expect(tester.binding.transientCallbackCount, 0);
      await scene.close(tester);
    });
  }

  testWidgets('normal quick-navigation finish has intermediate offset frames',
      (tester) async {
    final scene = _Scene();
    await scene.mount(tester);
    await scene.begin(tester);
    final samples = <double>[];
    for (var frame = 0; frame < 28; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      samples.add(scene.scroll(tester).offset);
    }
    // The original 180 ms scroll ends around frame 13. The residual 790 px
    // correction must contain real intermediate frames, not one final jump.
    final tail = samples.skip(12).toList();
    final steps = [
      for (var i = 1; i < tail.length; i++) tail[i] - tail[i - 1],
    ];
    expect(steps.where((step) => step > .1).length, greaterThanOrEqualTo(3));
    expect(steps.every((step) => step < scene.viewport(tester).height * .6),
        isTrue,
        reason: 'The final correction must not jump a viewport in one frame');
    scene.expectLatestVisible(tester);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await scene.close(tester);
  });

  testWidgets('narrow large-text normal navigation lands on the actual heading',
      (tester) async {
    final scene = _Scene();
    await scene.mount(tester, width: 420, scale: 1.5);
    await scene.begin(tester);
    await tester.pumpAndSettle();
    scene.expectLatestVisible(tester);
    await scene.close(tester);
  });

  for (final disabled in [false, true]) {
    testWidgets(
        'disabled=$disabled reduced navigation reaches idle final geometry',
        (tester) async {
      if (!disabled) {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(reduceMotion: true);
        addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      }
      final scene = _Scene();
      await scene.mount(tester, disabled: disabled);
      await scene.begin(tester);
      await tester.pumpAndSettle();
      scene.expectLatestVisible(tester);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await scene.close(tester);
    });
  }

  for (final input in ['wheel', 'touch', 'keyboard']) {
    testWidgets('$input scrolling retires the pending common-topic correction',
        (tester) async {
      final scene = _Scene();
      await scene.mount(tester);
      await scene.begin(tester);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 64));
      final before = scene.scroll(tester).offset;
      expect(before, greaterThan(200));
      if (input == 'wheel') {
        await tester.sendEventToBinding(PointerScrollEvent(
            kind: PointerDeviceKind.mouse,
            position: scene.viewport(tester).center,
            scrollDelta: const Offset(0, -200)));
      } else if (input == 'touch') {
        final gesture =
            await tester.startGesture(scene.viewport(tester).center);
        await gesture.moveBy(const Offset(0, 140));
        await gesture.up();
      } else {
        final focus = tester
            .widgetList<Focus>(find.descendant(
                of: _key('player-feature-guide-scroll'),
                matching: find.byType(Focus)))
            .firstWhere((widget) => widget.focusNode != null)
            .focusNode!;
        focus.requestFocus();
        await tester.pump();
        expect(focus.hasPrimaryFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      }
      await tester.pumpAndSettle();
      final interrupted = scene.scroll(tester).offset;
      expect(interrupted, lessThan(before - 40),
          reason: 'The input must actually scroll the production viewport');
      await tester.pump(const Duration(milliseconds: 500));
      expect(scene.scroll(tester).offset, interrupted);
      expect(_header('lyrics').hitTestable(), findsNothing,
          reason: 'The old quick action must not reclaim manual browsing');
      await scene.close(tester);
    });
  }

  testWidgets(
      'hiding during the short finishing scroll stops and never replays',
      (tester) async {
    final scene = _Scene();
    await scene.mount(tester);
    await scene.begin(tester);
    for (var frame = 0; frame < 15; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(scene.scroll(tester).position.isScrollingNotifier.value, isTrue);
    scene.hidden.value = true;
    await tester.pumpAndSettle();
    final stopped = scene.scroll(tester).offset;
    expect(scene.scroll(tester).position.isScrollingNotifier.value, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
    scene.hidden.value = false;
    await tester.pump(const Duration(milliseconds: 400));
    expect(scene.scroll(tester).offset, stopped);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await scene.close(tester);
  });

  testWidgets('closing during a common-topic scroll retires its late follow-up',
      (tester) async {
    final scene = _Scene();
    await scene.mount(tester);
    await scene.begin(tester);
    await tester.pump(const Duration(milliseconds: 32));
    await scene.close(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('contents keyboard navigation owns the settled chapter geometry',
      (tester) async {
    final scene = _Scene();
    await scene.mount(tester);
    await scene.begin(tester);
    await tester.pump(const Duration(milliseconds: 32));
    // Focus the actual contents control without sending a key or pointer event
    // that would retire the quick navigation before its own activation.
    final contents = _key('guide-jump-input-tools');
    final focus = Focus.of(tester.element(
        find.descendant(of: contents, matching: find.byType(Text)).first));
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final chapter = _key('guide-chapter-input-tools');
    expect(chapter.hitTestable(), findsOneWidget);
    final header = tester.getRect(chapter);
    expect(header.top, greaterThanOrEqualTo(scene.viewport(tester).top - .5));
    expect(
        header.bottom, lessThanOrEqualTo(scene.viewport(tester).bottom + .5));
    expect(_header('lyrics').hitTestable(), findsNothing);
    final finalOffset = scene.scroll(tester).offset;
    await tester.pump(const Duration(milliseconds: 400));
    expect(scene.scroll(tester).offset, finalOffset);
    await scene.close(tester);
  });
}
