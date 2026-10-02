import 'dart:io';

import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

import '../test/lyric_result_layout_polish_test.dart' as results;
import 'queue_insert_native_test.dart' as queue;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await windowManager.ensureInitialized();
    await windowManager.hide();
  });
  final onlyCase = Platform.environment['DAN_DIALOG_POLISH_NATIVE_CASE'];
  if (onlyCase != null && onlyCase != 'wheel' && onlyCase != 'queue') {
    throw StateError('Unknown dialog polish native case: $onlyCase');
  }
  if (onlyCase != 'queue') results.main(nativeWheelOnly: true);
  if (onlyCase != 'wheel') queue.main();
}
