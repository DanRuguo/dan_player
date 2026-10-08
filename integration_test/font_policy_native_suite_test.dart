import 'package:integration_test/integration_test.dart';

import '../test/desktop_lyric_font_render_test.dart' as desktop;
import '../test/player_font_policy_render_test.dart' as player;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  desktop.main();
  player.main();
}
