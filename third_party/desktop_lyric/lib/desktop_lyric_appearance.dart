/// Shared, immutable preferences. Only the player writes these to disk.
class DesktopLyricAppearance {
  static const defaults = DesktopLyricAppearance._(
      22, 18, null, 0, 1, false, false, 8, 56, 14, false, 0, true);

  const DesktopLyricAppearance._(
      this.lyricFontSize,
      this.translationFontSize,
      this.customColor,
      this.backgroundOpacity,
      this.textOpacity,
      this.strokeEnabled,
      this.taskbarMode,
      this.taskbarGap,
      this.taskbarHeight,
      this.taskbarMinimumFontSize,
      this.taskbarTranslation,
      this.lyricLetterSpacing,
      this.showJapaneseReading);

  final double lyricFontSize;
  final double translationFontSize;
  final int? customColor;
  final double backgroundOpacity;
  final double textOpacity;
  final bool strokeEnabled;

  /// A normal topmost window above the work-area bottom, never Explorer-owned.
  final bool taskbarMode;
  final double taskbarGap;
  final double taskbarHeight;
  final double taskbarMinimumFontSize;
  final bool taskbarTranslation;

  /// Additional logical pixels between lyric clusters on every lyric surface.
  /// Zero preserves each surface's existing natural typography.
  final double lyricLetterSpacing;

  /// Visibility only: hiding generated readings preserves their source/cache.
  final bool showJapaneseReading;

  static bool _number(Object? value, double min, double max) =>
      value is num && value.isFinite && value >= min && value <= max;
  static bool _color(Object? value) =>
      value == null || (value is int && value >= 0 && value <= 0xffffffff);

  /// Invalid fields in old/user-edited settings fall back independently.
  factory DesktopLyricAppearance.fromJson(Object? raw) {
    if (raw is! Map) return defaults;
    double number(String key, double min, double max, double fallback) =>
        _number(raw[key], min, max) ? (raw[key] as num).toDouble() : fallback;
    return DesktopLyricAppearance._(
      number('lyricFontSize', 18, 64, defaults.lyricFontSize),
      number('translationFontSize', 14, 60, defaults.translationFontSize),
      _color(raw['customColor']) ? raw['customColor'] as int? : null,
      number('backgroundOpacity', 0, 1, defaults.backgroundOpacity),
      number('textOpacity', .2, 1, defaults.textOpacity),
      raw['strokeEnabled'] is bool ? raw['strokeEnabled'] as bool : false,
      raw['taskbarMode'] is bool ? raw['taskbarMode'] as bool : false,
      number('taskbarGap', 0, 48, defaults.taskbarGap),
      number('taskbarHeight', 48, 96, defaults.taskbarHeight),
      number('taskbarMinimumFontSize', 12, 24, defaults.taskbarMinimumFontSize),
      raw['taskbarTranslation'] is bool
          ? raw['taskbarTranslation'] as bool
          : false,
      number('lyricLetterSpacing', 0, 12, defaults.lyricLetterSpacing),
      raw['showJapaneseReading'] is bool
          ? raw['showJapaneseReading'] as bool
          : defaults.showJapaneseReading,
    );
  }

  /// Pipe updates must be a complete valid snapshot; never reset a good value
  /// in response to malformed, non-finite or out-of-range input.
  static DesktopLyricAppearance? tryFromJson(Object? raw) {
    if (raw is! Map ||
        !_number(raw['lyricFontSize'], 18, 64) ||
        !_number(raw['translationFontSize'], 14, 60) ||
        !raw.containsKey('customColor') ||
        !_color(raw['customColor']) ||
        !_number(raw['backgroundOpacity'], 0, 1) ||
        !_number(raw['textOpacity'], .2, 1) ||
        raw['strokeEnabled'] is! bool ||
        (raw.containsKey('taskbarMode') && raw['taskbarMode'] is! bool) ||
        (raw.containsKey('taskbarGap') && !_number(raw['taskbarGap'], 0, 48)) ||
        (raw.containsKey('taskbarHeight') &&
            !_number(raw['taskbarHeight'], 48, 96)) ||
        (raw.containsKey('taskbarMinimumFontSize') &&
            !_number(raw['taskbarMinimumFontSize'], 12, 24)) ||
        (raw.containsKey('taskbarTranslation') &&
            raw['taskbarTranslation'] is! bool) ||
        (raw.containsKey('lyricLetterSpacing') &&
            !_number(raw['lyricLetterSpacing'], 0, 12)) ||
        (raw.containsKey('showJapaneseReading') &&
            raw['showJapaneseReading'] is! bool)) {
      return null;
    }
    return DesktopLyricAppearance.fromJson(raw);
  }

  DesktopLyricAppearance copyWith(
      {double? lyricFontSize,
      double? translationFontSize,
      int? customColor,
      bool followTheme = false,
      double? backgroundOpacity,
      double? textOpacity,
      bool? strokeEnabled,
      bool? taskbarMode,
      double? taskbarGap,
      double? taskbarHeight,
      double? taskbarMinimumFontSize,
      bool? taskbarTranslation,
      double? lyricLetterSpacing,
      bool? showJapaneseReading}) {
    final map = {
      'lyricFontSize': lyricFontSize ?? this.lyricFontSize,
      'translationFontSize': translationFontSize ?? this.translationFontSize,
      'customColor': followTheme ? null : customColor ?? this.customColor,
      'backgroundOpacity': backgroundOpacity ?? this.backgroundOpacity,
      'textOpacity': textOpacity ?? this.textOpacity,
      'strokeEnabled': strokeEnabled ?? this.strokeEnabled,
      'taskbarMode': taskbarMode ?? this.taskbarMode,
      'taskbarGap': taskbarGap ?? this.taskbarGap,
      'taskbarHeight': taskbarHeight ?? this.taskbarHeight,
      'taskbarMinimumFontSize':
          taskbarMinimumFontSize ?? this.taskbarMinimumFontSize,
      'taskbarTranslation': taskbarTranslation ?? this.taskbarTranslation,
      'lyricLetterSpacing': lyricLetterSpacing ?? this.lyricLetterSpacing,
      'showJapaneseReading': showJapaneseReading ?? this.showJapaneseReading,
    };
    return tryFromJson(map) ??
        (throw ArgumentError('Invalid lyric appearance'));
  }

  Map<String, dynamic> toJson() => {
        'lyricFontSize': lyricFontSize,
        'translationFontSize': translationFontSize,
        'customColor': customColor,
        'backgroundOpacity': backgroundOpacity,
        'textOpacity': textOpacity,
        'strokeEnabled': strokeEnabled,
        'taskbarMode': taskbarMode,
        'taskbarGap': taskbarGap,
        'taskbarHeight': taskbarHeight,
        'taskbarMinimumFontSize': taskbarMinimumFontSize,
        'taskbarTranslation': taskbarTranslation,
        'lyricLetterSpacing': lyricLetterSpacing,
        'showJapaneseReading': showJapaneseReading,
      };

  @override
  bool operator ==(Object other) =>
      other is DesktopLyricAppearance &&
      lyricFontSize == other.lyricFontSize &&
      translationFontSize == other.translationFontSize &&
      customColor == other.customColor &&
      backgroundOpacity == other.backgroundOpacity &&
      textOpacity == other.textOpacity &&
      strokeEnabled == other.strokeEnabled &&
      taskbarMode == other.taskbarMode &&
      taskbarGap == other.taskbarGap &&
      taskbarHeight == other.taskbarHeight &&
      taskbarMinimumFontSize == other.taskbarMinimumFontSize &&
      taskbarTranslation == other.taskbarTranslation &&
      lyricLetterSpacing == other.lyricLetterSpacing &&
      showJapaneseReading == other.showJapaneseReading;
  @override
  int get hashCode => Object.hash(
      lyricFontSize,
      translationFontSize,
      customColor,
      backgroundOpacity,
      textOpacity,
      strokeEnabled,
      taskbarMode,
      taskbarGap,
      taskbarHeight,
      taskbarMinimumFontSize,
      taskbarTranslation,
      lyricLetterSpacing,
      showJapaneseReading);
}
