import 'dart:async';
import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/font_preview_loader.dart';
import 'package:dan_player/page/settings_page/font_selector_dialog.dart';
import 'package:dan_player/src/rust/api/installed_font.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

InstalledFont font(int i) => InstalledFont(
    path: 'fixture-$i.ttf',
    fullName: 'Typeface ${i.toString().padLeft(3, '0')}');

void main() {
  test('preview loader shares work, limits concurrency and cancels unseen rows',
      () async {
    final started = <InstalledFont>[];
    final pending = <InstalledFont, Completer<void>>{};
    final loader = FontPreviewLoader(load: (font) {
      started.add(font);
      return (pending[font] = Completer<void>()).future;
    });
    final first = loader.acquire(font(0));
    final same = loader.acquire(font(0));
    final second = loader.acquire(font(1));
    final canceled = loader.acquire(font(2));
    final next = loader.acquire(font(3));
    await Future<void>.delayed(Duration.zero);
    expect(started, [font(0), font(1)]);
    canceled.release();
    expect(await canceled.family, isNull);
    pending[font(0)]!.complete();
    expect(await first.family, font(0).fullName);
    expect(await same.family, font(0).fullName);
    await Future<void>.delayed(Duration.zero);
    expect(started, [font(0), font(1), font(3)]);
    pending[font(1)]!.complete();
    pending[font(3)]!.complete();
    await Future.wait([second.family, next.family]);
    for (final lease in [first, same, second, next]) {
      lease.release();
    }
    final cached = loader.acquire(font(0));
    expect(await cached.family, font(0).fullName);
    expect(started, hasLength(3));
    cached.release();
  });

  test('failed preview can retry after the font becomes available', () async {
    var attempts = 0;
    final loader = FontPreviewLoader(load: (_) async {
      if (attempts++ == 0) throw const FileSystemException('fixture failure');
    });
    final failed = loader.acquire(font(0));
    expect(await failed.family, isNull);
    failed.release();
    final restored = loader.acquire(font(0));
    expect(await restored.family, font(0).fullName);
    restored.release();
  });

  test('automatic preview budget preserves explicitly selected fonts',
      () async {
    final loaded = <InstalledFont>[];
    final loader = FontPreviewLoader(
      load: (font) async => loaded.add(font),
      sizeOf: (_) async => 70,
      maximumAutomaticFonts: 2,
      maximumAutomaticBytes: 100,
    );
    final first = loader.acquire(font(0));
    expect(await first.family, font(0).fullName);
    final automatic = loader.acquire(font(1));
    expect(await automatic.family, isNull);
    expect(automatic.deferred, isTrue);
    final selected = loader.acquire(font(1), explicit: true);
    expect(await selected.family, font(1).fullName);
    final later = loader.acquire(font(2));
    expect(await later.family, isNull);
    expect(later.deferred, isTrue);
    expect(loaded, [font(0), font(1)]);
    for (final lease in [first, automatic, selected, later]) {
      lease.release();
    }
  });

  testWidgets(
      'font names use their own family; search and preview stage until apply',
      (tester) async {
    final loaded = <InstalledFont>[];
    final loader = FontPreviewLoader(load: (font) async => loaded.add(font));
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: SizedBox.expand())));
    final result = showDialog<InstalledFont>(
      context: navigator.currentContext!,
      builder: (_) => FontSelectorDialog(
        installedFont: List.generate(200, font),
        currentFont: font(0).fullName,
        loader: loader,
      ),
    );
    await tester.pumpAndSettle();
    expect(loaded, contains(font(0)));
    expect(loaded.length, lessThan(12),
        reason: 'Opening must not load the whole font collection');
    expect(find.text(ui('当前')), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('font-selector-search')), '199');
    await tester.pumpAndSettle();
    final row = find.byKey(ValueKey(('font-row', font(199))));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Text>(find.byKey(ValueKey(('font-name', font(199)))))
            .style!
            .fontFamily,
        font(199).fullName);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(FontSelectorDialog), findsOneWidget,
        reason: 'Selecting a row only changes the draft preview');
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('font-selector-preview')))
            .style!
            .fontFamily,
        font(199).fullName);
    await tester.tap(find.byKey(const ValueKey('font-selector-apply')));
    await tester.pumpAndSettle();
    expect(await result, font(199));
  });

  testWidgets(
      'empty search and load failures stay cancellable without choosing a font',
      (tester) async {
    final loader = FontPreviewLoader(
        load: (_) async => throw const FileSystemException('fixture failure'));
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: SizedBox.expand())));
    final result = showDialog<InstalledFont>(
        context: navigator.currentContext!,
        builder: (_) => FontSelectorDialog(
            installedFont: [font(0)],
            currentFont: font(0).fullName,
            loader: loader));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('font-selector-apply')))
            .onPressed,
        isNull);
    await tester.enterText(
        find.byKey(const ValueKey('font-selector-search')), 'missing');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(ui('没有匹配的字体')));
    await tester.pumpAndSettle();
    expect(find.text(ui('没有匹配的字体')), findsOneWidget);
    await tester.tap(find.text(ui('取消')));
    await tester.pumpAndSettle();
    expect(await result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'budget-deferred names retain their own font after selecting another',
      (tester) async {
    final loader =
        FontPreviewLoader(load: (_) async {}, maximumAutomaticFonts: 0);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: FontSelectorDialog(
                installedFont: [font(1), font(2)],
                currentFont: 'Default',
                loader: loader))));
    await tester.pumpAndSettle();
    for (final index in [1, 2]) {
      final row = find.byKey(ValueKey(('font-row', font(index))));
      await tester.scrollUntilVisible(row, 80,
          scrollable: find
              .descendant(
                  of: find.byKey(const ValueKey('font-selector-scroll')),
                  matching: find.byType(Scrollable))
              .first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Text>(find.byKey(ValueKey(('font-name', font(index)))))
              .style!
              .fontFamily,
          font(index).fullName);
    }
    final first = find.byKey(ValueKey(('font-name', font(1))));
    await tester.ensureVisible(first);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(first).style!.fontFamily, font(1).fullName);
    expect(loader.loadedFamilyFor(font(1)), font(1).fullName);
    expect(loader.loadedFamilyFor(font(2)), font(2).fullName);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets(
          'font picker ${language.code} narrow=$narrow fits with editable preview',
          (tester) async {
        final previous = uiLanguage.value;
        uiLanguage.value = language;
        addTearDown(() => uiLanguage.value = previous);
        tester.view.physicalSize =
            Size(narrow ? 360 : 1000, narrow ? 480 : 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final loader = FontPreviewLoader(load: (_) async {});
        await tester.pumpWidget(UiLanguageScope(
            child: MaterialApp(
          theme: applyAppControlTheme(ThemeData(
              colorScheme: ColorScheme.fromSeed(
                  seedColor: narrow ? Colors.deepOrange : Colors.teal,
                  brightness: narrow ? Brightness.dark : Brightness.light))),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(narrow ? 2 : 1)),
              child: child!),
          home: Scaffold(
              body: FontSelectorDialog(
                  installedFont: List.generate(40, font),
                  currentFont: font(1).fullName,
                  loader: loader)),
        )));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(ui('取消')).hitTestable(), findsOneWidget);
        final row = find.byKey(ValueKey(('font-row', font(1))));
        await tester.scrollUntilVisible(row, 50,
            scrollable: find
                .descendant(
                    of: find.byKey(const ValueKey('font-selector-scroll')),
                    matching: find.byType(Scrollable))
                .first);
        await tester.pumpAndSettle();
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('font-selector-apply')).hitTestable(),
            findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  const output = String.fromEnvironment('DAN_FONT_RENDER');
  testWidgets('actual installed fonts render their own names and preview',
      (tester) async {
    if (output.isEmpty || !Platform.isWindows) return;
    final fonts = [
      const InstalledFont(
          path: 'C:/Windows/Fonts/arial.ttf', fullName: 'Arial'),
      const InstalledFont(
          path: 'C:/Windows/Fonts/times.ttf', fullName: 'Times New Roman'),
      const InstalledFont(
          path: 'C:/Windows/Fonts/consola.ttf', fullName: 'Consolas'),
      const InstalledFont(
          path: 'C:/Windows/Fonts/msyh.ttc', fullName: 'Microsoft YaHei'),
    ].where((font) => File(font.path).existsSync()).toList();
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final korean = File('C:/Windows/Fonts/malgun.ttf');
    if (korean.existsSync()) {
      await tester.runAsync(() async {
        await (FontLoader('Malgun Gothic')
              ..addFont(Future.value(
                  ByteData.sublistView(await korean.readAsBytes()))))
            .load();
      });
    }
    final loader = FontPreviewLoader();
    for (final dark in [false, true]) {
      tester.view.physicalSize = const Size(1000, 840);
      tester.view.devicePixelRatio = 1;
      final key = GlobalKey();
      await tester.pumpWidget(UiLanguageScope(
          child: MaterialApp(
        theme: applyAppControlTheme(ThemeData(
            fontFamily: danEmbeddedFontFamily,
            colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.teal,
                brightness: dark ? Brightness.dark : Brightness.light))),
        home: RepaintBoundary(
            key: key,
            child: Scaffold(
                body: FontSelectorDialog(
                    installedFont: fonts,
                    currentFont: 'Arial',
                    loader: loader))),
      )));
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 30));
      }
      final row = find.byKey(ValueKey(('font-row', fonts[1])));
      await tester.scrollUntilVisible(row, 80,
          scrollable: find
              .descendant(
                  of: find.byKey(const ValueKey('font-selector-scroll')),
                  matching: find.byType(Scrollable))
              .first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextField>(
                  find.byKey(const ValueKey('font-selector-preview')))
              .style!
              .fontFamily,
          fonts[1].fullName);
      final controller = tester
          .widget<CustomScrollView>(
              find.byKey(const ValueKey('font-selector-scroll')))
          .controller!;
      controller.jumpTo(0);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image = await (key.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        try {
          await Directory(output).create(recursive: true);
          await File('$output/font-picker-${dark ? 'dark' : 'light'}.png')
              .writeAsBytes(
                  (await image.toByteData(format: drawing.ImageByteFormat.png))!
                      .buffer
                      .asUint8List());
        } finally {
          image.dispose();
        }
      });
      await tester.pumpWidget(const SizedBox.shrink());
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
