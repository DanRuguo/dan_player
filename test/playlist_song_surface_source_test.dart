import 'dart:async';
import 'dart:ui' as ui;

import 'package:dan_player/component/cover_caption_colors.dart';
import 'package:dan_player/component/playlist_song_surface.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cover_cache.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _CoverAudio extends Audio {
  _CoverAudio(String artworkUrl, this.image)
      : super('Track', 'Artist', 'Album', 0, 120, 320, 44100,
            'online://qq/surface-source', 0, 0, 'Test',
            onlineProvider: 'qq',
            onlineId: 'surface-source',
            artworkUrl: artworkUrl);

  final ImageProvider image;
  Completer<ImageProvider?>? pending;
  int reads = 0;

  @override
  Future<ImageProvider?> artworkForSize(ArtworkSize size) {
    reads++;
    return pending?.future ?? SynchronousFuture(image);
  }
}

Future<MemoryImage> _image(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(24, 24);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return MemoryImage(Uint8List.fromList(data.buffer.asUint8List()));
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  for (final delayed in [false, true]) {
    testWidgets(
        'a replaced online artwork URL refreshes its retained song palette (late=$delayed)',
        (tester) async {
      final images = (await tester.runAsync(() async => [
            await _image(Colors.red),
            await _image(Colors.blue),
          ]))!;
      final colors = (await tester.runAsync(() => Future.wait([
            for (final image in images)
              CoverCaptionCache.resolve(image, 1, revision: 0),
          ])))!;
      final first = _CoverAudio('https://fixture.invalid/old.png', images[0]);
      if (delayed) first.pending = Completer<ImageProvider?>();
      final replacement =
          _CoverAudio('https://fixture.invalid/new.png', images[1]);
      var audio = first;
      late StateSetter update;
      Color? primary;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
        update = setState;
        return PlaylistSongSurface(
            audio: audio,
            artworkColors: true,
            child: Builder(builder: (context) {
              primary = Theme.of(context).colorScheme.primary;
              return const SizedBox.square(dimension: 100);
            }));
      }))));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(first.reads, 1);
      if (!delayed) {
        expect(
            primary, ColorScheme.fromSeed(seedColor: colors[0].seed).primary);
      }

      update(() => audio = replacement);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(replacement.reads, 1,
          reason:
              'Stable track identity must not conceal a changed cover source');
      expect(primary, ColorScheme.fromSeed(seedColor: colors[1].seed).primary);
      if (delayed) {
        first.pending!.complete(first.image);
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
        expect(primary, ColorScheme.fromSeed(seedColor: colors[1].seed).primary,
            reason: 'Late old artwork cannot replace the current song palette');
      }
      CoverCache.instance.changes.value++;
      await tester.pumpAndSettle();
      expect(replacement.reads, 1,
          reason: 'Unrelated cover notifications must reuse the palette');
      expect(first.reads, 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
