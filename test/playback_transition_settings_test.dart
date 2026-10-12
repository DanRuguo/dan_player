import 'dart:io';
import 'dart:ui' as ui;
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/page/settings_page/playback_transition_settings.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_transition_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/playlist_feature_fixture.dart';

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  tearDown(() => uiLanguage.value = UiLanguage.zh);
  test(
      'transition preferences keep old profiles safe and sanitize damaged fields',
      () {
    for (final value in [
      null,
      true,
      'crossfade',
      {},
      {'mode': 'unknown'}
    ]) {
      expect(PlaybackTransitionPreferences.fromJson(value).enabled, isFalse);
    }
    for (final value in [double.nan, double.infinity, 'bad', null]) {
      expect(
          PlaybackTransitionPreferences.fromJson(
                  {'mode': 'crossfade', 'crossfadeSeconds': value})
              .crossfadeSeconds,
          3);
    }
    expect(PlaybackTransitionPreferences.safeSeconds(-100), .5);
    expect(PlaybackTransitionPreferences.safeSeconds(200), 12);
    const preference = PlaybackTransitionPreferences(
        mode: PlaybackTransitionMode.crossfade, crossfadeSeconds: 1.5);
    expect(PlaybackTransitionPreferences.fromJson(preference.toJson()),
        preference);
  });

  Future<void> mount(WidgetTester tester, Widget child, GlobalKey boundary,
      {double width = 1000, double scale = 1}) async {
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: applyAppControlTheme(ThemeData(
            fontFamily: danEmbeddedFontFamily,
            fontFamilyFallback: danFontFamilyFallback,
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal))),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale), disableAnimations: true),
            child: child!),
        home: Scaffold(
            body: RepaintBoundary(
                key: boundary,
                child: SingleChildScrollView(
                    child: Padding(
                        padding: const EdgeInsets.all(16), child: child))))));
    await tester.pumpAndSettle();
  }

  for (final language in UiLanguage.values) {
    for (final size in [(1000.0, 1.0), (360.0, 2.0)]) {
      testWidgets(
          'transition choices and long text ${language.code} ${size.$1} ${size.$2}',
          (tester) async {
        uiLanguage.value = language;
        final preference = ValueNotifier(const PlaybackTransitionPreferences(
            mode: PlaybackTransitionMode.crossfade));
        addTearDown(preference.dispose);
        final boundary = GlobalKey();
        await mount(
            tester,
            PlaybackTransitionSettings(
                preferences: preference, persist: () async {}),
            boundary,
            width: size.$1,
            scale: size.$2);
        expect(tester.takeException(), isNull);
        expect(
            find.text(uiLanguage.value == UiLanguage.zh
                ? '交叉淡入淡出'
                : translateUi('交叉淡入淡出', language)),
            findsOneWidget);
        final slider = find.byKey(const ValueKey('playback-crossfade-seconds'));
        await tester.ensureVisible(slider);
        await tester.pumpAndSettle();
        expect(slider.hitTestable(), findsOneWidget);
        expect(PlayService.isInitialized, isFalse);
        final output = Platform.environment['DAN_TRANSITION_RENDER_DIR'];
        if (output != null) {
          expect(
              output
                  .replaceAll('\\', '/')
                  .contains('/tool/qa-local/selection-folders-oct11/'),
              isTrue);
          await tester.drag(
              find.byType(SingleChildScrollView), const Offset(0, 1500));
          await tester.pumpAndSettle();
          final render = boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final picture = await render.toImage();
            final bytes =
                await picture.toByteData(format: ui.ImageByteFormat.png);
            picture.dispose();
            final directory = Directory(output)..createSync(recursive: true);
            await File(
                    '${directory.path}/transitions-${language.code}-${size.$1.toInt()}-${size.$2.toInt()}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          });
        }
      });
    }
  }

  testWidgets(
      'a failed preference save is retryable without constructing playback',
      (tester) async {
    uiLanguage.value = UiLanguage.zh;
    final preferences = ValueNotifier(const PlaybackTransitionPreferences());
    addTearDown(preferences.dispose);
    var saves = 0;
    await mount(
        tester,
        PlaybackTransitionSettings(
            preferences: preferences,
            persist: () async {
              if (++saves == 1) {
                throw const FileSystemException('fixture save failure');
              }
            }),
        GlobalKey());
    await tester.tap(find.text('常规切换').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('交叉淡入淡出').hitTestable());
    await tester.pumpAndSettle();
    expect(preferences.value.mode, PlaybackTransitionMode.crossfade);
    expect(find.text('设置保存失败，请重试'), findsOneWidget);
    await tester.tap(find.text('重试保存'));
    await tester.pumpAndSettle();
    expect(saves, 2);
    expect(find.text('设置保存失败，请重试'), findsNothing);
    expect(PlayService.isInitialized, isFalse);
  });

  for (final outcome in ['release', 'cancel', 'external']) {
    testWidgets('crossfade thumb $outcome retains one preference owner',
        (tester) async {
      final preferences = ValueNotifier(const PlaybackTransitionPreferences(
          mode: PlaybackTransitionMode.crossfade));
      addTearDown(preferences.dispose);
      var saves = 0;
      await mount(
          tester,
          PlaybackTransitionSettings(
              preferences: preferences,
              persist: () async {
                saves++;
              }),
          GlobalKey());
      final slider = find.byKey(const ValueKey('playback-crossfade-seconds'));
      final gesture = await tester.startGesture(tester.getCenter(slider));
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();
      expect(preferences.value.crossfadeSeconds, 3);
      expect(saves, 0);
      if (outcome == 'external') {
        preferences.value = preferences.value.copyWith(crossfadeSeconds: 5);
        await tester.pump();
      }
      if (outcome == 'cancel') {
        await gesture.cancel();
      } else {
        await gesture.up();
      }
      await tester.pumpAndSettle();
      expect(saves, outcome == 'release' ? 1 : 0);
      if (outcome != 'release') {
        expect(
            preferences.value.crossfadeSeconds, outcome == 'external' ? 5 : 3);
      } else {
        expect(preferences.value.crossfadeSeconds, greaterThan(3));
      }
      expect(PlayService.isInitialized, isFalse);
    });
  }

  testWidgets('crossfade vertical scroll arena cancellation discards draft',
      (tester) async {
    final preferences = ValueNotifier(const PlaybackTransitionPreferences(
        mode: PlaybackTransitionMode.crossfade));
    addTearDown(preferences.dispose);
    var saves = 0;
    await mount(
        tester,
        Column(children: [
          PlaybackTransitionSettings(
              preferences: preferences,
              persist: () async {
                saves++;
              }),
          const SizedBox(height: 1800),
        ]),
        GlobalKey());
    final slider = find.byKey(const ValueKey('playback-crossfade-seconds'));
    final scroll = tester.state<ScrollableState>(
        find.ancestor(of: slider, matching: find.byType(Scrollable)));
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    final gesture = await tester.startGesture(tester.getCenter(slider));
    var released = false;
    try {
      // Tap-down publishes a preview before either recognizer wins the arena.
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.widget<Slider>(slider).value, greaterThan(3));
      expect(preferences.value.crossfadeSeconds, 3);
      expect(saves, 0);
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      expect(scroll.position.pixels, greaterThan(0),
          reason: 'The real parent vertical scroll must win the arena.');
      expect(saves, 0,
          reason: 'Slider arena cancellation is not a physical release.');
      expect(preferences.value.crossfadeSeconds, 3);
      await gesture.up();
      released = true;
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(preferences.value.crossfadeSeconds, 3);
      expect(tester.widget<Slider>(slider).value, 3);
      expect(PlayService.isInitialized, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      if (!released) {
        await gesture.cancel();
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('crossfade held pointer retires before settings disposal',
      (tester) async {
    final preferences = ValueNotifier(const PlaybackTransitionPreferences(
        mode: PlaybackTransitionMode.crossfade));
    addTearDown(preferences.dispose);
    var saves = 0;
    await mount(
        tester,
        PlaybackTransitionSettings(
            preferences: preferences,
            persist: () async {
              saves++;
            }),
        GlobalKey());
    final slider = find.byKey(const ValueKey('playback-crossfade-seconds'));
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, greaterThan(3));
    expect(saves, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    // Cancellation still follows the real down hit path after unmounting.
    await gesture.cancel();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(saves, 0);
    expect(preferences.value.crossfadeSeconds, 3);
    expect(PlayService.isInitialized, isFalse);
  });

  testWidgets('crossfade pending touch retains ownership through semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    SemanticsNode adjustmentNode(Finder slider, SemanticsAction action) {
      SemanticsNode? result;
      void visit(SemanticsNode node) {
        if (node.getSemanticsData().hasAction(action)) {
          result = node;
          return;
        }
        node.visitChildren((child) {
          visit(child);
          return result == null;
        });
      }

      visit(tester.getSemantics(slider));
      expect(result, isNotNull,
          reason: 'Use the actual Slider semantics node.');
      return result!;
    }

    try {
      for (final action in [
        SemanticsAction.increase,
        SemanticsAction.decrease
      ]) {
        final preferences = ValueNotifier(const PlaybackTransitionPreferences(
            mode: PlaybackTransitionMode.crossfade));
        addTearDown(preferences.dispose);
        var saves = 0;
        await mount(
            tester,
            Column(children: [
              PlaybackTransitionSettings(
                  preferences: preferences,
                  persist: () async {
                    saves++;
                  }),
              const SizedBox(height: 1800),
            ]),
            GlobalKey());
        final slider = find.byKey(const ValueKey('playback-crossfade-seconds'));
        final gesture = await tester.startGesture(tester.getCenter(slider));
        var released = false;
        try {
          await tester.pump();
          expect(tester.widget<Slider>(slider).value, 3,
              reason: 'The scroll arena has not accepted Slider start yet.');
          final node = adjustmentNode(slider, action);
          node.owner!.performAction(node.id, action);
          await tester.pump();
          expect(saves, 0, reason: action.name);
          expect(preferences.value.crossfadeSeconds, 3, reason: action.name);
          expect(tester.widget<Slider>(slider).value, 3, reason: action.name);
          await gesture.moveBy(const Offset(80, 0));
          await tester.pump();
          final preview = tester.widget<Slider>(slider).value;
          expect(preview, greaterThan(3),
              reason: 'The pending primary touch must still start its draft.');
          expect(saves, 0);
          await gesture.up();
          released = true;
          await tester.pumpAndSettle();
          expect(saves, 1);
          expect(preferences.value.crossfadeSeconds, preview);
          final idle = adjustmentNode(slider, action);
          idle.owner!.performAction(idle.id, action);
          await tester.pumpAndSettle();
          expect(saves, 2,
              reason: 'Idle semantics must remain usable after touch release.');
          expect(
              preferences.value.crossfadeSeconds,
              action == SemanticsAction.increase
                  ? greaterThan(preview)
                  : lessThan(preview));
          expect(PlayService.isInitialized, isFalse);
          expect(tester.takeException(), isNull);
        } finally {
          if (!released) {
            await gesture.cancel();
          }
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('crossfade replacement rejects semantics until primary release',
      (tester) async {
    final original = ValueNotifier(const PlaybackTransitionPreferences(
        mode: PlaybackTransitionMode.crossfade));
    final replacement = ValueNotifier(const PlaybackTransitionPreferences(
        mode: PlaybackTransitionMode.crossfade, crossfadeSeconds: 7));
    final owner = ValueNotifier(original);
    addTearDown(original.dispose);
    addTearDown(replacement.dispose);
    addTearDown(owner.dispose);
    final saves = <ValueNotifier<PlaybackTransitionPreferences>>[];
    final semantics = tester.ensureSemantics();
    await mount(
        tester,
        Column(children: [
          ValueListenableBuilder(
              valueListenable: owner,
              builder: (_, preferences, __) => PlaybackTransitionSettings(
                  preferences: preferences,
                  persist: () async {
                    saves.add(preferences);
                  })),
          const SizedBox(height: 1800),
        ]),
        GlobalKey());
    final slider = find.byKey(const ValueKey('playback-crossfade-seconds'));
    SemanticsNode adjustmentNode() {
      SemanticsNode? result;
      void visit(SemanticsNode node) {
        if (node.getSemanticsData().hasAction(SemanticsAction.decrease)) {
          result = node;
          return;
        }
        node.visitChildren((child) {
          visit(child);
          return result == null;
        });
      }

      visit(tester.getSemantics(slider));
      expect(result, isNotNull,
          reason: 'Use the actual Slider semantics node.');
      return result!;
    }

    final gesture = await tester.startGesture(tester.getCenter(slider));
    var released = false;
    try {
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();
      expect(tester.widget<Slider>(slider).value, greaterThan(3));
      expect(saves, isEmpty);
      owner.value = replacement;
      await tester.pump();
      expect(tester.widget<Slider>(slider).value, 7);
      final node = adjustmentNode();
      node.owner!.performAction(node.id, SemanticsAction.decrease);
      await tester.pump();
      expect(saves, isEmpty,
          reason: 'Replacing preferences does not release the held pointer.');
      expect(original.value.crossfadeSeconds, 3);
      expect(replacement.value.crossfadeSeconds, 7);
      expect(tester.widget<Slider>(slider).value, 7);
      await gesture.up();
      released = true;
      await tester.pumpAndSettle();
      expect(saves, isEmpty);
      expect(original.value.crossfadeSeconds, 3);
      expect(replacement.value.crossfadeSeconds, 7);
      final fresh = await tester.startGesture(tester.getCenter(slider));
      await fresh.moveBy(const Offset(80, 0));
      await tester.pump();
      final preview = tester.widget<Slider>(slider).value;
      expect(preview, greaterThan(7));
      await fresh.up();
      await tester.pumpAndSettle();
      expect(saves, [replacement]);
      expect(replacement.value.crossfadeSeconds, preview);
      final idle = adjustmentNode();
      idle.owner!.performAction(idle.id, SemanticsAction.decrease);
      await tester.pumpAndSettle();
      expect(saves, [replacement, replacement]);
      expect(replacement.value.crossfadeSeconds, lessThan(preview));
      expect(PlayService.isInitialized, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      if (!released) {
        await gesture.cancel();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
    }
  });
}
