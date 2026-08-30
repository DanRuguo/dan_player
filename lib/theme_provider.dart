import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/library/artwork_image_provider.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeProvider._({
    required Color seedColor,
    required this.themeMode,
    required bool Function() dynamicThemeEnabled,
    Future<ImageProvider?> Function(Audio)? loadArtwork,
    Future<ColorScheme> Function(ImageProvider, Brightness)? extractScheme,
    bool connectPlayback = true,
  })  : _defaultSeed = seedColor,
        _readDynamicTheme = dynamicThemeEnabled,
        _dynamicThemeEnabled = dynamicThemeEnabled(),
        _loadArtwork = loadArtwork ?? ((audio) => audio.mediumCover),
        _extractScheme = extractScheme ?? _schemeFromImage,
        _connectPlayback = connectPlayback,
        lightScheme = ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
        darkScheme = ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        );

  /// Keeps artwork race/failure tests independent of native playback and IO.
  @visibleForTesting
  ThemeProvider.forTesting({
    required Color seedColor,
    ThemeMode themeMode = ThemeMode.light,
    required bool Function() dynamicThemeEnabled,
    required Future<ImageProvider?> Function(Audio) loadArtwork,
    required Future<ColorScheme> Function(ImageProvider, Brightness)
        extractScheme,
  }) : this._(
          seedColor: seedColor,
          themeMode: themeMode,
          dynamicThemeEnabled: dynamicThemeEnabled,
          loadArtwork: loadArtwork,
          extractScheme: extractScheme,
          connectPlayback: false,
        );

  ColorScheme lightScheme;
  ColorScheme darkScheme;

  Color _defaultSeed;
  final bool Function() _readDynamicTheme;
  final Future<ImageProvider?> Function(Audio) _loadArtwork;
  final Future<ColorScheme> Function(ImageProvider, Brightness) _extractScheme;
  final bool _connectPlayback;
  bool _dynamicThemeEnabled;
  bool _followingPlayback = false;
  bool _disposed = false;
  int _artworkRequest = 0;
  Audio? _latestAudio;
  (String, int, String?, int?)? _artworkIdentity;
  Future<void>? _artworkTask;
  ImageProvider? _backdropImage;

  ImageProvider? get backdropImage => _backdropImage;

  String fontFamily = danEmbeddedFontFamily;

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

  static Future<ColorScheme> _schemeFromImage(
    ImageProvider image,
    Brightness brightness,
  ) =>
      ColorScheme.fromImageProvider(provider: image, brightness: brightness);

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
    this.themeMode = themeMode;
    _publishTheme(includeMode: true);
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
    return _artworkTask = _loadArtworkTheme(audio, request);
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

  Future<void> _loadArtworkTheme(Audio audio, int request) async {
    try {
      final image = await _loadArtwork(audio).timeout(
        const Duration(seconds: 10),
      );
      if (!_isCurrentArtwork(request)) return;
      if (image == null) {
        _useDefaultTheme();
        _publishTheme();
        return;
      }

      // Bound decoding for remote artwork as well as high-DPI local covers.
      // The same cached provider supplies both palettes and the backdrop.
      // Unwrap foreground sizing: ResizeImage owns this smaller contain sample
      // and cannot compose with another provider's getTargetSize callback.
      final sample = ResizeImage(
        image is ArtworkImageProvider ? image.source : image,
        width: 320,
        height: 320,
        policy: ResizeImagePolicy.fit,
      );
      final schemes = await Future.wait([
        _extractScheme(sample, Brightness.light),
        _extractScheme(sample, Brightness.dark),
      ]).timeout(const Duration(seconds: 10));
      if (!_isCurrentArtwork(request)) return;

      // Publish the artwork and both modes atomically. Rapid skips cannot pair
      // an old cover with a new palette, even when extraction completes late.
      _backdropImage = sample;
      lightScheme = schemes[0];
      darkScheme = schemes[1];
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
    _invalidateArtwork();
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
