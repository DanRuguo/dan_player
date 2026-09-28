import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:ui' as ui;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('retained stretch shader assets stay synchronized and loadable',
      () async {
    expect(
        File('shaders/edge_stretch.glsl').readAsStringSync(),
        File('third_party/desktop_lyric/shaders/edge_stretch.glsl')
            .readAsStringSync());
    for (final manifest in [
      'pubspec.yaml',
      'third_party/desktop_lyric/pubspec.yaml'
    ]) {
      expect(File(manifest).readAsStringSync(),
          contains('    - shaders/app_edge_stretch.frag'));
    }
    // Keep the optional source asset buildable while the production scroll
    // behavior uses Flutter's native StretchingOverscrollIndicator.
    final program =
        await ui.FragmentProgram.fromAsset('shaders/app_edge_stretch.frag');
    final shader = program.fragmentShader();
    for (var index = 2; index <= 5; index++) {
      shader.setFloat(index, 0);
    }
    shader.dispose();
    expect(
        await rootBundle.loadString(
            'third_party/desktop_lyric/shaders/FLUTTER-LICENSE.txt'),
        contains('Copyright 2014 The Flutter Authors.'));
  });
}
