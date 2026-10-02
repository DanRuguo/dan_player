import 'dart:convert';
import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/overflow_marquee_text.dart';
import 'package:dan_player/page/now_playing_page/component/now_playing_metadata_header.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/listening_status_fixture.dart';
import 'support/playlist_feature_fixture.dart';

const _longSamples = {
  UiLanguage.zh: (
    title: '等你归来，穿过漫长月夜与星光的歌声',
    artist: '喜多村英梨 / 野中藍与特别合作歌手',
    album: '月光下漫长夜晚的完整珍藏专辑第五卷'
  ),
  UiLanguage.en: (
    title: 'and I’m home, through the longest moonlit night',
    artist: 'The performing artist and special guest singers',
    album: 'The complete collection of songs for the longest night'
  ),
  UiLanguage.ja: (
    title: 'and I’m home(魔法少女小圆红蓝角色曲)',
    artist: '喜多村英梨 / 野中藍と特別ゲスト',
    album: '魔法少女まどか☆マギカ 完全収録アルバム第五巻'
  ),
  UiLanguage.ko: (
    title: '달빛이 머무는 긴 밤을 지나 집으로 돌아와요',
    artist: '아주 긴 가수 이름과 특별 참여 가수',
    album: '달빛 아래 오래도록 간직하는 완전판 앨범'
  ),
};
const _shortSamples = {
  UiLanguage.zh: (title: '爱如火', artist: '那艺娜', album: '爱如火'),
  UiLanguage.en: (title: 'Fire', artist: 'Naina', album: 'Fire'),
  UiLanguage.ja: (title: '愛の炎', artist: 'ナイナ', album: '愛の炎'),
  UiLanguage.ko: (title: '불꽃', artist: '나이나', album: '불꽃'),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPlaylistFeatureFonts);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  testWidgets('normal motion paints continuously scrolling metadata evidence',
      (tester) async {
    sizePlaylistFeature(tester, width: 720, height: 400);
    final renderRoot = Platform.environment['DAN_HEADER_MARQUEE_RENDER_DIR'];
    final proof = <String, Object>{};
    for (final language in [
      UiLanguage.en,
      UiLanguage.zh,
      UiLanguage.ja,
      UiLanguage.ko
    ]) {
      await tester.pumpWidget(const SizedBox());
      uiLanguage.value = language;
      final boundary = GlobalKey();
      final sample = _longSamples[language]!;
      await tester.pumpWidget(listeningStatusHost(
          Builder(
              builder: (context) => MediaQuery(
                  data:
                      MediaQuery.of(context).copyWith(disableAnimations: false),
                  child: Center(
                      child: SizedBox(
                          width: 400,
                          child: NowPlayingMetadataHeader(
                              title: sample.title,
                              artist: sample.artist,
                              album: sample.album))))),
          boundary: boundary,
          seed: Colors.pink));
      final paints = find.descendant(
          of: find.byType(OverflowMarqueeText),
          matching: find.byType(CustomPaint));
      expect(paints, findsNWidgets(3));
      for (final text in [sample.title, sample.artist, sample.album]) {
        expect(find.text(text), findsNothing,
            reason: 'Normal overflowing text uses the full painted string.');
      }
      final poses = tester
          .widgetList<CustomPaint>(paints)
          .map((paint) => (paint.painter as dynamic).pose)
          .toList();
      final bounds = List.generate(3, (i) => tester.getRect(paints.at(i)));
      final rootOffset = tester.getRect(find.byKey(boundary)).topLeft;
      List<Uint8List>? previousPixels;
      List<double>? previousOffsets;
      final stages = <Object>[];
      for (var frame = 0; frame <= 60; frame++) {
        if (frame > 0) {
          await tester.pump(const Duration(microseconds: 66667));
        }
        final stage = frame == 0 || frame == 27 || frame == 54;
        final sequence = language == UiLanguage.en || language == UiLanguage.zh;
        final writeFrame =
            renderRoot != null && (stage || (sequence && frame < 60));
        if (!stage && !writeFrame) continue;
        final offsets =
            poses.map((pose) => pose.value.offset as double).toList();
        final pixels = (await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
          try {
            if (writeFrame) {
              final png =
                  await image.toByteData(format: raster.ImageByteFormat.png);
              final directory = Directory('$renderRoot/${language.name}');
              await directory.create(recursive: true);
              await File(
                      '${directory.path}/frame-${frame.toString().padLeft(3, '0')}.png')
                  .writeAsBytes(png!.buffer.asUint8List());
            }
            if (!stage) return <Uint8List>[];
            final raw = (await image.toByteData(
                    format: raster.ImageByteFormat.rawRgba))!
                .buffer
                .asUint8List();
            return bounds.map((global) {
              final local = global.shift(-rootOffset);
              final left = local.left.floor().clamp(0, image.width);
              final right = local.right.ceil().clamp(0, image.width);
              final top = local.top.floor().clamp(0, image.height);
              final bottom = local.bottom.ceil().clamp(0, image.height);
              final rowBytes = (right - left) * 4;
              final result = Uint8List((bottom - top) * rowBytes);
              for (var y = top; y < bottom; y++) {
                final source = (y * image.width + left) * 4;
                result.setRange((y - top) * rowBytes, (y - top + 1) * rowBytes,
                    raw, source);
              }
              return result;
            }).toList();
          } finally {
            image.dispose();
          }
        }))!;
        if (!stage) continue;
        if (frame == 0) {
          expect(offsets, everyElement(0.0));
        } else {
          for (var i = 0; i < 3; i++) {
            expect(offsets[i], greaterThan(previousOffsets![i]),
                reason:
                    '${language.name} row $i keeps moving at ${frame / 15}s.');
            expect(listEquals(pixels[i], previousPixels![i]), isFalse,
                reason: 'The rendered text pixels change, not only its clock.');
          }
        }
        previousOffsets = offsets;
        previousPixels = pixels;
        stages.add({'seconds': frame / 15, 'offsets': offsets});
      }
      proof[language.name] = stages;
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    uiLanguage.value = UiLanguage.zh;
    final shortBoundary = GlobalKey();
    await tester.pumpWidget(listeningStatusHost(
        Builder(
            builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: false),
                child: const Center(
                    child: SizedBox(
                        width: 400,
                        child: NowPlayingMetadataHeader(
                            title: '爱如火', artist: '那艺娜', album: '爱如火'))))),
        boundary: shortBoundary,
        seed: Colors.pink));
    expect(find.text('那艺娜'), findsOneWidget);
    expect(find.text('爱如火'), findsNWidgets(2));
    expect(
        find.descendant(
            of: find.byType(OverflowMarqueeText),
            matching: find.byType(CustomPaint)),
        findsNothing);
    if (renderRoot != null) {
      await tester.runAsync(() async {
        final image = await (shortBoundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
        try {
          final png =
              await image.toByteData(format: raster.ImageByteFormat.png);
          await File('$renderRoot/zh-short.png')
              .writeAsBytes(png!.buffer.asUint8List());
          await File('$renderRoot/proof.json')
              .writeAsString(const JsonEncoder.withIndent('  ').convert(proof));
        } finally {
          image.dispose();
        }
      });
    }
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'all overflowing metadata scrolls across theme resize and song changes',
      (tester) async {
    sizePlaylistFeature(tester, width: 720, height: 400);
    final hidden = ValueNotifier(false);
    addTearDown(hidden.dispose);
    Future<void> mount(
        {double width = 240,
        Color seed = Colors.pink,
        String title = 'and I’m home(魔法少女小圆红蓝角色曲)',
        String artist = '喜多村英梨 / 野中藍',
        String album = '魔法少女まどか☆マギカ 5'}) async {
      await tester.pumpWidget(listeningStatusHost(
          Builder(
              builder: (context) => MediaQuery(
                  data:
                      MediaQuery.of(context).copyWith(disableAnimations: false),
                  child: Center(
                      child: SizedBox(
                          width: width,
                          child: NowPlayingMetadataHeader(
                              title: title,
                              artist: artist,
                              album: album,
                              hidden: hidden))))),
          seed: seed));
    }

    List<dynamic> painters() => tester
        .widgetList<CustomPaint>(find.descendant(
            of: find.byType(OverflowMarqueeText),
            matching: find.byType(CustomPaint)))
        .map((paint) => paint.painter as dynamic)
        .toList();
    Future<void> advance() async {
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    for (var phase = 0; phase < 4; phase++) {
      await mount(
          width: phase >= 2 ? 180 : 240,
          seed: phase == 0 ? Colors.pink : Colors.amber,
          title: phase == 3
              ? '下一曲的长歌名 Next song title 最後の文字'
              : 'and I’m home(魔法少女小圆红蓝角色曲)');
      expect(painters(), hasLength(3));
      if (phase == 0 || phase == 2) {
        for (final painter in painters()) {
          expect(painter.pose.value.offset, 0);
        }
      } else if (phase == 3) {
        expect(painters().first.pose.value.offset, 0);
      }
      await advance();
      for (final painter in painters()) {
        expect(painter.pose.value.offset, greaterThan(0));
      }
      // Complete song information is painted, never replaced by an ellipsis.
      expect(find.text('喜多村英梨 / 野中藍'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    final offsets = painters().map((p) => p.pose.value.offset).toList();
    hidden.value = true;
    await tester.pump(const Duration(seconds: 5));
    expect(painters().map((p) => p.pose.value.offset).toList(), offsets);
    expect(tester.binding.transientCallbackCount, 0);
    hidden.value = false;
    await advance();
    final resumed =
        painters().map((p) => p.pose.value.offset as double).toList();
    for (var i = 0; i < resumed.length; i++) {
      expect(resumed[i], greaterThan(offsets[i] as double));
    }
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('header spacing preserves the existing cover allocation',
      (tester) async {
    sizePlaylistFeature(tester, width: 1080, height: 900);
    const title = 'and I’m home(魔法少女小圆红蓝角色曲)';
    const artist = '喜多村英梨/野中藍', album = '魔法少女まどか☆マギカ 5';
    for (final scale in [1.0, 2.0, 3.0]) {
      await tester.pumpWidget(listeningStatusHost(
          Builder(
              builder: (context) => Column(children: [
                    const SizedBox(
                        width: 400,
                        child: Column(
                            key: ValueKey('original-header'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OverflowMarqueeText(title,
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold)),
                              OverflowMarqueeText('$artist - $album'),
                              SizedBox(height: 16),
                            ])),
                    SizedBox(
                        width: 400,
                        child: Column(
                            key: const ValueKey('new-header'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const NowPlayingMetadataHeader(
                                  title: title, artist: artist, album: album),
                              SizedBox(
                                  height: nowPlayingMetadataCoverGap(
                                      context, title)),
                            ])),
                  ])),
          scale: scale));
      await tester.pumpAndSettle();
      final original = find.byKey(const ValueKey('original-header'));
      final current = find.byKey(const ValueKey('new-header'));
      final originalTitle = find
          .descendant(of: original, matching: find.byType(OverflowMarqueeText))
          .first;
      final currentTitle = find
          .descendant(of: current, matching: find.byType(OverflowMarqueeText))
          .first;
      final titleIncrease = tester.getSize(currentTitle).height -
          tester.getSize(originalTitle).height;
      // A 24px title at 300% is 17px taller with the real font. The old
      // 16px spacing budget cannot absorb the remaining 1px without overlap.
      final unavoidable = (titleIncrease - 16).clamp(0.0, double.infinity);
      expect(tester.getSize(current).height,
          closeTo(tester.getSize(original).height + unavoidable, .01));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('short song metadata stays adjacent at its natural width',
      (tester) async {
    sizePlaylistFeature(tester, width: 720, height: 400);
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(listeningStatusHost(
          const Center(
              child: SizedBox(
                  width: 400,
                  child: NowPlayingMetadataHeader(
                      title: '爱如火', artist: '那艺娜', album: '爱如火'))),
          scale: scale));
      await tester.pumpAndSettle();
      final textSurfaces = find.byType(OverflowMarqueeText);
      final artist = tester.getRect(textSurfaces.at(1));
      final album = tester.getRect(textSurfaces.at(2));
      expect(album.left - artist.right, closeTo(40, .01),
          reason:
              'Only the existing divider and album icon separate the words.');
      expect(
          album.right,
          lessThan(
              tester.getRect(find.byType(NowPlayingMetadataHeader)).right));
      expect(
          tester
              .widget<OverflowMarqueeText>(textSurfaces.first)
              .style!
              .fontSize,
          24);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('short metadata leaves remaining room to the long neighbor',
      (tester) async {
    sizePlaylistFeature(tester, width: 720, height: 400);
    for (final shortArtist in [false, true]) {
      await tester.pumpWidget(listeningStatusHost(Center(
          child: SizedBox(
              width: 240,
              child: NowPlayingMetadataHeader(
                  title: 'A title',
                  artist: shortArtist
                      ? 'A'
                      : 'A very long performing artist and featured singers',
                  album: shortArtist
                      ? 'A very long album with a complete collection of songs'
                      : 'A')))));
      await tester.pumpAndSettle();
      final textSurfaces = find.byType(OverflowMarqueeText);
      final shortWidth =
          tester.getSize(textSurfaces.at(shortArtist ? 1 : 2)).width;
      final longWidth =
          tester.getSize(textSurfaces.at(shortArtist ? 2 : 1)).width;
      expect(shortWidth, lessThan(20));
      expect(longWidth, greaterThan(160));
      expect(
          tester.getRect(textSurfaces.at(2)).right,
          closeTo(tester.getRect(find.byType(NowPlayingMetadataHeader)).right,
              .01));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('two long metadata entries share space by measured text width',
      (tester) async {
    sizePlaylistFeature(tester, width: 720, height: 400);
    await tester.pumpWidget(listeningStatusHost(const Center(
        child: SizedBox(
            width: 320,
            child: NowPlayingMetadataHeader(
                title: 'Song title',
                artist:
                    'An extraordinarily long performing artist with several special featured singers',
                album: 'A long album collection')))));
    await tester.pumpAndSettle();
    final textSurfaces = find.byType(OverflowMarqueeText);
    final artistWidth = tester.getSize(textSurfaces.at(1)).width;
    final albumWidth = tester.getSize(textSurfaces.at(2)).width;
    expect(artistWidth / albumWidth, greaterThan(2));
    expect(artistWidth + albumWidth, closeTo(320 - 59, .01));
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets(
          'metadata header ${language.name} ${narrow ? 'narrow large' : 'wide'}',
          (tester) async {
        sizePlaylistFeature(tester, width: 720, height: 400);
        uiLanguage.value = language;
        final boundary = GlobalKey();
        final sample = _longSamples[language]!;
        await tester.pumpWidget(listeningStatusHost(
            Center(
                child: SizedBox(
                    width: narrow ? 240 : 400,
                    child: NowPlayingMetadataHeader(
                        title: sample.title,
                        artist: sample.artist,
                        album: sample.album))),
            boundary: boundary,
            scale: narrow ? 2 : 1,
            seed: narrow ? Colors.amber : Colors.pink,
            brightness: narrow ? Brightness.dark : Brightness.light));
        await tester.pumpAndSettle();
        final header = find.byType(NowPlayingMetadataHeader);
        final scheme = Theme.of(tester.element(header)).colorScheme;
        final texts = tester
            .widgetList<OverflowMarqueeText>(find.descendant(
                of: header, matching: find.byType(OverflowMarqueeText)))
            .toList();
        expect(texts, hasLength(3));
        expect(texts.first.style!.fontSize, 24);
        expect(texts.first.style!.color, scheme.primary);
        expect(
            texts.skip(1).every((text) =>
                text.style!.color == scheme.primary.withValues(alpha: .88)),
            isTrue);
        for (final word in texts) {
          final label = find.text(word.text);
          expect(label, findsOneWidget);
          expect(tester.getRect(label).right,
              lessThanOrEqualTo(tester.getRect(header).right + .01));
        }
        await captureListeningStatus(tester, boundary,
            'header-${language.name}-${narrow ? 'narrow' : 'wide'}');
        final short = _shortSamples[language]!;
        await tester.pumpWidget(listeningStatusHost(
            Center(
                child: SizedBox(
                    width: narrow ? 240 : 400,
                    child: NowPlayingMetadataHeader(
                        title: short.title,
                        artist: short.artist,
                        album: short.album))),
            boundary: boundary,
            scale: narrow ? 2 : 1,
            seed: narrow ? Colors.amber : Colors.pink,
            brightness: narrow ? Brightness.dark : Brightness.light));
        await tester.pumpAndSettle();
        final shortSurfaces = find.byType(OverflowMarqueeText);
        expect(
            tester.getRect(shortSurfaces.at(2)).left -
                tester.getRect(shortSurfaces.at(1)).right,
            closeTo(40, .01));
        await captureListeningStatus(tester, boundary,
            'header-${language.name}-${narrow ? 'narrow' : 'wide'}-short');
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
