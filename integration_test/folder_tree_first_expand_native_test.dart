import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

import '../test/folder_tree_first_expand_test.dart' as regression;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Native renderer frames advance only on explicit pumps, preserving the
  // actual finite entrance/handoff samples instead of elapsed readback time.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  setUpAll(() async {
    await windowManager.ensureInitialized();
    await windowManager.hide();
  });
  final selected = Platform.environment['DAN_FOLDER_FIRST_EXPAND_CASE'] ??
      const String.fromEnvironment('DAN_FOLDER_FIRST_EXPAND_CASE');
  regression.main(onlyRender: true, onlyCase: selected);
}
