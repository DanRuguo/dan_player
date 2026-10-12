import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

import '../test/japanese_lyric_ruby_render_test.dart' as ruby;
import '../test/lyric_native_spacing_replay_test.dart' as replay;
import '../test/lyric_letter_spacing_visible_feedback_test.dart' as spacing;
import 'support/sampled_lyric_animation_binding.dart';

void main() {
  final binding = SampledLyricAnimationBinding();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  setUpAll(() async {
    await windowManager.ensureInitialized();
    await windowManager.hide();
  });
  spacing.main(onlyRender: true);
  replay.main();
  ruby.main(onlyRender: true);
}
