import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

import '../test/lyric_viewport_blur_test.dart' as regression;
import 'support/sampled_lyric_animation_binding.dart';

void main() {
  // These fixtures read RenderRepaintBoundary.toImage on the Windows engine.
  // LayerTree.Flatten omits the real window's raster cache, so their native
  // pixel/layer assertions do not replace a warmed, presented-window capture.
  final binding = SampledLyricAnimationBinding();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  setUpAll(() async {
    expect(Directory.systemTemp.absolute.path.replaceAll('\\', '/'),
        contains('/tool/qa-local/'));
    await windowManager.ensureInitialized();
    await windowManager.hide();
  });
  regression.main();
}
