import 'package:flutter/foundation.dart';

/// Sources are explicit: desktop glass never uses the current album's pixels.
enum BackgroundSource {
  solid('不模糊'),
  desktop('窗后背景'),
  artwork('专辑封面'),
  customImage('自定义图片');

  const BackgroundSource(this.label);
  final String label;

  bool get usesImage =>
      this == BackgroundSource.artwork || this == BackgroundSource.customImage;
}

/// Only immutable, app-owned PNG names may be read from persisted settings.
/// Paths, URLs and arbitrary relative names are never accepted as asset IDs.
bool isBackgroundImageId(Object? value) =>
    value is String && RegExp(r'^[a-f0-9]{64}\.png$').hasMatch(value);

enum BackgroundScene {
  main('主窗口'),
  nowPlaying('歌词播放页'),
  mini('迷你播放器');

  const BackgroundScene(this.label);
  final String label;
}

@immutable
class BackgroundAppearance {
  const BackgroundAppearance({
    this.source = BackgroundSource.desktop,
    this.opacity = .70,
    this.blur = 48,
    this.customImageId,
    this.customImageName,
    this.motion = false,
  });

  final BackgroundSource source;

  /// The readability veil, not the opacity of the text/cover/whole window.
  final double opacity;

  /// Logical-pixel blur for artwork only. Windows owns its native blur radius.
  final double blur;

  /// An app-owned rendering copy, never the user's original absolute path.
  final String? customImageId;
  final String? customImageName;

  /// Optional image drift. Desktop glass and solid backgrounds ignore it.
  final bool motion;

  static const minOpacity = .25;
  static const maxOpacity = .95;
  static const minBlur = 8.0;
  static const maxBlur = 100.0;

  BackgroundAppearance copyWith({
    BackgroundSource? source,
    double? opacity,
    double? blur,
    String? customImageId,
    String? customImageName,
    bool clearCustomImage = false,
    bool? motion,
  }) =>
      BackgroundAppearance(
        source: source ?? this.source,
        opacity: _number(opacity, this.opacity, minOpacity, maxOpacity),
        blur: _number(blur, this.blur, minBlur, maxBlur),
        customImageId:
            clearCustomImage ? null : customImageId ?? this.customImageId,
        customImageName:
            clearCustomImage ? null : customImageName ?? this.customImageName,
        motion: motion ?? this.motion,
      );

  Map<String, Object> toMap() => {
        'source': source.name,
        'opacity': opacity,
        'blur': blur,
        'motion': motion,
        if (isBackgroundImageId(customImageId)) 'customImageId': customImageId!,
        if (customImageName != null && isBackgroundImageId(customImageId))
          'customImageName': customImageName!,
      };

  static BackgroundAppearance fromMap(
    Object? value, {
    required BackgroundAppearance fallback,
  }) {
    if (value is! Map) return fallback;
    final source = BackgroundSource.values
        .where((candidate) => candidate.name == value['source'])
        .firstOrNull;
    return fallback.copyWith(
      source: source,
      opacity:
          _number(value['opacity'], fallback.opacity, minOpacity, maxOpacity),
      blur: _number(value['blur'], fallback.blur, minBlur, maxBlur),
      customImageId: isBackgroundImageId(value['customImageId'])
          ? value['customImageId'] as String
          : null,
      customImageName: _imageName(value['customImageName']),
      clearCustomImage: !isBackgroundImageId(value['customImageId']),
      motion: value['motion'] is bool ? value['motion'] as bool : false,
    );
  }

  static String? _imageName(Object? value) {
    if (value is! String) return null;
    final name = value.trim().replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '');
    if (name.isEmpty) return null;
    // A display label, not a filesystem locator. Bound untrusted settings text.
    return name.length > 180 ? name.substring(0, 180) : name;
  }

  static double _number(
          Object? value, double fallback, double min, double max) =>
      value is num && value.isFinite
          ? value.toDouble().clamp(min, max)
          : fallback;

  @override
  bool operator ==(Object other) =>
      other is BackgroundAppearance &&
      source == other.source &&
      opacity == other.opacity &&
      blur == other.blur &&
      customImageId == other.customImageId &&
      customImageName == other.customImageName &&
      motion == other.motion;

  @override
  int get hashCode => Object.hash(
      source, opacity, blur, customImageId, customImageName, motion);
}

@immutable
class BackgroundPreferences {
  const BackgroundPreferences({
    this.main = const BackgroundAppearance(),
    this.nowPlaying = const BackgroundAppearance(
        source: BackgroundSource.artwork, opacity: .54, blur: 64),
    this.mini = const BackgroundAppearance(opacity: .78),
  });

  final BackgroundAppearance main;
  final BackgroundAppearance nowPlaying;
  final BackgroundAppearance mini;

  BackgroundAppearance forScene(BackgroundScene scene) => switch (scene) {
        BackgroundScene.main => main,
        BackgroundScene.nowPlaying => nowPlaying,
        BackgroundScene.mini => mini,
      };

  BackgroundPreferences withScene(
          BackgroundScene scene, BackgroundAppearance value) =>
      BackgroundPreferences(
        main: scene == BackgroundScene.main ? value : main,
        nowPlaying: scene == BackgroundScene.nowPlaying ? value : nowPlaying,
        mini: scene == BackgroundScene.mini ? value : mini,
      );

  // Keep a single stable native policy while navigating or resizing into mini.
  // Reapplying DWM at page/drag boundaries causes Win10 flashes and move lag.
  bool get needsNativeGlass => [main, nowPlaying, mini]
      .any((value) => value.source == BackgroundSource.desktop);

  /// Include inactive selections too: changing source must not lose the image
  /// a user expects to recover by selecting "custom image" again.
  Set<String> get retainedImageIds => {
        for (final value in [main, nowPlaying, mini])
          if (isBackgroundImageId(value.customImageId)) value.customImageId!,
      };

  Map<String, Object> toMap() => {
        for (final scene in BackgroundScene.values)
          scene.name: forScene(scene).toMap(),
      };

  factory BackgroundPreferences.fromMap(Object? value) {
    const defaults = BackgroundPreferences();
    if (value is! Map) return defaults;
    return BackgroundPreferences(
      main:
          BackgroundAppearance.fromMap(value['main'], fallback: defaults.main),
      nowPlaying: BackgroundAppearance.fromMap(value['nowPlaying'],
          fallback: defaults.nowPlaying),
      mini:
          BackgroundAppearance.fromMap(value['mini'], fallback: defaults.mini),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BackgroundPreferences &&
      main == other.main &&
      nowPlaying == other.nowPlaying &&
      mini == other.mini;

  @override
  int get hashCode => Object.hash(main, nowPlaying, mini);
}
