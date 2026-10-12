import 'dart:async';
import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/audio_artwork.dart';
import 'package:dan_player/component/folder_tree_pane.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/folder_tree.dart';
import 'package:dan_player/page/folders_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

class _ColdCover extends ImageProvider<_ColdCover> {
  final frame = Completer<ImageInfo>();
  var decodes = 0;
  @override
  Future<_ColdCover> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(_ColdCover key, ImageDecoderCallback decode) {
    decodes++;
    return OneFrameImageStreamCompleter(
        frame.future.then((info) => info.clone()));
  }

  void complete(raster.Image image) {
    if (frame.isCompleted) return;
    final info = ImageInfo(image: image.clone());
    addTearDown(info.dispose);
    frame.complete(info);
  }
}

class _ColdPlayback extends PlaylistFeaturePlayback {
  _ColdPlayback() : super([]);
  List<Audio>? played;
  @override
  void play(int audioIndex, List<Audio> playlist) => played = playlist;
}

// Cache children are deliberately included: the default Finder hides the very
// offscreen thumbnail work this regression needs to observe.
List<(AudioArtwork, Rect)> _mountedArtwork(WidgetTester tester) => [
      for (final element
          in find.byType(AudioArtwork, skipOffstage: false).evaluate())
        if (element.findRenderObject() case final RenderBox box
            when box.attached && box.hasSize)
          (
            element.widget as AudioArtwork,
            box.localToGlobal(Offset.zero) & box.size
          ),
    ];

Rect _viewport(WidgetTester tester) {
  final first = find.byType(AudioArtwork, skipOffstage: false).evaluate().first;
  final render = first.findRenderObject()!;
  final box = RenderAbstractViewport.of(render) as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

void _expectColdBudget(WidgetTester tester) {
  final all = _mountedArtwork(tester);
  final viewport = _viewport(tester);
  final visible = all.where((entry) => entry.$2.overlaps(viewport)).toList();
  expect(visible, isNotEmpty);
  final firstRowY = visible.first.$2.top;
  final columns =
      visible.where((entry) => (entry.$2.top - firstRowY).abs() < .01).length;
  expect(columns, greaterThan(1));
  // A single cached row on each side may include the partial viewport row.
  // More than two rows starts unrelated offscreen artwork on a cold open.
  expect(all.length - visible.length, lessThanOrEqualTo(columns * 2),
      reason: 'Cold expansion must reserve at most one song row per side, '
          'rather than the generic 250 px cache of dense cover rows.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPlaylistFeatureFonts);
  for (final (width, height) in [(1440.0, 1200.0), (760.0, 720.0)]) {
    testWidgets(
        'cold folder viewport bounds artwork work at ${width.toInt()}px',
        (tester) async {
      final qa = Directory(path.join(Directory.current.parent.path, 'tool',
          'qa-local', 'folder-cold-feedback-oct12', 'formal-fixture'));
      final music = path.join(qa.path, 'Music');
      final folderId = folderTreePathId(music);
      final previousFolders = AudioLibrary.instance.folders;
      final previousFolderPreference = AppPreference.instance.foldersPagePref;
      final previousSongPreference =
          AppPreference.instance.folderDetailPagePref;
      final previousLanguage = uiLanguage.value;
      addTearDown(() {
        AudioLibrary.instance.folders = previousFolders;
        AppPreference.instance.foldersPagePref = previousFolderPreference;
        AppPreference.instance.folderDetailPagePref = previousSongPreference;
        uiLanguage.value = previousLanguage;
      });
      uiLanguage.value = UiLanguage.zh;
      AppPreference.instance.foldersPagePref =
          PagePreference(0, SortOrder.ascending, ContentView.table);
      AppPreference.instance.folderDetailPagePref =
          PagePreference(0, SortOrder.ascending, ContentView.table);
      sizePlaylistFeature(tester, width: width, height: height);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
      final songs = [
        for (var index = 0; index < 1600; index++)
          CategoryTestAudio('Track ${index.toString().padLeft(5, '0')}',
              path: path.join(music, '$index.mp3')),
      ];
      AudioLibrary.instance.folders = [AudioFolder(songs, music, 1, 1)];
      final calls = <String, int>{};
      final covers = <String, _ColdCover>{};
      var sortCalls = 0;
      final playback = _ColdPlayback();
      addTearDown(playback.dispose);
      await tester.pumpWidget(playlistFeatureHost(Builder(
          builder: (context) => MediaQuery(
              // The generic playlist fixture disables animations for static
              // layout tests. This case also measures actual late cover motion.
              data: MediaQuery.of(context).copyWith(disableAnimations: false),
              child: MotionPreferencesScope(
                  preferences: const MotionPreferences(),
                  child: AppEntranceScope(
                      child: FoldersPage(
                          dataDirectory: qa,
                          playbackService: playback,
                          // The actual ordering worker has a separate integration
                          // regression. This isolates viewport admission after its
                          // completed result without making native timing an oracle.
                          sortLargeFolder: (source, _, __) {
                            sortCalls++;
                            return SynchronousFuture(List<Audio>.of(source));
                          },
                          loadArtwork: (audio, size) {
                            final key =
                                '${audio.path}/${size.width}x${size.height}';
                            calls.update(key, (count) => count + 1,
                                ifAbsent: () => 1);
                            return SynchronousFuture(
                                covers.putIfAbsent(key, _ColdCover.new));
                          })))))));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      final toggle = find.byKey(ValueKey('folder-open-$music'));
      await tester.tapAt(tester.getTopLeft(toggle) + const Offset(70, 35));
      await tester.pumpAndSettle();
      expect(sortCalls, 1);
      expect(
          tester
              .widget<FolderTreePane>(find.byType(FolderTreePane))
              .sortingFolders,
          isEmpty);
      _expectColdBudget(tester);
      expect(covers.length, lessThan(songs.length));
      expect(calls.values, everyElement(1));
      final firstMount = _mountedArtwork(tester);
      expect(covers.length, firstMount.length,
          reason: 'No hidden eager preload should start additional songs.');
      final recorder = raster.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final picture = recorder.endRecording();
      final pixel = picture.toImageSync(4, 4);
      picture.dispose();
      addTearDown(pixel.dispose);
      for (final cover in covers.values) {
        cover.complete(pixel);
      }
      await tester.pump();
      // The image stream resolves after the prior frame; seed its finite
      // ticker before advancing to the measured handoff midpoint.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      final firstCover =
          find.byKey(ValueKey('folder-tree-cover-${songs.first.path}'));
      final fades = tester.widgetList<FadeTransition>(find.descendant(
          of: firstCover, matching: find.byType(FadeTransition)));
      expect(
          fades.any((fade) => fade.opacity.value > 0 && fade.opacity.value < 1),
          isTrue,
          reason: 'Reducing overscan must retain late-cover handoff.');
      await tester.pumpAndSettle();
      expect(covers.values.map((cover) => cover.decodes), everyElement(1));
      final pane = tester.widget<FolderTreePane>(find.byType(FolderTreePane));
      final controller = pane.controller!;
      controller.jumpTo(4 * (firstMount.first.$1.size + 14));
      await tester.pumpAndSettle();
      _expectColdBudget(tester);
      for (final cover in covers.values) {
        cover.complete(pixel);
      }
      await tester.pumpAndSettle();
      controller.jumpTo(0);
      await tester.pumpAndSettle();
      _expectColdBudget(tester);
      await tester.tapAt(tester.getTopLeft(toggle) + const Offset(70, 35));
      await tester.pumpAndSettle();
      expect(find.byType(AudioArtwork, skipOffstage: false), findsNothing);
      await tester.tapAt(tester.getTopLeft(toggle) + const Offset(70, 35));
      await tester.pumpAndSettle();
      expect(sortCalls, 1,
          reason: 'A warm reopen must reuse completed ordering.');
      _expectColdBudget(tester);
      expect(covers.values.map((cover) => cover.decodes), everyElement(1));
      expect(
          tester
              .widget<FolderTreePane>(find.byType(FolderTreePane))
              .songsByFolder[folderId],
          orderedEquals(songs));
      await tester.tap(firstCover);
      await tester.pumpAndSettle();
      expect(playback.played, orderedEquals(songs));
      expect(AudioLibrary.instance.folders.single.audios, same(songs));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
