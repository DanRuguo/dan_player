/// Pure window-geometry persistence policy.
///
/// This file intentionally has no Flutter or platform-plugin dependency so
/// startup, settings and tests can share the same validation and migration
/// rules without touching a native window.
abstract final class WindowGeometryPolicy {
  static const String schemaKey = 'WindowGeometrySchema';
  static const String sizeKey = 'WindowSize';
  static const String maximizedKey = 'IsWindowMaximized';

  static const int currentSchemaVersion = 1;

  static const WindowGeometrySize defaultSize = WindowGeometrySize(1280, 756);
  static const double normalMinimumWidth = 507;
  static const double normalMinimumHeight = 320;
  static const WindowGeometrySize normalMinimumSize = WindowGeometrySize(
    normalMinimumWidth,
    normalMinimumHeight,
  );

  /// A logical size read back from an integer native-pixel rectangle can be a
  /// fraction below its requested value at non-integer DPI scales. For
  /// example, 507 logical pixels can round-trip as 506.4 at 125% scaling.
  static const double dpiRoundingTolerance = 1.0;

  /// Restores geometry from the settings object and upgrades its persistence
  /// schema. Invalid or non-positive values use [defaultSize]; otherwise each
  /// dimension is independently constrained to [normalMinimumSize].
  ///
  /// Schema 0 (including the absence of a schema key) had a known failure mode:
  /// a maximized window could persist the square 507 x 507 minimum as its
  /// restored size. Only that old, maximized and tolerance-matched shape is
  /// migrated to [defaultSize]. A valid 507 x 507 value written by this or a
  /// newer schema is preserved.
  static WindowGeometryDecision restore(Object? settings) {
    final map = settings is Map ? settings : const <Object?, Object?>{};
    final rawSchema = map[schemaKey];
    final sourceSchema = _readSchema(rawSchema);
    final isLegacySchema = rawSchema == null ||
        (sourceSchema != null && sourceSchema < currentSchemaVersion);
    final isMaximized = _readMaximized(map[maximizedKey]);
    final parsed = tryParseSize(map[sizeKey]);

    final migratedLegacyMinimumSquare = isLegacySchema &&
        isMaximized &&
        parsed != null &&
        _approximately(parsed.width, 507) &&
        _approximately(parsed.height, 507);

    final size = migratedLegacyMinimumSquare
        ? defaultSize
        : constrain(parsed ?? defaultSize);
    final encoded = encodeSize(size);
    final sourceWasCanonical = parsed != null && map[sizeKey] == encoded;
    final sourceSchemaIsCurrent = sourceSchema == currentSchemaVersion;

    return WindowGeometryDecision(
      size: size,
      isMaximized: isMaximized,
      migratedLegacyMinimumSquare: migratedLegacyMinimumSquare,
      needsRewrite: !sourceSchemaIsCurrent ||
          !sourceWasCanonical ||
          migratedLegacyMinimumSquare,
    );
  }

  /// Parses the historical `width,height` representation without throwing.
  /// Both values must be finite and strictly positive.
  static WindowGeometrySize? tryParseSize(Object? value) {
    if (value is! String) return null;
    final parts = value.split(',');
    if (parts.length != 2) return null;
    final width = double.tryParse(parts[0].trim());
    final height = double.tryParse(parts[1].trim());
    if (width == null ||
        height == null ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0) {
      return null;
    }
    return WindowGeometrySize(width, height);
  }

  /// Applies the normal-window minimum independently to width and height.
  /// Invalid programmatic values use [defaultSize].
  static WindowGeometrySize constrain(WindowGeometrySize size) {
    if (!size.isFiniteAndPositive) return defaultSize;
    return WindowGeometrySize(
      size.width < normalMinimumSize.width
          ? normalMinimumSize.width
          : size.width,
      size.height < normalMinimumSize.height
          ? normalMinimumSize.height
          : size.height,
    );
  }

  /// Returns the canonical settings representation after validation.
  static String encodeSize(WindowGeometrySize size) {
    final safe = constrain(size);
    return '${safe.width.toStringAsFixed(1)},'
        '${safe.height.toStringAsFixed(1)}';
  }

  /// Creates the three fields owned by the geometry policy.
  static Map<String, Object> encode({
    required WindowGeometrySize size,
    required bool isMaximized,
  }) =>
      <String, Object>{
        schemaKey: currentSchemaVersion,
        sizeKey: encodeSize(size),
        maximizedKey: isMaximized,
      };

  static int? _readSchema(Object? value) {
    if (value is int && value >= 0) return value;
    if (value is num && value.isFinite && value >= 0 && value % 1 == 0) {
      return value.toInt();
    }
    return null;
  }

  static bool _readMaximized(Object? value) =>
      value == true || (value is num && value == 1);

  static bool _approximately(double value, double expected) =>
      (value - expected).abs() <= dpiRoundingTolerance;
}

class WindowGeometrySize {
  const WindowGeometrySize(this.width, this.height);

  final double width;
  final double height;

  bool get isFiniteAndPositive =>
      width.isFinite && height.isFinite && width > 0 && height > 0;

  @override
  bool operator ==(Object other) =>
      other is WindowGeometrySize &&
      width == other.width &&
      height == other.height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'WindowGeometrySize($width, $height)';
}

class WindowGeometryDecision {
  const WindowGeometryDecision({
    required this.size,
    required this.isMaximized,
    required this.migratedLegacyMinimumSquare,
    required this.needsRewrite,
  });

  final WindowGeometrySize size;
  final bool isMaximized;

  /// True only for the old maximized 507 x 507 persistence bug.
  final bool migratedLegacyMinimumSquare;

  /// Whether settings should be rewritten in the current canonical schema.
  final bool needsRewrite;
}
