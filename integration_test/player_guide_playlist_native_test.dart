import 'dart:io';

import 'package:integration_test/integration_test.dart';

import '../test/player_guide_playlist_demo_test.dart' as regression;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final selected = Platform.environment['DAN_GUIDE_PLAYLIST_NATIVE_CASE'] ??
      const String.fromEnvironment('DAN_GUIDE_PLAYLIST_NATIVE_CASE');
  regression.main(
      onlyCases: selected.isNotEmpty
          ? {selected}
          : {
              'four view selections reuse the actual bounded tracker and settle once',
              'rapid view retarget including return to the old layout keeps the last request',
              'playlist flight hidden gate settles and retains selection without restarting',
              'playlist flight native gate settles and retains selection without restarting',
              'pending capture hidden by the parent keeps its requested layout',
              'nested outer scroll retires the clipped playlist flight',
            });
}
