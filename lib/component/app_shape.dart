import 'package:flutter/material.dart';

/// Shared shape hierarchy in logical pixels on Windows 10 and Windows 11.
/// Search capsules, navigation indicators, avatars and chart geometry remain
/// intentional semantic exceptions; ordinary actions must not default to pills.
abstract final class AppShape {
  static const smallRadius = BorderRadius.all(Radius.circular(8));
  static const controlRadius = BorderRadius.all(Radius.circular(12));
  static const surfaceRadius = BorderRadius.all(Radius.circular(16));

  static const control = RoundedRectangleBorder(borderRadius: controlRadius);
  static const surface = RoundedRectangleBorder(borderRadius: surfaceRadius);
  static const inputBorder = OutlineInputBorder(borderRadius: controlRadius);
}
