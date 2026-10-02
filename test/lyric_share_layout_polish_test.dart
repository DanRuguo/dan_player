import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/lyric_share_card.dart';
import 'package:dan_player/component/lyric_share_dialog.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/listening_status_fixture.dart';
import 'support/lyric_share_fixture.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String name) => find.byKey(ValueKey(name));
const _samples = {
  'zh': 'Fighting flames with fire\n四射的火花\n注音：火花仍在闪耀',
  'en': 'Fighting flames with fire\n四射的火花\nPronunciation and translation',
  'ja': 'Fighting flames with fire\n炎と炎がぶつかる\nほのお と ほのお',
  'ko': 'Fighting flames with fire\n불길이 서로 부딪혀요\n발음과 원문을 모두 표시',
};

void main({String? onlyCase}) {
  void register(String name, WidgetTesterCallback callback) {
    if (onlyCase == null || name == onlyCase) testWidgets(name, callback);
  }

  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadLyricShareFonts);
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  Future<void> open(WidgetTester tester, LyricShareDialog dialog,
      {double width = 812,
      double height = 834,
      double scale = 1,
      GlobalKey? boundary,
      Brightness brightness = Brightness.dark}) async {
    sizePlaylistFeature(tester, width: width, height: height);
    await tester.pumpWidget(listeningStatusHost(
        Builder(
            builder: (context) => TextButton(
                  onPressed: () => showAppDialog<void>(
                      context: context, builder: (_) => dialog),
                  child: const Text('Open'),
                )),
        boundary: boundary,
        scale: scale,
        brightness: brightness,
        seed: brightness == Brightness.dark ? Colors.amber : Colors.indigo));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  register(
      'sparse wide dialog balances selection and preview without empty rows',
      (tester) async {
    await open(
        tester,
        const LyricShareDialog(
            title: 'All We Know',
            artist: 'The Chainsmokers',
            album: 'Collage',
            lines: ['Fighting flames with fire\n四射的火花']));
    expect(_key('lyric-share-parallel'), findsOneWidget);
    final list = tester.getRect(_key('lyric-share-selection-list'));
    final preview = tester.getRect(_key('lyric-share-preview-viewport'));
    expect(preview.left, greaterThan(list.right));
    expect(preview.top, lessThanOrEqualTo(list.top));
    expect(list.height, lessThan(100),
        reason: 'One row does not reserve a quarter-screen list.');
    expect(tester.getSize(find.byType(AppDialogContent)).height, lessThan(500));
    expect(_key('lyric-share-export').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  register(
      'selection scroll remains independent and PNG retains the complete fixed canvas',
      (tester) async {
    final saved = Completer<void>.sync();
    Uint8List? bytes;
    final lines = List.generate(60, (i) => 'Original line $i\n译文 $i\n注音 $i');
    await open(
        tester,
        LyricShareDialog(
            title: 'All We Know',
            artist: 'The Chainsmokers',
            album: 'Collage',
            lines: lines,
            savePng: (png, _) async {
              bytes = png;
              saved.complete();
              return true;
            }));
    final list = _key('lyric-share-selection-list');
    final scrollable =
        find.descendant(of: list, matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(_key('lyric-share-select-59'), 260,
        scrollable: scrollable, maxScrolls: 50);
    await tester.tap(_key('lyric-share-select-59'));
    await tester.pumpAndSettle();
    final card = tester.widget<LyricShareCard>(find.byType(LyricShareCard));
    expect(card.lines, [lines.first, lines.last]);
    expect(_key('lyric-share-export').hitTestable(), findsOneWidget);
    await tester.runAsync(() => tester.tap(_key('lyric-share-export')));
    await tester.pump();
    await tester
        .runAsync(() => saved.future.timeout(const Duration(seconds: 5)));
    await tester.pumpAndSettle();
    final decoded = await decodeLyricSharePng(tester, bytes!);
    expect(decoded.width, 1080);
    expect(
        decoded.height, (card.measuredHeight(TextDirection.ltr)! * 2).ceil());
    expect(decoded.ink, greaterThan(1000));
    expect(tester.takeException(), isNull);
  });

  register(
      'wide narrow and language handoffs keep selection and captured song details',
      (tester) async {
    final source = ['First\n第一句', 'Second\n第二句', 'Third\n第三句'];
    await open(
        tester,
        LyricShareDialog(
            title: 'Original title',
            artist: 'Original artist',
            album: 'Original album',
            lines: source));
    await tester.tap(_key('lyric-share-select-1'));
    await tester.tap(_key('lyric-share-song-info'));
    await tester.pumpAndSettle();
    source[1] = 'Late mutation';
    tester.view.physicalSize = const Size(360, 834);
    uiLanguage.value = UiLanguage.ja;
    await tester.pumpAndSettle();
    expect(_key('lyric-share-stacked'), findsOneWidget);
    expect(_key('lyric-share-export').hitTestable(), findsOneWidget);
    tester.view.physicalSize = const Size(1100, 834);
    await tester.pumpAndSettle();
    expect(_key('lyric-share-parallel'), findsOneWidget);
    final card = tester.widget<LyricShareCard>(find.byType(LyricShareCard));
    expect(card.lines, ['First\n第一句', 'Second\n第二句']);
    expect(card.title, 'Original title');
    expect(card.showSongInfo, isFalse);
    expect(tester.takeException(), isNull);
  });

  register(
      'short narrow large text keeps actions visible and complete preview scrollable',
      (tester) async {
    await open(
        tester,
        LyricShareDialog(
            title: '长歌曲名称 Long song name',
            artist: 'Artist',
            album: 'Album',
            lines: [_samples['ja']!]),
        width: 320,
        height: 480,
        scale: 2);
    expect(_key('lyric-share-stacked'), findsOneWidget);
    expect(_key('lyric-share-export').hitTestable(), findsOneWidget);
    final export = tester.getRect(_key('lyric-share-export'));
    expect(export.bottom, lessThanOrEqualTo(480));
    await tester.ensureVisible(_key('lyric-share-preview-viewport'));
    await tester.pumpAndSettle();
    expect(_key('lyric-share-export').hitTestable(), findsOneWidget);
    expect(tester.widget<LyricShareCard>(find.byType(LyricShareCard)).lines,
        [_samples['ja']!]);
    expect(tester.takeException(), isNull);
  });

  register('long failure feedback stays scrollable above fixed narrow actions',
      (tester) async {
    final attempted = Completer<void>.sync();
    await open(
        tester,
        LyricShareDialog(
            title: 'Title',
            artist: '',
            album: '',
            lines: const ['A complete lyric line'],
            savePng: (_, __) async {
              attempted.complete();
              throw StateError('write failed');
            }),
        width: 320,
        height: 480,
        scale: 2);
    await tester.runAsync(() => tester.tap(_key('lyric-share-export')));
    await tester.pump();
    await tester
        .runAsync(() => attempted.future.timeout(const Duration(seconds: 5)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(_key('lyric-share-error'));
    await tester.pumpAndSettle();
    expect(_key('lyric-share-error'), findsOneWidget);
    expect(_key('lyric-share-export').hitTestable(), findsOneWidget);
    expect(tester.getRect(_key('lyric-share-export')).bottom,
        lessThanOrEqualTo(480));
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      register(
          'polished share renders ${language.name} ${narrow ? 'narrow-large' : 'wide'}',
          (tester) async {
        uiLanguage.value = language;
        final boundary = GlobalKey();
        final sample = _samples[language.name]!;
        await open(
            tester,
            LyricShareDialog(
                title: 'All We Know 月夜 달빛',
                artist: 'The Chainsmokers',
                album: 'Collage',
                lines: List.generate(8, (i) => '$sample $i')),
            width: narrow ? 360 : 1100,
            height: 1000,
            scale: narrow ? 2 : 1,
            boundary: boundary,
            brightness: narrow ? Brightness.dark : Brightness.light);
        final mode = narrow ? 'stacked' : 'parallel';
        expect(_key('lyric-share-$mode'), findsOneWidget);
        expect(_key('lyric-share-export').hitTestable(), findsOneWidget);
        final name = '${language.name}-${narrow ? 'narrow-large' : 'wide'}';
        await captureLyricShare(tester, boundary, name: '$name-selection');
        for (final index in [1, 2, 3]) {
          await tester.ensureVisible(_key('lyric-share-select-$index'));
          await tester.pumpAndSettle();
          await tester.tap(_key('lyric-share-select-$index'));
          await tester.pumpAndSettle();
        }
        expect(tester.widget<LyricShareCard>(find.byType(LyricShareCard)).lines,
            List.generate(4, (i) => '$sample $i'));
        await tester.ensureVisible(_key('lyric-share-preview-viewport'));
        await tester.pumpAndSettle();
        await captureLyricShare(tester, boundary, name: '$name-preview');
        final action = tester.getRect(_key('lyric-share-export'));
        expect(action.left, greaterThanOrEqualTo(0));
        expect(action.right, lessThanOrEqualTo(narrow ? 360 : 1100));
        expect(action.bottom, lessThanOrEqualTo(1000));
        expect(tester.takeException(), isNull);
      });
    }
  }

  register('selection wheel clips hovered and pressed ink outside its viewport',
      (tester) async {
    final boundary = GlobalKey();
    await open(
        tester,
        LyricShareDialog(
            title: 'All We Know',
            artist: 'The Chainsmokers',
            album: 'Collage',
            lines: List.generate(40, (i) => 'Original line $i\n译文 $i')),
        width: 1100,
        height: 1000,
        boundary: boundary);
    final list = _key('lyric-share-selection-list');
    final scroll = tester.widget<ListView>(list).controller!;
    final offsetBefore = scroll.offset;
    final row = _key('lyric-share-select-1');
    final rowBefore = tester.getRect(row);
    final title = tester.getRect(find.text(ui('导出歌词卡片')));
    final outside = [
      title.inflate(4),
      tester.getRect(find.text(ui('选择最多 4 句歌词；卡片保留所选文字与换行。'))),
      tester.getRect(_key('lyric-share-song-info')),
    ];
    Future<({int width, int height, Uint8List bytes})> pixels() async =>
        (await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
          try {
            final data =
                await image.toByteData(format: raster.ImageByteFormat.rawRgba);
            return (
              width: image.width,
              height: image.height,
              bytes: Uint8List.fromList(data!.buffer.asUint8List())
            );
          } finally {
            image.dispose();
          }
        }))!;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: rowBefore.center);
    await mouse.down(rowBefore.center);
    try {
      await tester.pumpAndSettle();
      final before = await pixels();
      await tester.sendEventToBinding(PointerScrollEvent(
          position: rowBefore.center,
          scrollDelta: Offset(0, rowBefore.center.dy - title.center.dy)));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(offsetBefore),
          reason: 'The selection viewport must receive the actual wheel input');
      if (row.evaluate().isNotEmpty) {
        expect(tester.getRect(row).top, lessThan(rowBefore.top));
      }
      final after = await pixels();
      await captureLyricShare(tester, boundary, name: 'selection-ink-wheel');
      for (final area in outside) {
        var changed = 0;
        for (var y = area.top.ceil().clamp(0, after.height);
            y < area.bottom.floor().clamp(0, after.height);
            y++) {
          for (var x = area.left.ceil().clamp(0, after.width);
              x < area.right.floor().clamp(0, after.width);
              x++) {
            final p = (y * after.width + x) * 4;
            if (after.bytes[p] != before.bytes[p] ||
                after.bytes[p + 1] != before.bytes[p + 1] ||
                after.bytes[p + 2] != before.bytes[p + 2]) {
              changed++;
            }
          }
        }
        expect(changed, 0,
            reason:
                'List ink must not repaint the title, instructions or song-info switch');
      }
      expect(tester.widget<LyricShareCard>(find.byType(LyricShareCard)).lines,
          ['Original line 0\n译文 0']);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.cancel();
      await mouse.removePointer();
    }
  });
}
