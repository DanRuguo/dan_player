import 'package:integration_test/integration_test.dart';

import '../test/taskbar_lyric_text_projection_test.dart' as regression;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Live taskbar row + production painter, captured with native fonts through
  // PictureRecorder/toImage. No Explorer HWND capture or GPU frame-rate claim.
  regression.main();
}
