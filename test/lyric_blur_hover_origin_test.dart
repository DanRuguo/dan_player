import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_fractional_filter.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_viewport_blur.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Keep real-I/O failures in the test body. The live binding otherwise returns
// null after reporting an async error, hiding its cause behind a second failure.
Future<T> _runWithRealIo<T>(
  WidgetTester tester,
  Future<T> Function() callback,
) async {
  Object? error;
  StackTrace? stack;
  final result = await tester.runAsync<T?>(() async {
    try {
      return await callback();
    } catch (caught, trace) {
      error = caught;
      stack = trace;
      return null;
    }
  });
  if (error != null) Error.throwWithStackTrace(error!, stack!);
  return result as T;
}

const _background = Color(0xff627172);
const _foreground = Color(0xffe6f1d8);
const _texts = <String, String>{
  'primary': 'まぶしく輝く空の下',
  'translation': '在灿烂明亮的天空之下',
  'romanization': 'mabushiku kagayaku sora no shita de',
};
final _policy = AppFontPolicy.defaults();

String get _output =>
    Platform.environment['DAN_LYRIC_BLUR_HOVER_RENDER_DIR'] ??
    const String.fromEnvironment('DAN_LYRIC_BLUR_HOVER_RENDER_DIR');

class _Lyrics extends Lyric {
  _Lyrics(super.lines);
}

class _Rig {
  _Rig(this.dpr) {
    settings = LyricViewController(
      preferences: NowPlayingPagePreference.fromMap({}),
      appearance: appearance,
      persistAppearance: () async {},
    )
      ..lyricFontSize = 32
      ..translationFontSize = 22
      ..lyricTextAlign = LyricTextAlign.left
      ..showTranslation = true
      ..showRomanization = true
      ..showTimestamps = false;
    lyric = _Lyrics([
      for (var index = 0; index < 8; index++)
        LrcLine(
          Duration(seconds: index * 5),
          index == 2
              ? '${_texts['primary']}┃${_texts['translation']}'
              : '静かな歌 $index',
          isBlank: false,
          length: const Duration(seconds: 5),
        )..romanization = index == 2 ? _texts['romanization'] : null,
    ]);
  }

  final double dpr;
  final appearance = ValueNotifier(DesktopLyricAppearance.defaults);
  final hidden = ValueNotifier(false);
  final preferences = ValueNotifier(const RenderingPreferences(
    lyricSpectrum: false,
    compactSpectrum: false,
  ));
  final positions = StreamController<double>.broadcast(sync: true);
  final boundary = GlobalKey();
  late final LyricViewController settings;
  late final _Lyrics lyric;
  bool highContrast = false, reduced = false;
  bool _closed = false;
  int reads = 0, seeks = 0;
  double get position => 15.2;

  Finder get scroll => find.byKey(const ValueKey('vertical-lyric-scroll'));
  Finder get tile => find.byWidgetPredicate((widget) =>
      widget is LyricViewTile && identical(widget.line, lyric.lines[2]));

  Widget app() => MaterialApp(
        theme: ThemeData(
          platform: TargetPlatform.windows,
          fontFamily: _policy.uiFamily,
          fontFamilyFallback: _policy.fallback,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal).copyWith(
            surface: _background,
            primary: _foreground,
            onSecondaryContainer: _foreground,
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            highContrast: highContrast,
            disableAnimations: reduced,
          ),
          child: AppFontScope(
            policy: _policy,
            child: RenderingPreferencesScope(
              preferences: preferences,
              child: child!,
            ),
          ),
        ),
        home: ValueListenableBuilder<bool>(
          valueListenable: hidden,
          builder: (context, value, child) => TickerMode(
            enabled: !value,
            child: child!,
          ),
          child: Scaffold(
            backgroundColor: _background,
            body: Center(
              child: RepaintBoundary(
                key: boundary,
                child: SizedBox(
                  width: 800,
                  height: 860,
                  child: ColoredBox(
                    color: _background,
                    child: ChangeNotifierProvider.value(
                      value: settings,
                      child: VerticalLyricScrollView(
                        lyric: lyric,
                        playing: false,
                        springLyrics: false,
                        positionStream: positions.stream,
                        readPosition: () {
                          reads++;
                          return position;
                        },
                        onSeek: (_) => seeks++,
                        hidden: hidden,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = Size(960 * dpr, 940 * dpr);
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => close(tester));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(tile, findsOneWidget);
    expect(seeks, 0);
  }

  ScrollController scrollController(WidgetTester tester) =>
      tester.widget<CustomScrollView>(scroll).controller!;

  Finder get viewportBlur =>
      find.ancestor(of: scroll, matching: find.byType(LyricViewportBlur));

  List<RenderBackdropFilter> viewportFilters(WidgetTester tester) => tester
      .renderObjectList<RenderBackdropFilter>(find.descendant(
        of: viewportBlur,
        matching: find.byType(BackdropFilter),
      ))
      .toList();

  double sigma(WidgetTester tester) {
    final filters = viewportFilters(tester);
    expect(filters, hasLength(24),
        reason: 'Read the actual twelve-strip top and bottom viewport masks');
    for (final filter in filters.where((filter) => filter.enabled)) {
      // ignore: invalid_use_of_protected_member
      expect(filter.layer, isA<BackdropFilterLayer>(),
          reason: 'A positive kernel must reach the actual native scene');
    }
    return filters.fold<double>(
        0,
        (maximum, filter) => math.max(maximum,
            filter.enabled ? _gaussianSigma(filter.layer!.filter!).$1 : 0));
  }

  AnimationController readingClock(WidgetTester tester) {
    final viewport = tester.widget<LyricViewportBlur>(viewportBlur);
    expect(viewport.reading, isA<AnimationController>());
    return viewport.reading as AnimationController;
  }

  Future<void> close(WidgetTester tester) async {
    if (_closed) return;
    _closed = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await positions.close();
    settings.dispose();
    appearance.dispose();
    preferences.dispose();
    hidden.dispose();
  }
}

Finder _paint(_Rig rig, String text) => find.descendant(
      of: rig.tile,
      matching: find.byWidgetPredicate((widget) =>
          widget is CustomPaint &&
          widget.painter is PlainLyricWordFollowPainter &&
          (widget.painter! as PlainLyricWordFollowPainter)
                  .text
                  .text!
                  .toPlainText() ==
              text),
    );

class _Track {
  _Track(WidgetTester tester, _Rig rig, this.name) {
    finder = _paint(rig, _texts[name]!);
    expect(finder, findsOneWidget);
    element = tester.element(finder);
    render = tester.renderObject<RenderCustomPaint>(finder);
    painter = (tester.widget<CustomPaint>(finder).painter!
        as PlainLyricWordFollowPainter);
    paragraph = painter.text;
    layout = painter.layoutIdentity;
    final viewport =
        rig.boundary.currentContext!.findRenderObject()! as RenderBox;
    transform = render.getTransformTo(viewport);
    final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: _texts[name]!.length));
    expect(boxes, isNotEmpty);
    bounds = boxes
        .map((box) => MatrixUtils.transformRect(
            transform, box.toRect().shift(painter.inkOffset)))
        .reduce((a, b) => a.expandToInclude(b));
    glyphBounds =
        _glyphBounds(paragraph, _texts[name]!, transform, painter.inkOffset);
    expect(paragraph.computeLineMetrics(), hasLength(1));
    expect(paragraph.didExceedMaxLines, isFalse);
    Element? filter;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is LyricFractionalFilter) {
        filter = ancestor;
        return false;
      }
      return true;
    });
    expect(filter, isNotNull);
    filterElement = filter!;
    // Production places the leaf filter directly in a paragraph boundary;
    // retain this actual root instead of an isolated synthetic filter host.
    expect(filter!.renderObject!.parent, isA<RenderRepaintBoundary>());
    final scale = (filter!.renderObject! as RenderBox).getTransformTo(viewport);
    scaleX = math.sqrt(scale[0] * scale[0] + scale[1] * scale[1]);
    scaleY = math.sqrt(scale[4] * scale[4] + scale[5] * scale[5]);
    crop = bounds.inflate(24);
  }

  final String name;
  late final Finder finder;
  late final Element element;
  late final Element filterElement;
  late final RenderCustomPaint render;
  late final PlainLyricWordFollowPainter painter;
  late final TextPainter paragraph;
  late final Object? layout;
  late final Matrix4 transform;
  late final Rect bounds, crop;
  late final List<Rect> glyphBounds;
  late final double scaleX, scaleY;

  void unchanged(WidgetTester tester, _Rig rig) {
    expect(tester.element(finder), same(element));
    expect(tester.renderObject<RenderCustomPaint>(finder), same(render));
    final actual = tester.widget<CustomPaint>(finder).painter!
        as PlainLyricWordFollowPainter;
    expect(actual.text, same(paragraph));
    expect(actual.layoutIdentity, equals(layout));
    expect(actual.text.text!.toPlainText(), _texts[name]);
    final viewport =
        rig.boundary.currentContext!.findRenderObject()! as RenderBox;
    final next = render.getTransformTo(viewport);
    final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: _texts[name]!.length));
    final nextBounds = boxes
        .map((box) => MatrixUtils.transformRect(
            next, box.toRect().shift(actual.inkOffset)))
        .reduce((a, b) => a.expandToInclude(b));
    final nextGlyphs =
        _glyphBounds(actual.text, _texts[name]!, next, actual.inkOffset);
    expect(nextGlyphs, hasLength(glyphBounds.length));
    for (var index = 0; index < glyphBounds.length; index++) {
      final previous = glyphBounds[index], current = nextGlyphs[index];
      for (final coordinate in [
        (previous.left, current.left),
        (previous.top, current.top),
        (previous.right, current.right),
        (previous.bottom, current.bottom),
      ]) {
        expect(coordinate.$2, closeTo(coordinate.$1, .05),
            reason: '$name character $index must not move during hover');
      }
    }
    for (final coordinate in [
      (bounds.left, nextBounds.left),
      (bounds.top, nextBounds.top),
      (bounds.right, nextBounds.right),
      (bounds.bottom, nextBounds.bottom),
    ]) {
      expect(coordinate.$2, closeTo(coordinate.$1, .05),
          reason:
              '$name hover is paint-only; source glyph geometry stays fixed');
    }
  }
}

List<Rect> _glyphBounds(
    TextPainter paragraph, String text, Matrix4 transform, Offset inkOffset) {
  final bounds = <Rect>[];
  var offset = 0;
  for (final rune in text.runes) {
    final end = offset + (rune > 0xffff ? 2 : 1);
    final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: end));
    if (boxes.isNotEmpty) {
      bounds.add(boxes
          .map((box) => MatrixUtils.transformRect(
              transform, box.toRect().shift(inkOffset)))
          .reduce((a, b) => a.expandToInclude(b)));
    }
    offset = end;
  }
  expect(bounds, isNotEmpty);
  return bounds;
}

// Freeze this fixture's transparent sampler pictures and their real layer
// transforms, clips and post-Gaussian opacity. Unknown layers fail explicitly.
class _SnapshotPictureLayer extends Layer {
  _SnapshotPictureLayer(PictureLayer original)
      : picture = _freezePicture(original.picture!),
        complex = original.isComplexHint,
        changing = original.willChangeHint;
  final ui.Picture picture;
  final bool complex, changing;

  static ui.Picture _freezePicture(ui.Picture original) {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawPicture(original);
    return recorder.endRecording();
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    builder.addPicture(
      Offset.zero,
      picture,
      isComplexHint: complex,
      willChangeHint: changing,
    );
  }

  @override
  void dispose() {
    picture.dispose();
    super.dispose();
  }
}

typedef _GaussianKernel = ({
  double sigmaX,
  double sigmaY,
  ui.TileMode? tileMode,
  Rect? bounds,
});

_GaussianKernel _gaussianKernel(ui.ImageFilter filter) {
  // This SDK's real Gaussian has public value fields. Debug toString is
  // stripped in Profile; inspect those fields and prove the complete type and
  // value with an independently constructed official Gaussian equality check.
  final dynamic native = filter;
  late final Object? x, y, mode, bounds;
  try {
    x = native.sigmaX;
    y = native.sigmaY;
    mode = native.tileMode;
    bounds = native.bounds;
  } on NoSuchMethodError {
    fail('The painted native viewport filter is not a Gaussian');
  }
  expect(x, isA<double>());
  expect(y, isA<double>());
  expect(mode == null || mode is ui.TileMode, isTrue);
  expect(bounds == null || bounds is Rect, isTrue);
  final kernel = (
    sigmaX: x as double,
    sigmaY: y as double,
    tileMode: mode as ui.TileMode?,
    bounds: bounds as Rect?,
  );
  expect(kernel.sigmaX.isFinite && kernel.sigmaX >= 0, isTrue);
  expect(kernel.sigmaY, kernel.sigmaX);
  expect(filter, _officialGaussian(kernel),
      reason: 'Verify Gaussian type, both radii, tile mode and native bounds');
  return kernel;
}

ui.ImageFilter _officialGaussian(_GaussianKernel kernel) => ui.ImageFilter.blur(
    sigmaX: kernel.sigmaX,
    sigmaY: kernel.sigmaY,
    tileMode: kernel.tileMode,
    bounds: kernel.bounds);

(double, double) _gaussianSigma(ui.ImageFilter filter) {
  final kernel = _gaussianKernel(filter);
  return (kernel.sigmaX, kernel.sigmaY);
}

/// Capture the real fixed mask geometry, rather than deriving it again from
/// fractions or adding a Gaussian to already flattened opaque RGB pixels.
class _FrozenViewportBand {
  _FrozenViewportBand(this.filter, this.outer, this.offset)
      : clip = filter.parent! as RenderClipRect {
    bounds = _bounds();
    expect(filter.backdropKey, isNull,
        reason: 'The production mask has independent backdrop snapshots');
  }
  final RenderBackdropFilter filter;
  final RenderClipRect clip, outer;
  final Offset offset;
  late final Rect bounds;

  ui.ImageFilter get nativeFilter {
    final resolved =
        filter.filterConfig.resolve(ImageFilterContext(bounds: bounds));
    if (!filter.enabled) return resolved;
    // Read the actual painted layer, including context-resolved bounded blur.
    // Widget sigma/config alone cannot prove the kernel used by the scene.
    // ignore: invalid_use_of_protected_member
    final painted = filter.layer?.filter;
    expect(painted, isNotNull,
        reason: 'Every enabled native viewport strip has a painted filter');
    expect(painted, resolved,
        reason: 'The actual filter retains the real clip/paint-context bounds');
    return painted!;
  }

  Rect _bounds() => MatrixUtils.transformRect(
          clip.getTransformTo(outer), Offset.zero & clip.size)
      .shift(offset);

  void unchanged() {
    expect(filter.attached && clip.attached && outer.attached, isTrue);
    final current = _bounds();
    for (final pair in [
      (bounds.left, current.left),
      (bounds.top, current.top),
      (bounds.right, current.right),
      (bounds.bottom, current.bottom),
    ]) {
      expect(pair.$2, closeTo(pair.$1, .05),
          reason: 'Hover changes only the kernel, never the fixed mask');
    }
  }
}

/// An independent official native Gaussian with a true zero-radius bypass.
/// Its clear branch is empty, as the disabled production BackdropFilter is.
class _FrozenBackdropLayer extends ContainerLayer {
  _FrozenBackdropLayer(this.band);
  final _FrozenViewportBand band;
  bool enabled = false;
  ui.ImageFilter filter = ui.ImageFilter.blur();
  BlendMode blendMode = BlendMode.src;

  void updateKernel() {
    band.unchanged();
    enabled = band.filter.enabled;
    // Tiny native no-op kernels use the live safe composition policy. Freeze
    // source pictures and clip geometry, not a now-obsolete blend-mode choice.
    blendMode = band.filter.blendMode;
    filter = _officialGaussian(_gaussianKernel(band.nativeFilter));
    markNeedsAddToScene();
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    if (enabled) builder.pushBackdropFilter(filter, blendMode: blendMode);
    addChildrenToScene(builder);
    if (enabled) builder.pop();
  }
}

class _FrozenLayerView {
  _FrozenLayerView(OffsetLayer root, this.filters, this.backdrops)
      : root = LayerHandle<OffsetLayer>(root);
  final LayerHandle<OffsetLayer> root;
  final Map<ImageFilterLayer, _FrozenSource> filters;
  final List<_FrozenBackdropLayer> backdrops;

  void updateKernels() {
    for (final entry in filters.entries) {
      final spec = entry.value.filter.widget as LyricFractionalFilter;
      expect(spec.sigma, 0,
          reason: 'Paragraph sampling stays clear beneath the viewport mask');
    }
    expect(backdrops, hasLength(24));
    for (final backdrop in backdrops) {
      backdrop.updateKernel();
    }
  }

  Future<_Frame> capture(Rect bounds, double dpr) async {
    final image = await root.layer!.toImage(bounds, pixelRatio: dpr);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return _Frame(image, Uint8List.fromList(data!.buffer.asUint8List()));
    } catch (_) {
      image.dispose();
      rethrow;
    }
  }

  void dispose() {
    root.layer = null;
    filters.clear();
    backdrops.clear();
  }
}

class _FrozenNativeSources {
  _FrozenNativeSources(WidgetTester tester, _Rig rig, _Frame clear) {
    final viewport = rig.boundary.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    // debugLayer is null in Profile; read the retained boundary layer used by
    // RenderRepaintBoundary.toImage without adding any production test hook.
    // ignore: invalid_use_of_protected_member
    final originalRoot = viewport.layer! as OffsetLayer;
    bounds = Offset.zero & viewport.size;
    final outer = tester.renderObject<RenderClipRect>(find
        .descendant(
          of: rig.viewportBlur,
          matching: find.byType(ClipRect),
        )
        .first);
    // ignore: invalid_use_of_protected_member
    final maskOwner = outer.layer! as ClipRectLayer;
    final bands = [
      for (final filter in rig.viewportFilters(tester))
        _FrozenViewportBand(filter, outer, maskOwner.clipRect!.topLeft),
    ];
    expect(bands, hasLength(24));
    final sourceLayers = <ImageFilterLayer, _FrozenSource>{};
    final allSamplers = <ImageFilterLayer>{};
    for (final element in tester.elementList(find.descendant(
        of: rig.scroll, matching: find.byType(LyricFractionalFilter)))) {
      final owner = element.renderObject!.parent;
      if (owner is! RenderRepaintBoundary) continue;
      // ignore: invalid_use_of_protected_member
      final sampler = (owner.layer as OffsetLayer?)?.firstChild;
      if (sampler is ImageFilterLayer) allSamplers.add(sampler);
    }
    for (final source in clear.sources) {
      final boundary = source.filter.renderObject!.parent;
      expect(boundary, isA<RenderRepaintBoundary>());
      // ignore: invalid_use_of_protected_member
      final layer = (boundary as RenderRepaintBoundary).layer!;
      final gaussian = layer.firstChild;
      expect(gaussian, isA<ImageFilterLayer>());
      expect(
        gaussian!.nextSibling,
        isNull,
        reason: 'Freeze the one actual transparent sampler boundary',
      );
      sourceLayers[gaussian as ImageFilterLayer] = source;
    }
    try {
      full = _copyView(originalRoot, sourceLayers, maskOwner, bands);
      background = _copyView(originalRoot, sourceLayers, maskOwner, bands,
          excludedSources: allSamplers);
      expect(full!.filters, hasLength(sourceLayers.length),
          reason: 'Every visible frozen source keeps its own native Gaussian');
      for (final entry in sourceLayers.entries) {
        isolated[entry.value] = _copyView(
          originalRoot,
          sourceLayers,
          maskOwner,
          bands,
          onlySource: entry.key,
        );
      }
    } catch (_) {
      full?.dispose();
      background?.dispose();
      for (final view in isolated.values) {
        view.dispose();
      }
      rethrow;
    }
  }

  late final Rect bounds;
  _FrozenLayerView? full;
  _FrozenLayerView? background;
  bool _reportedUniformRounding = false;
  final isolated = <_FrozenSource, _FrozenLayerView>{};

  static _FrozenLayerView _copyView(
    OffsetLayer original,
    Map<ImageFilterLayer, _FrozenSource> sources,
    ClipRectLayer maskOwner,
    List<_FrozenViewportBand> bands, {
    ImageFilterLayer? onlySource,
    Set<ImageFilterLayer> excludedSources = const {},
  }) {
    final filters = <ImageFilterLayer, _FrozenSource>{};
    final backdrops = <_FrozenBackdropLayer>[];
    Layer? copy(Layer layer) {
      if (layer is PictureLayer) return _SnapshotPictureLayer(layer);
      if (layer is ImageFilterLayer &&
          (excludedSources.contains(layer) ||
              (sources.containsKey(layer) &&
                  onlySource != null &&
                  !identical(layer, onlySource)))) {
        return null;
      }
      final ContainerLayer result;
      if (layer is ImageFilterLayer) {
        result = ImageFilterLayer(
          imageFilter: layer.imageFilter,
          offset: layer.offset,
        );
        final source = sources[layer];
        if (source != null) filters[result as ImageFilterLayer] = source;
      } else if (layer is BackdropFilterLayer) {
        result = BackdropFilterLayer(
            filter: layer.filter, blendMode: layer.blendMode)
          ..backdropKey = layer.backdropKey;
      } else if (layer is OpacityLayer) {
        result = OpacityLayer(alpha: layer.alpha, offset: layer.offset);
      } else if (layer is TransformLayer) {
        result = TransformLayer(
          offset: layer.offset,
          transform:
              layer.transform == null ? null : Matrix4.copy(layer.transform!),
        );
      } else if (layer is ClipRectLayer) {
        result = ClipRectLayer(
          clipRect: layer.clipRect,
          clipBehavior: layer.clipBehavior,
        );
      } else if (layer is ShaderMaskLayer) {
        result = ShaderMaskLayer(
          shader: layer.shader,
          maskRect: layer.maskRect,
          blendMode: layer.blendMode,
        );
      } else if (layer is ClipRRectLayer) {
        result = ClipRRectLayer(
          clipRRect: layer.clipRRect,
          clipBehavior: layer.clipBehavior,
        );
      } else if (layer is ColorFilterLayer) {
        result = ColorFilterLayer(colorFilter: layer.colorFilter);
      } else if (layer.runtimeType == OffsetLayer) {
        result = OffsetLayer(offset: (layer as OffsetLayer).offset);
      } else if (layer.runtimeType == ContainerLayer) {
        result = ContainerLayer();
      } else {
        throw UnsupportedError('Unfrozen fixture layer: ${layer.runtimeType}');
      }
      try {
        for (var child = (layer as ContainerLayer).firstChild;
            child != null;
            child = child.nextSibling) {
          final cloned = copy(child);
          if (cloned != null) result.append(cloned);
        }
        if (identical(layer, maskOwner)) {
          // Clear disables the live backdrop layers, but the independently
          // frozen clip geometry remains at this exact compositing level.
          for (final band in bands) {
            final backdrop = _FrozenBackdropLayer(band);
            backdrops.add(backdrop);
            result.append(ClipRectLayer(
                clipRect: band.bounds, clipBehavior: band.clip.clipBehavior)
              ..append(backdrop));
          }
        }
        return result;
      } catch (_) {
        result.dispose();
        rethrow;
      }
    }

    final root = copy(original)! as OffsetLayer;
    expect(backdrops, hasLength(24),
        reason: 'Every actual viewport strip belongs to the frozen scene');
    return _FrozenLayerView(root, filters, backdrops);
  }

  Future<_Frame> reference(_Rig rig, _Frame clear, _Frame actual) async {
    full!.updateKernels();
    background!.updateKernels();
    final nativeBackground = await background!.capture(bounds, rig.dpr);
    try {
      // Retain the complete Gaussian-tail assertion for each transparent source,
      // now with its original transforms, clips, post-Gaussian alpha and backdrop.
      for (final entry in isolated.entries) {
        final source = entry.key;
        if (entry.value.backdrops
            .every((layer) => !layer.band.filter.enabled)) {
          continue;
        }
        entry.value.updateKernels();
        // A backdrop strip may read a previous strip's filtered edge. Bound the
        // complete composed tail, not the radius of one old paragraph filter.
        final radii = entry.value.backdrops
            .where((layer) => layer.band.filter.enabled)
            .map((layer) =>
                _gaussianSigma(layer.band.nativeFilter).$1 * rig.dpr);
        final padding = math.max(
            (24 * rig.dpr).ceil() + 2,
            (6 * radii.fold<double>(0, (sum, radius) => sum + radius)).ceil() +
                2);
        final region = source.region.inflate(padding.toDouble()).intersect(
              Rect.fromLTWH(
                0,
                0,
                clear.image.width.toDouble(),
                clear.image.height.toDouble(),
              ),
            );
        // Re-rendering to a cropped target changes the backdrop input/culling
        // and sampler origin. Keep the complete native viewport target, then
        // inspect its already rendered bytes at the physical tail boundary.
        final tail = await entry.value.capture(bounds, rig.dpr);
        try {
          final rows = [
            if (region.top > 0) region.top.floor(),
            if (region.bottom < clear.image.height) region.bottom.ceil() - 1,
          ];
          final columns = [
            if (region.left > 0) region.left.floor(),
            if (region.right < clear.image.width) region.right.ceil() - 1,
          ];
          for (final y in rows) {
            for (var x = region.left.floor(); x < region.right.ceil(); x++) {
              _expectTailBackground(
                  tail, nativeBackground, actual, source, region, x, y, rig);
            }
          }
          for (final x in columns) {
            for (var y = region.top.floor(); y < region.bottom.ceil(); y++) {
              _expectTailBackground(
                  tail, nativeBackground, actual, source, region, x, y, rig);
            }
          }
        } finally {
          tail.dispose();
        }
      }
      return await full!.capture(bounds, rig.dpr);
    } finally {
      nativeBackground.dispose();
    }
  }

  void _expectTailBackground(
      _Frame tail,
      _Frame nativeBackground,
      _Frame actual,
      _FrozenSource source,
      Rect region,
      int x,
      int y,
      _Rig rig) {
    final at = (y * tail.image.width + x) * 4;
    final expected = nativeBackground.rgba.sublist(at, at + 4);
    if (!_reportedUniformRounding &&
        !listEquals(expected, const [0x62, 0x71, 0x72, 255])) {
      _reportedUniformRounding = true;
      debugPrintSynchronously('LYRIC_HOVER_UNIFORM_NATIVE_BACKGROUND '
          '${jsonEncode({
            'dpr': rig.dpr,
            'source': source.text,
            'pixel': [x, y],
            'region': [region.left, region.top, region.right, region.bottom],
            'nativeEmpty': expected,
            'tail': tail.rgba.sublist(at, at + 4),
            'actualViewport': actual.rgba.sublist(at, at + 4),
            'radii': full!.backdrops
                .map((layer) => _gaussianSigma(layer.band.nativeFilter).$1)
                .toList(),
          })}');
    }
    _expectBackgroundPixel(tail.rgba, at,
        expected: expected,
        diagnostic: 'source=${source.text} region=$region pixel=($x,$y) '
            'dpr=${rig.dpr} nativeEmpty=$expected '
            'tail=${tail.rgba.sublist(at, at + 4)} '
            'actual=${actual.rgba.sublist(at, at + 4)}');
    expect(actual.rgba[at + 3], 255,
        reason: 'The real opaque lyric viewport must not be erased. '
            'source=${source.text} region=$region pixel=($x,$y) '
            'nativeEmpty=$expected actual=${actual.rgba.sublist(at, at + 4)}');
  }

  void dispose() {
    full?.dispose();
    background?.dispose();
    for (final view in isolated.values) {
      view.dispose();
    }
    isolated.clear();
  }
}

class _Frame {
  _Frame(this.image, this.rgba);
  final ui.Image image;
  final Uint8List rgba;
  final sources = <_FrozenSource>[];
  _FrozenNativeSources? nativeSources;

  Rect physical(Rect logical, double dpr) => Rect.fromLTRB(
        logical.left * dpr,
        logical.top * dpr,
        logical.right * dpr,
        logical.bottom * dpr,
      );

  Uint8List pixels(Rect bounds) {
    final left = bounds.left.floor().clamp(0, image.width);
    final right = bounds.right.ceil().clamp(0, image.width);
    final top = bounds.top.floor().clamp(0, image.height);
    final bottom = bounds.bottom.ceil().clamp(0, image.height);
    final result = Uint8List((right - left) * (bottom - top) * 4);
    for (var y = top; y < bottom; y++) {
      result.setRange(
          (y - top) * (right - left) * 4,
          (y - top + 1) * (right - left) * 4,
          rgba,
          (y * image.width + left) * 4);
    }
    return result;
  }

  Offset center(Rect bounds) {
    var mass = 0.0, xMoment = 0.0, yMoment = 0.0;
    for (var y = bounds.top.floor().clamp(0, image.height);
        y < bounds.bottom.ceil().clamp(0, image.height);
        y++) {
      for (var x = bounds.left.floor().clamp(0, image.width);
          x < bounds.right.ceil().clamp(0, image.width);
          x++) {
        final index = (y * image.width + x) * 4;
        final weight = (rgba[index] - 0x62).abs() +
            (rgba[index + 1] - 0x71).abs() +
            (rgba[index + 2] - 0x72).abs();
        mass += weight;
        xMoment += weight * (x + .5);
        yMoment += weight * (y + .5);
      }
    }
    expect(mass, greaterThan(0),
        reason: 'The actual track contains painted ink');
    return Offset(xMoment / mass, yMoment / mass);
  }

  void dispose() {
    nativeSources?.dispose();
    for (final source in sources) {
      source.image.dispose();
    }
    image.dispose();
  }
}

class _FrozenSource {
  _FrozenSource({
    required this.text,
    required this.element,
    required this.filter,
    required this.render,
    required this.bounds,
    required this.region,
    required this.scaleX,
    required this.scaleY,
    required this.rgba,
    required this.image,
  });

  final String text;
  final Element element, filter;
  final RenderCustomPaint render;
  final Rect bounds, region;
  final double scaleX, scaleY;
  final Uint8List rgba;
  final ui.Image image;

  void unchanged(_Rig rig) {
    final viewport =
        rig.boundary.currentContext!.findRenderObject()! as RenderBox;
    final painter =
        (element.widget as CustomPaint).painter! as PlainLyricWordFollowPainter;
    expect(painter.text.text!.toPlainText(), text);
    final transform = render.getTransformTo(viewport);
    final boxes = painter.text.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length),
    );
    final actual = boxes
        .map((box) => MatrixUtils.transformRect(
            transform, box.toRect().shift(painter.inkOffset)))
        .reduce((a, b) => a.expandToInclude(b));
    for (final pair in [
      (bounds.left, actual.left),
      (bounds.top, actual.top),
      (bounds.right, actual.right),
      (bounds.bottom, actual.bottom),
    ]) {
      expect(pair.$2, closeTo(pair.$1, .05),
          reason: 'The fixed native viewport reference cannot move $text');
    }
  }
}

Uint8List _backgroundBytes(int width, int height) {
  final result = Uint8List(width * height * 4);
  for (var at = 0; at < result.length; at += 4) {
    result[at] = 0x62;
    result[at + 1] = 0x71;
    result[at + 2] = 0x72;
    result[at + 3] = 255;
  }
  return result;
}

Future<_Frame> _decodeFrame(Uint8List rgba, int width, int height) async {
  final ready = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      rgba, width, height, ui.PixelFormat.rgba8888, ready.complete);
  final image = await ready.future;
  try {
    final decoded = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return _Frame(image, Uint8List.fromList(decoded!.buffer.asUint8List()));
  } catch (_) {
    image.dispose();
    rethrow;
  }
}

Future<void> _freezeSources(WidgetTester tester, _Rig rig, _Frame clear) async {
  final viewport =
      rig.boundary.currentContext!.findRenderObject()! as RenderBox;
  final physicalViewport = Rect.fromLTWH(
      0, 0, clear.image.width.toDouble(), clear.image.height.toDouble());
  final inputs = <({
    String text,
    Element element,
    Element filter,
    RenderCustomPaint render,
    Rect bounds,
    Rect region,
    double scaleX,
    double scaleY,
    Uint8List rgba,
  })>[];
  final paints = find.descendant(
    of: rig.scroll,
    matching: find.byWidgetPredicate((widget) =>
        widget is CustomPaint && widget.painter is PlainLyricWordFollowPainter),
  );
  for (final element in tester.elementList(paints)) {
    final painter =
        (element.widget as CustomPaint).painter! as PlainLyricWordFollowPainter;
    final text = painter.text.text!.toPlainText();
    if (text.isEmpty) continue;
    final render = element.renderObject! as RenderCustomPaint;
    final transform = render.getTransformTo(viewport);
    final boxes = painter.text.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length),
    );
    if (boxes.isEmpty) continue;
    final bounds = boxes
        .map((box) => MatrixUtils.transformRect(
            transform, box.toRect().shift(painter.inkOffset)))
        .reduce((a, b) => a.expandToInclude(b));
    // This is only the source ownership guard for a frozen screenshot, not a
    // blur/centroid crop. The final oracle retains all neighboring blur tails.
    final guarded = clear.physical(bounds, rig.dpr).inflate(2);
    final region = Rect.fromLTRB(
            guarded.left.floorToDouble(),
            guarded.top.floorToDouble(),
            guarded.right.ceilToDouble(),
            guarded.bottom.ceilToDouble())
        .intersect(physicalViewport);
    if (region.isEmpty) continue;
    Element? filter;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is LyricFractionalFilter) {
        filter = ancestor;
        return false;
      }
      return true;
    });
    expect(filter, isNotNull);
    final matrix = filter!.renderObject!.getTransformTo(viewport);
    inputs.add((
      text: text,
      element: element,
      filter: filter!,
      render: render,
      bounds: bounds,
      region: region,
      scaleX: math.sqrt(matrix[0] * matrix[0] + matrix[1] * matrix[1]),
      scaleY: math.sqrt(matrix[4] * matrix[4] + matrix[5] * matrix[5]),
      rgba: _backgroundBytes(region.width.toInt(), region.height.toInt()),
    ));
  }
  expect(inputs, isNotEmpty);
  final owned = List<int>.filled(inputs.length, 0);
  for (var y = 0; y < clear.image.height; y++) {
    for (var x = 0; x < clear.image.width; x++) {
      final at = (y * clear.image.width + x) * 4;
      if (clear.rgba[at + 3] != 255) {
        fail('The frozen viewport must retain its opaque fixed backdrop');
      }
      if (clear.rgba[at] == 0x62 &&
          clear.rgba[at + 1] == 0x71 &&
          clear.rgba[at + 2] == 0x72) {
        continue;
      }
      final point = Offset(x + .5, y + .5);
      final owners = <int>[
        for (var index = 0; index < inputs.length; index++)
          if (inputs[index].region.contains(point)) index,
      ];
      if (owners.isEmpty) {
        fail('Every original viewport ink pixel belongs to a real '
            'paragraph glyph rect; unowned pixel ($x,$y)');
      }
      // Adjacent font selection boxes can overlap in empty line leading. A
      // painted pixel is assigned once to the nearest actual source row.
      owners.sort((a, b) => (inputs[a].region.center.dy - point.dy)
          .abs()
          .compareTo((inputs[b].region.center.dy - point.dy).abs()));
      final owner = owners.first;
      owned[owner]++;
      final input = inputs[owner];
      final destination =
          ((y - input.region.top.toInt()) * input.region.width.toInt() +
                  x -
                  input.region.left.toInt()) *
              4;
      input.rgba.setRange(destination, destination + 4, clear.rgba, at);
    }
  }
  await _runWithRealIo(tester, () async {
    try {
      for (var index = 0; index < inputs.length; index++) {
        if (owned[index] == 0) continue;
        final input = inputs[index];
        final frame = await _decodeFrame(input.rgba, input.region.width.toInt(),
            input.region.height.toInt());
        clear.sources.add(_FrozenSource(
          text: input.text,
          element: input.element,
          filter: input.filter,
          render: input.render,
          bounds: input.bounds,
          region: input.region,
          scaleX: input.scaleX,
          scaleY: input.scaleY,
          rgba: frame.rgba,
          image: frame.image,
        ));
      }
      final replayBytes =
          _backgroundBytes(clear.image.width, clear.image.height);
      for (final source in clear.sources) {
        _addSourceContrast(replayBytes, clear.image.width, source.rgba,
            source.image.width, source.image.height,
            offsetX: source.region.left.toInt(),
            offsetY: source.region.top.toInt());
      }
      final replay = await _decodeFrame(
          replayBytes, clear.image.width, clear.image.height);
      try {
        expect(replay.rgba, orderedEquals(clear.rgba),
            reason: 'At zero Gaussian the frozen paragraph layers reproduce '
                'every actual viewport byte, without repainting text');
      } finally {
        replay.dispose();
      }
    } catch (_) {
      for (final source in clear.sources) {
        source.image.dispose();
      }
      clear.sources.clear();
      rethrow;
    }
  });
  debugPrintSynchronously('LYRIC_HOVER_ZERO_REPLAY ${jsonEncode({
        'dpr': rig.dpr,
        'viewportBytes': clear.rgba.length,
        'exact': true,
        'layers': clear.sources.length,
        'ownedPixels': owned.fold<int>(0, (a, b) => a + b),
      })}');
}

void _addSourceContrast(Uint8List output, int width, Uint8List source,
    int sourceWidth, int sourceHeight,
    {int offsetX = 0, int offsetY = 0}) {
  const background = [0x62, 0x71, 0x72];
  var minimum = 0, maximum = 255;
  for (var y = 0; y < sourceHeight; y++) {
    for (var x = 0; x < sourceWidth; x++) {
      final from = (y * sourceWidth + x) * 4;
      final to = ((y + offsetY) * width + x + offsetX) * 4;
      for (var channel = 0; channel < 3; channel++) {
        final value =
            output[to + channel] + source[from + channel] - background[channel];
        if (value < minimum) minimum = value;
        if (value > maximum) maximum = value;
        output[to + channel] = value;
      }
    }
  }
  expect(minimum, greaterThanOrEqualTo(0),
      reason: 'Frozen foreground contrast must not clip');
  expect(maximum, lessThanOrEqualTo(255),
      reason: 'Frozen foreground contrast must not saturate');
}

Future<_Frame> _capture(WidgetTester tester, _Rig rig, String label) async =>
    (await _runWithRealIo(tester, () async {
      final image = await (rig.boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage(pixelRatio: rig.dpr);
      try {
        final bytes =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (_output.isNotEmpty) {
          final directory = Directory(_output).absolute;
          expect(directory.path.replaceAll('\\', '/'),
              contains('/tool/qa-local/'));
          await directory.create(recursive: true);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('${directory.path}/hover-${rig.dpr}-$label.png')
              .writeAsBytes(png!.buffer.asUint8List());
        }
        return _Frame(image, Uint8List.fromList(bytes!.buffer.asUint8List()));
      } catch (_) {
        image.dispose();
        rethrow;
      }
    }));

void _expectBackgroundPixel(Uint8List rgba, int at,
    {List<int> expected = const [0x62, 0x71, 0x72, 255],
    String diagnostic = ''}) {
  if (!listEquals(rgba.sublist(at, at + 4), expected)) {
    fail('The complete Gaussian tail must end in the independent native '
        'fixed backdrop exactly. $diagnostic');
  }
}

Future<_Frame> _gaussianReference(
    WidgetTester tester, _Rig rig, _Frame clear, _Frame actual) async {
  expect(clear.sources, isNotEmpty);
  for (final source in clear.sources) {
    source.unchanged(rig);
  }
  return _runWithRealIo(
      tester, () => clear.nativeSources!.reference(rig, clear, actual));
}

class _HoverPose {
  _HoverPose(this.sigma, this.rgba, this.centers);
  final double sigma;
  final Uint8List rgba;
  final Map<String, Offset> centers;

  void expectSameSigma(_HoverPose other) {
    expect(other.sigma, sigma,
        reason: 'Compare the actual forward and reverse poses at equal sigma');
    expect(other.rgba, orderedEquals(rgba),
        reason:
            'At equal sigma, reversing hover retraces every viewport pixel');
    for (final name in centers.keys) {
      expect(other.centers[name], centers[name],
          reason: '$name retraces the same measured ink trajectory');
    }
  }

  void expectClear(_Frame clear) {
    expect(sigma, 0);
    expect(rgba, orderedEquals(clear.rgba),
        reason: 'The clear endpoint retains every original viewport pixel');
  }
}

Future<_HoverPose> _checkFrame(
    WidgetTester tester,
    _Rig rig,
    List<_Track> tracks,
    _Frame clear,
    String label,
    double scrollOffset,
    int reads) async {
  expect(rig.position, 15.2);
  expect(rig.reads, reads,
      reason: 'Hover cannot resample or move the media timeline');
  expect(rig.seeks, 0);
  expect(rig.scrollController(tester).offset, closeTo(scrollOffset, .05));
  final sigma = rig.sigma(tester);
  final frame = await _capture(tester, rig, label);
  final centers = <String, Offset>{};
  _Frame? independent;
  try {
    final allClear = sigma == 0;
    final reference = allClear
        ? clear
        : independent = await _gaussianReference(tester, rig, clear, frame);
    expect(frame.rgba.length, reference.rgba.length);
    for (var at = 0; at < frame.rgba.length; at++) {
      if (at % 4 == 3 && frame.rgba[at] != 255) {
        fail('Positive viewport blur erased opaque pixels: '
            'sigma=$sigma pixel=(${at ~/ 4 % frame.image.width},'
            '${at ~/ 4 ~/ frame.image.width}) '
            'actualRGBA=${frame.rgba.sublist(at - 3, at + 1)}');
      }
      final delta = (frame.rgba[at] - reference.rgba[at]).abs();
      if (delta > (at % 4 == 3 ? 0 : 2)) {
        fail('The independent frozen viewport Gaussian differs at '
            'byte $at by $delta (RGB tolerance 2, alpha exact)');
      }
    }
    for (final track in tracks) {
      track.unchanged(tester, rig);
      final bounds = frame.physical(track.crop, rig.dpr);
      final actual = frame.center(bounds);
      final expected = reference.center(bounds);
      centers[track.name] = actual;
      debugPrintSynchronously('LYRIC_HOVER dpr=${rig.dpr} frame=$label '
          'track=${track.name} sigma=$sigma '
          'fromClear=${actual - clear.center(bounds)} '
          'referenceDelta=${actual - expected}');
      if (_output.isNotEmpty && sigma != 0) {
        await _runWithRealIo(tester, () async {
          final png =
              await reference.image.toByteData(format: ui.ImageByteFormat.png);
          await File('${Directory(_output).absolute.path}/'
                  'hover-${rig.dpr}-$label-reference-${track.name}.png')
              .writeAsBytes(png!.buffer.asUint8List());
        });
      }
      expect((actual - expected).distance, lessThan(.25),
          reason:
              '${track.name}: the actual ink follows the independent native '
              'Gaussian at the same sigma');
      if (sigma == 0) {
        expect(frame.pixels(bounds), orderedEquals(clear.pixels(bounds)),
            reason:
                '${track.name}: the clear endpoint is the original viewport pixels');
      }
    }
    return _HoverPose(sigma, frame.rgba, centers);
  } finally {
    independent?.dispose();
    frame.dispose();
  }
}

class _Mouse {
  _Mouse(this.gesture);
  final TestGesture gesture;
  bool _removed = false;
  Future<void> moveTo(Offset point) => gesture.moveTo(point);
  Future<void> removePointer() async {
    if (_removed) return;
    _removed = true;
    await gesture.removePointer();
  }
}

Future<_Mouse> _mouse(WidgetTester tester) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: const Offset(5, 5));
  final pointer = _Mouse(gesture);
  addTearDown(pointer.removePointer);
  return pointer;
}

Future<_Frame> _clear(WidgetTester tester, _Rig rig, _Mouse pointer) async {
  await pointer.moveTo(tester.getCenter(rig.scroll));
  await tester.pump();
  await tester.pumpAndSettle();
  expect(rig.sigma(tester), 0);
  expect(tester.binding.transientCallbackCount, 0);
  final clear = await _capture(tester, rig, 'initial-clear');
  try {
    await _freezeSources(tester, rig, clear);
    clear.nativeSources = _FrozenNativeSources(tester, rig, clear);
    final empty = await _runWithRealIo(
        tester,
        () => clear.nativeSources!.background!
            .capture(clear.nativeSources!.bounds, rig.dpr));
    try {
      for (var at = 0; at < empty.rgba.length; at += 4) {
        _expectBackgroundPixel(empty.rgba, at,
            diagnostic: 'The zero-kernel control must contain no lyric ink');
      }
    } finally {
      empty.dispose();
    }
    final replay = await _runWithRealIo(
        tester,
        () => clear.nativeSources!.full!
            .capture(clear.nativeSources!.bounds, rig.dpr));
    try {
      expect(replay.rgba, orderedEquals(clear.rgba),
          reason: 'Frozen transparent sampler pictures and original native '
              'layers reproduce every initial viewport byte before blur');
      debugPrintSynchronously('LYRIC_HOVER_NATIVE_ZERO_REPLAY dpr=${rig.dpr} '
          'exact=true sources=${clear.nativeSources!.isolated.length}');
    } finally {
      replay.dispose();
    }
    return clear;
  } catch (_) {
    clear.dispose();
    rethrow;
  }
}

Future<void> _settled(WidgetTester tester, _Rig rig) async {
  await tester.pumpAndSettle();
  expect(rig.seeks, 0);
  expect(tester.binding.transientCallbackCount, 0);
  expect(tester.takeException(), isNull);
}

Future<void> _checkDirectionRetrace(
    WidgetTester tester,
    _Rig rig,
    _Mouse pointer,
    List<_Track> tracks,
    _Frame clear,
    double scrollOffset,
    int reads,
    _Frame blurred) async {
  // Both production directions use easeOutCubic, so equal elapsed times do
  // not yield equal sigma. Cubic also returns discrete bisection samples.
  // Reverse the real pointer-driven controller at its actual painted value:
  // its zero-elapsed first frame provides an exactly equal-sigma counterpart
  // without setting controller values or replacing the production curve.
  for (final milliseconds in [16, 40, 88]) {
    await pointer.moveTo(tester.getCenter(rig.scroll));
    await tester.pump();
    await tester.pump(Duration(milliseconds: milliseconds));
    expect(rig.readingClock(tester).lastElapsedDuration,
        Duration(milliseconds: milliseconds));
    final reverse = await _checkFrame(tester, rig, tracks, clear,
        'retrace-$milliseconds-reverse-moving', scrollOffset, reads);
    expect(reverse.sigma, greaterThan(0));

    await pointer.moveTo(const Offset(5, 5));
    await tester.pump();
    expect(rig.readingClock(tester).lastElapsedDuration, Duration.zero);
    final forwardFirst = await _checkFrame(tester, rig, tracks, clear,
        'retrace-$milliseconds-forward-first', scrollOffset, reads);
    reverse.expectSameSigma(forwardFirst);

    await tester.pump(const Duration(milliseconds: 16));
    expect(rig.readingClock(tester).lastElapsedDuration,
        const Duration(milliseconds: 16));
    final forward = await _checkFrame(tester, rig, tracks, clear,
        'retrace-$milliseconds-forward-moving', scrollOffset, reads);
    expect(forward.sigma, greaterThan(forwardFirst.sigma));

    await pointer.moveTo(tester.getCenter(rig.scroll));
    await tester.pump();
    expect(rig.readingClock(tester).lastElapsedDuration, Duration.zero);
    final reverseFirst = await _checkFrame(tester, rig, tracks, clear,
        'retrace-$milliseconds-reverse-first', scrollOffset, reads);
    forward.expectSameSigma(reverseFirst);

    await _settled(tester, rig);
    (await _checkFrame(tester, rig, tracks, clear,
            'retrace-$milliseconds-clear', scrollOffset, reads))
        .expectClear(clear);
    await pointer.moveTo(const Offset(5, 5));
    await _settled(tester, rig);
    final restored =
        await _capture(tester, rig, 'retrace-$milliseconds-blur-restored');
    try {
      expect(restored.rgba, orderedEquals(blurred.rgba),
          reason: 'Every real reversal restores the same blurred endpoint');
    } finally {
      restored.dispose();
    }
  }
}

Future<void> _checkClearHandoff(WidgetTester tester, _Rig rig, _Mouse pointer,
    List<_Track> tracks, _Frame clear, double scrollOffset, int reads) async {
  await pointer.moveTo(tester.getCenter(rig.scroll));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 119));
  expect(rig.readingClock(tester).lastElapsedDuration,
      const Duration(milliseconds: 119));
  final lastPositive = await _checkFrame(
      tester, rig, tracks, clear, 'handoff-last-positive', scrollOffset, reads);
  expect(lastPositive.sigma, greaterThan(0));

  await tester.pump(const Duration(milliseconds: 1));
  final zero = await _checkFrame(
      tester, rig, tracks, clear, 'handoff-zero', scrollOffset, reads);
  zero.expectClear(clear);
  for (final name in lastPositive.centers.keys) {
    final before = lastPositive.centers[name]!;
    final after = zero.centers[name]!;
    debugPrintSynchronously('LYRIC_HOVER_HANDOFF_POSITION ${jsonEncode({
          'dpr': rig.dpr,
          'track': name,
          'lastPositiveSigma': lastPositive.sigma,
          'lastPositive': [before.dx, before.dy],
          'zero': [after.dx, after.dy],
          'delta': [after.dx - before.dx, after.dy - before.dy],
        })}');
    // Reaching zero may undo the displacement introduced by positive blur.
    // The actual equal-sigma reversal checks above cover that inverse path;
    // zero and every later frame must preserve the original clear pixels.
  }
  await _settled(tester, rig);
  (await _checkFrame(
          tester, rig, tracks, clear, 'handoff-settled', scrollOffset, reads))
      .expectClear(clear);
  for (var frame = 1; frame <= 15; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    (await _checkFrame(tester, rig, tracks, clear, 'handoff-idle-$frame',
            scrollOffset, reads))
        .expectClear(clear);
  }
  expect(tester.binding.transientCallbackCount, 0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => ensureAppFontsLoaded(_policy));
  for (final dpr in [1.0, 1.25, 1.5]) {
    testWidgets(
        'real lyric hover retraces all three track ink origins at ${dpr}x',
        (tester) async {
      final rig = _Rig(dpr);
      await rig.mount(tester);
      expect(rig.sigma(tester), greaterThan(0));
      final pointer = await _mouse(tester);
      final clear = await _clear(tester, rig, pointer);
      try {
        final tracks = [
          for (final name in _texts.keys) _Track(tester, rig, name)
        ];
        final offset = rig.scrollController(tester).offset;
        final reads = rig.reads;
        final endpoints = <String, Uint8List>{};
        for (final outward in [true, false]) {
          await pointer.moveTo(
              outward ? const Offset(5, 5) : tester.getCenter(rig.scroll));
          await tester.pump();
          await _checkFrame(tester, rig, tracks, clear,
              '${outward ? 'blur' : 'deblur'}-first', offset, reads);
          for (var frame = 1; frame <= 15; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            await _checkFrame(tester, rig, tracks, clear,
                '${outward ? 'blur' : 'deblur'}-$frame', offset, reads);
          }
          await _settled(tester, rig);
          expect(rig.sigma(tester), outward ? greaterThan(0) : 0);
          final endpoint =
              await _capture(tester, rig, outward ? 'blur-end' : 'deblur-end');
          try {
            for (final track in tracks) {
              final bounds = endpoint.physical(track.crop, dpr);
              if (outward) {
                endpoints[track.name] = endpoint.pixels(bounds);
              } else {
                expect(endpoint.pixels(bounds),
                    orderedEquals(clear.pixels(bounds)));
              }
            }
            if (outward) {
              expect(endpoint.rgba, isNot(orderedEquals(clear.rgba)),
                  reason: 'The actual fixed bands must blur visible lyric ink');
            }
          } finally {
            endpoint.dispose();
          }
        }
        await pointer.moveTo(const Offset(5, 5));
        await _settled(tester, rig);
        final restored = await _capture(tester, rig, 'blur-restored');
        try {
          for (final track in tracks) {
            expect(restored.pixels(restored.physical(track.crop, dpr)),
                orderedEquals(endpoints[track.name]!),
                reason:
                    'The reverse process returns the same blurred viewport ink');
          }
          await _checkDirectionRetrace(
              tester, rig, pointer, tracks, clear, offset, reads, restored);
        } finally {
          restored.dispose();
        }
        await _checkClearHandoff(
            tester, rig, pointer, tracks, clear, offset, reads);
      } finally {
        clear.dispose();
      }
      await rig.close(tester);
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  testWidgets(
      'real lyric near-zero hover reversal preserves current painted origin',
      (tester) async {
    final rig = _Rig(1);
    await rig.mount(tester);
    final pointer = await _mouse(tester);
    final clear = await _clear(tester, rig, pointer);
    try {
      final tracks = [
        for (final name in _texts.keys) _Track(tester, rig, name)
      ];
      final offset = rig.scrollController(tester).offset;
      final reads = rig.reads;
      await pointer.moveTo(const Offset(5, 5));
      await _settled(tester, rig);
      final fullBlur = rig.sigma(tester);
      await pointer.moveTo(tester.getCenter(rig.scroll));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 96));
      final beforeSigma = rig.sigma(tester);
      expect(beforeSigma, inExclusiveRange(0, fullBlur * .1));
      final before = await _capture(tester, rig, 'reverse-near-zero-before');
      try {
        await pointer.moveTo(const Offset(5, 5));
        await tester.pump();
        expect(rig.sigma(tester), closeTo(beforeSigma, 1e-8));
        final first = await _capture(tester, rig, 'reverse-near-zero-first');
        try {
          for (final track in tracks) {
            final bounds = first.physical(track.crop, rig.dpr);
            expect(first.pixels(bounds), orderedEquals(before.pixels(bounds)),
                reason:
                    'Retargeting hover starts from the currently painted source');
          }
        } finally {
          first.dispose();
        }
      } finally {
        before.dispose();
      }
      await tester.pump(const Duration(milliseconds: 16));
      await _checkFrame(
          tester, rig, tracks, clear, 'reverse-near-zero-next', offset, reads);
      await _settled(tester, rig);
      expect(rig.sigma(tester), closeTo(fullBlur, 1e-8));
      await pointer.moveTo(tester.getCenter(rig.scroll));
      await _settled(tester, rig);
      await _checkFrame(
          tester, rig, tracks, clear, 'reverse-near-zero-final', offset, reads);
    } finally {
      clear.dispose();
    }
    await rig.close(tester);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
      'hidden lyric retires in-flight hover and unmount cancels its clock',
      (tester) async {
    final rig = _Rig(1);
    await rig.mount(tester);
    final pointer = await _mouse(tester);
    await pointer.moveTo(tester.getCenter(rig.scroll));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    rig.hidden.value = true;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
    rig.hidden.value = false;
    await tester.pumpAndSettle();
    expect(rig.sigma(tester), 0);
    expect(rig.seeks, 0);
    await pointer.moveTo(const Offset(5, 5));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await rig.close(tester);
    await pointer.removePointer();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'high contrast and reduced motion keep real hover tracks complete and idle',
      (tester) async {
    for (final highContrast in [true, false]) {
      final rig = _Rig(1)
        ..highContrast = highContrast
        ..reduced = !highContrast;
      await rig.mount(tester);
      final pointer = await _mouse(tester);
      await pointer.moveTo(tester.getCenter(rig.scroll));
      await tester.pumpAndSettle();
      final filters = tester.widgetList<LyricFractionalFilter>(find.descendant(
        of: rig.tile,
        matching: find.byType(LyricFractionalFilter),
      ));
      expect(filters, isNotEmpty);
      expect(filters.every((filter) => !filter.enabled && filter.sigma == 0),
          isTrue);
      expect(tester.widget<LyricViewportBlur>(rig.viewportBlur).enabled,
          !highContrast);
      expect(rig.viewportFilters(tester).every((filter) => !filter.enabled),
          isTrue);
      for (final name in _texts.keys) {
        final painter = tester
            .widget<CustomPaint>(_paint(rig, _texts[name]!))
            .painter! as PlainLyricWordFollowPainter;
        expect(painter.text.text!.toPlainText(), _texts[name]);
        expect(painter.text.didExceedMaxLines, isFalse);
      }
      await pointer.moveTo(const Offset(5, 5));
      await _settled(tester, rig);
      expect(rig.sigma(tester), highContrast ? 0 : greaterThan(0),
          reason: 'Reduced motion retains configured static blur without '
              'an animated reading clock; high contrast stays clear');
      await pointer.removePointer();
      await rig.close(tester);
      expect(tester.binding.transientCallbackCount, 0);
    }
  });
}
