import 'package:integration_test/integration_test.dart';

import '../test/lyric_reading_content_anchor_test.dart' as regression;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // The mounted production rows are captured through RenderRepaintBoundary
  // with native engine/font pixels. Visibility and media position use an
  // isolated fixture; this does not capture a private HWND, measure GPU frame
  // pacing or play through a sound card.
  regression.main();
}
