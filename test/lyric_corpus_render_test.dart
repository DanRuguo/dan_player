import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  final folder = Platform.environment['DAN_LYRIC_RENDER_SAMPLES'];
  TestWidgetsFlutterBinding.ensureInitialized();
  final samples = <Map>[];
  setUpAll(() async {
    if (folder == null) return;
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
    final files = Directory(folder)
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      samples.add(jsonDecode(await file.readAsString()) as Map);
    }
  });
  testWidgets(
      'real API corpus long lines and sustained words render and settle',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    expect(samples, isNotEmpty);
    for (var sample = 0; sample < samples.length; sample++) {
      final data = samples[sample];
      final lyric = LyricSnapshot.fromJson(data['snapshot'])!.toLyric();
      final lines = lyric.lines
          .whereType<SyncLyricLine>()
          .where((line) => line.words.isNotEmpty && line.length > Duration.zero)
          .toList();
      if (lines.isEmpty) continue;
      final longest = [...lines]
        ..sort((a, b) => b.content.length.compareTo(a.content.length));
      final held = [...lines]..sort((a, b) {
          int duration(SyncLyricLine line) => line.words
              .map((word) => word.length.inMilliseconds)
              .reduce((a, b) => a > b ? a : b);
          return duration(b).compareTo(duration(a));
        });
      final selected = <SyncLyricLine>{
        lines[lines.length ~/ 2],
        longest.first,
        held.first
      };
      for (final narrow in [false, true]) {
        tester.view.physicalSize = Size(narrow ? 480 : 1040, 760);
        var pose = 0;
        for (final line in selected) {
          var position =
              (line.start.inMilliseconds + line.length.inMilliseconds * .35) /
                  1000;
          final source = StreamController<double>.broadcast(sync: true);
          final settings = LyricViewController()..lyricFontSize = 30;
          final key = GlobalKey();
          await tester.pumpWidget(MaterialApp(
              theme: ThemeData(
                  brightness: narrow ? Brightness.light : Brightness.dark,
                  fontFamily: danEmbeddedFontFamily,
                  fontFamilyFallback: danFontFamilyFallback),
              home: Scaffold(
                  body: RepaintBoundary(
                      key: key,
                      child: ColoredBox(
                          color: narrow
                              ? const Color(0xfffaf7ff)
                              : const Color(0xff17131f),
                          child: ChangeNotifierProvider.value(
                              value: settings,
                              child: VerticalLyricScrollView(
                                  lyric: lyric,
                                  positionStream: source.stream,
                                  readPosition: () => position,
                                  onSeek: (_) {},
                                  springLyrics: true)))))));
          await tester.pumpAndSettle();
          position += .08;
          source.add(position);
          await tester.pump(const Duration(milliseconds: 80));
          expect(tester.takeException(), isNull,
              reason: data['sample'] as String);
          const output = String.fromEnvironment('DAN_CORPUS_RENDER');
          if (output.isNotEmpty) {
            await tester.runAsync(() async {
              final image = await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
              final file = File(
                  '$output/$sample-${narrow ? 'narrow' : 'wide'}-${pose++}.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(
                  (await image.toByteData(format: ui.ImageByteFormat.png))!
                      .buffer
                      .asUint8List());
              image.dispose();
            });
          }
          await tester.pumpAndSettle();
          await tester.pump(const Duration(seconds: 2));
          expect(tester.binding.hasScheduledFrame, isFalse);
          await tester.pumpWidget(const SizedBox());
          settings.dispose();
          await source.close();
        }
      }
    }
  }, skip: folder == null);
}
