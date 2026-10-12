import 'dart:async';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/artwork_handoff.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Image extends ImageProvider<_Image> {
  final frame = Completer<ImageInfo>();
  var decodes = 0;
  @override
  Future<_Image> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(_Image key, ImageDecoderCallback decode) {
    decodes++;
    return OneFrameImageStreamCompleter(
        frame.future.then((info) => info.clone()));
  }

  void complete(raster.Image image) {
    final info = ImageInfo(image: image.clone());
    addTearDown(info.dispose);
    frame.complete(info);
  }
}

Widget _cover(String id, _Image provider,
        {Object? source, Future<ImageProvider?> Function()? loader}) =>
    SizedBox.square(
      dimension: 8,
      child: ArtworkHandoff(
        key: ValueKey('cover-$id'),
        artworkKey: source ?? id,
        loadArtwork: loader ?? () => SynchronousFuture(provider),
        animateFirstFrame: true,
        placeholder: const ColoredBox(color: Colors.black),
        imageBuilder: (image) => Image(image: image, fit: BoxFit.cover),
      ),
    );

Widget _entry(String id) => AppEntrance(
    key: ValueKey('entry-$id'),
    identity: id,
    child: const SizedBox.square(dimension: 8));

double _coverOpacity(WidgetTester tester, String id) {
  final fades = tester.widgetList<FadeTransition>(find.descendant(
      of: find.byKey(ValueKey('cover-$id')),
      matching: find.byType(FadeTransition)));
  expect(fades, isNotEmpty);
  return fades.last.opacity.value;
}

double _entryOpacity(WidgetTester tester, String id) => tester
    .widget<Opacity>(find.descendant(
        of: find.byKey(ValueKey('entry-$id')), matching: find.byType(Opacity)))
    .opacity;

Widget _host(Widget child,
    {int budget = 24,
    bool scoped = true,
    bool visible = true,
    bool reduced = false,
    bool entrance = true}) {
  final content = scoped
      ? AppEntranceScope(
          key: const ValueKey('scope'),
          maxConcurrentAnimations: budget,
          child: child)
      : child;
  return MaterialApp(
      home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: TickerMode(
              enabled: visible,
              child: MotionPreferencesScope(
                  preferences: entrance
                      ? const MotionPreferences()
                      : const MotionPreferences(
                          disabled: {MotionKind.entrance}),
                  child: Center(child: content)))));
}

raster.Image _pixels() {
  final recorder = raster.PictureRecorder();
  Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
  final picture = recorder.endRecording();
  final result = picture.toImageSync(4, 4);
  picture.dispose();
  addTearDown(result.dispose);
  return result;
}

Future<void> _accept(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    // Image providers are per-case; do not retain pending cache entries.
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  void cleanup(WidgetTester tester) => addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });

  testWidgets('dense late first frames share the entrance concurrency budget',
      (tester) async {
    cleanup(tester);
    final pixel = _pixels();
    final images = List.generate(64, (_) => _Image());
    Widget row({bool probe = false}) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < images.length; i++) _cover('$i', images[i]),
          if (probe) _entry('completed'),
        ]);
    await tester.pumpWidget(_host(row()));
    await tester.pumpAndSettle();
    for (final image in images) {
      image.complete(pixel);
    }
    await _accept(tester);
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(RawImage), findsNWidgets(64));
    final values = [for (var i = 0; i < 64; i++) _coverOpacity(tester, '$i')];
    expect(values.where((value) => value > 0 && value < 1), hasLength(24));
    expect(values.where((value) => value == 1), hasLength(40));
    expect(tester.binding.transientCallbackCount, lessThanOrEqualTo(24));
    expect(images.map((image) => image.decodes), everyElement(1));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(_host(row(probe: true)));
    expect(_entryOpacity(tester, 'completed'), 0,
        reason:
            'Completed first-frame reveals must return their reservations.');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('late cover and normal entry consume the same existing budget',
      (tester) async {
    cleanup(tester);
    final pixel = _pixels();
    final first = _Image(), late = _Image();
    await tester.pumpWidget(_host(
        Row(children: [_entry('held'), _cover('first', first)]),
        budget: 1));
    first.complete(pixel);
    await _accept(tester);
    expect(_coverOpacity(tester, 'first'), 1);
    expect(_entryOpacity(tester, 'held'), lessThan(1));
    expect(tester.binding.transientCallbackCount, 1);
    await tester.pumpAndSettle();
    await tester.pumpWidget(_host(
        Row(children: [_cover('first', first), _cover('late', late)]),
        budget: 1));
    await tester.pumpAndSettle();
    late.complete(pixel);
    await _accept(tester);
    await tester.pump(const Duration(milliseconds: 60));
    expect(_coverOpacity(tester, 'late'), inExclusiveRange(0.0, 1.0));
    await tester.pumpAndSettle();
    expect(_coverOpacity(tester, 'late'), 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('unscoped late first covers retain their independent fades',
      (tester) async {
    cleanup(tester);
    final pixel = _pixels();
    final images = List.generate(3, (_) => _Image());
    await tester.pumpWidget(_host(
        Row(children: [for (var i = 0; i < 3; i++) _cover('$i', images[i])]),
        scoped: false));
    await tester.pumpAndSettle();
    for (final image in images) {
      image.complete(pixel);
    }
    await _accept(tester);
    await tester.pump(const Duration(milliseconds: 60));
    for (var i = 0; i < 3; i++) {
      expect(_coverOpacity(tester, '$i'), inExclusiveRange(0.0, 1.0));
    }
    expect(tester.binding.transientCallbackCount, 3);
    await tester.pumpAndSettle();
  });

  testWidgets('replacement cover keeps its theme fade under a saturated budget',
      (tester) async {
    cleanup(tester);
    final pixel = _pixels();
    final first = _Image()..complete(pixel), next = _Image();
    await tester
        .pumpWidget(_host(Row(children: [_cover('a', first)]), budget: 1));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_host(
        Row(children: [_entry('held'), _cover('a', next, source: 'next')]),
        budget: 1));
    next.complete(pixel);
    await _accept(tester);
    await tester.pump(const Duration(milliseconds: 60));
    expect(_coverOpacity(tester, 'a'), inExclusiveRange(0.0, 1.0));
    expect(find.byType(RawImage), findsNWidgets(2));
    final fades =
        tester.widgetList<FadeTransition>(find.byType(FadeTransition));
    expect(fades.first.opacity.value, 1,
        reason: 'The outgoing cover stays opaque underneath the replacement.');
    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final gate in ['hidden', 'reduced', 'entrance disabled']) {
    testWidgets('first-frame reservation releases immediately when $gate',
        (tester) async {
      cleanup(tester);
      final pixel = _pixels();
      final image = _Image();
      await tester
          .pumpWidget(_host(Row(children: [_cover('a', image)]), budget: 1));
      await tester.pumpAndSettle();
      image.complete(pixel);
      await _accept(tester);
      await tester.pump(const Duration(milliseconds: 60));
      expect(_coverOpacity(tester, 'a'), inExclusiveRange(0.0, 1.0));
      await tester.pumpWidget(_host(Row(children: [_cover('a', image)]),
          budget: 1,
          visible: gate != 'hidden',
          reduced: gate == 'reduced',
          entrance: gate != 'entrance disabled'));
      expect(_coverOpacity(tester, 'a'), 1);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(_host(
          Row(children: [_cover('a', image), _entry('resumed')]),
          budget: 1));
      expect(_entryOpacity(tester, 'resumed'), 0);
      expect(_coverOpacity(tester, 'a'), 1,
          reason: 'Returning visibility must not replay a finished cover.');
      await tester.pumpAndSettle();
    });
  }

  testWidgets('disposing an active first-frame reveal returns its reservation',
      (tester) async {
    cleanup(tester);
    final pixel = _pixels();
    final image = _Image();
    await tester
        .pumpWidget(_host(Row(children: [_cover('a', image)]), budget: 1));
    await tester.pumpAndSettle();
    image.complete(pixel);
    await _accept(tester);
    await tester.pump(const Duration(milliseconds: 60));
    expect(_coverOpacity(tester, 'a'), inExclusiveRange(0.0, 1.0));
    await tester.pumpWidget(_host(const Row(children: []), budget: 1));
    await tester
        .pumpWidget(_host(Row(children: [_entry('after-dispose')]), budget: 1));
    expect(_entryOpacity(tester, 'after-dispose'), 0);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final outcome in ['missing', 'error', 'timeout']) {
    testWidgets(
        'first-frame replacement $outcome returns the original reservation',
        (tester) async {
      cleanup(tester);
      final pixel = _pixels();
      final image = _Image(), stale = _Image();
      final replacement = Completer<ImageProvider?>();
      await tester
          .pumpWidget(_host(Row(children: [_cover('a', image)]), budget: 1));
      await tester.pumpAndSettle();
      image.complete(pixel);
      await _accept(tester);
      await tester.pump(const Duration(milliseconds: 60));
      expect(_coverOpacity(tester, 'a'), inExclusiveRange(0.0, 1.0));
      await tester.pumpWidget(_host(
          Row(children: [
            _cover('a', stale, source: 'new', loader: () => replacement.future),
            _entry('replacement'),
          ]),
          budget: 1));
      expect(_entryOpacity(tester, 'replacement'), 0);
      expect(_coverOpacity(tester, 'a'), 1);
      if (outcome == 'timeout') {
        await tester
            .pump(ArtworkHandoff.loadTimeout + const Duration(milliseconds: 1));
        stale.complete(pixel);
        replacement.complete(stale);
      } else if (outcome == 'error') {
        replacement.completeError(StateError('owned fixture failure'));
      } else {
        replacement.complete(null);
      }
      await _accept(tester);
      await tester.pumpAndSettle();
      expect(find.byType(RawImage), findsNothing);
      expect(stale.decodes, 0,
          reason: 'A retired request must not begin decoding.');
      await tester.pumpWidget(_host(
          Row(children: [_entry('replacement'), _entry('after-failure')]),
          budget: 1));
      expect(_entryOpacity(tester, 'after-failure'), 0);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reservation release is idempotent and holds its exact old scope',
      (tester) async {
    cleanup(tester);
    final move = GlobalKey();
    VoidCallback? release;
    Widget holder() => Builder(
        key: move,
        builder: (context) {
          release ??= AppEntranceScope.reserveAnimationOf(context);
          return const SizedBox.square(dimension: 8);
        });
    Widget scopes(
            {bool moved = false, bool probes = false, bool extra = false}) =>
        _host(
            Row(children: [
              AppEntranceScope(
                  key: const ValueKey('old'),
                  maxConcurrentAnimations: 1,
                  child: Row(children: [
                    if (!moved) holder(),
                    if (probes) _entry('old-scope'),
                    if (extra) _entry('old-denied'),
                  ])),
              AppEntranceScope(
                  key: const ValueKey('new'),
                  maxConcurrentAnimations: 1,
                  child: Row(children: [
                    _entry('new-held'),
                    if (moved) holder(),
                    if (probes) _entry('new-denied'),
                  ])),
            ]),
            scoped: false);
    await tester.pumpWidget(scopes());
    expect(release, isNotNull);
    await tester.pumpWidget(scopes(moved: true));
    release!();
    release!();
    await tester.pumpWidget(scopes(moved: true, probes: true));
    expect(_entryOpacity(tester, 'old-scope'), 0);
    expect(_entryOpacity(tester, 'new-denied'), 1,
        reason:
            'Reparenting must not return the destination scope reservation.');
    release!();
    await tester.pumpWidget(scopes(moved: true, probes: true, extra: true));
    expect(_entryOpacity(tester, 'old-denied'), 1,
        reason: 'Repeated release must not return another entrance slot.');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
