import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/current_playlist_search_height_test.dart' as regression;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // These cases send controlled text instead of operating the native IME.
  setUp(binding.testTextInput.register);
  tearDown(binding.testTextInput.unregister);
  regression.main(
      onlyCase: Platform.environment['DAN_QUEUE_HEIGHT_NATIVE_CASE']);
}
