import 'dart:io';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_reading_tools.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_segment_practice_dialog.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:desktop_lyric/l10n/catalog_lyric_segment_practice.dart';
import 'package:desktop_lyric/l10n/ui_catalog.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/listening_status_fixture.dart';
import 'support/lyric_share_fixture.dart';
import 'support/playlist_feature_fixture.dart';

class _Playback extends PlaylistFeaturePlayback {
  _Playback() : super([]);
  @override
  int playbackSessionToken = 7;
  @override
  double length = 100;
  bool local = true;
  int enables = 0, starts = 0;
  double? sought;
  @override
  bool get canUseSegmentLoop =>
      local && resolvingAudioPath.value == null && !isChangingOutput.value;
  @override
  bool setSegmentLoopEnabled(bool value) {
    enables++;
    segmentLoop.setEnabled(value);
    if (segmentLoop.enabled) sought = segmentLoop.start;
    return segmentLoop.enabled;
  }

  @override
  void start({bool recordIntent = true}) => starts++;

  void switchSession() {
    playbackSessionToken++;
    notifyListeners();
  }
}

LrcLine _line(int start, int length, String text, {String? romanization}) =>
    LrcLine(Duration(milliseconds: start), text,
        isBlank: text.trim().isEmpty, length: Duration(milliseconds: length))
      ..romanization = romanization;

Lrc _sample() => Lrc([
      _line(10000, 1000, '雨が降る night┃夜雨', romanization: 'ame ga furu'),
      _line(11000, 1000, ''),
      _line(12000, 1000, '第二句 hidden'),
      _line(14000, 1000, '第三句 중간 가사'),
      _line(16000, 1000, '風が吹く night┃夜风'),
      _line(19000, 1000, '最后一句 밖의 가사'),
    ], LrcSource.local);

Finder _key(String value) => find.byKey(ValueKey(value));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final output = Platform.environment['DAN_LYRIC_SEGMENT_RENDER_DIR'];
  setUpAll(() async {
    if (output != null &&
        !path.isWithin(
            path.join(Directory.current.parent.path, 'tool', 'qa-local'),
            output)) {
      throw StateError('Render output must stay in workspace QA');
    }
    await loadLyricShareFonts();
  });
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  Future<void> mount(WidgetTester tester, _Playback playback,
      {Lyric? lyric,
      bool Function()? current,
      ValueNotifier<int>? changes,
      Duration position = const Duration(seconds: 10),
      double width = 900,
      double scale = 1,
      GlobalKey? capture}) async {
    sizePlaylistFeature(tester, width: width, height: 1000);
    final selected = lyric ?? _sample();
    final controller =
        LyricViewController(preferences: NowPlayingPagePreference.fromMap({}));
    addTearDown(controller.dispose);
    final future = Future<Lyric?>.value(selected);
    final session = playback.playbackSessionToken;
    await tester.pumpWidget(listeningStatusHost(
        LyricReadingMenu(
          controller: controller,
          readLyric: () => future,
          onPracticeSegment: (navigator) async {
            await showLyricSegmentPracticeDialog(navigator.context,
                playback: playback,
                lyric: selected,
                playbackSession: session,
                isCurrentLyric: current ?? () => true,
                songTitle: 'Night 夜の練習 밤 연습',
                lyricChanges: changes,
                initialPosition: position);
          },
        ),
        scale: scale,
        brightness: width < 500 ? Brightness.dark : Brightness.light,
        boundary: capture));
    await tester.tap(_key('lyric-reading-tools'));
    await tester.pumpAndSettle();
    await tester.tap(_key('lyric-practice-segment-open'));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, int index) async {
    final row = _key('lyric-segment-line-$index');
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.ensureVisible(_key('lyric-segment-search'));
    await tester.enterText(_key('lyric-segment-search'), query);
    await tester.pumpAndSettle();
  }

  FilledButton applyButton(WidgetTester tester) =>
      tester.widget<FilledButton>(_key('lyric-segment-apply'));

  test('segment catalog is registered in all languages with matching arguments',
      () {
    final placeholders = RegExp(r'\{\d+\}');
    for (final entry in catalogLyricSegmentPractice.entries) {
      expect(uiCatalog[entry.key], same(entry.value), reason: entry.key);
      expect(entry.value, hasLength(3));
      final expected =
          placeholders.allMatches(entry.key).map((match) => match[0]).toList();
      for (final translated in entry.value) {
        expect(translated.trim(), isNotEmpty);
        expect(placeholders.allMatches(translated).map((match) => match[0]),
            orderedEquals(expected));
      }
    }
  });

  testWidgets('real reading menu filters text but keeps every intervening line',
      (tester) async {
    final playback = _Playback();
    addTearDown(playback.dispose);
    await mount(tester, playback);
    await search(tester, 'AME');
    expect(_key('lyric-segment-line-0'), findsOneWidget);
    expect(_key('lyric-segment-line-4'), findsNothing);
    await search(tester, '夜');
    expect(_key('lyric-segment-line-0'), findsOneWidget);
    expect(_key('lyric-segment-line-4'), findsOneWidget);
    await search(tester, 'NIGHT');
    await choose(tester, 0);
    await choose(tester, 4);
    expect(tester.widget<Text>(_key('lyric-segment-range')).data,
        '练习范围：0:00:10 — 0:00:17 · 4 句');
    await search(tester, 'does not match');
    expect(find.text(ui('当前歌词中没有匹配内容')), findsOneWidget);
    expect(applyButton(tester).onPressed, isNotNull);
    await tester.tap(_key('lyric-segment-apply'));
    await tester.pumpAndSettle();
    expect(playback.segmentLoop.start, 10);
    expect(playback.segmentLoop.end, 17);
    expect(playback.starts, 0);
  });

  testWidgets('short line selection becomes valid as a reversed two-line range',
      (tester) async {
    final playback = _Playback();
    addTearDown(playback.dispose);
    playback.segmentLoop.configurePractice(rounds: 4, interval: 1.5);
    final lyric = Lrc([
      _line(10000, 300, '短句一'),
      _line(10800, 300, '短句二'),
    ], LrcSource.local);
    await mount(tester, playback, lyric: lyric);
    expect(applyButton(tester).onPressed, isNull);
    await choose(tester, 1);
    expect(applyButton(tester).onPressed, isNull);
    await choose(tester, 0);
    expect(applyButton(tester).onPressed, isNotNull);
    await tester.tap(_key('lyric-segment-apply'));
    await tester.pumpAndSettle();
    expect(playback.segmentLoop.start, 10);
    expect(playback.segmentLoop.end, 11.1);
    expect(playback.segmentLoop.totalRounds, 4);
    expect(playback.segmentLoop.intervalSeconds, 1.5);
    expect(playback.sought, 10);
    expect(playback.starts, 0);
  });

  for (final source in [false, true]) {
    testWidgets(
        'saved apply callback rejects ${source ? 'lyric replacement' : 'new session with same lyric'}',
        (tester) async {
      final playback = _Playback();
      addTearDown(playback.dispose);
      final changes = ValueNotifier(0);
      addTearDown(changes.dispose);
      var valid = true;
      await mount(tester, playback, current: () => valid, changes: changes);
      final oldApply = applyButton(tester).onPressed!;
      playback.segmentLoop.setStart(1, 100);
      playback.segmentLoop.setEnd(3, 100);
      if (source) {
        valid = false;
        changes.value++;
      } else {
        playback.switchSession();
      }
      await tester.pumpAndSettle();
      expect(applyButton(tester).onPressed, isNull);
      oldApply();
      await tester.pumpAndSettle();
      expect(playback.segmentLoop.start, 1);
      expect(playback.segmentLoop.end, 3);
      expect(playback.enables, 0);
      expect(find.text(ui('歌曲或歌词已改变，请重新选择练习片段')), findsOneWidget);
    });
  }

  testWidgets('output transition disables selection then preserves the draft',
      (tester) async {
    final playback = _Playback();
    addTearDown(playback.dispose);
    await mount(tester, playback);
    await search(tester, 'night');
    await choose(tester, 0);
    await choose(tester, 4);
    playback.isChangingOutput.value = true;
    await tester.pumpAndSettle();
    expect(applyButton(tester).onPressed, isNull);
    final end = tester.widget<ListTile>(_key('lyric-segment-line-4'));
    expect(end.onTap, isNull);
    playback.isChangingOutput.value = false;
    await tester.pumpAndSettle();
    expect(applyButton(tester).onPressed, isNotNull);
    expect(tester.widget<Text>(_key('lyric-segment-range')).data,
        '练习范围：0:00:10 — 0:00:17 · 4 句');
  });

  testWidgets('keyboard find and Escape close without altering the loop',
      (tester) async {
    final playback = _Playback();
    addTearDown(playback.dispose);
    playback.segmentLoop.setStart(1, 100);
    playback.segmentLoop.setEnd(3, 100);
    await mount(tester, playback);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF,
        physicalKey: PhysicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.pump();
    final field = tester.widget<TextField>(_key('lyric-segment-search'));
    expect(field.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape,
        physicalKey: PhysicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(LyricSegmentPracticeDialog), findsNothing);
    expect(playback.segmentLoop.start, 1);
    expect(playback.segmentLoop.end, 3);
    expect(playback.enables, 0);
  });

  for (final language in UiLanguage.values) {
    testWidgets(
        'four-language segment dialog wide narrow large ${language.name}',
        (tester) async {
      uiLanguage.value = language;
      for (final (width, scale, size) in [
        (900.0, 1.0, 'wide'),
        (420.0, 1.3, 'narrow'),
        (360.0, 3.0, 'large'),
      ]) {
        final playback = _Playback();
        final capture = GlobalKey();
        await mount(tester, playback,
            width: width, scale: scale, capture: capture);
        expect(tester.takeException(), isNull);
        expect(find.text(ui('起始句')), findsOneWidget);
        expect(find.text(ui('结束句')), findsOneWidget);
        expect(applyButton(tester).onPressed, isNotNull);
        if (output != null) {
          final bytes = await captureLyricShare(tester, capture);
          await tester.runAsync(() async {
            await Directory(output).create(recursive: true);
            await File(path.join(output, '${language.name}-$size.png'))
                .writeAsBytes(bytes);
          });
        }
        await tester.ensureVisible(_key('lyric-segment-start'));
        await tester.tap(_key('lyric-segment-start'));
        await tester.pumpAndSettle();
        expect(
            (tester.getRect(_key('lyric-segment-start')).height -
                    tester.getRect(_key('lyric-segment-end')).height)
                .abs(),
            lessThan(.01));
        await tester.ensureVisible(_key('lyric-segment-apply'));
        await tester.tap(_key('lyric-segment-apply'));
        await tester.pumpAndSettle();
        expect(playback.enables, 1);
        expect(playback.starts, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        playback.dispose();
      }
    });
  }
}
