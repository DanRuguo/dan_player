import 'package:integration_test/integration_test.dart';

import '../test/category_cover_source_handoff_test.dart' as regression;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  regression.main();
}
