import 'dart:async';
import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/fluid_artwork.dart';
import 'package:dan_player/component/player_logo.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Lyric extends Lyric {
  _Lyric(super.lines);
}

class _Word extends SyncLyricWord {
  _Word(int start, int length, String content)
      : super(Duration(milliseconds: start), Duration(milliseconds: length),
            content);
}

class _Line extends SyncLyricLine {
  _Line(int start, String first, String held, String translation)
      : super(
            Duration(milliseconds: start),
            const Duration(seconds: 4),
            [
              _Word(start, 700, first),
              _Word(start + 700, 3300, held),
            ],
            translation);
}

class _Fixture {
  final positions = StreamController<double>.broadcast(sync: true);
  final backgroundPhase = ValueNotifier(.16);
  final settings = LyricViewController()
    ..lyricFontSize = 30
    ..translationFontSize = 17
    ..lyricTextAlign = LyricTextAlign.left;
  final lyric = _Lyric([
    _Line(0, '夜色里，', '等一束光', 'Waiting for a light in the quiet night'),
    _Line(4000, '星空に ', '届くように', '让声音抵达星空'),
    _Line(8000, 'Stay in ', 'this moment', '就停留在这一刻'),
    _Line(12000, '이 순간을 ', '기억해', '记住此刻的声音'),
    _Line(16000, '心中的 ', '旋律 🎵', 'A melody that stays with you'),
    _Line(20000, 'Let the ', 'night unfold', '让夜色缓缓展开'),
    _Line(24000, '光の中で ', 'また会おう', '在光中再见'),
  ]);
  double position = 9.8;
  void emit(double value) {
    position = value;
    positions.add(value);
  }

  Widget build(Brightness brightness, {bool reduced = false}) {
    final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xffa365bd), brightness: brightness);
    return UiLanguageScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          platform: TargetPlatform.windows,
          colorScheme: scheme,
          fontFamily: danEmbeddedFontFamily,
          fontFamilyFallback: danFontFamilyFallback,
        ),
        home: MotionPreferencesScope(
          preferences: const MotionPreferences().all(!reduced),
          child: Scaffold(
            body: Stack(fit: StackFit.expand, children: [
              FluidArtwork(
                phase: backgroundPhase,
                child: ImageFiltered(
                  imageFilter: drawing.ImageFilter.blur(sigmaX: 48, sigmaY: 48),
                  child: Image.asset('app_icon.ico', fit: BoxFit.cover),
                ),
              ),
              ColoredBox(color: scheme.surface.withValues(alpha: .54)),
              SafeArea(
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 20),
                    child: Row(children: [
                      const PlayerLogo(size: 24),
                      const SizedBox(width: 10),
                      const Text('Dan Player'),
                      const Spacer(),
                      Text(ui('歌词')),
                    ]),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: ChangeNotifierProvider.value(
                        value: settings,
                        child: VerticalLyricScrollView(
                          lyric: lyric,
                          positionStream: positions.stream,
                          readPosition: () => position,
                          onSeek: emit,
                          springLyrics: true,
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> dispose() async {
    await positions.close();
    backgroundPhase.dispose();
    settings.dispose();
  }
}

Future<void> _capture(GlobalKey key, String name) async {
  const folder = String.fromEnvironment('DAN_NATIVE_LYRIC_RENDER');
  if (folder.isEmpty) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final bytes = await image.toByteData(format: drawing.ImageByteFormat.png);
    final file = File('$folder/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [
      (danEmbeddedFontFamily, 'assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
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
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  for (final language in UiLanguage.values) {
    for (final brightness in Brightness.values) {
      testWidgets('native lyric surface ${language.name} ${brightness.name}',
          (tester) async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        tester.view.physicalSize = brightness == Brightness.dark
            ? const Size(1040, 760)
            : const Size(480, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        uiLanguage.value = language;
        final boundary = GlobalKey();
        await tester.pumpWidget(
            RepaintBoundary(key: boundary, child: fixture.build(brightness)));
        final logo = tester.widget<Image>(find.descendant(
            of: find.byType(PlayerLogo), matching: find.byType(Image)));
        await tester.runAsync(() =>
            precacheImage(logo.image, tester.element(find.byType(PlayerLogo))));
        await tester.runAsync(() => precacheImage(
            const AssetImage('app_icon.ico'),
            tester.element(find.byType(FluidArtwork))));
        await tester.pumpAndSettle();
        final prefix = '${language.name}-${brightness.name}';
        await tester.runAsync(() => _capture(boundary, '$prefix-held'));
        if (language == UiLanguage.zh &&
            brightness == Brightness.dark &&
            const String.fromEnvironment('DAN_NATIVE_LYRIC_RENDER')
                .isNotEmpty) {
          for (var frame = 0; frame < 240; frame++) {
            fixture.emit(9.8 + frame / 60);
            fixture.backgroundPhase.value = .16 + frame / 60 / 36;
            await tester.pump(const Duration(microseconds: 16667));
            await tester.runAsync(() => _capture(boundary,
                'sequence/frame-${frame.toString().padLeft(3, '0')}'));
          }
          fixture.emit(9.8);
          await tester.pumpAndSettle();
        }
        final rows =
            tester.widgetList<LyricViewTile>(find.byType(LyricViewTile));
        expect(rows.where((row) => row.distance == 0), hasLength(1));
        fixture.emit(12.1);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 160));
        await tester.runAsync(() => _capture(boundary, '$prefix-follow'));
        await tester.pumpAndSettle();
        final active = find.byWidgetPredicate(
            (widget) => widget is LyricViewTile && widget.distance == 0);
        final viewport =
            tester.getRect(find.byKey(const ValueKey('vertical-lyric-scroll')));
        expect(tester.getRect(active).center.dy,
            inInclusiveRange(viewport.top, viewport.bottom));
        expect(tester.takeException(), isNull);
        expect(tester.binding.transientCallbackCount, 0);
        await tester.pump(const Duration(seconds: 2));
        expect(tester.binding.hasScheduledFrame, isFalse,
            reason: 'A paused source must not leave a lyric effect ticker');
      });
    }
  }

  testWidgets('hover reading renders a gradual clear and restore',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    final boundary = GlobalKey();
    await tester.pumpWidget(
        RepaintBoundary(key: boundary, child: fixture.build(Brightness.dark)));
    await tester.runAsync(() => precacheImage(const AssetImage('app_icon.ico'),
        tester.element(find.byType(FluidArtwork))));
    await tester.pumpAndSettle();
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: const Offset(10, 10));
    await pointer
        .moveTo(tester.getCenter(find.byType(VerticalLyricScrollView)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.runAsync(() => _capture(boundary, 'hover-mid'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => _capture(boundary, 'hover-clear'));
    await pointer.moveTo(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.runAsync(() => _capture(boundary, 'hover-restored'));
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
    await pointer.removePointer();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('lyric disabled state and seek remain readable without motion',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    final boundary = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: boundary, child: fixture.build(Brightness.dark, reduced: true)));
    await tester.pumpAndSettle();
    fixture.emit(24.2);
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<LyricViewTile>(find.byType(LyricViewTile))
            .where((row) => row.distance == 0)
            .single
            .line
            .start
            .inSeconds,
        24);
    expect(tester.binding.transientCallbackCount, 0);
    final active = find.byWidgetPredicate(
        (widget) => widget is LyricViewTile && widget.distance == 0);
    final viewport =
        tester.getRect(find.byKey(const ValueKey('vertical-lyric-scroll')));
    expect(tester.getRect(active).center.dy,
        inInclusiveRange(viewport.top, viewport.bottom));
    await tester.runAsync(() => _capture(boundary, 'disabled-seek'));
    expect(tester.takeException(), isNull);
  });
}
