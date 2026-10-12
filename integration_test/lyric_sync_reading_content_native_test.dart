import 'package:flutter_test/flutter_test.dart';

import '../test/lyric_sync_reading_content_anchor_test.dart' as regression;
import 'support/sampled_lyric_animation_binding.dart';

void main() {
  final binding = SampledLyricAnimationBinding();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  // Production QRC rows are captured via RenderRepaintBoundary using the
  // native engine/fonts, at a fixed isolated media position. This does not
  // capture a private HWND or verify GPU frame pacing or sound-card output.
  regression.main();
}
