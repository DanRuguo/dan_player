import 'package:flutter_test/flutter_test.dart';

import '../test/player_guide_transition_demo_test.dart' as guide;
import '../test/sidebar_resize_input_ownership_test.dart' as sidebar;
import '../test/statistics_trends_menu_lifecycle_test.dart' as statistics;
import 'support/sampled_lyric_animation_binding.dart';

/// Real Windows rendering with explicit animation samples. This checks input
/// ownership and finite UI clocks; it does not measure device frame rate.
void main() {
  final binding = SampledLyricAnimationBinding();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  guide.main();
  sidebar.main();
  statistics.main();
}
