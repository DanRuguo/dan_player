import 'package:integration_test/integration_test.dart';

import '../test/lyric_source_render_test.dart' as regression;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  regression.main();
}
