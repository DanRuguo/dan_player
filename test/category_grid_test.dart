import 'package:dan_player/component/audio_artwork.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/page/categories_page.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

class _CardAudio extends CategoryTestAudio {
  _CardAudio(super.id, String artist)
      : super(artist: artist, composer: '作曲家', language: 'zh');

  final requests = <ArtworkSize>[];

  @override
  Future<ImageProvider?> artworkForSize(ArtworkSize size) {
    requests.add(size);
    return super.artworkForSize(size);
  }
}

void _viewport(WidgetTester tester, {double dpr = 1}) {
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = Size(900 * dpr, 700 * dpr);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(body: child),
    );

Finder _artwork(_CardAudio audio) => find.byWidgetPredicate(
    (widget) => widget is AudioArtwork && identical(widget.audio, audio));

void main() {
  tearDown(() => expect(PlayService.isInitialized, isFalse));

  for (final kind in MusicCategoryKind.values) {
    testWidgets(
        '$kind has a round cover above its label and opens the original songs',
        (tester) async {
      _viewport(tester, dpr: 2);
      final song = _CardAudio('Fixture', '艺术家');
      final expected = MusicCategories([song]).groups(kind).single;
      final opened = <MusicCategoryGroup>[];
      await tester.pumpWidget(_host(CategoriesPage(
        initialCategory: kind,
        audios: [song],
        onOpenGroup: opened.add,
      )));
      await tester.pumpAndSettle();
      final cover = find.byKey(ValueKey(('category-cover', expected.id)));
      final rect = tester.getRect(cover);
      expect(tester.widget<ClipRRect>(cover).borderRadius,
          BorderRadius.circular(rect.width / 2));
      expect(rect.width, rect.height);
      expect(rect.width, inInclusiveRange(80, 112));
      final title = find.descendant(
          of: find.byKey(ValueKey(('category-card', expected.id))),
          matching: find.text(expected.title));
      expect(
          tester.getTopLeft(title).dy, greaterThanOrEqualTo(rect.bottom + 7.9));
      expect(song.requests.single.width, greaterThanOrEqualTo(rect.width * 2));
      expect(
          song.requests.single.height, greaterThanOrEqualTo(rect.height * 2));
      await tester.tap(cover);
      await tester.pumpAndSettle();
      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(opened, hasLength(2));
      expect(opened.every((group) => group.kind == kind), isTrue);
      expect(opened.last.audios.single, same(song));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('round category cards remain keyboard-activatable',
      (tester) async {
    _viewport(tester);
    final song = _CardAudio('Fixture', 'Keyboard artist');
    var opened = 0;
    await tester.pumpWidget(_host(CategoriesPage(
      audios: [song],
      onOpenGroup: (_) => opened++,
    )));
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.text('Keyboard artist'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filtering keeps a surviving category artwork state and request',
      (tester) async {
    _viewport(tester);
    final alpha = _CardAudio('First', 'Alpha');
    final beta = _CardAudio('Second', 'Beta');
    await tester.pumpWidget(_host(CategoriesPage(audios: [alpha, beta])));
    await tester.pumpAndSettle();
    final state = tester.state(_artwork(beta));
    final requests = beta.requests.length;
    await tester.enterText(
        find.byKey(const ValueKey('category-search')), 'Beta');
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsNothing);
    expect(tester.state(_artwork(beta)), same(state));
    expect(beta.requests.length, requests);
    expect(tester.takeException(), isNull);
  });

  testWidgets('category grid remains virtualized for a large synthetic library',
      (tester) async {
    _viewport(tester);
    final songs =
        List.generate(1000, (i) => _CardAudio('Song $i', 'Artist $i'));
    await tester.pumpWidget(_host(CategoriesPage(audios: songs)));
    await tester.pumpAndSettle();
    expect(find.byType(SliverGrid), findsOneWidget);
    expect(
        songs.where((song) => song.requests.isNotEmpty).length, lessThan(100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('moving to a higher DPR upgrades covers without discarding state',
      (tester) async {
    _viewport(tester);
    final song = _CardAudio('Fixture', 'Artist');
    final page = CategoriesPage(audios: [song]);
    await tester.pumpWidget(_host(page));
    await tester.pumpAndSettle();
    final state = tester.state(_artwork(song));
    final first = song.requests.single;
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(1800, 1400);
    await tester.pumpAndSettle();
    expect(tester.state(_artwork(song)), same(state));
    expect(song.requests, hasLength(2));
    expect(song.requests.last.width, greaterThan(first.width));
    expect(song.requests.last.height, greaterThan(first.height));
    expect(tester.takeException(), isNull);
  });
}
