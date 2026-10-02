import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

import '../test/lyric_share_layout_polish_test.dart' as share;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await windowManager.ensureInitialized();
    await windowManager.hide();
  });
  share.main(
      onlyCase:
          'selection wheel clips hovered and pressed ink outside its viewport');
}
