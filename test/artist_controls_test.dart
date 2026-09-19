import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_menu_anchor.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/song_artist_menu.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/artist_separators.dart';
import 'package:dan_player/page/settings_page/artist_separator_editor.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

void main() {
  test('literal separators handle regex symbols, overlapping tokens and none',
      () {
    for (final delimiter in [
      '|',
      '+',
      '[',
      '(',
      r'\',
      '.',
      '*',
      '?',
      '^',
      r'$'
    ]) {
      expect(
          'A${delimiter}B'.split(RegExp(artistSeparatorPattern([delimiter]))),
          ['A', 'B']);
    }
    expect('A / B/C'.split(RegExp(artistSeparatorPattern(['/', ' / ']))),
        ['A', 'B', 'C']);
    expect('林 俊杰'.split(RegExp(artistSeparatorPattern([]))), ['林 俊杰']);
    expect(
        '林 俊杰'.split(RegExp(artistSeparatorPattern(['', null, 1]))), ['林 俊杰']);
    expect('A + B、C'.split(RegExp(artistSeparatorPattern([' + ', '、']))),
        ['A', 'B', 'C']);
  });

  testWidgets(
      'single artist is direct; duplicate and blank entries are ignored',
      (tester) async {
    String? selected;
    final menu = MenuController();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MenuAnchor(
      controller: menu,
      menuChildren: [
        SongArtistMenu(
            artists: const ['  Singer A ', '', 'Singer A'],
            onSelected: (value) => selected = value),
      ],
      child: const SizedBox(width: 40, height: 40),
    ))));
    menu.open();
    await tester.pumpAndSettle();
    expect(find.byType(SubmenuButton), findsNothing);
    await tester.tap(find.widgetWithText(MenuItemButton, 'Singer A'));
    await tester.pumpAndSettle();
    expect(selected, '  Singer A ');
    expect(menu.isOpen, isFalse);
  });

  testWidgets(
      'artist submenu opens on hover and closes after choosing an artist',
      (tester) async {
    final originalLanguage = uiLanguage.value;
    uiLanguage.value = UiLanguage.en;
    addTearDown(() => uiLanguage.value = originalLanguage);
    String? selected;
    await tester.pumpWidget(UiLanguageScope(
        child: MaterialApp(
            home: Scaffold(
                body: AppMenuAnchor(
      menuChildren: [
        SongArtistMenu(
            artists: const ['Singer A', '  Singer B ', '歌手 C'],
            onSelected: (value) => selected = value),
      ],
      builder: (_, controller, child) => TextButton(
          onPressed: () => controller.open(), child: const Text('Open')),
    )))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Singer B'), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(790, 590));
    await mouse.moveTo(tester.getCenter(find.byType(SubmenuButton)));
    await tester.pumpAndSettle();
    expect(find.text('Singer B'), findsOneWidget);
    final first = tester.getRect(find.text('Singer A'));
    final parent = tester.getRect(find.byType(SubmenuButton));
    expect(first.left, greaterThan(parent.right));
    await tester.tap(find.widgetWithText(MenuItemButton, 'Singer B'));
    await tester.pumpAndSettle();
    expect(selected, '  Singer B ');
    expect(find.byType(SubmenuButton), findsNothing);
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets('long artist submenu fits narrow viewport without overflowing',
      (tester) async {
    tester.view.physicalSize = const Size(320, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final name = List.filled(20, 'Long Artist 中文').join(' ');
    final controller = MenuController();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Align(
      alignment: Alignment.topRight,
      child: MenuAnchor(
          controller: controller,
          menuChildren: [
            SongArtistMenu(artists: [name, 'B'], onSelected: (_) {}),
          ],
          child: const SizedBox.square(dimension: 40)),
    ))));
    controller.open();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SubmenuButton));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.widgetWithText(MenuItemButton, name));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  Future<void> openEditor(WidgetTester tester,
      {List<String> initial = const ['/', '、'],
      required Future<void> Function(List<String>) onSave}) async {
    await tester.pumpWidget(MaterialApp(
        theme: applyAppControlTheme(ThemeData(useMaterial3: true)),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showAppDialog<void>(
                        context: context,
                        dialogBottomInset: 0,
                        builder: (_) => ArtistSeparatorEditDialog(
                            initialSeparators: initial, onSave: onSave)),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'separator editor previews literal symbols and saves pending input',
      (tester) async {
    List<String>? saved;
    await openEditor(tester, onSave: (value) async => saved = value);
    final input = find.byKey(const ValueKey('artist-separator-input'));
    await tester.enterText(input, '|');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('artist-separator-example')), 'A|B/C');
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    await tester.enterText(input, '+');
    await tester.tap(find.byKey(const ValueKey('artist-separator-save')));
    await tester.pumpAndSettle();
    expect(saved, ['/', '、', '|', '+']);
    expect(find.byType(ArtistSeparatorEditDialog), findsNothing);
  });

  testWidgets(
      'duplicate delimiter explains problem and a failed save keeps draft',
      (tester) async {
    var calls = 0;
    await openEditor(tester, onSave: (_) async {
      calls++;
      throw StateError('test save failure');
    });
    final input = find.byKey(const ValueKey('artist-separator-input'));
    await tester.enterText(input, '/');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text(ui('此分隔符已添加。')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('artist-separator-save')));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.enterText(input, '[');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('artist-separator-save')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('“[”'), findsOneWidget);
    await tester.ensureVisible(find.text(ui('保存失败，原设置已保留。请重试。')));
    await tester.pumpAndSettle();
    expect(find.text(ui('保存失败，原设置已保留。请重试。')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text(ui('取消')));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'saving reindexes existing audio objects; failure restores settings',
      (tester) async {
    final library = AudioLibrary.instance;
    final settings = AppSettings.instance;
    final oldFolders = library.folders;
    final oldOnline = library.onlineAudioCollection;
    final oldSeparators = settings.artistSeparator;
    final oldPattern = settings.artistSplitPattern;
    addTearDown(() {
      settings.artistSeparator = oldSeparators;
      settings.artistSplitPattern = oldPattern;
      library.folders = oldFolders;
      library.onlineAudioCollection = oldOnline;
      library.rebuildDerivedCollections();
    });
    settings.artistSeparator = ['/'];
    settings.artistSplitPattern = artistSeparatorPattern(['/']);
    final audio = CategoryTestAudio('literal-artist', artist: 'A|B');
    library.folders = [
      AudioFolder([audio], 'J:/artist-test-fixtures', 0, 0)
    ];
    library.onlineAudioCollection = [];
    library.rebuildDerivedCollections();
    var fail = true;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ArtistSeparatorEditor(persist: () async {
      if (fail) throw StateError('disk full');
    }))));
    await tester.tap(find.text(ui('管理艺术家分隔符')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('artist-separator-input')), '|');
    await tester.tap(find.byKey(const ValueKey('artist-separator-save')));
    await tester.pumpAndSettle();
    expect(settings.artistSeparator, ['/']);
    expect(library.artistCollection.keys, ['A|B']);
    fail = false;
    await tester.tap(find.byKey(const ValueKey('artist-separator-save')));
    await tester.pumpAndSettle();
    expect(settings.artistSeparator, ['/', '|']);
    expect(library.artistCollection.keys, ['A', 'B']);
    expect(library.audioCollection.single, same(audio));
    expect(audio.splitedArtists, ['A', 'B']);
    expect(find.byType(ArtistSeparatorEditDialog), findsNothing);
  });

  setUpAll(() async {
    for (final font in [
      (danEmbeddedFontFamily, 'assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      ),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    final korean = File('C:/Windows/Fonts/malgun.ttf');
    if (await korean.exists()) {
      await (FontLoader('Malgun Gothic')
            ..addFont(
                Future.value(ByteData.sublistView(await korean.readAsBytes()))))
          .load();
    }
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets('separator dialog ${language.code} narrow=$narrow',
          (tester) async {
        final previous = uiLanguage.value;
        uiLanguage.value = language;
        addTearDown(() => uiLanguage.value = previous);
        tester.view.physicalSize =
            narrow ? const Size(360, 720) : const Size(780, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundary = GlobalKey();
        await tester.pumpWidget(UiLanguageScope(
            child: MaterialApp(
          theme: applyAppControlTheme(ThemeData(
              fontFamily: danEmbeddedFontFamily,
              fontFamilyFallback: const ['Malgun Gothic'],
              colorScheme: ColorScheme.fromSeed(
                  seedColor: narrow ? Colors.teal : Colors.orange,
                  brightness: narrow ? Brightness.dark : Brightness.light))),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(narrow ? 1.35 : 1)),
              child: RepaintBoundary(key: boundary, child: child!)),
          home: Scaffold(
              body: ArtistSeparatorEditDialog(
                  initialSeparators: const ['/', '、', ' & '],
                  onSave: (_) async {})),
        )));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
            tester
                .getRect(find.byKey(const ValueKey('artist-separator-save')))
                .bottom,
            lessThanOrEqualTo(tester.view.physicalSize.height));
        expect(tester.binding.hasScheduledFrame, isFalse);
        const output = String.fromEnvironment('DAN_ARTIST_RENDER');
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
            await Directory(output).create(recursive: true);
            await File('$output/artists-${language.code}-$narrow.png')
                .writeAsBytes((await image.toByteData(
                        format: drawing.ImageByteFormat.png))!
                    .buffer
                    .asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}
