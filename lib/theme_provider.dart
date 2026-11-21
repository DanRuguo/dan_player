import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:dan_player/font/app_font_manager.dart';
import 'package:desktop_lyric/font_policy.dart';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/library/artwork_image_provider.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

Future<int> _quantizeAbgrSeed(Uint32List abgrPixels) async {
  final result = await QuantizerCelebi().quantize(abgrPixels, 128);
  final argbToCount = <int, int>{};
  result.colorToCount.forEach((abgr, count) {
    final argb = (abgr & 0xFF00FF00) |
        ((abgr & 0x00FF0000) >> 16) |
        ((abgr & 0x000000FF) << 16);
    argbToCount[argb] = count;
  });
  final scored = Score.score(argbToCount, desired: 1);
  return scored.first;
}

Future<int> _quantizeAbgrSeedInIsolate(Uint32List abgrPixels) =>
    Isolate.run(() => _quantizeAbgrSeed(abgrPixels));

/// Extracts a single Material 3 seed color from [provider] with one bounded
/// `<= 112px` readback and off-main-thread Celebi quantization, matching
/// [ColorScheme.fromImageProvider] without running quantization twice or
/// blocking the UI thread during track-switch animations.
@visibleForTesting
Future<Color> extractDynamicSeedColorFromImage(
  ImageProvider provider, {
  bool useIsolate = true,
}) async {
  const maxDimension = 112.0;
  final stream = provider.resolve(
    const ImageConfiguration(size: Size(maxDimension, maxDimension)),
  );
  final completer = Completer<ImageInfo>();
  late ImageStreamListener listener;
  Timer? timeout;

  listener = ImageStreamListener(
    (ImageInfo info, bool sync) {
      timeout?.cancel();
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.complete(info);
    },
    onError: (Object error, StackTrace? stack) {
      timeout?.cancel();
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.completeError(error, stack);
    },
  );
  timeout = Timer(const Duration(seconds: 5), () {
    stream.removeListener(listener);
    if (!completer.isCompleted) {
      completer.completeError(
        TimeoutException('Timeout occurred trying to load image'),
      );
    }
  });
  stream.addListener(listener);

  final info = await completer.future;
  ui.Image? scaledImage;
  try {
    final source = info.image;
    final width = source.width;
    final height = source.height;
    ui.Image sample;
    if (width > maxDimension || height > maxDimension) {
      final paintWidth =
          (width > height) ? maxDimension : (maxDimension / height) * width;
      final paintHeight =
          (height > width) ? maxDimension : (maxDimension / width) * height;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      paintImage(
        canvas: canvas,
        rect: Rect.fromLTRB(0, 0, paintWidth, paintHeight),
        image: source,
        filterQuality: FilterQuality.none,
      );
      final picture = recorder.endRecording();
      try {
        scaledImage = await picture.toImage(
          paintWidth.toInt().clamp(1, 112),
          paintHeight.toInt().clamp(1, 112),
        );
      } finally {
        picture.dispose();
      }
      sample = scaledImage;
    } else {
      sample = source;
    }

    final byteData = await sample.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null || byteData.lengthInBytes < 4) {
      throw StateError('Failed to read image pixel bytes for dynamic theme.');
    }
    final pixels = Uint32List.fromList(
      byteData.buffer.asUint32List(
        byteData.offsetInBytes,
        byteData.lengthInBytes ~/ 4,
      ),
    );
    final seedArgb = useIsolate
        ? await _quantizeAbgrSeedInIsolate(pixels)
        : await _quantizeAbgrSeed(pixels);
    return Color(seedArgb);
  } finally {
    scaledImage?.dispose();
    info.dispose();
  }
}

class ThemeProvider extends ChangeNotifier with WidgetsBindingObserver {
  ThemeProvider._({
    required Color seedColor,
    required this.themeMode,
    required bool Function() dynamicThemeEnabled,
    Future<ImageProvider?> Function(Audio)? loadArtwork,
    Future<ColorScheme> Function(ImageProvider, Brightness)? extractScheme,
    Future<Color> Function(ImageProvider)? extractSeed,
    bool connectPlayback = true,
  })  : _defaultSeed = seedColor,
        _readDynamicTheme = dynamicThemeEnabled,
        _dynamicThemeEnabled = dynamicThemeEnabled(),
        _loadArtwork = loadArtwork ?? ((audio) => audio.mediumCover),
        _extractScheme = extractScheme,
        _extractSeed = extractSeed ?? extractDynamicSeedColorFromImage,
        _connectPlayback = connectPlayback,
        lightScheme = ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
        darkScheme = ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ) {
    _platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    WidgetsBinding.instance.addObserver(this);
    if (_connectPlayback) {
      fontFamily = AppFontManager.instance.policy.value.uiFamily;
      AppFontManager.instance.policy.addListener(_fontChanged);
    }
  }

  /// Keeps artwork race/failure tests independent of native playback and IO.
  @visibleForTesting
  ThemeProvider.forTesting({
    required Color seedColor,
    ThemeMode themeMode = ThemeMode.light,
    required bool Function() dynamicThemeEnabled,
    required Future<ImageProvider?> Function(Audio) loadArtwork,
    Future<ColorScheme> Function(ImageProvider, Brightness)? extractScheme,
    Future<Color> Function(ImageProvider)? extractSeed,
  }) : this._(
          seedColor: seedColor,
          themeMode: themeMode,
          dynamicThemeEnabled: dynamicThemeEnabled,
          loadArtwork: loadArtwork,
          extractScheme: extractScheme,
          extractSeed: extractSeed,
          connectPlayback: false,
        );

  static const int _maxCachedSeeds = 32;

  ColorScheme lightScheme;
  ColorScheme darkScheme;

  Color _defaultSeed;
  final bool Function() _readDynamicTheme;
  final Future<ImageProvider?> Function(Audio) _loadArtwork;
  final Future<ColorScheme> Function(ImageProvider, Brightness)? _extractScheme;
  final Future<Color> Function(ImageProvider) _extractSeed;
  final bool _connectPlayback;
  bool _dynamicThemeEnabled;
  bool _followingPlayback = false;
  bool _disposed = false;
  int _artworkRequest = 0;
  Audio? _latestAudio;
  (String, int, String?, int?)? _artworkIdentity;
  Future<void>? _artworkTask;
  ImageProvider? _backdropImage;
  late Brightness _platformBrightness;
  final LinkedHashMap<(String, int, String?, int?), Color> _seedCache =
      LinkedHashMap();

  @visibleForTesting
  int get seedCacheLength => _seedCache.length;

  void _rememberSeed((String, int, String?, int?) identity, Color seed) {
    _seedCache.remove(identity);
    _seedCache[identity] = seed;
    while (_seedCache.length > _maxCachedSeeds) {
      _seedCache.remove(_seedCache.keys.first);
    }
  }

  Color? _lookupSeed((String, int, String?, int?) identity) {
    final hit = _seedCache.remove(identity);
    if (hit != null) {
      _seedCache[identity] = hit;
    }
    return hit;
  }

  ImageProvider? get backdropImage => _backdropImage;

  String fontFamily = danEmbeddedFontFamily;
  AppFontPolicy get fontPolicy => AppFontManager.instance.policy.value;
  void _fontChanged() {
    fontFamily = fontPolicy.uiFamily;
    _publishTheme();
  }

  ColorScheme get currScheme {
    final isDark = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    return isDark ? darkScheme : lightScheme;
  }

  ThemeMode themeMode;

  static ThemeProvider? _instance;

  static ThemeProvider get instance {
    _instance ??= ThemeProvider._(
      seedColor: Color(AppSettings.instance.defaultTheme),
      themeMode: AppSettings.instance.themeMode,
      dynamicThemeEnabled: () => AppSettings.instance.dynamicTheme,
    );
    return _instance!;
  }

  void applyTheme({required Color seedColor}) {
    if (_disposed) return;
    ++_artworkRequest;
    _artworkTask = null;
    _defaultSeed = seedColor;
    _useDefaultTheme();
    _publishTheme();
  }

  void _useDefaultTheme() {
    _backdropImage = null;
    lightScheme = ColorScheme.fromSeed(
      seedColor: _defaultSeed,
      brightness: Brightness.light,
    );
    darkScheme = ColorScheme.fromSeed(
      seedColor: _defaultSeed,
      brightness: Brightness.dark,
    );
  }

  void _publishTheme({bool includeMode = false}) {
    if (_disposed) return;
    notifyListeners();
    if (_connectPlayback && PlayService.isInitialized) {
      unawaited(_sendDesktopTheme(includeMode: includeMode));
    }
  }

  Future<void> _sendDesktopTheme({required bool includeMode}) async {
    try {
      final desktop = PlayService.instance.desktopLyricService;
      if (!await desktop.canSendMessage || _disposed) return;
      // Read the latest state after the await, never an obsolete palette.
      desktop.sendThemeMessage(currScheme);
      if (includeMode) {
        desktop.sendThemeModeMessage(currScheme.brightness == Brightness.dark);
      }
    } catch (_) {
      // Closing/restarting the optional lyric window must not break the theme.
    }
  }

  void applyThemeMode(ThemeMode themeMode) {
    if (_disposed) return;
    if (this.themeMode == themeMode) return;
    this.themeMode = themeMode;
    _publishTheme(includeMode: true);
  }

  @override
  void didChangePlatformBrightness() {
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    if (_disposed || brightness == _platformBrightness) return;
    _platformBrightness = brightness;
    if (themeMode == ThemeMode.system) {
      // MaterialApp follows the OS itself; notify non-widget consumers too
      // (tray, Peek and the desktop lyric process) using the same palette.
      _publishTheme(includeMode: true);
    }
  }

  /// Called after the settings switch changes its stored value. Disabling is
  /// immediate; enabling reuses the current track without waiting for a skip.
  void syncDynamicThemeSetting() {
    if (_disposed || !_updateDynamicSetting()) return;
    final audio = _latestAudio;
    if (_dynamicThemeEnabled && audio != null) {
      unawaited(applyThemeFromAudio(audio));
    }
  }

  bool _updateDynamicSetting() {
    final enabled = _readDynamicTheme();
    if (enabled == _dynamicThemeEnabled) return false;
    _dynamicThemeEnabled = enabled;
    _invalidateArtwork();
    _useDefaultTheme();
    _publishTheme();
    return true;
  }

  void _invalidateArtwork() {
    ++_artworkRequest;
    _artworkIdentity = null;
    _artworkTask = null;
  }

  /// The snapshot includes revision fields because metadata editing mutates
  /// Audio in place. Playback notifications alone never trigger image IO.
  Future<void> applyThemeFromAudio(Audio audio) {
    if (_disposed) return Future.value();
    _latestAudio = audio;
    _followPlayback();
    _updateDynamicSetting();
    if (!_dynamicThemeEnabled) return Future.value();

    final identity =
        (audio.path, audio.modified, audio.artworkUrl, audio.fileSizeBytes);
    if (_artworkIdentity == identity) {
      return _artworkTask ?? Future.value();
    }
    _artworkIdentity = identity;
    final request = ++_artworkRequest;
    return _artworkTask = _loadArtworkTheme(audio, identity, request);
  }

  void _followPlayback() {
    if (!_connectPlayback || _followingPlayback) return;
    PlayService.instance.playbackService.addListener(_onPlaybackChanged);
    _followingPlayback = true;
  }

  void _onPlaybackChanged() {
    final audio = PlayService.instance.playbackService.nowPlaying;
    if (audio != null) {
      unawaited(applyThemeFromAudio(audio));
    } else if (_latestAudio != null) {
      _latestAudio = null;
      _invalidateArtwork();
      _useDefaultTheme();
      _publishTheme();
    }
  }

  bool _isCurrentArtwork(int request) =>
      !_disposed &&
      request == _artworkRequest &&
      _dynamicThemeEnabled &&
      _readDynamicTheme();

  Future<void> _loadArtworkTheme(
    Audio audio,
    (String, int, String?, int?) identity,
    int request,
  ) async {
    try {
      final image = await _loadArtwork(audio).timeout(
        const Duration(seconds: 10),
      );
      if (!_isCurrentArtwork(request)) return;
      if (image == null) {
        _seedCache.remove(identity);
        _useDefaultTheme();
        _publishTheme();
        return;
      }

      // Bound decoding for remote artwork as well as high-DPI local covers.
      // The same cached provider supplies both palettes and the backdrop.
      // Unwrap foreground sizing: ResizeImage owns this smaller contain sample
      // and cannot compose with another provider's getTargetSize callback.
      final source = image is ArtworkImageProvider ? image.source : image;
      final sample = ResizeImage(
        source,
        width: 320,
        height: 320,
        policy: ResizeImagePolicy.fit,
      );

      final ColorScheme nextLight;
      final ColorScheme nextDark;
      final customExtractor = _extractScheme;
      if (customExtractor != null) {
        final schemes = await Future.wait([
          customExtractor(sample, Brightness.light),
          customExtractor(sample, Brightness.dark),
        ]).timeout(const Duration(seconds: 10));
        if (!_isCurrentArtwork(request)) return;
        nextLight = schemes[0];
        nextDark = schemes[1];
      } else {
        var seed = _lookupSeed(identity);
        if (seed == null) {
          final seedSample = ResizeImage(
            source,
            width: 112,
            height: 112,
            policy: ResizeImagePolicy.fit,
          );
          seed = await _extractSeed(seedSample)
              .timeout(const Duration(seconds: 10));
          if (!_isCurrentArtwork(request)) return;
          _rememberSeed(identity, seed);
        }
        nextLight = ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        );
        nextDark = ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        );
      }

      // Publish the artwork and both modes atomically. Rapid skips cannot pair
      // an old cover with a new palette, even when extraction completes late.
      _backdropImage = sample;
      lightScheme = nextLight;
      darkScheme = nextDark;
      _publishTheme();
    } catch (error) {
      if (!_isCurrentArtwork(request)) return;
      debugPrint('Artwork theme unavailable (${error.runtimeType}).');
      _useDefaultTheme();
      _publishTheme();
    }
  }

  void changeFontFamily(String? fontFamily) {
    if (_disposed) return;
    this.fontFamily = fontFamily ?? danEmbeddedFontFamily;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_connectPlayback) {
      AppFontManager.instance.policy.removeListener(_fontChanged);
    }
    WidgetsBinding.instance.removeObserver(this);
    _invalidateArtwork();
    _seedCache.clear();
    if (_followingPlayback) {
      PlayService.instance.playbackService.removeListener(_onPlaybackChanged);
      _followingPlayback = false;
    }
    super.dispose();
  }

  // ButtonStyle get primaryButtonStyle => ButtonStyle(
  //       backgroundColor: WidgetStatePropertyAll(scheme.primary),
  //       foregroundColor: WidgetStatePropertyAll(scheme.onPrimary),
  //       fixedSize: const WidgetStatePropertyAll(Size.fromHeight(40.0)),
  //       overlayColor:
  //           WidgetStatePropertyAll(scheme.onPrimary.withOpacity(0.08)),
  //     );

  // ButtonStyle get secondaryButtonStyle => ButtonStyle(
  //       backgroundColor: WidgetStatePropertyAll(scheme.secondaryContainer),
  //       foregroundColor: WidgetStatePropertyAll(scheme.onSecondaryContainer),
  //       fixedSize: const WidgetStatePropertyAll(Size.fromHeight(40.0)),
  //       overlayColor: WidgetStatePropertyAll(
  //           scheme.onSecondaryContainer.withOpacity(0.08)),
  //     );

  // ButtonStyle get primaryIconButtonStyle => ButtonStyle(
  //       backgroundColor: WidgetStatePropertyAll(scheme.primary),
  //       foregroundColor: WidgetStatePropertyAll(scheme.onPrimary),
  //       overlayColor: WidgetStatePropertyAll(
  //         scheme.onPrimary.withOpacity(0.08),
  //       ),
  //     );

  // ButtonStyle get secondaryIconButtonStyle => ButtonStyle(
  //       backgroundColor: WidgetStatePropertyAll(scheme.secondaryContainer),
  //       foregroundColor: WidgetStatePropertyAll(scheme.onSecondaryContainer),
  //       overlayColor: WidgetStatePropertyAll(
  //         scheme.onSecondaryContainer.withOpacity(0.08),
  //       ),
  //     );

  // ButtonStyle get menuItemStyle => ButtonStyle(
  //       backgroundColor: WidgetStatePropertyAll(scheme.secondaryContainer),
  //       foregroundColor: WidgetStatePropertyAll(scheme.onSecondaryContainer),
  //       padding: const WidgetStatePropertyAll(
  //         EdgeInsets.symmetric(horizontal: 16.0),
  //       ),
  //       overlayColor: WidgetStatePropertyAll(
  //         scheme.onSecondaryContainer.withOpacity(0.08),
  //       ),
  //     );

  // MenuStyle get menuStyleWithFixedSize => MenuStyle(
  //       backgroundColor: WidgetStatePropertyAll(scheme.secondaryContainer),
  //       surfaceTintColor: WidgetStatePropertyAll(scheme.secondaryContainer),
  //       shape: WidgetStatePropertyAll(RoundedRectangleBorder(
  //         borderRadius: BorderRadius.circular(20.0),
  //       )),
  //       fixedSize: const WidgetStatePropertyAll(Size.fromWidth(149.0)),
  //     );

  // MenuStyle get menuStyle => MenuStyle(
  //       shape: WidgetStatePropertyAll(
  //         RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  //       ),
  //       backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
  //       surfaceTintColor: WidgetStatePropertyAll(scheme.surfaceContainer),
  //     );

  // InputDecoration inputDecoration(String labelText) => InputDecoration(
  //       enabledBorder: OutlineInputBorder(
  //         borderSide: BorderSide(color: scheme.outline, width: 2),
  //       ),
  //       focusedBorder: OutlineInputBorder(
  //         borderSide: BorderSide(color: scheme.primary, width: 2),
  //       ),
  //       labelText: labelText,
  //       labelStyle: TextStyle(color: scheme.onSurfaceVariant),
  //       floatingLabelStyle: TextStyle(color: scheme.primary),
  //       focusColor: scheme.primary,
  //     );
}
