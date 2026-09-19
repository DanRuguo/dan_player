import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/brand_logo.dart';
import 'package:dan_player/component/startup_splash.dart';
import 'package:dan_player/component/ui_layout_options.dart';
import 'package:dan_player/startup_progress.dart';
import 'package:dan_player/ui_layout_preferences.dart';
import 'package:desktop_lyric/l10n/catalog_startup_progress.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child,
        {Brightness brightness = Brightness.light,
        MotionPreferences motion = const MotionPreferences()}) =>
    UiLanguageScope(
      child: MaterialApp(
        theme: ThemeData(
          fontFamily: danEmbeddedFontFamily,
          fontFamilyFallback: danFontFamilyFallback,
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal, brightness: brightness),
        ),
        home: MotionPreferencesScope(preferences: motion, child: child),
      ),
    );

StartupProgress loading() => StartupProgress()
  ..begin()
  ..advance(StartupStage.checkingLibrary);

class _ObservedProgress extends StartupProgress {
  int observers = 0;
  @override
  void addListener(VoidCallback listener) {
    observers++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    observers--;
    super.removeListener(listener);
  }
}

void main() {
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final korean = File('C:/Windows/Fonts/malgun.ttf');
    if (await korean.exists()) {
      await (FontLoader('Malgun Gothic')
            ..addFont(
                Future.value(ByteData.sublistView(await korean.readAsBytes()))))
          .load();
    }
  });
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  test('startup footer defaults safely and survives settings backup roundtrip',
      () {
    for (final old in [
      null,
      {},
      {'startupFooter': 'future'},
      {'startupFooter': 1}
    ]) {
      expect(
          UiLayoutPreferences.fromMap(old).startupFooter, StartupFooter.brand);
    }
    const preferences = UiLayoutPreferences(
        compactPlaylists: false,
        libraryRowLayout: LibraryRowLayout.columns,
        startupFooter: StartupFooter.progress);
    expect(UiLayoutPreferences.fromMap(preferences.toMap()), preferences);
    expect(preferences.copyWith(compactPlaylists: true).startupFooter,
        StartupFooter.progress);
  });

  test('only real stages advance progress and scan messages stay bounded', () {
    final progress = loading();
    addTearDown(progress.dispose);
    var changes = 0;
    progress.addListener(() => changes++);
    for (var i = 0; i <= 10000; i++) {
      progress.scan(i / 10000);
    }
    expect(changes, lessThanOrEqualTo(200));
    expect(progress.value.progress, closeTo(.64, .004));
    progress.advance(StartupStage.playback);
    progress.advance(StartupStage.loadingLibrary);
    progress.scan(double.nan);
    expect(progress.value.stage, StartupStage.playback);
    expect(progress.value.ready, isFalse);
    progress.advance(StartupStage.ready);
    expect(progress.value.progress, 1);
    expect(progress.value.label, '等待开屏动画结束');
  });

  testWidgets('early readiness reaches 100 percent and waits until 1250 ms',
      (tester) async {
    final progress = loading();
    addTearDown(progress.dispose);
    await tester.pumpWidget(host(StartupSplash(
        progress: progress, showProgress: true, child: const Text('Player'))));
    await tester.pump(const Duration(milliseconds: 300));
    progress.advance(StartupStage.ready);
    await tester.pump();
    expect(find.text('等待开屏动画结束'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byKey(StartupSplash.progressKey))
            .value,
        1);
    expect(find.byKey(StartupSplash.playerSignatureKey), findsNothing);
    await tester.pump(const Duration(milliseconds: 949));
    expect(find.byKey(StartupSplash.overlayKey), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(StartupSplash.overlayKey), findsNothing);
  });

  testWidgets('slow startup holds opaque final brand without idle frames',
      (tester) async {
    final progress = loading();
    addTearDown(progress.dispose);
    await tester.pumpWidget(host(StartupSplash(
        progress: progress, showProgress: true, child: const Text('Player'))));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(StartupSplash.overlayKey), findsOneWidget);
    expect(
        tester
            .widget<Opacity>(find.byKey(StartupSplash.danRuguoOpacityKey))
            .opacity,
        1);
    expect(
        tester
            .widget<Opacity>(find
                .ancestor(
                    of: find.byKey(StartupSplash.surfaceKey),
                    matching: find.byType(Opacity))
                .first)
            .opacity,
        1);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    progress.advance(StartupStage.ready);
    await tester.pump();
    expect(find.byKey(StartupSplash.overlayKey), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('late readiness starts the fade continuously without a jump',
      (tester) async {
    final progress = loading();
    addTearDown(progress.dispose);
    await tester.pumpWidget(host(StartupSplash(
        progress: progress, showProgress: true, child: const Text('Player'))));
    await tester.pump(const Duration(milliseconds: 1100));
    progress.advance(StartupStage.ready);
    await tester.pump();
    double opacity() => tester
        .widget<Opacity>(find
            .ancestor(
                of: find.byKey(StartupSplash.surfaceKey),
                matching: find.byType(Opacity))
            .first)
        .opacity;
    expect(opacity(), 1);
    await tester.pump(const Duration(milliseconds: 75));
    expect(opacity(), allOf(greaterThan(0), lessThan(1)));
    await tester.pump(const Duration(milliseconds: 75));
    expect(find.byKey(StartupSplash.overlayKey), findsNothing);
  });

  testWidgets('loading failure immediately exposes recovery instead of hanging',
      (tester) async {
    final progress = loading();
    addTearDown(progress.dispose);
    await tester.pumpWidget(host(StartupSplash(
        progress: progress,
        showProgress: true,
        child: const Text('Recovery'))));
    progress.fail();
    await tester.pump();
    expect(find.byKey(StartupSplash.overlayKey), findsNothing);
    expect(find.text('Recovery').hitTestable(), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('disabled startup leaves normal loading visible without a timer',
      (tester) async {
    final progress = loading();
    addTearDown(progress.dispose);
    await tester.pumpWidget(host(
      StartupSplash(
          progress: progress,
          showProgress: true,
          child: const Text('Normal loading')),
      motion: const MotionPreferences(disabled: {MotionKind.startup}),
    ));
    expect(find.byKey(StartupSplash.overlayKey), findsNothing);
    expect(find.text('Normal loading').hitTestable(), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('slow native scan remains cancellable from the loading footer',
      (tester) async {
    final progress = loading();
    addTearDown(progress.dispose);
    var cancelled = false;
    progress.scan(.5, cancel: () => cancelled = true);
    await tester.pumpWidget(host(StartupSplash(
        progress: progress, showProgress: true, child: const Text('Player'))));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('取消扫描'));
    expect(cancelled, isTrue);
    progress.scan(.5, cancelling: true);
    await tester.pump();
    expect(find.text('正在取消扫描'), findsNWidgets(2));
    progress.advance(StartupStage.ready);
    await tester.pump();
    expect(find.byKey(StartupSplash.overlayKey), findsNothing);
  });

  testWidgets('closing a held startup detaches progress and cancels its clock',
      (tester) async {
    final progress = _ObservedProgress()..begin();
    addTearDown(progress.dispose);
    await tester.pumpWidget(host(StartupSplash(
        progress: progress, showProgress: true, child: const Text('Player'))));
    await tester.pump(const Duration(seconds: 2));
    expect(progress.observers, 1);
    await tester.pumpWidget(const SizedBox());
    expect(progress.observers, 0);
    progress.fail();
    await tester.pump(const Duration(seconds: 5));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('four languages fit narrow startup footer and themed settings',
      (tester) async {
    final output = Platform.environment['DAN_STARTUP_RENDER_DIR'];
    tester.view.resetPhysicalSize();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(580, 420);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<void> render(String name) async {
      if (output == null) return;
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('render')));
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes =
            await image.toByteData(format: raster.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File('$output/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      for (final entry in catalogStartupProgress.entries) {
        if (language != UiLanguage.zh) {
          expect(translateUi(entry.key, language), isNot(entry.key));
        }
      }
      for (final brightness in Brightness.values) {
        final progress = loading();
        await tester.pumpWidget(host(
            RepaintBoundary(
                key: const ValueKey('render'),
                child: StartupSplash(
                    key: UniqueKey(),
                    progress: progress,
                    showProgress: true,
                    child: const SizedBox())),
            brightness: brightness));
        await tester.runAsync(() async {
          final context = tester.element(find.byType(StartupSplash));
          for (final brand in AppBrand.values) {
            await precacheImage(
                AssetImage(BrandLogo.assetFor(brand, brightness)), context);
          }
        });
        await tester.pump(const Duration(milliseconds: 1300));
        await render('${language.code}-${brightness.name}-loading');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        progress.dispose();
      }
      var preferences = const UiLayoutPreferences();
      await tester.pumpWidget(host(RepaintBoundary(
        key: const ValueKey('render'),
        child: Scaffold(
            body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: StatefulBuilder(
              builder: (context, setState) => UiLayoutOptions(
                    value: preferences,
                    onChanged: (value) => setState(() => preferences = value),
                  )),
        )),
      )));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(ui('加载进度')));
      await tester.tap(find.text(ui('加载进度')));
      await tester.pumpAndSettle();
      expect(preferences.startupFooter, StartupFooter.progress);
      await render('${language.code}-settings');
      expect(tester.takeException(), isNull);
    }
  });
}
