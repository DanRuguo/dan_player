import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;

// Windows profile capture of the production tree rows and their real clocks.
// Pass an absolute workspace QA path through DAN_TREE_MOTION_OUTPUT.
Future<void> _capture(WidgetTester tester, GlobalKey boundary, String folder,
    int frame, Stopwatch watch, List<Map<String, Object?>> trace) async {
  final labels = <String, Map<String, double>>{};
  for (final label in ['2026', '2026-song', '2026-music', 'Track 2026']) {
    final found = find.text(label);
    if (found.evaluate().isNotEmpty) {
      final rect = tester.getRect(found.first);
      labels[label] = {
        'left': rect.left,
        'top': rect.top,
        'width': rect.width,
        'height': rect.height,
      };
    }
  }
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await render.toImage(pixelRatio: tester.view.devicePixelRatio);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file =
        File(path.join(folder, '${frame.toString().padLeft(3, '0')}.png'));
    await tester.runAsync(
        () => file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true));
    trace.add({
      'frame': frame,
      'elapsedWallMs': watch.elapsedMilliseconds,
      'labels': labels,
      'png': path.basename(file.path),
    });
  } finally {
    image.dispose();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('tree text keeps one rise on Windows', (tester) async {
    const target = String.fromEnvironment('DAN_TREE_MOTION_OUTPUT');
    expect(target, isNotEmpty, reason: 'Supply a workspace QA output path');
    expect(path.isAbsolute(target), isTrue);
    final normalized = path.normalize(target).replaceAll('\\', '/');
    expect(normalized.toLowerCase().contains('/tool/qa-local/'), isTrue,
        reason: 'Captures must stay under the workspace tool/qa-local');
    final output = Directory(target);
    await tester.runAsync(() => output.create(recursive: true));

    final tree = PlaylistTree([]);
    final year = tree.createPlaylist('2026');
    final song = tree.createPlaylist('2026-song', parent: year);
    final music = tree.createPlaylist('2026-music', parent: year);
    tree.createPlaylist('GAL');
    tree.createPlaylist('伤感音乐');
    tree.addAudio(
        music,
        Audio.online(
            provider: 'qq',
            id: 'tree-motion',
            title: 'Track 2026',
            artist: 'Singer 2026',
            album: 'Album 2026',
            duration: 193));
    tree.addAudio(
        song,
        Audio.online(
            provider: 'qq',
            id: 'tree-motion-2',
            title: 'Second Track 2026',
            artist: 'Singer',
            album: 'Album',
            duration: 180));
    final boundary = GlobalKey();
    await tester.pumpWidget(UiLanguageScope(
        child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: Entry(welcome: false).fromSchemeAndFontFamily(
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff6659a0), brightness: Brightness.light),
          fontFamily: danEmbeddedFontFamily),
      home: Scaffold(
          body: RepaintBoundary(
              key: boundary,
              child: PlaylistBrowser(
                  tree: tree,
                  initialView: PlaylistViewMode.tree,
                  persist: () async {},
                  onPlay: (_, __) {},
                  trackBuilder: (_, audio, play, actions) =>
                      ListTile(title: Text(audio.displayTitle), onTap: play)))),
    )));
    await tester.pump(const Duration(milliseconds: 800));

    Future<void> expand(String id, String name) async {
      final folder = path.join(output.path, name);
      await tester.runAsync(() => Directory(folder).create(recursive: true));
      await tester.tap(find.byKey(ValueKey('playlist-tree-toggle-$id')));
      final trace = <Map<String, Object?>>[];
      final watch = Stopwatch()..start();
      for (var frame = 0; frame < 32; frame++) {
        await tester.pump(Duration(milliseconds: frame < 25 ? 16 : 80));
        await _capture(tester, boundary, folder, frame, watch, trace);
      }
      await tester.runAsync(() => File(path.join(folder, 'trace.json'))
          .writeAsString(jsonEncode(trace), flush: true));
    }

    await expand(year.id, 'expand-year');
    expect(find.text('2026-song'), findsOneWidget);
    expect(find.text('2026-music'), findsOneWidget);
    await expand(music.id, 'expand-music');
    expect(find.text('Track 2026'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
