import 'dart:async';

import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:flutter/painting.dart';

class FakeDesktopLyricWindow implements DesktopLyricWindowAdapter {
  Rect bounds = const Rect.fromLTWH(400, 500, 800, 160);
  Rect area = const Rect.fromLTWH(0, 0, 1920, 1040);
  Size minimum = Size.zero;
  @override
  double pixelRatio = 1;
  final operations = <Object>[];
  Object? failNextBounds;
  Completer<void>? blockNextRead;

  @override
  Future<Rect> getBounds() async {
    final gate = blockNextRead;
    blockNextRead = null;
    if (gate != null) await gate.future;
    return bounds;
  }

  @override
  Future<Rect> workAreaFor(Rect bounds) async => area;

  @override
  Future<void> setBounds(Rect value) async {
    operations.add(('bounds', value));
    final error = failNextBounds;
    failNextBounds = null;
    if (error != null) throw error;
    if (value.width < minimum.width || value.height < minimum.height) {
      throw StateError('Old orientation minimum was not cleared');
    }
    bounds = value;
  }

  @override
  Future<void> setMinimumSize(Size size) async {
    operations.add(('minimum', size));
    minimum = size;
  }
}
