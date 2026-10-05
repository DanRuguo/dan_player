import 'package:integration_test/integration_test.dart';

import '../test/timed_lyric_resize_shaping_test.dart' as regression;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  regression.main();
}
