import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

import '../test/desktop_lyric_spacing_layout_test.dart' as spacing;
import '../test/japanese_ruby_spacing_attachment_test.dart' as attachment;
import '../test/japanese_lyric_ruby_render_test.dart' as ruby;
import '../test/japanese_ruby_visible_gap_test.dart' as gap;
import 'support/sampled_lyric_animation_binding.dart';

void main() {
  const onlyCase = String.fromEnvironment('DAN_LYRIC_PRIORITY_CASE');
  if (!{'', 'attachment', 'spacing', 'ruby'}.contains(onlyCase)) {
    throw ArgumentError.value(onlyCase, 'DAN_LYRIC_PRIORITY_CASE');
  }
  final binding = SampledLyricAnimationBinding();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  setUpAll(() async {
    await windowManager.ensureInitialized();
    await windowManager.hide();
  });
  if (onlyCase.isEmpty || onlyCase == 'attachment') attachment.main();
  if (onlyCase.isEmpty || onlyCase == 'spacing') spacing.main();
  if (onlyCase.isEmpty || onlyCase == 'ruby') {
    ruby.main(onlyRender: true);
    gap.main(onlyRender: true);
  }
}
