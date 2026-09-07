import 'dart:async';
import 'dart:ui' as ui;

import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/audio_artwork.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/playlist_reorder_surface.dart';
import 'package:dan_player/component/playlist_toolbar.dart';
import 'package:dan_player/component/playlist_ui_actions.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'support/playlist_actions.dart';
import 'support/music_category_fixtures.dart';

Audio _audio(String name) => Audio.online(
      provider: 'qq',
      id: name,
      title: name,
      artist: 'Artist',
      album: 'Album',
      duration: 180,
    );

class _ImageAudio extends Audio {
  _ImageAudio(String name, this.image)
      : super(name, 'Artist', 'Album', 0, 180, null, null, 'online://qq/$name',
            0, 0, 'Test',
            onlineProvider: 'qq', onlineId: name);

  final ImageProvider image;
  int requests = 0;

  @override
  Future<ImageProvider?> artworkForSize(ArtworkSize target) {
    requests++;
    return SynchronousFuture<ImageProvider?>(image);
  }
}

class _Fixture {
  final roots = <Playlist>[];
  late final tree = PlaylistTree(roots);
  late final root = tree.createPlaylist('Parent');
  int saves = 0;
  final played = <({int index, List<Audio> queue})>[];

  Widget browser({Future<void> Function()? persist, bool realRows = false}) =>
      PlaylistBrowser(
        tree: tree,
        initialPlaylist: root,
        persist: persist ?? () async => saves++,
        onPlay: (index, queue) => played.add((index: index, queue: queue)),
        trackBuilder: realRows
            ? null
            : (_, audio, play, action) => SizedBox(
                  height: 64,
                  child: ListTile(
                    title: Text(audio.title),
                    onTap: play,
                    trailing: action,
                  ),
                ),
      );
}

Future<void> _show(WidgetTester tester, Widget child,
    {bool animations = false, double textScale = 1}) async {
  tester.view.physicalSize = const Size(1100, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(platform: TargetPlatform.windows, useMaterial3: true),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: !animations,
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
    home: Scaffold(body: child),
  ));
  await tester.pumpAndSettle();
}

Finder _row(String id) => find.byKey(ValueKey(('playlist-entry', id)));
Finder _handle(String id) => find.byKey(ValueKey('playlist-drag-$id'));

Future<void> _sort(WidgetTester tester, String label) async {
  final mode =
      PlaylistSortMode.values.firstWhere((mode) => mode.label == label);
  await tester.tap(find.byKey(const ValueKey('playlist-sort')));
  await tester.pumpAndSettle();
  final field = find.byKey(ValueKey('playlist-sort-${mode.baseMode.name}'));
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  if (mode.direction != null) {
    await tester.tap(find.byKey(const ValueKey('playlist-sort')));
    await tester.pumpAndSettle();
    final direction =
        find.byKey(ValueKey('app-sort-direction-${mode.direction!.name}'));
    await tester.ensureVisible(direction);
    await tester.tap(direction);
    await tester.pumpAndSettle();
  }
}

Future<TestGesture> _dragPast(
    WidgetTester tester, String id, String last) async {
  final start = tester.getCenter(_handle(id));
  final grabOffset = start.dy - tester.getTopLeft(_row(id)).dy;
  final drag =
      await tester.startGesture(start, kind: ui.PointerDeviceKind.mouse);
  await drag.moveBy(const Offset(0, 16));
  await tester.pump(const Duration(milliseconds: 80));
  // Cross the target with the proxy's top edge, not only the pointer, and use
  // a continuous gesture as a real mouse/touch drag would deliver.
  final end =
      Offset(start.dx, tester.getBottomRight(_row(last)).dy + grabOffset + 4);
  for (var step = 1; step <= 4; step++) {
    await drag.moveTo(Offset.lerp(start, end, step / 4)!);
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 300));
  return drag;
}

void main() {
  setUp(() {
    playlistUiSaveError.value = null;
    playlistUiSaving.value = false;
  });

  tearDown(() {
    expect(PlayService.isInitialized, isFalse,
        reason: 'UI regression must not initialize BASS or play real music');
  });

  testWidgets(
      'one right-side ellipsis is both handle and menu, never left dots',
      (tester) async {
    final fixture = _Fixture();
    final song = fixture.tree.addAudio(fixture.root, _audio('Song'));
    final folder = fixture.tree.createPlaylist('Child', parent: fixture.root);
    await _show(tester, fixture.browser());
    for (final id in [song.id, folder.id]) {
      expect(
          find.descendant(
              of: _row(id), matching: find.byIcon(Icons.drag_indicator)),
          findsNothing);
      expect(
          find.descendant(
              of: _row(id), matching: find.byIcon(Symbols.more_vert)),
          findsOneWidget);
      final bounds = tester.getRect(_row(id));
      final grip = tester.getRect(_handle(id));
      expect(grip.center.dx, greaterThan(bounds.right - 64));
      expect(grip.width, greaterThanOrEqualTo(40));
    }
    await tester.tap(_handle(song.id));
    await tester.pumpAndSettle();
    expect(find.text('移动到…'), findsOneWidget);
    expect(fixture.played, isEmpty);
    expect(fixture.saves, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('display sorting preserves custom order and sorted playback',
      (tester) async {
    final fixture = _Fixture();
    final z = fixture.tree.addAudio(fixture.root, _audio('Zulu'));
    final a = fixture.tree.addAudio(fixture.root, _audio('Alpha'));
    final m = fixture.tree.addAudio(fixture.root, _audio('Middle'));
    await _show(tester, fixture.browser());
    await _sort(tester, '名称升序');
    expect(fixture.root.entries.map((entry) => entry.id), [z.id, a.id, m.id]);
    expect(tester.getTopLeft(_row(a.id)).dy,
        lessThan(tester.getTopLeft(_row(m.id)).dy));
    expect(tester.getTopLeft(_row(m.id)).dy,
        lessThan(tester.getTopLeft(_row(z.id)).dy));
    expect(find.byType(PlaylistReorderHandle), findsNothing);
    expect(
        tester
            .widget<PlaylistReorderSurface>(find.byType(PlaylistReorderSurface))
            .enabled,
        isFalse);
    await playVisiblePlaylistSelection(tester);
    expect(fixture.played.last.queue.map((audio) => audio.title),
        ['Alpha', 'Middle', 'Zulu']);
    await _sort(tester, '自定义');
    expect(find.byType(PlaylistReorderHandle), findsNWidgets(3));
    expect(tester.getTopLeft(_row(z.id)).dy,
        lessThan(tester.getTopLeft(_row(a.id)).dy));
    await playVisiblePlaylistSelection(tester);
    expect(fixture.played.last.queue.map((audio) => audio.title),
        ['Zulu', 'Alpha', 'Middle']);
    expect(fixture.saves, 0,
        reason: 'Display preferences must never rewrite the custom tree order');
    expect(tester.takeException(), isNull);
  });

  testWidgets('child display order participates in depth-first parent playback',
      (tester) async {
    final fixture = _Fixture();
    fixture.tree.addAudio(fixture.root, _audio('Parent first'));
    final child = fixture.tree.createPlaylist('Child', parent: fixture.root);
    fixture.tree.addAudio(child, _audio('Zulu'));
    fixture.tree.addAudio(child, _audio('Alpha'));
    fixture.tree.addAudio(fixture.root, _audio('Parent last'));
    await _show(tester, fixture.browser());
    await tester.tap(find.byKey(ValueKey('playlist-open-${child.id}')));
    await tester.pumpAndSettle();
    await _sort(tester, '名称升序');
    await tester
        .tap(find.byKey(ValueKey('playlist-breadcrumb-${fixture.root.id}')));
    await tester.pumpAndSettle();
    await playVisiblePlaylistSelection(tester);
    expect(fixture.played.last.queue.map((audio) => audio.title),
        ['Parent first', 'Alpha', 'Zulu', 'Parent last']);
    expect(child.entries.map((entry) => entry.audio!.title), ['Zulu', 'Alpha']);
    expect(fixture.saves, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a second drag is accepted while an earlier save is pending',
      (tester) async {
    final fixture = _Fixture();
    final a = fixture.tree.addAudio(fixture.root, _audio('A'));
    final b = fixture.tree.addAudio(fixture.root, _audio('B'));
    final c = fixture.tree.addAudio(fixture.root, _audio('C'));
    final pending = <Completer<void>>[];
    addTearDown(() {
      for (final save in pending) {
        if (!save.isCompleted) save.complete();
      }
    });
    await _show(tester, fixture.browser(persist: () {
      final save = Completer<void>();
      pending.add(save);
      return save.future;
    }));
    var drag = await _dragPast(tester, a.id, c.id);
    await drag.up();
    await tester.pumpAndSettle();
    expect(fixture.root.entries.map((entry) => entry.id), [b.id, c.id, a.id]);
    expect(pending.length, 1);
    expect(playlistUiSaving.value, isTrue);
    expect(
        tester
            .widget<PlaylistToolbar>(find.byType(PlaylistToolbar))
            .editingEnabled,
        isTrue);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    drag = await _dragPast(tester, b.id, a.id);
    await drag.up();
    await tester.pumpAndSettle();
    expect(pending.length, 2);
    expect(fixture.root.entries.map((entry) => entry.id), [c.id, a.id, b.id]);
    pending.last.complete();
    await tester.pumpAndSettle();
    pending.first.completeError(StateError('An older snapshot failed'));
    await tester.pumpAndSettle();
    expect(playlistUiSaveError.value, isNull);
    expect(find.textContaining('保存失败'), findsNothing);
    expect(fixture.root.entries.map((entry) => entry.id), [c.id, a.id, b.id]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('200 percent real song rows keep their height and state in drag',
      (tester) async {
    final fixture = _Fixture();
    final entries = ['First', 'Middle', 'Last']
        .map((name) => fixture.tree
            .addAudio(fixture.root, CategoryTestAudio(name, online: true)))
        .toList();
    await _show(tester, fixture.browser(realRows: true),
        textScale: 2, animations: true);
    final first = entries.first;
    final artwork = find.descendant(
        of: _row(first.id), matching: find.byType(AudioArtwork));
    final originalState = tester.state(artwork);
    final originalHeight = tester.getSize(_row(first.id)).height;
    expect(originalHeight, greaterThan(64));
    expect(tester.takeException(), isNull);
    final drag = await _dragPast(tester, first.id, entries.last.id);
    expect(tester.getSize(_row(first.id)).height, originalHeight);
    expect(tester.state(artwork), same(originalState));
    expect(tester.takeException(), isNull);
    await drag.up();
    await tester.pumpAndSettle();
    expect(fixture.root.entries.map((entry) => entry.id),
        [entries[1].id, entries[2].id, first.id]);
    expect(tester.getSize(_row(first.id)).height, originalHeight);
    expect(tester.state(artwork), same(originalState));
    expect(fixture.saves, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('real AudioTile keeps decoded artwork and entrance state in drag',
      (tester) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 96, 96),
        Paint()..color = const Color(0xFF256A80));
    final picture = recorder.endRecording();
    final bytes = await tester.runAsync(() async {
      final image = await picture.toImage(96, 96);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return png!.buffer.asUint8List();
    });
    picture.dispose();
    final fixture = _Fixture();
    final illustrated = _ImageAudio('Illustrated', MemoryImage(bytes!));
    final first = fixture.tree.addAudio(fixture.root, illustrated);
    final last = fixture.tree.addAudio(fixture.root, _audio('Other'));
    await _show(tester, fixture.browser(realRows: true), animations: true);
    expect(find.byType(AudioTile), findsNWidgets(2));
    final artwork = find.descendant(
        of: _row(first.id), matching: find.byType(AudioArtwork));
    final originalState = tester.state(artwork);
    // Both the enlarged header cover and this row's 48px cover subscribe once.
    // Moving the row must not restart either artwork subscription.
    expect(illustrated.requests, 2);
    final originalRequests = illustrated.requests;
    await tester.runAsync(
        () => precacheImage(illustrated.image, tester.element(artwork)));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<RawImage>(
                find.descendant(of: artwork, matching: find.byType(RawImage)))
            .image,
        isNotNull);
    expect(find.descendant(of: artwork, matching: find.byType(Image)),
        findsOneWidget);
    final drag = await _dragPast(tester, first.id, last.id);
    expect(tester.state(artwork), same(originalState));
    expect(illustrated.requests, originalRequests);
    for (final opacity in tester.widgetList<Opacity>(
        find.descendant(of: _row(first.id), matching: find.byType(Opacity)))) {
      expect(opacity.opacity, 1,
          reason: 'The proxy must not replay a first-appearance fade');
    }
    await drag.up();
    await tester.pumpAndSettle();
    expect(tester.state(artwork), same(originalState));
    expect(illustrated.requests, originalRequests);
    expect(find.descendant(of: artwork, matching: find.byType(Image)),
        findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(fixture.root.entries.first.id, last.id);
    expect(find.byType(AppEntrance), findsWidgets,
        reason: 'Normal first-appearance animation remains in place');
    expect(tester.takeException(), isNull);
  });
}
