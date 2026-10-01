import 'dart:async';
import 'dart:typed_data';

import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/lyric_share_card.dart';
import 'package:dan_player/component/lyric_share_dialog.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lyric_share_fixture.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String name) => find.byKey(ValueKey(name));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadLyricShareFonts);
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  Future<void> open(WidgetTester tester, LyricShareDialog dialog,
      {GlobalKey? boundary, double scale = 1, double width = 1100}) async {
    sizePlaylistFeature(tester, width: width, height: 900);
    await tester.pumpWidget(playlistFeatureHost(
        Builder(
            builder: (context) => TextButton(
                onPressed: () => showAppDialog<void>(
                    context: context, builder: (_) => dialog),
                child: const Text('Open'))),
        textScale: scale,
        boundary: boundary));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> export(WidgetTester tester, Future<void> saved) async {
    await tester.runAsync(() => tester.tap(_key('lyric-share-export')));
    await tester.pump();
    await tester.runAsync(() => saved.timeout(const Duration(seconds: 5)));
    await tester.pumpAndSettle();
  }

  testWidgets('API snapshots lines before the deferred dialog builder runs',
      (tester) async {
    sizePlaylistFeature(tester);
    final source = ['Original lyric\nOriginal translation', 'Second line'];
    await tester.pumpWidget(playlistFeatureHost(Builder(
        builder: (context) => TextButton(
            onPressed: () {
              showLyricShareDialog(context,
                  title: 'Original song',
                  artist: 'Artist',
                  album: 'Album',
                  lines: source,
                  initialIndex: 1);
              source[1] = 'Later source update';
            },
            child: const Text('Open')))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.widget<LyricShareCard>(find.byType(LyricShareCard)).lines,
        ['Second line']);
    expect(find.text('Later source update'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('four choices retain source order and reject a fifth selection',
      (tester) async {
    await open(
        tester,
        const LyricShareDialog(
            title: 'Title',
            artist: 'Artist',
            album: 'Album',
            lines: ['Line 0', 'Line 1', 'Line 2', 'Line 3', 'Line 4']));
    for (final index in [3, 1, 2]) {
      await tester.ensureVisible(_key('lyric-share-select-$index'));
      await tester.tap(_key('lyric-share-select-$index'));
      await tester.pumpAndSettle();
    }
    expect(tester.widget<LyricShareCard>(find.byType(LyricShareCard)).lines,
        ['Line 0', 'Line 1', 'Line 2', 'Line 3']);
    await tester.ensureVisible(_key('lyric-share-select-4'));
    expect(
        tester.widget<CheckboxListTile>(_key('lyric-share-select-4')).onChanged,
        isNull);
    await tester.ensureVisible(_key('lyric-share-select-0'));
    await tester.tap(_key('lyric-share-select-0'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(_key('lyric-share-select-4'));
    await tester.tap(_key('lyric-share-select-4'));
    await tester.pumpAndSettle();
    expect(tester.widget<LyricShareCard>(find.byType(LyricShareCard)).lines,
        ['Line 1', 'Line 2', 'Line 3', 'Line 4']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PNG export produces complete bounded pixels with safe filename',
      (tester) async {
    final saved = Completer<void>.sync();
    Uint8List? bytes;
    String? name;
    await open(
        tester,
        LyricShareDialog(
            title: 'Song:/名称?',
            artist: 'Artist',
            album: 'Album',
            lines: const ['Original lyric 😀\n完整译文'],
            savePng: (png, suggested) async {
              bytes = png;
              name = suggested;
              saved.complete();
              return true;
            }));
    final card = tester.widget<LyricShareCard>(find.byType(LyricShareCard));
    await export(tester, saved.future);
    final decoded = await decodeLyricSharePng(tester, bytes!);
    expect(decoded.width, 1080);
    expect(
        decoded.height,
        (card.measuredHeight(TextDirection.ltr)! * LyricShareCard.pixelRatio)
            .ceil());
    expect(decoded.height, lessThanOrEqualTo(1920));
    expect(decoded.ink, greaterThan(1000));
    expect(name, 'Dan Player - Song__名称_.png');
    expect(_key('lyric-share-saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'picker cancellation and write failure allow retry without closing',
      (tester) async {
    var invocation = 0;
    var completed = Completer<void>.sync();
    await open(
        tester,
        LyricShareDialog(
            title: 'Title',
            artist: 'Artist',
            album: 'Album',
            lines: const ['A complete lyric line'],
            savePng: (_, __) async {
              invocation++;
              completed.complete();
              if (invocation == 1) return false;
              if (invocation == 2) throw const FileSystemExceptionForTest();
              return true;
            }));
    await export(tester, completed.future);
    expect(find.byType(LyricShareDialog), findsOneWidget);
    expect(_key('lyric-share-saved'), findsNothing);
    expect(_key('lyric-share-error'), findsNothing);
    completed = Completer<void>.sync();
    await export(tester, completed.future);
    expect(_key('lyric-share-error'), findsOneWidget);
    expect(tester.widget<FilledButton>(_key('lyric-share-export')).onPressed,
        isNotNull);
    completed = Completer<void>.sync();
    await export(tester, completed.future);
    expect(_key('lyric-share-error'), findsNothing);
    expect(_key('lyric-share-saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long contents disable export and hiding metadata can restore it',
      (tester) async {
    await open(
        tester,
        LyricShareDialog(
            title: List.filled(5000, 'x').join(),
            artist: 'Artist',
            album: 'Album',
            lines: const ['A complete lyric line']));
    expect(_key('lyric-share-too-long'), findsOneWidget);
    expect(tester.widget<FilledButton>(_key('lyric-share-export')).onPressed,
        isNull);
    await tester.tap(_key('lyric-share-song-info'));
    await tester.pumpAndSettle();
    expect(_key('lyric-share-too-long'), findsNothing);
    expect(
        tester.widget<LyricShareCard>(find.byType(LyricShareCard)).showSongInfo,
        isFalse);
    expect(tester.widget<FilledButton>(_key('lyric-share-export')).onPressed,
        isNotNull);
    await tester.tap(_key('lyric-share-select-0'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(_key('lyric-share-export')).onPressed,
        isNull);
    expect(find.text(ui('请至少选择一句歌词')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'closing during an awaited save does not update a disposed dialog',
      (tester) async {
    final started = Completer<void>.sync();
    final pending = Completer<bool>.sync();
    await open(
        tester,
        LyricShareDialog(
            title: 'Title',
            artist: 'Artist',
            album: 'Album',
            lines: const ['A complete lyric line'],
            savePng: (_, __) {
              started.complete();
              return pending.future;
            }));
    await tester.runAsync(() => tester.tap(_key('lyric-share-export')));
    await tester.pump();
    await tester
        .runAsync(() => started.future.timeout(const Duration(seconds: 5)));
    expect(tester.widget<FilledButton>(_key('lyric-share-export')).onPressed,
        isNull);
    await tester.tap(find.widgetWithText(TextButton, ui('关闭')));
    await tester.pumpAndSettle();
    pending.complete(true);
    await tester.pump();
    expect(find.byType(LyricShareDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('network artwork and empty lyric snapshots perform no export',
      (tester) async {
    await open(
        tester,
        const LyricShareDialog(
            title: 'Title',
            artist: 'Artist',
            album: 'Album',
            lines: ['A complete lyric line'],
            artwork:
                NetworkImage('https://example.invalid/never-requested.png')));
    expect(tester.widget<LyricShareCard>(find.byType(LyricShareCard)).artwork,
        isNull);
    await tester.tap(find.widgetWithText(TextButton, ui('关闭')));
    await tester.pumpAndSettle();
    await open(
        tester,
        const LyricShareDialog(
            title: 'Title', artist: '', album: '', lines: ['', '  ']));
    expect(find.text(ui('没有可导出的歌词')), findsOneWidget);
    expect(tester.widget<FilledButton>(_key('lyric-share-export')).onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    for (final width in [320.0, 380.0, 1100.0]) {
      testWidgets('share dialog fits $language at ${width.toInt()} pixels',
          (tester) async {
        uiLanguage.value = language;
        final boundary = GlobalKey();
        await open(
            tester,
            LyricShareDialog(
                title: 'Moonlight 月光',
                artist: 'Artist',
                album: 'Album',
                lines: [lyricShareSamples[language.name]!]),
            width: width,
            scale: width < 500 ? 2 : 1,
            boundary: boundary);
        expect(_key('lyric-share-export').hitTestable(), findsOneWidget);
        final button = tester.getRect(_key('lyric-share-export'));
        expect(button.left, greaterThanOrEqualTo(0));
        expect(button.right, lessThanOrEqualTo(width));
        expect(button.bottom, lessThanOrEqualTo(900));
        if (language != UiLanguage.zh) {
          expect(find.text('保存 PNG'), findsNothing);
        }
        expect(tester.takeException(), isNull);
        await captureLyricShare(tester, boundary,
            name: '${language.name}-${width.toInt()}-dialog');
        await tester.ensureVisible(find.byType(LyricShareCard));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await captureLyricShare(tester, boundary,
            name: '${language.name}-${width.toInt()}-preview');
      });
    }
  }
}

class FileSystemExceptionForTest implements Exception {
  const FileSystemExceptionForTest();
}
