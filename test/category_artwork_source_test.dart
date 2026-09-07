import 'dart:io';
import 'dart:ui' as ui;

import 'package:dan_player/component/category_cover.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/category_cover_store.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/music_category_fixtures.dart';

class _CoveredAudio extends CategoryTestAudio {
  _CoveredAudio(super.id, this.image, {super.track});
  final ImageProvider image;
  int reads = 0;

  @override
  Future<ImageProvider?> artworkForSize(ArtworkSize size) {
    reads++;
    return SynchronousFuture(image);
  }
}

Future<Uint8List> _png(Color color) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(color, ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(32, 32);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pumpAndSettle();
}

void main() {
  late Directory fixture;
  late CategoryCoverStore covers;
  final fixtureRoot = Directory(path.join(
      Directory.current.parent.path, 'tool', 'qa-local', 'snapshot5-artwork'));

  setUp(() async {
    await fixtureRoot.create(recursive: true);
    fixture = await fixtureRoot.createTemp('category-artwork-');
    covers = CategoryCoverStore(dataDirectory: () async => fixture);
  });
  tearDown(() async {
    covers.dispose();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (!path.isWithin(fixtureRoot.absolute.path, fixture.absolute.path)) {
      throw StateError('Refusing cleanup outside artwork fixtures');
    }
    await fixture.delete(recursive: true);
  });

  for (final kind in MusicCategoryKind.browsableValues) {
    testWidgets('${kind.name} uses the first default detail row and real art',
        (tester) async {
      final firstImage =
          MemoryImage((await tester.runAsync(() => _png(Colors.blue)))!);
      final secondImage =
          MemoryImage((await tester.runAsync(() => _png(Colors.orange)))!);
      final first = _CoveredAudio('First indexed', firstImage, track: 9);
      final second = _CoveredAudio('First album track', secondImage, track: 1);
      final group = MusicCategories([first, second]).groups(kind).single;
      final expected = kind == MusicCategoryKind.album ? second : first;
      expect(group.coverAudio, same(expected));
      expect(group.audios, [same(first), same(second)],
          reason: 'choosing artwork must not mutate library or playback order');
      await tester.pumpWidget(MaterialApp(
          home: CategoryCover(
              group: group,
              store: covers,
              size: 112,
              placeholder: const Text('No cover'))));
      await _settle(tester);
      expect(
          tester.widget<Image>(find.byType(Image)).image, same(expected.image));
      expect(find.text('No cover'), findsNothing);
      expect(expected.reads, 1);
      expect((identical(expected, first) ? second : first).reads, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('custom category art wins and removal restores its first song',
      (tester) async {
    final songImage =
        MemoryImage((await tester.runAsync(() => _png(Colors.blue)))!);
    final chosenBytes = (await tester.runAsync(() => _png(Colors.purple)))!;
    final selected = File(path.join(fixture.path, 'custom.png'))
      ..writeAsBytesSync(chosenBytes);
    final song = _CoveredAudio('Song', songImage);
    final group =
        MusicCategories([song]).groups(MusicCategoryKind.artist).single;
    await tester.runAsync(() => covers.setCover(group, selected.path));
    await tester.runAsync(() => covers.imageFor(group));
    Widget page() => MaterialApp(
        home: CategoryCover(
            group: group,
            store: covers,
            size: 112,
            placeholder: const Text('No cover')));
    await tester.pumpWidget(page());
    await _settle(tester);
    expect(covers.hasCover(group), isTrue);
    expect(find.byType(Image), findsOneWidget);
    expect(
        tester.widget<Image>(find.byType(Image)).image, isNot(same(songImage)));
    await tester.runAsync(() => covers.removeCover(group));
    await tester.pumpWidget(page());
    await _settle(tester);
    expect(covers.hasCover(group), isFalse);
    expect(tester.widget<Image>(find.byType(Image)).image, same(songImage));
    expect(tester.takeException(), isNull);
  });
}
