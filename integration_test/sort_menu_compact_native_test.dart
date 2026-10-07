import 'dart:io';

import 'package:integration_test/integration_test.dart';

import '../test/sort_menu_compact_layout_test.dart' as regression;
import '../test/independent_sort_menu_compact_test.dart' as independent;
import '../test/smart_sort_menu_compact_test.dart' as smart;
import 'sort_menu_native_stretch_test.dart' as stretch;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Exercise all sorting surfaces and their existing native stretch path.
  // RepaintBoundary captures are engine pixels, not private HWND captures or
  // measurements of hardware touch, GPU frame pacing, or audio output.
  final group = Platform.environment['DAN_SORT_COMPACT_NATIVE_GROUP'] ?? 'all';
  if (!['all', 'shared', 'independent', 'smart', 'resume'].contains(group)) {
    throw ArgumentError.value(group, 'DAN_SORT_COMPACT_NATIVE_GROUP');
  }
  if (['all', 'shared', 'resume'].contains(group)) regression.main();
  if (['all', 'independent', 'resume'].contains(group)) independent.main();
  if (['all', 'smart', 'resume'].contains(group)) smart.main();
  if (group == 'all') stretch.main();
}
