import 'package:integration_test/integration_test.dart';

import '../test/lyric_reading_font_anchor_test.dart' as regression;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Only the new QRC reading/font cases are registered. The production glyph
  // boundary uses native engine/font pixels at an isolated fixed media time;
  // this is not a private-HWND capture, GPU pacing or sound-card measurement.
  regression.main();
}
