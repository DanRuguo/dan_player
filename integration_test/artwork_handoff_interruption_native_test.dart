import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../test/artwork_handoff_interruption_test.dart' as regression;
import 'support/sampled_lyric_animation_binding.dart';

// Real Windows raster/compositing with explicit animation samples. Image
// readbacks cannot advance the handoff clock. This is not a GPU frame-rate test.
void main() {
  final binding = SampledLyricAnimationBinding();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  regression.main(onlyCase: Platform.environment['DAN_ARTWORK_HANDOFF_CASE']);
}
