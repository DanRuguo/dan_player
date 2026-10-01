import 'dart:typed_data';

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/lyric_share_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lyric_share_fixture.dart';
import 'support/playlist_feature_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadLyricShareFonts);

  for (final entry in lyricShareSamples.entries) {
    testWidgets(
        'complete ${entry.key} and emoji pixels survive fixed PNG export',
        (tester) async {
      sizePlaylistFeature(tester, width: 1100, height: 1000);
      final boundary = GlobalKey();
      final card = LyricShareCard(
          title: 'Moonlight 月光',
          artist: 'Artist',
          album: 'Album',
          lines: [entry.value, 'Original / Translation']);
      await tester.pumpWidget(playlistFeatureHost(
          Center(child: RepaintBoundary(key: boundary, child: card)),
          textScale: 2));
      await tester.pumpAndSettle();
      final paragraph = tester.renderObject<RenderParagraph>(
          find.byKey(const ValueKey('lyric-share-card-line-0')));
      expect(paragraph.text.toPlainText(), entry.value);
      expect(paragraph.didExceedMaxLines, isFalse);
      final bytes = await captureLyricShare(tester, boundary,
          ratio: LyricShareCard.pixelRatio, name: 'card-${entry.key}');
      final decoded = await decodeLyricSharePng(tester, bytes);
      expect(decoded.width, 1080);
      expect(decoded.height, lessThanOrEqualTo(1920));
      expect(decoded.ink, greaterThan(1500));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('preview scaling and large UI text preserve the same PNG surface',
      (tester) async {
    sizePlaylistFeature(tester, width: 1100, height: 1000);
    final boundary = GlobalKey();
    const card = LyricShareCard(
        title: 'Title',
        artist: 'Artist',
        album: 'Album',
        lines: ['A complete lyric line', 'Another line with translation']);
    Future<Uint8List> paint(double width, double scale) async {
      await tester.pumpWidget(playlistFeatureHost(
          Center(
              child: SizedBox(
                  width: width,
                  child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: RepaintBoundary(key: boundary, child: card)))),
          textScale: scale));
      await tester.pumpAndSettle();
      return captureLyricShare(tester, boundary,
          ratio: LyricShareCard.pixelRatio);
    }

    final wide = await paint(800, 1);
    final narrow = await paint(280, 2);
    expect(narrow, wide,
        reason:
            'The preview transform and UI scaler never alter export pixels');
    expect(tester.takeException(), isNull);
  });

  test('oversized lyrics and metadata are rejected without taking a substring',
      () {
    final long = List.filled(2000, '字').join();
    expect(
        LyricShareCard(title: 'Title', artist: '', album: '', lines: [long])
            .measuredHeight(TextDirection.ltr),
        isNull);
    expect(
        LyricShareCard(
            title: List.filled(5000, 'a').join(),
            artist: '',
            album: '',
            lines: const ['one line']).measuredHeight(TextDirection.ltr),
        isNull);
    expect(
        LyricShareCard(
                title: List.filled(5000, 'a').join(),
                artist: '',
                album: '',
                lines: const ['one line'],
                showSongInfo: false)
            .measuredHeight(TextDirection.ltr),
        isNotNull);
  });

  testWidgets('dynamic palette changes the exported card pixels',
      (tester) async {
    sizePlaylistFeature(tester, width: 1100, height: 1000);
    final boundary = GlobalKey();
    Future<Uint8List> paint(Color seed) async {
      await tester.pumpWidget(MaterialApp(
          theme: applyAppControlTheme(ThemeData(
              fontFamily: danEmbeddedFontFamily,
              fontFamilyFallback: danFontFamilyFallback,
              colorScheme: ColorScheme.fromSeed(seedColor: seed))),
          home: Center(
              child: RepaintBoundary(
                  key: boundary,
                  child: const LyricShareCard(
                      title: 'Title',
                      artist: 'Artist',
                      album: 'Album',
                      lines: ['A complete lyric line'])))));
      await tester.pumpAndSettle();
      return captureLyricShare(tester, boundary,
          ratio: LyricShareCard.pixelRatio);
    }

    final first = await paint(Colors.teal);
    final second = await paint(Colors.deepOrange);
    expect(second, isNot(first));
    expect((await decodeLyricSharePng(tester, second)).width, 1080);
    expect(tester.takeException(), isNull);
  });
}
