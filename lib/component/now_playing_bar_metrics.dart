import 'dart:math' as math;

import 'package:flutter/material.dart';

abstract final class NowPlayingBarMetrics {
  static double height(BuildContext context) =>
      math.max(72, MediaQuery.textScalerOf(context).scale(28) * 1.35 + 24);

  static double bottomInset(BuildContext context) =>
      MediaQuery.sizeOf(context).width <= 640 ? 8 : 32;

  static double reservedSpace(BuildContext context) =>
      height(context) + bottomInset(context) + 8;
}
