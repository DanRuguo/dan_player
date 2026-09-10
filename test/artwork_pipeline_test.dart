import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dan_player/component/artwork_backdrop.dart';
import 'package:dan_player/component/audio_artwork.dart';
import 'package:dan_player/component/playlist_cover.dart';
import 'package:dan_player/library/artwork_image_provider.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('physical artwork request', () {
    test('uses current DPR and rounds up instead of reusing 48px', () {
      final expected = {1.0: 48, 1.25: 64, 1.5: 96, 2.0: 96, 3.0: 192};
      for (final entry in expected.entries) {
        expect(_request(48, entry.key), ArtworkSize(entry.value, entry.value));
      }
      expect(_request(52, 1), const ArtworkSize(64, 64));
      expect(_request(80, 2), const ArtworkSize(192, 192));
    });

    test('bounded buckets do not create a cache entry for every drag pixel',
        () {
      final requests = <ArtworkSize>{};
      for (var logical = 1; logical < 1200; logical++) {
        requests.add(_request(logical.toDouble(), 2.5));
      }
      expect(requests.length, lessThanOrEqualTo(ArtworkSize.buckets.length));
      expect(_request(1e308, 1e308), const ArtworkSize(2048, 2048));
      expect(_request(80, double.nan), _request(80, 1));
    });

    test('landscape and portrait keep enough pixels on both crop axes', () {
      const target = ArtworkSize(400, 400);
      expect(target.decodeSize(1600, 900), const ArtworkSize(712, 400));
      expect(target.decodeSize(900, 1600), const ArtworkSize(400, 712));
      expect(const ArtworkSize(300, 180).decodeSize(1200, 800),
          const ArtworkSize(300, 200));
    });

    test('small originals are not decoded into invented larger bitmaps', () {
      const target = ArtworkSize(512, 512);
      expect(target.decodeSize(32, 16), const ArtworkSize(32, 16));
      expect(target.decodeSize(16, 32), const ArtworkSize(16, 32));
      expect(target.decodeSize(24, 24), const ArtworkSize(24, 24));
      expect(() => target.decodeSize(0, 100), throwsArgumentError);
    });

    test('extreme panoramas and large images obey an explicit memory cap', () {
      for (final source in const [
        ArtworkSize(16000, 100),
        ArtworkSize(100, 16000),
        ArtworkSize(16000, 16000),
      ]) {
        final decoded = const ArtworkSize(2048, 2048)
            .decodeSize(source.width, source.height);
        expect(decoded.width, lessThanOrEqualTo(ArtworkSize.maxDecodeEdge));
        expect(decoded.height, lessThanOrEqualTo(ArtworkSize.maxDecodeEdge));
        expect(decoded.decodedRgbaBytes,
            lessThanOrEqualTo(ArtworkSize.maxDecodePixels * 4));
      }
    });

    test('provider cache identity includes physical size and cover revision',
        () async {
      final source = MemoryImage(Uint8List.fromList([1, 2, 3]));
      final first = ArtworkImageProvider(source, _request(48, 1));
      final sameBucket = ArtworkImageProvider(source, _request(47, 1));
      final highDpi = ArtworkImageProvider(source, _request(48, 2));
      final edited = ArtworkImageProvider(source, _request(48, 1), revision: 1);
      expect(first, sameBucket);
      expect(first, isNot(highDpi));
      expect(first, isNot(edited));
      expect(await first.obtainKey(ImageConfiguration.empty),
          await sameBucket.obtainKey(ImageConfiguration.empty));
      expect(await first.obtainKey(ImageConfiguration.empty),
          isNot(await highDpi.obtainKey(ImageConfiguration.empty)));
    });

    test('online artwork is bounded without fetching or needing native code',
        () async {
      final song = Audio.online(
        provider: 'qq',
        id: 'remote-art',
        title: 'Test',
        artist: 'Artist',
        album: 'Album',
        duration: 30,
        artworkUrl: 'https://example.invalid/cover.png',
      );
      final small = await song.coverForDisplay(size: 48, devicePixelRatio: 1);
      final large = await song.coverForDisplay(size: 400, devicePixelRatio: 2);
      expect(small, isA<ArtworkImageProvider>());
      expect((small! as ArtworkImageProvider).size, const ArtworkSize(48, 48));
      expect(
          (large! as ArtworkImageProvider).size, const ArtworkSize(1024, 1024));
    });

    test('large QQ views choose the verified 800px public album rendition', () {
      final uri = Uri.parse('https://y.qq.com/music/photo_new/'
          'T002R300x300M000000MkMni19ClKG.jpg');
      expect(artworkUriForSize(uri, const ArtworkSize(96, 96), provider: 'qq'),
          uri);
      expect(
          artworkUriForSize(uri, const ArtworkSize(512, 512), provider: 'qq')
              .path,
          '/music/photo_new/T002R800x800M000000MkMni19ClKG.jpg');
    });

    test('artwork rendition selection never rewrites signed or unknown URLs',
        () {
      for (final url in [
        'https://y.qq.com/music/photo_new/T002R300x300M000album.jpg?signature=keep',
        'https://example.invalid/music/photo_new/T002R300x300M000album.jpg',
        'https://y.qq.com/other/R300x300.jpg',
      ]) {
        final uri = Uri.parse(url);
        expect(
            artworkUriForSize(uri, const ArtworkSize(512, 512), provider: 'qq'),
            uri);
      }
      final otherProvider = Uri.parse('https://y.qq.com/music/photo_new/'
          'T002R300x300M000album.jpg');
      expect(
          artworkUriForSize(otherProvider, const ArtworkSize(512, 512),
              provider: 'netease'),
          otherProvider);
    });
  });

  testWidgets('the real codec decodes a wide/tall cover at sufficient pixels',
      (tester) async {
    await tester.runAsync(() async {
      for (final sourceSize in const [
        ArtworkSize(800, 400),
        ArtworkSize(400, 800)
      ]) {
        final source =
            MemoryImage(await _png(sourceSize.width, sourceSize.height));
        final decoded = await _decode(
            ArtworkImageProvider(source, const ArtworkSize(96, 96)));
        expect(
            decoded,
            sourceSize.width > sourceSize.height
                ? const ArtworkSize(192, 96)
                : const ArtworkSize(96, 192));
      }
    });
  });

  testWidgets('the real codec does not upscale a tiny source', (tester) async {
    await tester.runAsync(() async {
      final image = MemoryImage(await _png(8, 4));
      expect(
          await _decode(
              ArtworkImageProvider(image, const ArtworkSize(512, 512))),
          const ArtworkSize(8, 4));
    });
  });

  testWidgets(
      'background unwraps foreground cover sizing for its 512 fit sample',
      (tester) async {
    final source =
        (await tester.runAsync(() async => MemoryImage(await _png(800, 400))))!;
    final foreground = ArtworkImageProvider(source, const ArtworkSize(96, 96));
    await tester.pumpWidget(MaterialApp(
      home: ArtworkBackdrop(
        artworkKey: 'bounded-online-shape',
        loadArtwork: () async => foreground,
        child: const SizedBox.expand(),
      ),
    ));
    await _finishImage(tester);
    final background =
        tester.widget<Image>(find.byType(Image)).image as ResizeImage;
    expect(background.imageProvider, same(source));
    expect((background.width, background.height), (512, 512));
    expect(background.policy, ResizeImagePolicy.fit);
    await tester.runAsync(() async {
      expect(await _decode(background), const ArtworkSize(512, 256));
      expect(await _decode(foreground), const ArtworkSize(192, 96));
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'theme uses real codec and a separate 320 fit sample for palettes',
      (tester) async {
    await tester.runAsync(() async {
      final source = MemoryImage(await _png(400, 800));
      final foreground =
          ArtworkImageProvider(source, const ArtworkSize(96, 96));
      final paletteSizes = <ArtworkSize>[];
      final theme = ThemeProvider.forTesting(
        seedColor: Colors.teal,
        dynamicThemeEnabled: () => true,
        loadArtwork: (_) async => foreground,
        extractScheme: (image, brightness) async {
          paletteSizes.add(await _decode(image));
          return ColorScheme.fromImageProvider(
              provider: image, brightness: brightness);
        },
      );
      try {
        await theme.applyThemeFromAudio(_song('palette-cover'));
        final background = theme.backdropImage! as ResizeImage;
        expect(background.imageProvider, same(source));
        expect((background.width, background.height), (320, 320));
        expect(background.policy, ResizeImagePolicy.fit);
        expect(paletteSizes,
            [const ArtworkSize(160, 320), const ArtworkSize(160, 320)]);
        expect(theme.lightScheme.brightness, Brightness.light);
        expect(theme.darkScheme.brightness, Brightness.dark);
        expect(await _decode(foreground), const ArtworkSize(96, 192));
      } finally {
        theme.dispose();
      }
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary rebuilds keep one request and do not flash loading',
      (tester) async {
    final image =
        (await tester.runAsync(() async => MemoryImage(await _png(96, 96))))!;
    final audio = _song('stable');
    var requests = 0;
    Widget page() => _app(AudioArtwork(
          audio: audio,
          placeholder: const Text('missing'),
          loading: const Text('loading'),
          loadArtwork: (_, __) async {
            requests++;
            return image;
          },
        ));
    await tester.pumpWidget(page());
    await _finishImage(tester);
    for (var index = 0; index < 12; index++) {
      await tester.pumpWidget(page());
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('loading'), findsNothing);
    }
    expect(requests, 1);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('current View DPR changes request a new physical cache size',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <ArtworkSize>[];
    await tester.pumpWidget(_app(AudioArtwork(
      audio: _song('dpi'),
      size: 80,
      placeholder: const Text('missing'),
      loadArtwork: (_, size) async {
        requests.add(size);
        return null;
      },
    )));
    await tester.pumpAndSettle();
    expect(requests, [const ArtworkSize(96, 96)]);
    tester.view.devicePixelRatio = 2;
    await tester.pumpAndSettle();
    expect(requests, [const ArtworkSize(96, 96), const ArtworkSize(192, 192)]);
  });

  testWidgets('same-bucket layout changes do not restart loading',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final audio = _song('resize');
    final requests = <ArtworkSize>[];
    Widget page(double size) => _app(AudioArtwork(
          audio: audio,
          size: size,
          placeholder: const Text('missing'),
          loadArtwork: (_, target) async {
            requests.add(target);
            return null;
          },
        ));
    await tester.pumpWidget(page(50));
    await tester.pumpAndSettle();
    await tester.pumpWidget(page(60));
    await tester.pumpAndSettle();
    expect(requests, [const ArtworkSize(64, 64)]);
    await tester.pumpWidget(page(80));
    await tester.pumpAndSettle();
    expect(requests.last, const ArtworkSize(96, 96));
    expect(requests.length, 2);
  });

  testWidgets('DPR upgrades retain the visible cover while sharper art loads',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final image =
        (await tester.runAsync(() async => MemoryImage(await _png(96, 96))))!;
    final upgrade = Completer<ImageProvider?>();
    var requests = 0;
    await tester.pumpWidget(_app(AudioArtwork(
      audio: _song('upgrade'),
      placeholder: const Text('missing'),
      loading: const Text('loading'),
      loadArtwork: (_, __) =>
          ++requests == 1 ? Future.value(image) : upgrade.future,
    )));
    await _finishImage(tester);
    tester.view.devicePixelRatio = 2;
    await tester.pump();
    expect(requests, 2);
    expect(find.text('loading'), findsNothing);
    expect(tester.widget<Image>(find.byType(Image)).image, image);
    upgrade.complete(image);
    await tester.pumpAndSettle();
  });

  testWidgets('late results cannot replace a different song or edited cover',
      (tester) async {
    final first = Completer<ImageProvider?>();
    final second = Completer<ImageProvider?>();
    final image =
        (await tester.runAsync(() async => MemoryImage(await _png(32, 32))))!;
    var reads = 0;
    Widget page(Audio song, int revision) => _app(AudioArtwork(
          audio: song,
          revision: revision,
          placeholder: const Text('missing'),
          loadArtwork: (_, __) => ++reads == 1 ? first.future : second.future,
        ));
    await tester.pumpWidget(page(_song('old'), 0));
    final current = _song('new');
    await tester.pumpWidget(page(current, 0));
    second.complete(image);
    await _finishImage(tester);
    first.complete(null);
    await tester.pumpAndSettle();
    expect(tester.widget<Image>(find.byType(Image)).image, image);
    await tester.pumpWidget(page(current, 1));
    await tester.pumpAndSettle();
    expect(reads, 3);
  });

  testWidgets('same-second embedded-cover changes resolve a new fingerprint',
      (tester) async {
    final audio = _song('edited-cover')..modifiedNanos = '1000000001';
    final image =
        (await tester.runAsync(() async => MemoryImage(await _png(32, 32))))!;
    var reads = 0;
    Widget page() => _app(AudioArtwork(
          audio: audio,
          placeholder: const Text('missing'),
          loadArtwork: (_, __) async {
            reads++;
            return image;
          },
        ));
    await tester.pumpWidget(page());
    await _finishImage(tester);
    audio.modifiedNanos = '1000000002';
    await tester.pumpWidget(page());
    await _finishImage(tester);
    expect(reads, 2);
    expect(tester.widget<Image>(find.byType(Image)).image, image);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dispose while pending has no frame polling or late setState',
      (tester) async {
    final pending = Completer<ImageProvider?>();
    await tester.pumpWidget(_app(AudioArtwork(
      audio: _song('dispose'),
      placeholder: const Text('missing'),
      loadArtwork: (_, __) => pending.future,
    )));
    await tester.pumpWidget(const SizedBox.shrink());
    pending.completeError(StateError('late image failure'));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('playlist song fallback uses its actual display size, not 48',
      (tester) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    final song = _RecordingAudio();
    final playlist = Playlist('Art', {song.path: song});
    await tester.pumpWidget(_app(PlaylistCover(playlist: playlist, size: 180)));
    await tester.pumpAndSettle();
    expect(song.requests, [const ArtworkSize(384, 384)]);
  });

  testWidgets('custom cover widget uses aspect-aware bounded provider',
      (tester) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    final image =
        (await tester.runAsync(() async => MemoryImage(await _png(640, 320))))!;
    await tester.pumpWidget(_app(ArtworkImage(
      image: image,
      size: 80,
      revision: 'edited',
      errorBuilder: (_, __, ___) => const Text('failed'),
    )));
    await _finishImage(tester);
    final rendered = tester.widget<Image>(find.byType(Image));
    final provider = rendered.image as ArtworkImageProvider;
    expect(provider.size, const ArtworkSize(192, 192));
    expect(provider.revision, 'edited');
    expect(rendered.fit, BoxFit.cover);
    expect(rendered.filterQuality, FilterQuality.high);
    expect(await tester.runAsync(() => _decode(provider)),
        const ArtworkSize(384, 192));
  });
}

ArtworkSize _request(double size, double dpr) => ArtworkSize.forDisplay(
    logicalWidth: size, logicalHeight: size, devicePixelRatio: dpr);

Audio _song(String id) => Audio.online(
    provider: 'qq',
    id: id,
    title: id,
    artist: 'Artist',
    album: 'Album',
    duration: 60);

class _RecordingAudio extends Audio {
  _RecordingAudio()
      : super('Art', 'Artist', 'Album', 1, 60, null, null,
            'online://qq/recording-art', 0, 0, null,
            onlineProvider: 'qq', onlineId: 'recording-art');
  final requests = <ArtworkSize>[];
  @override
  Future<ImageProvider?> artworkForSize(ArtworkSize size) async {
    requests.add(size);
    return null;
  }
}

Widget _app(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..drawColor(Colors.blue, BlendMode.src);
  canvas.drawRect(Rect.fromLTWH(0, 0, width / 2, height / 2),
      Paint()..color = Colors.amber);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return bytes.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<ArtworkSize> _decode(ImageProvider provider) async {
  final completed = Completer<ImageInfo>();
  final stream = provider.resolve(ImageConfiguration.empty);
  final listener = ImageStreamListener(
    (image, _) {
      if (!completed.isCompleted) completed.complete(image);
    },
    onError: (Object error, StackTrace? trace) =>
        completed.completeError(error, trace),
  );
  stream.addListener(listener);
  try {
    final info = await completed.future.timeout(const Duration(seconds: 5));
    try {
      return ArtworkSize(info.image.width, info.image.height);
    } finally {
      info.dispose();
    }
  } finally {
    stream.removeListener(listener);
  }
}

Future<void> _finishImage(WidgetTester tester) async {
  await tester.pump();
  // Artwork now commits only after decoding; its preparatory stream can exist
  // before an Image widget is mounted. Let real codecs finish outside fake time.
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (PaintingBinding.instance.imageCache.pendingImageCount > 0 &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  });
  await tester.pump();
  final image = find.byType(Image);
  if (image.evaluate().isNotEmpty) {
    final provider = tester.widget<Image>(image.first).image;
    await tester.runAsync(() => precacheImage(
        provider, tester.element(image.first),
        onError: (_, __) {}));
  }
  await tester.pumpAndSettle();
}
