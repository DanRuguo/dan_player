import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/playlist_ui_actions.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/page/page_scaffold.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String name) => find.byKey(ValueKey(name));

class _CountingAudio extends CategoryTestAudio {
  _CountingAudio(super.id, {super.duration});
  int reads = 0;
  @override
  int get duration {
    reads++;
    return super.duration;
  }
}

class _DurationFixture {
  final roots = <Playlist>[];
  late final tree = PlaylistTree(roots);
  late final parent = tree.createPlaylist('Evening collection');
  late final child = tree.createPlaylist('Quiet songs', parent: parent);
  late final grandchild = tree.createPlaylist('Piano pieces', parent: child);
  final repeated = _CountingAudio('Repeated song', duration: 60);
  final unknown = CategoryTestAudio('Unknown duration', duration: 0);

  _DurationFixture() {
    tree.addAudio(parent, repeated);
    tree.addAudio(child, repeated);
    tree.addAudio(grandchild, CategoryTestAudio('Piano', duration: 3600));
    tree.addAudio(parent, unknown);
    tree.addAudio(child, CategoryTestAudio('Unverified', duration: -1));
  }

  Widget browser({Playlist? current, bool root = false}) => PlaylistBrowser(
        tree: tree,
        initialPlaylist: root ? null : current ?? parent,
        persist: () async {},
        onPlay: (_, __) {},
        trackBuilder: (_, audio, play, actions) => ListTile(
          title: Text(audio.displayTitle),
          onTap: play,
          trailing: actions,
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() {
    uiLanguage.value = UiLanguage.zh;
    playlistUiSaveError.value = null;
    playlistUiSaving.value = false;
  });
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  String summary(WidgetTester tester) =>
      tester.widget<Text>(_key('playlist-duration-summary')).data!;

  testWidgets('playlist duration includes descendants and repeated references',
      (tester) async {
    sizePlaylistFeature(tester);
    final fixture = _DurationFixture();
    await tester.pumpWidget(playlistFeatureHost(fixture.browser()));
    await tester.pumpAndSettle();
    expect(summary(tester),
        '${ui('总时长 {0}（含子歌单）', ['1:02:00'])}\n${ui('另有 {0} 首时长未知', [2])}');
    await tester.tap(_key('playlist-open-${fixture.child.id}'));
    await tester.pumpAndSettle();
    expect(summary(tester),
        '${ui('总时长 {0}（含子歌单）', ['1:01:00'])}\n${ui('另有 {0} 首时长未知', [1])}');
    await tester.pumpWidget(playlistFeatureHost(fixture.browser(root: true)));
    await tester.pumpAndSettle();
    expect(tester.widget<PageScaffold>(find.byType(PageScaffold)).subtitle,
        contains(ui('总时长 {0}（含子歌单）', ['1:02:00'])));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'duration refreshes after metadata and tree edits while idle stays cached',
      (tester) async {
    sizePlaylistFeature(tester);
    final fixture = _DurationFixture();
    await tester.pumpWidget(playlistFeatureHost(fixture.browser()));
    await tester.pumpAndSettle();
    final reads = fixture.repeated.reads;
    await tester.pump(const Duration(seconds: 2));
    expect(fixture.repeated.reads, reads,
        reason:
            'A duration summary has no playback timer or animation listener');
    fixture.unknown.duration = 150;
    AudioLibrary.instance.publishDurationChanges();
    await tester.pumpAndSettle();
    expect(summary(tester),
        '${ui('总时长 {0}（含子歌单）', ['1:04:30'])}\n${ui('另有 {0} 首时长未知', [1])}');
    fixture.tree.addAudio(
        fixture.grandchild, CategoryTestAudio('New known song', duration: 30));
    await savePlaylistUiChanges(persist: () async {});
    await tester.pumpAndSettle();
    expect(summary(tester), contains('1:05:00'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    // Global metadata invalidation after teardown must not reach a dead browser.
    AudioLibrary.instance.publishDurationChanges();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty and unknown-only playlists show descriptor limits',
      (tester) async {
    sizePlaylistFeature(tester);
    final tree = PlaylistTree([]);
    final empty = tree.createPlaylist('Empty');
    Widget browser() => playlistFeatureHost(PlaylistBrowser(
        tree: tree,
        initialPlaylist: empty,
        persist: () async {},
        trackBuilder: (_, audio, __, ___) => Text(audio.displayTitle)));
    await tester.pumpWidget(browser());
    await tester.pumpAndSettle();
    expect(summary(tester), ui('总时长 {0}（含子歌单）', ['0:00']));
    tree.addAudio(empty, CategoryTestAudio('Unknown', duration: 0));
    await savePlaylistUiChanges(persist: () async {});
    await tester.pumpAndSettle();
    expect(summary(tester),
        '${ui('总时长 {0}（含子歌单）', ['0:00'])}\n${ui('另有 {0} 首时长未知', [1])}');
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets('playlist duration stays complete $language narrow=$narrow',
          (tester) async {
        sizePlaylistFeature(tester, width: narrow ? 380 : 1100, height: 900);
        uiLanguage.value = language;
        final fixture = _DurationFixture();
        final boundary = GlobalKey();
        await tester.pumpWidget(playlistFeatureHost(fixture.browser(),
            textScale: narrow ? 2 : 1, boundary: boundary));
        await tester.pumpAndSettle();
        expect(summary(tester), contains(ui('另有 {0} 首时长未知', [2])));
        if (language != UiLanguage.zh) {
          expect(summary(tester), isNot(contains('含子歌单')));
        }
        final paragraph = tester
            .renderObject<RenderParagraph>(_key('playlist-duration-summary'));
        expect(paragraph.didExceedMaxLines, isFalse);
        final summaryBounds = tester.getRect(_key('playlist-duration-summary'));
        expect(summaryBounds.left, greaterThanOrEqualTo(0));
        expect(summaryBounds.right, lessThanOrEqualTo(narrow ? 380 : 1100));
        expect(summaryBounds.bottom, lessThan(900));
        expect(_key('playlist-play-${fixture.child.id}').hitTestable(),
            findsOneWidget);
        expect(tester.takeException(), isNull);
        await capturePlaylistFeature(tester, boundary,
            '${language.name}-${narrow ? 'narrow' : 'wide'}-duration');
      });
    }
  }
}
