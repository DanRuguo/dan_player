import 'package:integration_test/integration_test.dart';

import '../test/desktop_lyric_resize_shaping_test.dart' as regression;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // These cases paint the production painter through PictureRecorder using
  // native engine/font pixels. They do not capture a private HWND or measure
  // screen compositing, GPU frame pacing or sound-card playback.
  regression.main();
}
