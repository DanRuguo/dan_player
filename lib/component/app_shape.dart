import 'package:flutter/material.dart';

/// Shared shape hierarchy in logical pixels on Windows 10 and Windows 11.
/// Core radii ([smallRadius], [controlRadius], [surfaceRadius]) remain stable
/// for existing surface/shader consumers, while Material 3 Expressive controls,
/// search bars, pills, and dialogs use [pillRadius] and [dialogRadius].
abstract final class AppShape {
  static const smallRadius = BorderRadius.all(Radius.circular(8));
  static const controlRadius = BorderRadius.all(Radius.circular(12));
  static const surfaceRadius = BorderRadius.all(Radius.circular(16));
  static const cardRadius = BorderRadius.all(Radius.circular(20));
  static const dialogRadius = BorderRadius.all(Radius.circular(24));
  static const pillRadius = BorderRadius.all(Radius.circular(999));

  static const control = RoundedRectangleBorder(borderRadius: controlRadius);
  static const surface = RoundedRectangleBorder(borderRadius: surfaceRadius);
  static const card = RoundedRectangleBorder(borderRadius: cardRadius);
  static const dialog = RoundedRectangleBorder(borderRadius: dialogRadius);
  static const pill = StadiumBorder();
  static const inputBorder = OutlineInputBorder(borderRadius: controlRadius);

  static OutlineInputBorder searchBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: pillRadius,
        borderSide: BorderSide(color: color, width: width),
      );

  /// Material 3 Expressive tonal capsule search bar decoration.
  static InputDecoration searchDecoration(
    BuildContext context, {
    required String hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    EdgeInsetsGeometry contentPadding =
        const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final restBorder =
        scheme.outlineVariant.withValues(alpha: isDark ? .38 : .46);
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      hoverColor:
          scheme.secondaryContainer.withValues(alpha: isDark ? .26 : .34),
      hintText: hintText,
      hintStyle: TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: .78),
        fontWeight: FontWeight.w400,
      ),
      prefixIcon:
          prefixIcon ?? Icon(Icons.search_rounded, size: 20, color: scheme.primary),
      suffixIcon: suffixIcon,
      contentPadding: contentPadding,
      border: searchBorder(restBorder),
      enabledBorder: searchBorder(restBorder),
      focusedBorder: searchBorder(scheme.primary, 1.8),
      disabledBorder:
          searchBorder(scheme.outlineVariant.withValues(alpha: .24)),
    );
  }
}
