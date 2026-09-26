import 'dart:async';
import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/page/now_playing_page/component/detail_progress_slider.dart';
import 'package:dan_player/page/now_playing_page/component/detail_waveform_track.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class Fixture {
  final positions = StreamController<double>.broadcast(sync: true);
  late final stream = positions.stream;
  final hidden = ValueNotifier(false);
  final seeks = <double>[];
  double position = 25;
  Object identity = 'track';
  Widget host({
    List<double>? peaks,
    String? tooltip,
    double width = 400,
    TextDirection direction = TextDirection.ltr,
    bool reduced = false,
    bool enabled = true,
    bool highContrast = false,
    double scale = 1,
    GlobalKey? boundary,
  }) =>
      MaterialApp(
          theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
          home: MediaQuery(
              data: MediaQueryData(
                  disableAnimations: reduced,
                  highContrast: highContrast,
                  textScaler: TextScaler.linear(scale)),
              child: Directionality(
                  textDirection: direction,
                  child: Scaffold(
                      body: Center(
                          child: RepaintBoundary(
                              key: boundary,
                              child: SizedBox(
                                  width: width,
                                  child: DetailProgressSlider(
                                      positions: stream,
                                      readPosition: () => position,
                                      duration: 100,
                                      trackIdentity: identity,
                                      hidden: hidden,
                                      enabled: enabled,
                                      waveform: peaks,
                                      waveformTooltip: tooltip,
                                      onSeek: (target) {
                                        seeks.add(target);
                                        position = target;
                                      }))))))));
  Future<void> dispose() async {
    hidden.dispose();
    await positions.close();
  }
}

Slider slider(WidgetTester tester) =>
    tester.widget<Slider>(find.byType(Slider));
SliderThemeData sliderTheme(WidgetTester tester) =>
    tester.widget<SliderTheme>(find.byType(SliderTheme).last).data;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
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

  test(
      'peak snapshots are bounded, finite, immutable and cover the entire source',
      () {
    final input = List<double>.filled(1024, 0)
      ..[0] = double.nan
      ..[1] = -.5
      ..[2] = double.infinity
      ..[3] = 2
      ..[1023] = .75;
    final peaks = boundedWaveformPeaks(input);
    expect(peaks, hasLength(512));
    expect(peaks.first, 0);
    expect(peaks[1], 1);
    expect(peaks.last, .75);
    input[1023] = 0;
    expect(peaks.last, .75);
    expect(() => peaks[0] = 1, throwsUnsupportedError);
  });

  testWidgets(
      'waveform preserves the stock 48px seek geometry and empty fallback',
      (tester) async {
    final fixture = Fixture();
    addTearDown(fixture.dispose);
    Future<double> tap({List<double>? peaks}) async {
      fixture.position = 25;
      await tester.pumpWidget(fixture.host(peaks: peaks));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(Slider));
      expect(rect.height, 48);
      await tester.tapAt(Offset(rect.left + rect.width * .73, rect.center.dy));
      await tester.pumpAndSettle();
      return fixture.seeks.last;
    }

    final plain = await tap();
    expect(sliderTheme(tester).trackShape.runtimeType,
        RoundedRectSliderTrackShape);
    expect(await tap(peaks: const []), plain);
    expect(await tap(peaks: List.filled(512, .8)), plain);
    final theme = sliderTheme(tester);
    expect(theme.trackShape, isA<DetailWaveformTrackShape>());
    final box = tester.renderObject<RenderBox>(find.byType(Slider));
    expect(
        theme.trackShape!.getPreferredRect(parentBox: box, sliderTheme: theme),
        const RoundedRectSliderTrackShape()
            .getPreferredRect(parentBox: box, sliderTheme: theme));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'waveform arriving during capture preserves preview and cancelled drags never seek',
      (tester) async {
    final fixture = Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.host());
    final rect = tester.getRect(find.byType(Slider));
    final gesture = await tester.startGesture(rect.center);
    await gesture.moveBy(const Offset(65, 0));
    await tester.pump();
    final preview = slider(tester).value;
    await tester.pumpWidget(fixture.host(peaks: List.filled(512, .6)));
    expect(slider(tester).value, preview);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fixture.seeks, [preview]);
    fixture.seeks.clear();
    final cancelled = await tester.startGesture(rect.center);
    await cancelled.moveBy(const Offset(45, 0));
    fixture.position = 30;
    fixture.positions.add(30);
    await cancelled.cancel();
    await tester.pumpAndSettle();
    expect(fixture.seeks, isEmpty);
    expect(slider(tester).value, 30);
  });

  testWidgets(
      'new track peaks cannot commit an old capture and hidden waveforms stop demand',
      (tester) async {
    final fixture = Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.host(peaks: List.filled(512, .6)));
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Slider)));
    await gesture.moveBy(const Offset(45, 0));
    fixture.identity = 'replacement';
    fixture.position = 60;
    await tester.pumpWidget(fixture.host(peaks: List.filled(512, .2)));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fixture.seeks, isEmpty);
    expect(slider(tester).value, 60);
    fixture.hidden.value = true;
    await tester.pumpAndSettle();
    expect(fixture.positions.hasListener, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
    fixture.position = 75;
    fixture.hidden.value = false;
    await tester.pumpAndSettle();
    expect(slider(tester).value, 75);
    expect(fixture.positions.hasListener, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(fixture.positions.hasListener, isFalse);
  });

  testWidgets(
      'waveform keeps keyboard and semantic seeks and does not create idle frames',
      (tester) async {
    final fixture = Fixture();
    addTearDown(fixture.dispose);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(fixture.host(
        peaks: List.filled(512, .9),
        tooltip: 'Decoded local waveform',
        reduced: true));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Decoded local waveform'), findsOneWidget);
    expect(slider(tester).semanticFormatterCallback!(25), '0:25');
    var increased = false;
    tester.getSemantics(find.byType(Slider)).visitChildren((node) {
      if (node.getSemanticsData().hasAction(drawing.SemanticsAction.increase)) {
        node.owner!.performAction(node.id, drawing.SemanticsAction.increase);
        increased = true;
      }
      return true;
    });
    expect(increased, isTrue);
    await tester.pumpAndSettle();
    expect(fixture.seeks.single, greaterThan(25));
    tester
        .widget<FocusableActionDetector>(find.descendant(
            of: find.byType(Slider),
            matching: find.byType(FocusableActionDetector)))
        .focusNode!
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(fixture.seeks, hasLength(2));
    fixture.position += .25;
    fixture.positions.add(fixture.position);
    await tester.pumpAndSettle();
    expect(slider(tester).value, fixture.position);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    semantics.dispose();
  });

  testWidgets(
      'played waveform amplitudes stay symmetric and follow RTL time direction',
      (tester) async {
    final fixture = Fixture();
    addTearDown(fixture.dispose);
    final key = GlobalKey();
    for (final direction in TextDirection.values) {
      await tester.pumpWidget(fixture.host(
          peaks: List.filled(512, 1),
          boundary: key,
          direction: direction,
          reduced: true));
      await tester.pumpAndSettle();
      final track = tester.getRect(find.byType(Slider));
      final boundary = tester.getRect(find.byKey(key));
      final center = (track.center.dy - boundary.top).round();
      final color = sliderTheme(tester).activeTrackColor!;
      final bytes = (await tester.runAsync(() async {
        final image = await (key.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        try {
          return (await image.toByteData(
              format: drawing.ImageByteFormat.rawRgba))!;
        } finally {
          image.dispose();
        }
      }))!;
      final width = boundary.width.round();
      final pixels = bytes.buffer.asUint8List();
      bool active(int x, int y) {
        final offset = (y * width + x) * 4;
        return pixels[offset] == (color.r * 255).round() &&
            pixels[offset + 1] == (color.g * 255).round() &&
            pixels[offset + 2] == (color.b * 255).round() &&
            pixels[offset + 3] == 255;
      }

      var left = 0, right = 0;
      for (var x = 0; x < width; x++) {
        if (active(x, center - 8)) {
          expect(active(x, center + 7), isTrue,
              reason: 'symmetric amplitude at $x');
          if (x < width / 2) {
            left++;
          } else {
            right++;
          }
        }
      }
      if (direction == TextDirection.ltr) {
        expect(left, greaterThan(15));
        expect(right, 0);
      } else {
        expect(right, greaterThan(15));
        expect(left, 0);
      }
    }
  });

  testWidgets(
      'high contrast and unavailable waveforms preserve disabled seek feedback',
      (tester) async {
    final fixture = Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture
        .host(peaks: const [.1, .6, 1, .3], highContrast: true, reduced: true));
    await tester.pumpAndSettle();
    final scheme = Theme.of(tester.element(find.byType(Slider))).colorScheme;
    expect(sliderTheme(tester).inactiveTrackColor, scheme.outline);
    await tester.pumpWidget(fixture.host(
        peaks: const [],
        enabled: false,
        tooltip: 'Waveform unavailable',
        reduced: true));
    await tester.pumpAndSettle();
    expect(sliderTheme(tester).trackShape.runtimeType,
        RoundedRectSliderTrackShape);
    expect(find.byTooltip('Waveform unavailable'), findsOneWidget);
    expect(slider(tester).onChanged, isNull);
    await tester.tap(find.byType(Slider));
    await tester.pumpAndSettle();
    expect(fixture.seeks, isEmpty);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets(
      'waveform and both times render in four languages with short enlarged and minimum widths',
      (tester) async {
    const output = String.fromEnvironment('DAN_WAVEFORM_RENDER');
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final fixture = Fixture()..position = 38;
    addTearDown(fixture.dispose);
    // Known amplitude envelope for this visual fixture, never production data.
    final peaks = List<double>.generate(512, (index) {
      final section = index ~/ 64;
      final ramp = (index % 32) / 31;
      return section.isEven ? ramp * .8 + .1 : (1 - ramp) * .45 + .05;
    });
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      for (final width in [800.0, 300.0, 120.0]) {
        tester.view.physicalSize = Size(width, 240);
        final key = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: language.locale,
            supportedLocales: [
              for (final item in UiLanguage.values) item.locale
            ],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: Entry(welcome: false).fromSchemeAndFontFamily(
                colorScheme: ColorScheme.fromSeed(
                    seedColor: Colors.teal,
                    brightness:
                        width == 800 ? Brightness.light : Brightness.dark)),
            builder: (context, child) => UiLanguageScope(
                child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(width == 800 ? 1 : 2),
                        disableAnimations: true),
                    child: child!)),
            home: Scaffold(
                body: Center(
                    child: DetailProgressSlider(
                        positions: fixture.stream,
                        readPosition: () => fixture.position,
                        duration: 100,
                        trackIdentity: fixture.identity,
                        waveform: peaks,
                        waveformTooltip: ui('播放进度'),
                        onSeek: (_) {}))),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text('0:38'), findsOneWidget);
        expect(find.text('1:40'), findsOneWidget);
        expect(tester.takeException(), isNull,
            reason: '${language.name} $width');
        expect(tester.binding.hasScheduledFrame, isFalse);
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final image = await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            try {
              final bytes =
                  await image.toByteData(format: drawing.ImageByteFormat.png);
              final file =
                  File('$output/${language.name}-${width.toInt()}.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
      }
    }
  });
}
