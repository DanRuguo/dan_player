import 'dart:ui' as ui;

import 'package:dan_player/component/cover_caption_colors.dart';
import 'package:dan_player/library/artwork_image_provider.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RevisedSource extends ImageProvider<_RevisedSource> {
  _RevisedSource(this.bytes);
  Uint8List bytes;
  int decodes = 0;

  @override
  Future<_RevisedSource> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
      _RevisedSource key, ImageDecoderCallback decode) {
    decodes++;
    return MultiFrameImageStreamCompleter(
        codec: ui.ImmutableBuffer.fromUint8List(bytes).then(decode), scale: 1);
  }
}

Future<Uint8List> _png(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(24, 24);
  try {
    return Uint8List.fromList(
        (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  for (final explicit in [false, true]) {
    testWidgets(
        'palette sampling retains ${explicit ? 'explicit' : 'provider'} source revisions',
        (tester) async {
      final bytes = (await tester.runAsync(() async => [
            await _png(Colors.red),
            await _png(Colors.blue),
          ]))!;
      final source = _RevisedSource(bytes[0]);
      ImageProvider provider(int revision) {
        if (explicit) return source;
        return ArtworkImageProvider(source, const ArtworkSize(160, 160),
            revision: revision);
      }

      Future<CoverCaptionColors> colors(int revision) =>
          CoverCaptionCache.resolve(provider(revision), 1,
              revision: explicit ? revision : null);
      final before = (await tester.runAsync(() => colors(1)))!;
      expect(source.decodes, 1);
      source.bytes = bytes[1];
      final after = (await tester.runAsync(() => colors(2)))!;
      expect(source.decodes, 2,
          reason: 'A changed source must bypass the old 48 px decoded sample');
      expect(after.seed, isNot(before.seed));
      expect((await tester.runAsync(() => colors(2)))!.seed, after.seed);
      expect(source.decodes, 2,
          reason: 'The same source revision must continue to share its sample');
      final overridden = ArtworkImageProvider(
          source, const ArtworkSize(160, 160),
          revision: 1);
      final explicitNew = (await tester.runAsync(
          () => CoverCaptionCache.resolve(overridden, 1, revision: 2)))!;
      expect(explicitNew.seed, after.seed,
          reason: 'An explicit revision takes precedence over its wrapper');
      expect(source.decodes, 2);
    });
  }
}
