import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/page/now_playing_page/component/current_playlist_view.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

Widget _host(PlaylistFeaturePlayback playback, {double scale = 2, GlobalKey? boundary, bool dialog = false}) =>
    RepaintBoundary(
        key: boundary,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: uiLanguage.value.locale,
            supportedLocales: [
              for (final item in UiLanguage.values) item.locale
            ],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: Entry(welcome: false).fromSchemeAndFontFamily(
                colorScheme: ColorScheme.fromSeed(
                    seedColor: Colors.teal, brightness: Brightness.dark)),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true),
                child: child!),
            home: Scaffold(
                body: dialog
                    ? AlertDialog(
                        content: AppDialogContent(
                            width: 300,
                            maxHeight: 440,
                            child: CurrentPlaylistView(
                                shrinkWrap: true,
                                showTitle: false,
                                playbackService: playback)))
                    : Padding(padding: const EdgeInsets.all(16), child: CurrentPlaylistView(playbackService: playback)))));

Future<void> _capture(
    WidgetTester tester, GlobalKey boundary, String name) async {
  final output = Platform.environment['DAN_QUEUE_SEARCH_HEIGHT_RENDER_DIR'];
  if (output == null) return;
  await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary)
        .toImage();
    try {
      final bytes = await image.toByteData(format: raster.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File(path.join(output, '$name.png'))
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main({String? onlyCase}) {
  const cases = [
    'queue search retains usable controls and songs with a keyboard',
    'short queue header accepts wheel touch and keyboard independently',
    'shrink wrapped queue keeps AlertDialog intrinsic sizing',
  ];
  if (onlyCase != null && !cases.contains(onlyCase)) {
    throw ArgumentError.value(
        onlyCase, 'onlyCase', 'Unknown queue height case');
  }
  void widgetCase(String name, WidgetTesterCallback body) {
    if (onlyCase == null || onlyCase == name) testWidgets(name, body);
  }

  setUpAll(loadPlaylistFeatureFonts);
  setUp(() {
    uiLanguage.value = UiLanguage.zh;
    final output = Platform.environment['DAN_QUEUE_SEARCH_HEIGHT_RENDER_DIR'];
    if (output == null) return;
    final qa = path.normalize(
        path.join(Directory.current.parent.path, 'tool', 'qa-local'));
    expect(path.isWithin(qa, path.normalize(path.absolute(output))), isTrue);
  });
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  widgetCase('queue search retains usable controls and songs with a keyboard',
      (tester) async {
    sizePlaylistFeature(tester, width: 420, height: 600);
    addTearDown(tester.view.resetViewInsets);
    final playback = PlaylistFeaturePlayback([
      CategoryTestAudio('Moonlit road · 夜空の向こうへ · 밤하늘 너머',
          artist: 'Dan Orchestra'),
      CategoryTestAudio('Canon', artist: 'Dan Orchestra'),
      CategoryTestAudio('Other song'),
    ]);
    addTearDown(playback.dispose);
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      for (final variant in [
        ('wide', 760.0, 650.0, 1.0, 0.0),
        ('narrow', 420.0, 600.0, 2.0, 0.0),
        ('keyboard', 420.0, 600.0, 2.0, 280.0),
      ]) {
        tester.view.physicalSize = Size(variant.$2, variant.$3);
        tester.view.viewInsets = FakeViewPadding(bottom: variant.$5);
        final boundary = GlobalKey();
        await tester
            .pumpWidget(_host(playback, scale: variant.$4, boundary: boundary));
        await tester.pumpAndSettle();
        await tester.enterText(_key('queue-search'), 'orchestra');
        await tester.pumpAndSettle();
        final header = tester.getRect(_key('queue-header-scroll'));
        final summary = tester.getRect(_key('queue-search-count'));
        expect(summary.top, greaterThanOrEqualTo(header.top));
        expect(summary.bottom, lessThanOrEqualTo(header.bottom));
        expect(_key('queue-clear-search').hitTestable(), findsOneWidget);
        expect(tester.getSize(_key('current-playlist-list')).height,
            greaterThan(40));
        expect(tester.takeException(), isNull,
            reason: '${language.name}/${variant.$1}');
        await _capture(tester, boundary, '${language.name}-${variant.$1}');
        await tester.tap(_key('queue-clear-search'));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(_key('queue-search')).controller!.text,
            isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });

  widgetCase(
      'short queue header accepts wheel touch and keyboard independently',
      (tester) async {
    sizePlaylistFeature(tester, width: 420, height: 600);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    final playback = PlaylistFeaturePlayback(List.generate(
        60, (index) => CategoryTestAudio('Track $index', artist: 'Orchestra')));
    addTearDown(playback.dispose);
    await tester.pumpWidget(_host(playback));
    await tester.pumpAndSettle();
    await tester.enterText(_key('queue-search'), 'orchestra');
    await tester.pumpAndSettle();
    final header = tester
        .widget<SingleChildScrollView>(_key('queue-header-scroll'))
        .controller!;
    final songs =
        tester.widget<ListView>(_key('current-playlist-list')).controller!;
    final offset = header.offset;
    expect(offset, greaterThan(0));
    await tester.sendEventToBinding(PointerScrollEvent(
        position: tester.getCenter(_key('queue-search-count')),
        scrollDelta: const Offset(0, -100)));
    await tester.pumpAndSettle();
    expect(header.offset, lessThan(offset));
    expect(songs.offset, 0);

    header.jumpTo(header.position.maxScrollExtent);
    await tester.pump();
    final touch = await tester.startGesture(
        tester.getCenter(_key('queue-header-scroll')),
        kind: raster.PointerDeviceKind.touch);
    await touch.moveBy(const Offset(0, 30));
    await touch.moveBy(const Offset(0, 70));
    await touch.up();
    await tester.pumpAndSettle();
    expect(header.offset, lessThan(header.position.maxScrollExtent));
    expect(songs.offset, 0);

    await tester.ensureVisible(_key('queue-search'));
    await tester.pumpAndSettle();
    await tester.tap(_key('queue-search'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft,
        physicalKey: PhysicalKeyboardKey.shiftLeft);
    try {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab,
          physicalKey: PhysicalKeyboardKey.tab);
    } finally {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft,
          physicalKey: PhysicalKeyboardKey.shiftLeft);
    }
    await tester.pumpAndSettle();
    final control = _key('queue-segment-loop');
    expect(control.hitTestable(), findsOneWidget);
    expect(
        tester
            .getRect(_key('queue-header-scroll'))
            .contains(tester.getCenter(control)),
        isTrue);

    final beforeHeader = header.offset;
    await tester.drag(_key('current-playlist-list'), const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(songs.offset, greaterThan(0));
    expect(header.offset, beforeHeader);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
  });

  widgetCase('shrink wrapped queue keeps AlertDialog intrinsic sizing',
      (tester) async {
    sizePlaylistFeature(tester, width: 520, height: 700);
    final playback = PlaylistFeaturePlayback([CategoryTestAudio('Canon')]);
    addTearDown(playback.dispose);
    await tester.pumpWidget(_host(playback, scale: 1.5, dialog: true));
    await tester.pumpAndSettle();
    await tester.enterText(_key('queue-search'), 'canon');
    await tester.pumpAndSettle();
    expect(_key('queue-header-scroll'), findsNothing);
    if (_key('queue-clear-search').hitTestable().evaluate().isEmpty) {
      final clear = _key('queue-clear-search');
      debugPrint('Queue dialog fixture: '
          'query=${tester.widget<TextField>(_key('queue-search')).controller!.text}, '
          'clear=${clear.evaluate().length}, '
          'searchRect=${tester.getRect(_key('queue-search'))}, '
          'clearRect=${clear.evaluate().isEmpty ? null : tester.getRect(clear)}, '
          'size=${tester.view.physicalSize}, '
          'inset=${tester.view.viewInsets.bottom}, '
          'textInputRegistered=${tester.testTextInput.isRegistered}');
    }
    expect(_key('queue-clear-search').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(_key('queue-clear-search'));
    await tester.pumpAndSettle();
    expect(_key('current-playlist-item-0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
