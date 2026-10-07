import 'package:integration_test/integration_test.dart';

import '../test/submenu_layout_regression_test.dart' as regression;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // The production menus use Windows engine fonts and actual overlay layout.
  // This does not measure GPU frame timing or exercise physical input devices.
  regression.main();
}
