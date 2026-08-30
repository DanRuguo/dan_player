import 'dart:async';

import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/desktop_lyric_test_support.dart';

void main() {
  test('construction is passive and initialization clamps to current work area',
      () async {
    final native = FakeDesktopLyricWindow()
      ..bounds = const Rect.fromLTWH(1800, 900, 800, 160);
    final layout = DesktopLyricWindowLayout(adapter: native);
    expect(native.operations, isEmpty);
    await layout.initialize(vertical: false);
    expect(native.bounds.right, lessThanOrEqualTo(native.area.right));
    expect(native.bounds.bottom, lessThanOrEqualTo(native.area.bottom));
    expect(native.minimum, DesktopLyricGeometry.horizontalMinimum);
  });

  test('horizontal and vertical each restore their own moved bounds', () async {
    final native = FakeDesktopLyricWindow();
    final layout = DesktopLyricWindowLayout(adapter: native);
    await layout.initialize(vertical: false);
    final horizontal = native.bounds;
    await layout.setVertical(true);
    expect(native.bounds.size, DesktopLyricGeometry.verticalSize);
    native.bounds = const Rect.fromLTWH(30, 100, 280, 600);
    final vertical = native.bounds;
    await layout.setVertical(false);
    expect(native.bounds, horizontal);
    await layout.setVertical(true);
    expect(native.bounds, vertical);
  });

  test('negative monitor coordinates and tiny work areas never force offscreen',
      () {
    const area = Rect.fromLTWH(-600, -200, 300, 250);
    final fitted = DesktopLyricGeometry.fit(
        const Rect.fromLTWH(-2500, -1000, 800, 900),
        area,
        DesktopLyricGeometry.verticalMinimum);
    expect(fitted, area);
  });

  test(
      'invalid geometry is rejected instead of emitting NaN native coordinates',
      () {
    expect(
        () => DesktopLyricGeometry.fit(
            const Rect.fromLTWH(double.nan, 0, 800, 160),
            const Rect.fromLTWH(0, 0, 1920, 1080),
            const Size(320, 100)),
        throwsStateError);
    expect(
        () => DesktopLyricGeometry.fit(const Rect.fromLTWH(0, 0, 800, 160),
            Rect.zero, const Size(320, 100)),
        throwsStateError);
  });

  test('rapid rotations serialize and end in latest direction', () async {
    final native = FakeDesktopLyricWindow();
    final layout = DesktopLyricWindowLayout(adapter: native);
    await layout.initialize(vertical: false);
    final horizontal = native.bounds;
    final gate = Completer<void>();
    native.blockNextRead = gate;
    final first = layout.setVertical(true);
    final second = layout.setVertical(false);
    final third = layout.setVertical(true);
    await Future<void>.delayed(Duration.zero);
    expect(native.bounds, horizontal);
    gate.complete();
    await Future.wait([first, second, third]);
    expect(layout.vertical, true);
    expect(native.bounds.size, DesktopLyricGeometry.verticalSize);
    expect(native.minimum, DesktopLyricGeometry.verticalMinimum);
  });

  test('palette open/close restores portrait without overwriting landscape',
      () async {
    final native = FakeDesktopLyricWindow();
    final layout = DesktopLyricWindowLayout(adapter: native);
    await layout.initialize(vertical: false);
    final horizontal = native.bounds;
    await layout.setVertical(true);
    final vertical = native.bounds;
    await layout.setPaletteOpen(true);
    expect(native.bounds.size, const Size(640, 560));
    await layout.setPaletteOpen(false);
    expect(native.bounds, vertical);
    await layout.setVertical(false);
    expect(native.bounds, horizontal);
  });

  test(
      'direction changed during palette restores new mode, not expanded bounds',
      () async {
    final native = FakeDesktopLyricWindow();
    final layout = DesktopLyricWindowLayout(adapter: native);
    await layout.initialize(vertical: false);
    final horizontal = native.bounds;
    await layout.setPaletteOpen(true);
    await layout.setVertical(true);
    await layout.setPaletteOpen(false);
    expect(native.bounds.size, DesktopLyricGeometry.verticalSize);
    await layout.setVertical(false);
    expect(native.bounds, horizontal);
  });

  test('restore reprojects stored physical bounds across a DPI change',
      () async {
    final native = FakeDesktopLyricWindow();
    final layout = DesktopLyricWindowLayout(adapter: native);
    await layout.initialize(vertical: false);
    final horizontal = native.bounds;
    await layout.setVertical(true);
    native.pixelRatio = 2;
    native.area = const Rect.fromLTWH(0, 0, 960, 520);
    await layout.setVertical(false);
    expect(native.bounds.left, horizontal.left / 2);
    expect(native.bounds.top, horizontal.top / 2);
    expect(native.bounds.width, horizontal.width / 2);
    expect(native.bounds.height, DesktopLyricGeometry.horizontalMinimum.height);
  });

  test('removed monitor bounds recover into nearest available work area',
      () async {
    final native = FakeDesktopLyricWindow();
    final layout = DesktopLyricWindowLayout(adapter: native);
    await layout.initialize(vertical: false);
    await layout.setVertical(true);
    native.bounds = const Rect.fromLTWH(-1100, -100, 248, 560);
    await layout.setVertical(false);
    native.area = const Rect.fromLTWH(0, 0, 1200, 760);
    await layout.setVertical(true);
    expect(native.bounds.left, 0);
    expect(native.bounds.top, 0);
    expect(native.bounds.bottom, lessThanOrEqualTo(native.area.bottom));
  });

  test(
      'failed rotation restores bounds/minimum and next identical request succeeds',
      () async {
    final native = FakeDesktopLyricWindow();
    final layout = DesktopLyricWindowLayout(adapter: native);
    await layout.initialize(vertical: false);
    final original = native.bounds;
    native.failNextBounds = StateError('fixture resize failure');
    await expectLater(layout.setVertical(true), throwsStateError);
    expect(native.bounds, original);
    expect(native.minimum, DesktopLyricGeometry.horizontalMinimum);
    expect(layout.vertical, false);
    await layout.setVertical(true);
    expect(layout.vertical, true);
  });

  test('large text raises minimum but never exceeds work area', () async {
    final native = FakeDesktopLyricWindow()
      ..area = const Rect.fromLTWH(0, 0, 640, 360);
    final layout = DesktopLyricWindowLayout(adapter: native);
    await layout.initialize(vertical: true);
    await layout.ensureContentMinimum(const Size(700, 800), vertical: true);
    expect(native.minimum, const Size(640, 360));
    expect(native.bounds, native.area);
  });

  test('failed content resize can retry exactly the same minimum', () async {
    final native = FakeDesktopLyricWindow();
    final layout = DesktopLyricWindowLayout(adapter: native);
    await layout.initialize(vertical: false);
    native.failNextBounds = StateError('fixture resize failure');
    await expectLater(
        layout.ensureContentMinimum(const Size(400, 260), vertical: false),
        throwsStateError);
    await layout.ensureContentMinimum(const Size(400, 260), vertical: false);
    expect(native.bounds.height, 260);
    expect(native.minimum, const Size(400, 260));
  });

  test('unchanged fit operations do not continuously resize a settled window',
      () async {
    final native = FakeDesktopLyricWindow();
    final layout = DesktopLyricWindowLayout(adapter: native);
    await layout.initialize(vertical: false);
    native.operations.clear();
    for (var i = 0; i < 10; i++) {
      await layout.fitToWorkArea();
    }
    expect(native.operations, isEmpty);
  });
}
