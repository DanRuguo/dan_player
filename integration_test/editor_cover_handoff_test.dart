import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/lyric_editor_background_continuity_test.dart' as editor;
import '../test/playlist_cover_entrance_handoff_test.dart' as covers;

// Render the production flows on Windows while keeping frame samples tied to
// explicit pumps. Raster readbacks must not advance staggered entrance clocks.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  // These fixtures send controlled text input rather than OS IME events.
  // Integration bindings otherwise leave the fake text channel unregistered.
  setUp(binding.testTextInput.register);
  tearDown(binding.testTextInput.unregister);
  // A native process retains its accessibility tree. Select one case when
  // isolating testWidgets' per-test reset of semantic node IDs on Windows.
  final onlyCase = Platform.environment['DAN_HANDOFF_CASE'];
  editor.main(onlyCase: onlyCase);
  covers.main(onlyCase: onlyCase);
}
