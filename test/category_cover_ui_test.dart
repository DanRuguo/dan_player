import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dan_player/component/artwork_handoff.dart';
import 'package:dan_player/library/category_cover_store.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/page/categories_page.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/music_category_fixtures.dart';

class _TestCategoryCoverStore extends CategoryCoverStore {
  _TestCategoryCoverStore(Directory directory)
      : super(dataDirectory: () async => directory);

  void pulse() => notifyListeners();
}

class _ReconciliationSpyStore extends CategoryCoverStore {
  _ReconciliationSpyStore(Directory directory)
      : super(dataDirectory: () async => directory);

  final List<(MusicCategoryKind, List<String>)> reconciliations = [];

  @override
  Future<void> load() async {}

  @override
  Future<void> reconcileKind(
      MusicCategoryKind kind, Iterable<MusicCategoryGroup> activeGroups) async {
    reconciliations.add((
      kind,
      activeGroups.map((group) => group.persistenceKey).toList(),
    ));
  }
}

Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xff336688), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(96, 64);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory parent;
  late Directory fixture;
  late _TestCategoryCoverStore covers;

  setUp(() async {
    parent = await Directory(path.join(
            Directory.current.parent.path, 'tool', 'qa-category-cover-ui'))
        .create(recursive: true);
    fixture = await parent.createTemp('category-cover-ui-');
    covers = _TestCategoryCoverStore(fixture);
  });

  tearDown(() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    final resolved = await fixture.resolveSymbolicLinks();
    if (!path.isWithin(await parent.resolveSymbolicLinks(), resolved) ||
        !path.basename(resolved).startsWith('category-cover-ui-')) {
      throw StateError('Refusing to remove an unverified category UI fixture.');
    }
    await Directory(resolved).delete(recursive: true);
  });

  testWidgets(
      'visible cover menu displays managed art and exposes both actions',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final bytes = await tester.runAsync(_png);
    final source = File(path.join(fixture.path, 'selected.png'))
      ..writeAsBytesSync(bytes!, flush: true);
    final audio = CategoryTestAudio('Song', artist: 'Visible Artist');
    final group =
        MusicCategories([audio]).groups(MusicCategoryKind.artist).single;
    await tester.runAsync(() => covers.setCover(group, source.path));
    await tester.runAsync(() => covers.imageFor(group));
    var pickerOpened = false;
    final pickerResult = Completer<String?>();

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      home: Scaffold(
        body: CategoriesPage(
          audios: [audio],
          coverStore: covers,
          pickCover: () {
            pickerOpened = true;
            return pickerResult.future;
          },
          onOpenGroup: (_) {},
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
        find.descendant(
            of: find.byKey(ValueKey(('category-cover', group.id))),
            matching: find.byType(ArtworkHandoff)),
        findsOneWidget);
    final coverMenu = find.byKey(ValueKey(('category-cover-menu', group.id)));
    Future<void> openCoverMenu() async {
      final gesture = await tester.startGesture(tester.getCenter(coverMenu),
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.byIcon(Icons.more_horiz), findsNothing);
    await openCoverMenu();
    expect(find.widgetWithText(MenuItemButton, '更改歌单封面'), findsOneWidget);
    expect(find.widgetWithText(MenuItemButton, '移除自定义封面'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey(('category-change-cover', group.id))));
    await tester.pump();
    expect(pickerOpened, isTrue);
    covers.pulse();
    await tester.pump();
    await openCoverMenu();
    expect(
        tester
            .widget<MenuItemButton>(
                find.byKey(ValueKey(('category-change-cover', group.id))))
            .onPressed,
        isNull);
    await tester.tapAt(Offset.zero);
    await tester.pump();
    pickerResult.complete(null);
    await tester.pumpAndSettle();
    await openCoverMenu();
    expect(
        tester
            .widget<MenuItemButton>(
                find.byKey(ValueKey(('category-change-cover', group.id))))
            .onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'pending language scan cannot reconcile covers until groups are ready',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final lyrics = Completer<String?>();
    final spy = _ReconciliationSpyStore(fixture);
    final audio = CategoryTestAudio('Pending language');

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      home: Scaffold(
        body: CategoriesPage(
          initialCategory: MusicCategoryKind.language,
          audios: [audio],
          coverStore: spy,
          classificationScanner:
              MusicClassificationScanner(readLyrics: (_) => lyrics.future),
          onOpenGroup: (_) {},
        ),
      ),
    ));
    await tester.pump();
    expect(spy.reconciliations, isEmpty,
        reason: 'an empty pre-scan projection must not delete saved covers');

    lyrics.complete('[language:ja]\n[00:00]さくら');
    await tester.pumpAndSettle();
    expect(spy.reconciliations, hasLength(1));
    expect(spy.reconciliations.single.$1, MusicCategoryKind.language);
    expect(spy.reconciliations.single.$2, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing managed category cover falls back to first-song art',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final bytes = (await tester.runAsync(_png))!;
    final source = File(path.join(fixture.path, 'will-disappear.png'))
      ..writeAsBytesSync(bytes, flush: true);
    final audio = CategoryTestAudio('Fallback song', artist: 'Fallback artist');
    final group =
        MusicCategories([audio]).groups(MusicCategoryKind.artist).single;
    await tester.runAsync(() => covers.setCover(group, source.path));
    final id = covers.coverIdFor(group)!;
    await tester.runAsync(
        () => File(path.join(fixture.path, 'category-covers', id)).delete());
    final recovered = CategoryCoverStore(dataDirectory: () async => fixture);
    await tester.runAsync(recovered.load);
    // Complete real file I/O outside the widget clock before the fallback is
    // painted. A pending fake-zone future cannot be awaited from runAsync.
    await tester.runAsync(() => recovered.imageFor(group));

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      home: Scaffold(
        body: CategoriesPage(
          audios: [audio],
          coverStore: recovered,
          onOpenGroup: (_) {},
        ),
      ),
    ));
    await tester.pump();

    final cover = find.byKey(ValueKey(('category-cover', group.id)));
    expect(recovered.coverIdFor(group), id,
        reason: 'an unavailable image must not erase the manual choice');
    await tester.pumpAndSettle();
    expect(
        find.descendant(of: cover, matching: find.byType(Image)), findsNothing);
    expect(find.descendant(of: cover, matching: find.byType(Icon)),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(ValueKey(('category-cover', group.id))),
            matching: find.byType(ArtworkHandoff)),
        findsOneWidget);
    await tester.runAsync(() async {
      await File(path.join(fixture.path, 'category-covers', id))
          .writeAsBytes(bytes, flush: true);
      expect(await recovered.reread(group), isA<FileImage>());
    });
    await tester.pump();
    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pumpAndSettle();
    expect(recovered.coverIdFor(group), id);
    expect(find.descendant(of: cover, matching: find.byType(Image)),
        findsOneWidget);
    expect(
        find.descendant(of: cover, matching: find.byType(Icon)), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
