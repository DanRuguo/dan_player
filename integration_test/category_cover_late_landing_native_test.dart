import 'package:integration_test/integration_test.dart';

import '../test/category_cover_late_landing_test.dart' as regression;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  regression.main(includePlaceholderCase: false);
}
