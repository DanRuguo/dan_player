import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/player_feature_guide.dart';
import 'package:dan_player/component/player_guide_demo.dart';
import 'package:dan_player/component/playlist_cover_transition.dart';
import 'package:dan_player/component/viewport_visibility.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playlist_feature_fixture.dart';

Finder _header(String id) => find
    .descendant(
        of: find.byKey(ValueKey('guide-section-$id')),
        matching: find.byType(ListTile))
    .first;

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  for (final scenario in [
    (PlayerGuideDemoKind.progress, 'queue', 1400.0, 'guide-demo-seek-forward'),
    (PlayerGuideDemoKind.lyrics, 'lyrics', 1800.0, 'guide-demo-highlight'),
  ]) {
    testWidgets(
        'real preceding chapter expansion retires ${scenario.$1.name} demo',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(1080, scenario.$3);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final hidden = ValueNotifier(false);
      addTearDown(hidden.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: applyAppControlTheme(ThemeData(
            useMaterial3: true,
            platform: TargetPlatform.windows,
            fontFamily: danEmbeddedFontFamily,
            fontFamilyFallback: danFontFamilyFallback)),
        home: Scaffold(body: PlayerFeatureGuideDialog(demoIsHidden: hidden)),
      ));
      await tester.pumpAndSettle();
      await tester.tap(_header('getting-started'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_header('playlists'));
      await tester.pumpAndSettle();
      await tester.tap(_header('playlists'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_header(scenario.$2));
      await tester.pumpAndSettle();
      await tester.tap(_header(scenario.$2));
      await tester.pumpAndSettle();
      final scroll = tester
          .state<ScrollableState>(find
              .descendant(
                  of: find.byKey(const ValueKey('player-feature-guide-scroll')),
                  matching: find.byType(Scrollable))
              .first)
          .position;
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      final demo = find.byWidgetPredicate(
          (widget) => widget is PlayerGuideDemo && widget.kind == scenario.$1);
      final surface =
          find.descendant(of: demo, matching: find.byType(DecoratedBox)).first;
      final trigger = find.byKey(ValueKey(scenario.$4));
      final clock = tester
          .widget<AnimatedBuilder>(find
              .descendant(of: demo, matching: find.byType(AnimatedBuilder))
              .first)
          .animation as AnimationController;
      final screen = Size(1080, scenario.$3);
      expect(_header('getting-started').hitTestable(), findsOneWidget);
      expect(trigger.hitTestable(), findsOneWidget);
      expect(intersectsPaintViewport(tester.renderObject(surface), screen),
          isTrue);
      await tester.tap(trigger);
      await tester.pump();
      expect(clock.isAnimating, isTrue);
      final terminal =
          scenario.$1 == PlayerGuideDemoKind.progress ? .32 + 10 / 180 : 1.0;

      // The ordinary chapter only rebuilds its own ExpansionTile. Neither
      // the retained demo nor the guide's ScrollPosition changes here.
      final scrollOffset = scroll.pixels;
      await tester.tap(_header('getting-started'));
      await tester.pump();
      var leftViewport = false;
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (!intersectsPaintViewport(tester.renderObject(surface), screen)) {
          leftViewport = true;
          expect(clock.isAnimating, isFalse,
              reason: 'Fully clipped demos stop within that layout frame');
          expect(clock.value, closeTo(terminal, .000001));
          break;
        }
      }
      expect(leftViewport, isTrue,
          reason: 'The actual chapter must move the demo outside the clip');
      expect(scroll.pixels, scrollOffset);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);

      // Restoring geometry is passive. Only another deliberate input starts
      // the finite demonstration, and unmounting retires its pending check.
      await tester.tap(_header('getting-started'));
      await tester.pumpAndSettle();
      expect(trigger.hitTestable(), findsOneWidget);
      expect(clock.isAnimating, isFalse);
      expect(clock.value, closeTo(terminal, .000001));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.tap(trigger);
      await tester.pump();
      expect(clock.isAnimating, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      expect(PlayService.isInitialized, isFalse);
    });
  }

  for (final layoutDisabled in [false, true]) {
    testWidgets(
        'real chapter layout retires playlist demo layoutDisabled=$layoutDisabled',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1080, 1660);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final hidden = ValueNotifier(false);
      addTearDown(hidden.dispose);
      await tester.pumpWidget(MaterialApp(
          theme: applyAppControlTheme(ThemeData(
              useMaterial3: true,
              platform: TargetPlatform.windows,
              fontFamily: danEmbeddedFontFamily,
              fontFamilyFallback: danFontFamilyFallback)),
          builder: (context, child) => MotionPreferencesScope(
              preferences: MotionPreferences(
                  disabled: layoutDisabled ? {MotionKind.layout} : {}),
              child: child!),
          home: Builder(
              builder: (context) => Scaffold(
                      body: TextButton(
                    onPressed: () => showAppDialog<void>(
                        context: context,
                        builder: (_) =>
                            PlayerFeatureGuideDialog(demoIsHidden: hidden)),
                    child: const Text('Open isolated guide'),
                  )))));
      await tester.tap(find.text('Open isolated guide'));
      await tester.pumpAndSettle();
      await tester.tap(_header('getting-started'));
      await tester.pumpAndSettle();
      final scroll = tester
          .state<ScrollableState>(find
              .descendant(
                  of: find.byKey(const ValueKey('player-feature-guide-scroll')),
                  matching: find.byType(Scrollable))
              .first)
          .position;
      expect(scroll.pixels, 0);
      final body = find.byKey(const ValueKey('guide-demo-playlist-body'));
      final menu = find.byKey(const ValueKey('guide-demo-playlist-menu'));
      final host = find.byType(PlaylistCoverTransitionHost);
      final controller =
          tester.widget<PlaylistCoverTransitionHost>(host).controller;
      expect(_header('getting-started').hitTestable(), findsOneWidget);
      expect(menu.hitTestable(), findsOneWidget);
      // Collapsing the preceding chapter brought this retained demo into
      // view without scrolling; its actual tracking gate must refresh too.
      expect(TickerMode.valuesOf(tester.element(host)).enabled, isTrue);
      await tester.runAsync(() => precacheImage(
          const AssetImage('assets/images/RCE_logo_transparent.png'),
          tester.element(find.byType(PlayerGuideDemo)),
          onError: (error, stack) =>
              fail('Sample artwork decode failed: $error')));
      await tester.pumpAndSettle();
      Future<void> select(String mode) async {
        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tester
            .tap(find.byKey(ValueKey('guide-demo-playlist-select-$mode')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 35));
        await tester.pump(const Duration(milliseconds: 35));
        expect(controller.active, isTrue);
        expect(controller.debugSnapshotCount, 3);
      }

      await select('grid');
      await tester.tap(_header('getting-started'));
      await tester.pump();
      var clipped = false;
      for (var frame = 0; frame < 8; frame++) {
        if (!intersectsPaintViewport(
            tester.renderObject(body), const Size(1080, 1660))) {
          clipped = true;
          // Metrics may arrive after the layout frame. Their single queued
          // check then updates TickerMode on its normal following build.
          for (var check = 0; check < 2 && controller.active; check++) {
            await tester.pump();
          }
          expect(controller.active, isFalse);
          expect(controller.busy, isFalse);
          expect(controller.debugSnapshotCount, 0);
          break;
        }
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(clipped, isTrue,
          reason: 'Actual body after expansion: ${tester.getRect(body)}');
      expect(scroll.pixels, 0);
      expect(find.byKey(const ValueKey('guide-demo-playlist-layout-grid')),
          findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.tap(_header('getting-started'));
      await tester.pumpAndSettle();
      expect(menu.hitTestable(), findsOneWidget);
      expect(TickerMode.valuesOf(tester.element(host)).enabled, isTrue);
      expect(controller.active, isFalse);
      expect(controller.debugSnapshotCount, 0);
      await select('circular');
      await tester
          .tap(find.byKey(const ValueKey('close-player-feature-guide')));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerFeatureGuideDialog), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
      expect(PlayService.isInitialized, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
