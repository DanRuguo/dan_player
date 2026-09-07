import 'package:flutter/material.dart';

abstract final class AppMotion {
  static const Duration quick = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 180);
  static const Duration emphasized = Duration(milliseconds: 240);
  static const Duration long = Duration(milliseconds: 300);

  // Smooth sampled positions without changing the playback or word clock.
  static const Duration followSample = Duration(milliseconds: 60);
  static const Duration lyricLine = Duration(milliseconds: 480);
  static const Duration lyricScroll = Duration(milliseconds: 600);
  static const Duration lyricSpring = Duration(milliseconds: 720);

  static const Curve standardCurve = Curves.easeOutCubic;
  static const Curve emphasizedCurve = Cubic(0.2, 0.0, 0.0, 1.0);
}
