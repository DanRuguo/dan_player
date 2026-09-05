import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dan_player/page/now_playing_page/component/detail_progress_slider.dart';
import 'package:dan_player/page/now_playing_page/component/detail_transport_button.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final renderDirectory = Platform.environment['DAN_PLAYER_QA_OUTPUT'];
  setUpAll(() async {
    if (renderDirectory == null) return;
    final icons = FontLoader(
        'packages/${Symbols.play_arrow.fontPackage}/${Symbols.play_arrow.fontFamily}')
      ..addFont(rootBundle.load(
          'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'));
    final font = FontLoader('DetailTestFont')
      ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf'));
    await Future.wait([icons.load(), font.load()]);
  });

  Widget host(Widget child, {bool reduced = false}) => MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: Scaffold(
                body: Center(child: SizedBox(width: 320, child: child)))),
      );

  testWidgets(
      'real samples settle, hidden view releases subscription and resumes at actual time',
      (tester) async {
    final positions = StreamController<double>.broadcast(sync: true);
    final hidden = ValueNotifier(false);
    var actual = 12.0;
    await tester.pumpWidget(host(DetailProgressSlider(
      positions: positions.stream,
      readPosition: () => actual,
      duration: 180,
      trackIdentity: 'song',
      hidden: hidden,
      onSeek: (_) {},
    )));
    await tester.pumpAndSettle();
    expect(positions.hasListener, isTrue);
    actual = 12.4;
    positions.add(actual);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    final mid = tester.widget<Slider>(find.byType(Slider)).value;
    expect(mid, greaterThan(12));
    expect(mid, lessThan(12.4));
    await tester.pump(const Duration(milliseconds: 70));
    expect(tester.widget<Slider>(find.byType(Slider)).value, 12.4);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    hidden.value = true;
    await tester.pump();
    expect(positions.hasListener, isFalse);
    actual = 90;
    positions.add(actual);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<Slider>(find.byType(Slider)).value, 12.4);
    hidden.value = false;
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 90);
    await tester.pumpWidget(const SizedBox());
    await positions.close();
    hidden.dispose();
  });

  testWidgets(
      'reduced motion snaps to samples and a track change cancels the old drag',
      (tester) async {
    final positions = StreamController<double>.broadcast(sync: true);
    final seeks = <double>[];
    var actual = 10.0;
    Widget progress(String identity) => host(
        DetailProgressSlider(
          positions: positions.stream,
          readPosition: () => actual,
          duration: 180,
          trackIdentity: identity,
          onSeek: seeks.add,
        ),
        reduced: true);
    await tester.pumpWidget(progress('first'));
    await tester.pumpAndSettle();
    actual = 10.4;
    positions.add(actual);
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 10.4);
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Slider)));
    await gesture.moveBy(const Offset(35, 0));
    await tester.pump();
    actual = 0;
    await tester.pumpWidget(progress('second'));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(seeks, isEmpty);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await positions.close();
  });

  testWidgets(
      'hover and drag expand a vertical handle without changing its hit area',
      (tester) async {
    var actual = 60.0;
    final seeks = <double>[];
    await tester.pumpWidget(host(DetailProgressSlider(
      positions: const Stream.empty(),
      readPosition: () => actual,
      duration: 180,
      trackIdentity: 'song',
      onSeek: (value) {
        actual = value;
        seeks.add(value);
      },
    )));
    await tester.pumpAndSettle();
    DetailProgressHandleShape shape() =>
        tester.widget<SliderTheme>(find.byType(SliderTheme)).data.thumbShape!
            as DetailProgressHandleShape;
    expect(shape().width, 4);
    final hitArea = shape().getPreferredSize(true, false);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    await mouse.moveTo(tester.getCenter(find.byType(Slider)));
    await tester.pumpAndSettle();
    expect(shape().width, 6);
    await mouse.down(tester.getCenter(find.byType(Slider)));
    await mouse.moveBy(const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(shape().width, 8);
    expect(shape().height, greaterThan(shape().width));
    expect(shape().getPreferredSize(true, false), hitArea);
    await mouse.up();
    await mouse.moveTo(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(shape().width, 4);
    expect(seeks, hasLength(1));
    await mouse.removePointer();
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        '$brightness transparent controls render at narrow width and large text',
        (tester) async {
      final scheme =
          ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness);
      final narrow = brightness == Brightness.dark;
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
            useMaterial3: true,
            colorScheme: scheme,
            fontFamily: renderDirectory == null ? null : 'DetailTestFont'),
        home: Scaffold(
            body: Center(
                child: RepaintBoundary(
          key: boundaryKey,
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(narrow ? 2 : 1)),
            child: Container(
              width: narrow ? 320 : 640,
              color: scheme.surface,
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Dan Player',
                    style: TextStyle(color: scheme.onSurface, fontSize: 20)),
                const SizedBox(height: 16),
                DetailProgressSlider(
                    positions: const Stream.empty(),
                    readPosition: () => 75,
                    duration: 210,
                    trackIdentity: 'render',
                    onSeek: (_) {}),
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  DetailTransportButton(
                      tooltip: '上一曲',
                      icon: Symbols.skip_previous,
                      onPressed: () {}),
                  const SizedBox(width: 16),
                  DetailTransportButton(
                      tooltip: '播放',
                      icon: Symbols.play_arrow,
                      primary: true,
                      onPressed: () {}),
                  const SizedBox(width: 16),
                  DetailTransportButton(
                      tooltip: '下一曲',
                      icon: Symbols.skip_next,
                      onPressed: () {}),
                ]),
              ]),
            ),
          ),
        ))),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final button
          in tester.widgetList<IconButton>(find.byType(IconButton))) {
        for (final states in [
          <WidgetState>{},
          {WidgetState.hovered},
          {WidgetState.disabled}
        ]) {
          expect(button.style!.backgroundColor!.resolve(states),
              Colors.transparent);
        }
      }
      if (renderDirectory != null) {
        await tester.runAsync(() async {
          final boundary = boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory =
              await Directory(renderDirectory).create(recursive: true);
          await File('${directory.path}/detail-controls-${brightness.name}.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}
