import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

import '../test/statistics_resize_motion_test.dart' as resize;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Capture one explicit renderer frame without advancing the finite clock
  // while reading back pixels. This does not measure GPU frame pacing.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  setUpAll(() async {
    await windowManager.ensureInitialized();
    await windowManager.hide();
  });
  resize.main(nativeOnly: true);
}
