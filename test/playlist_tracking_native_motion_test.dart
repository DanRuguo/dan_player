import 'dart:async';
import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/playlist_cover_transition.dart';
import 'package:dan_player/component/playlist_toolbar.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

class _ArtworkAudio extends CategoryTestAudio {
  _ArtworkAudio(this.image) : super('Native tracking', online: true);
  final ImageProvider image;
  Future<ImageProvider?>? pending;
  @override
  Future<ImageProvider?> artworkForSize(ArtworkSize size) =>
      pending ?? Future.value(image);
}

Future<Uint8List> _art() async {
  final recorder = drawing.PictureRecorder();
  Canvas(recorder).drawColor(Colors.red, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(128, 128);
  try {
    return (await image.toByteData(format: drawing.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<void> _decode(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
  }
}

void main() {
  late Directory directory;
  late ImageProvider artwork;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('native-tracking-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => directory.path);
    artwork = MemoryImage(await _art());
    await loadPlaylistFeatureFonts();
  });
  tearDownAll(() async {
    await AppPreference.instance.save();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    await directory.delete(recursive: true);
  });

  for (final phase in [
    'active cover flight',
    'late artwork holding',
    'capture'
  ]) {
    final holding = phase == 'late artwork holding';
    final capturing = phase == 'capture';
    testWidgets('native reduceMotion retires real browser $phase',
        (tester) async {
      sizePlaylistFeature(tester, width: 1080, height: 850);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final tree = PlaylistTree([]);
      final playlist = tree.createPlaylist('Tracking');
      final song = _ArtworkAudio(artwork);
      tree.addAudio(playlist, song);
      await tester.pumpWidget(MaterialApp(
          theme: applyAppControlTheme(ThemeData(
              useMaterial3: true,
              fontFamily: danEmbeddedFontFamily,
              fontFamilyFallback: danFontFamilyFallback)),
          home: Scaffold(
              body: PlaylistBrowser(
                  tree: tree,
                  initialPlaylist: playlist,
                  initialView: PlaylistViewMode.list,
                  onPlay: (_, __) {},
                  persist: () async {}))));
      await _decode(tester);
      await tester.pumpAndSettle();
      final controller = tester
          .widget<PlaylistCoverTransitionHost>(
              find.byType(PlaylistCoverTransitionHost))
          .controller;
      final pending = Completer<ImageProvider?>();
      if (holding) song.pending = pending.future;
      addTearDown(() {
        if (!pending.isCompleted) pending.complete(artwork);
      });
      await tester.runAsync(() async {
        tester
            .widget<PlaylistToolbar>(find.byType(PlaylistToolbar))
            .onViewChanged!(PlaylistViewMode.grid);
        if (capturing) {
          expect(controller.busy, isTrue,
              reason: 'The selected view must survive a pending capture');
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(reduceMotion: true);
        }
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      await tester.pump();
      await tester.pump(Duration(milliseconds: holding ? 400 : 50));
      if (!capturing) {
        expect(controller.active, isTrue);
        expect(controller.debugSnapshotCount, 1);
      }
      expect(tester.widget<PlaylistToolbar>(find.byType(PlaylistToolbar)).view,
          PlaylistViewMode.grid);

      // This flag is a real dispatcher event, without a MediaQuery override or
      // a parent rebuild that could accidentally hide the missing observer.
      if (!capturing) {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(reduceMotion: true);
      }
      await tester.pump();
      expect(controller.active, isFalse,
          reason: 'Changing the native preference must retire cached flights');
      expect(controller.busy, isFalse);
      expect(controller.debugSnapshotCount, 0);
      final cover = find.byType(PlaylistCoverTransitionMarker);
      final opacity = tester
          .widget<FadeTransition>(find
              .descendant(of: cover, matching: find.byType(FadeTransition))
              .first)
          .opacity;
      expect(opacity, isA<AlwaysStoppedAnimation<double>>());
      expect(opacity.value, 1,
          reason: 'The live cover is immediately revealed');
      // The grid's pre-existing Material text-style transition is independent
      // of cover tracking. After its finite tail, no page clock may remain.
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.binding.transientCallbackCount, 0);
      pending.complete(artwork);
      await _decode(tester);
      await tester.pump(const Duration(seconds: 11));
      expect(controller.active, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
