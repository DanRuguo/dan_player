import 'package:integration_test/integration_test.dart';

import '../test/lyric_sync_reading_content_anchor_test.dart' as regression;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Production QRC rows are captured via RenderRepaintBoundary using the
  // native engine/fonts, at a fixed isolated media position. This does not
  // capture a private HWND or verify GPU frame pacing or sound-card output.
  regression.main();
}
