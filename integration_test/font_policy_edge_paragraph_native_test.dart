import 'package:integration_test/integration_test.dart';

import '../test/font_policy_edge_paragraph_test.dart' as regression;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  regression.main(onlyRender: true);
}
