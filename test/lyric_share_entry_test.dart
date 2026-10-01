import 'dart:async';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_share_projection.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_reading_tools.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:desktop_lyric/l10n/catalog_offline_tools.dart';
import 'package:desktop_lyric/l10n/ui_catalog.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playlist_feature_fixture.dart';

class _Lyrics extends Lyric {
  _Lyrics(super.lines);
}

class _Line extends UnsyncLyricLine {
  _Line(super.start, super.content);
}

class _Word extends SyncLyricWord {
  _Word(super.start, super.length, super.content);
}

class _SyncLine extends SyncLyricLine {
  _SyncLine(super.start, super.length, super.words, [super.translation]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPlaylistFeatureFonts);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  test('share projection maps the current line after filtering timing spacers',
      () {
    final lyric = _Lyrics([
      _Line(Duration.zero, ''),
      _Line(const Duration(seconds: 2), 'first'),
      _Line(const Duration(seconds: 4), ' \t'),
      _Line(const Duration(seconds: 6), 'second'),
      _Line(const Duration(seconds: 8), 'last'),
    ]);
    for (final (position, expected) in [(0, 0), (4, 0), (6, 1), (9, 2)]) {
      final result = lyricShareProjection(lyric,
          position: Duration(seconds: position), project: lyricReadingText);
      expect(result.lines, ['first', 'second', 'last']);
      expect(result.initialIndex, expected);
    }
  });

  test(
      'word lyric display flags preserve translations, emoji and source timing',
      () {
    final first = _Word(const Duration(milliseconds: 12500),
        const Duration(milliseconds: 500), '  Hello 👩🏽‍🚀');
    final second =
        _Word(const Duration(seconds: 13), const Duration(seconds: 1), '世界 ');
    final words = [first, second];
    final line = _SyncLine(const Duration(milliseconds: 12500),
        const Duration(milliseconds: 1500), words, '  訳文 e\u0301  ')
      ..romanization = '  Héllo world  ';
    final lyric = _Lyrics([line]);
    final source = (
      line.start,
      line.length,
      line.content,
      line.translation,
      line.romanization,
      [for (final word in words) (word.start, word.length, word.content)],
    );
    final shown = lyricShareProjection(lyric,
        position: const Duration(seconds: 13),
        project: (line) => lyricReadingText(line, timestamp: true));
    expect(shown.lines,
        ['  Héllo world  \n[00:12.500]   Hello 👩🏽‍🚀世界 \n  訳文 e\u0301  ']);
    final hidden = lyricShareProjection(lyric,
        position: const Duration(seconds: 13),
        project: (line) => lyricReadingText(line,
            translation: false, romanization: false, timestamp: false));
    expect(hidden.lines, ['  Hello 👩🏽‍🚀世界 ']);
    expect((
      line.start,
      line.length,
      line.content,
      line.translation,
      line.romanization
    ), (
      source.$1,
      source.$2,
      source.$3,
      source.$4,
      source.$5
    ));
    expect(line.words, same(words));
    expect([for (final word in words) (word.start, word.length, word.content)],
        source.$6);
  });

  test('untimed CRLF text becomes individual nonempty candidates without times',
      () {
    const text = 'First\r\n \t\r\n  👨‍👩‍👧‍👦  e\u0301 日本語  \r\nLast';
    final lyric = PlainLyric(text);
    final originalContent = (lyric.lines.single as PlainLyricLine).content;
    final result = lyricShareProjection(lyric,
        position: const Duration(hours: 1), project: lyricReadingText);
    expect(result.lines, ['First', '  👨‍👩‍👧‍👦  e\u0301 日本語  ', 'Last']);
    expect(result.initialIndex, 0,
        reason: 'The technical zero anchor is not per-line timing.');
    expect(result.lines.any((line) => line.startsWith('[00:')), isFalse);
    expect(lyric.text, text);
    expect(lyric.lines.length, 1);
    expect((lyric.lines.single as PlainLyricLine).content, originalContent);
  });

  test(
      'share text is a detached immutable snapshot including empty projections',
      () {
    final first = _Line(Duration.zero, 'old 👨‍👩‍👧‍👦');
    final second = _Line(const Duration(seconds: 1), 'second');
    final lyric = _Lyrics([first, second]);
    final result = lyricShareProjection(lyric,
        position: const Duration(seconds: 1), project: lyricReadingText);
    first.content = 'edited';
    lyric.lines.removeLast();
    expect(result.lines, ['old 👨‍👩‍👧‍👦', 'second']);
    expect(result.initialIndex, 1);
    expect(() => result.lines.add('extra'), throwsUnsupportedError);
    expect(() => result.lines[0] = 'replacement', throwsUnsupportedError);
    final empty = lyricShareProjection(_Lyrics([_Line(Duration.zero, ' \t')]),
        position: Duration.zero, project: lyricReadingText);
    expect(empty.lines, isEmpty);
    expect(empty.initialIndex, 0);
    expect(() => empty.lines.add('extra'), throwsUnsupportedError);
  });

  test('new offline catalog is complete and reached by actual ui lookups', () {
    final placeholder = RegExp(r'\{\d+\}');
    for (final entry in catalogOfflineTools.entries) {
      expect(entry.value, hasLength(3));
      expect(uiCatalog[entry.key], entry.value);
      final expected =
          placeholder.allMatches(entry.key).map((match) => match[0]).toSet();
      for (var i = 0; i < entry.value.length; i++) {
        final translated = entry.value[i];
        expect(translated.trim(), isNotEmpty);
        expect(
            placeholder.allMatches(translated).map((match) => match[0]).toSet(),
            expected);
        uiLanguage.value = UiLanguage.values[i + 1];
        expect(ui(entry.key), translated);
      }
    }
  });

  for (final language in UiLanguage.values) {
    testWidgets(
        'share menu forwards the mounted root navigator ${language.name}',
        (tester) async {
      uiLanguage.value = language;
      sizePlaylistFeature(tester, width: 360, height: 850);
      final controller = LyricViewController(
          preferences: NowPlayingPagePreference.fromMap({}));
      addTearDown(controller.dispose);
      final root = GlobalKey<NavigatorState>();
      final nested = GlobalKey<NavigatorState>();
      final release = Completer<void>();
      NavigatorState? captured;
      final lyric = Future<Lyric?>.value(PlainLyric('one\ntwo'));
      final host = playlistFeatureHost(
          Navigator(
              key: nested,
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                      body: Center(
                          child: LyricReadingMenu(
                              controller: controller,
                              readLyric: () => lyric,
                              onCreateCard: (navigator) async {
                                captured = navigator;
                                await release.future;
                                expect(navigator.mounted, isTrue);
                                await showDialog<void>(
                                    context: navigator.context,
                                    builder: (_) => AlertDialog(
                                            key: const ValueKey(
                                                'host-card-dialog'),
                                            title: const Text('card'),
                                            actions: [
                                              TextButton(
                                                  onPressed: () =>
                                                      navigator.pop(),
                                                  child: const Text('Done')),
                                            ]));
                              }))))),
          textScale: 2);
      final app = host as MaterialApp;
      await tester.pumpWidget(MaterialApp(
          navigatorKey: root,
          theme: app.theme,
          builder: app.builder,
          home: app.home));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lyric-reading-tools')));
      await tester.pumpAndSettle();
      final action = find.byKey(const ValueKey('lyric-create-share-card'));
      expect(find.text(ui('制作歌词卡片')), findsOneWidget);
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(captured, same(root.currentState));
      expect(captured, isNot(same(nested.currentState)));
      expect(captured!.mounted, isTrue);
      expect(action, findsNothing,
          reason:
              'The menu has closed before the delayed card callback resumes.');
      release.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('host-card-dialog')), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('host-card-dialog')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('share entry remains optional for existing reading menus',
      (tester) async {
    final controller =
        LyricViewController(preferences: NowPlayingPagePreference.fromMap({}));
    addTearDown(controller.dispose);
    await tester.pumpWidget(playlistFeatureHost(Center(
        child:
            LyricReadingMenu(controller: controller, readLyric: () => null))));
    await tester.tap(find.byKey(const ValueKey('lyric-reading-tools')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lyric-create-share-card')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
