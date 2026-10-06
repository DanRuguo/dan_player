import 'package:integration_test/integration_test.dart';

import '../test/desktop_lyric_grapheme_timing_test.dart' as regression;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  regression.main(includeAutomaticSampling: false);
}
