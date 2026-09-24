import 'dart:io';

import 'package:dan_player/online/app_network_proxy.dart';
import 'package:dan_player/online/network_proxy_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows system, direct, and local custom proxy reach GitHub as chosen',
      () async {
    const system = NetworkProxyPreferences();
    const direct = NetworkProxyPreferences(mode: NetworkProxyMode.direct);
    const custom = NetworkProxyPreferences(
        mode: NetworkProxyMode.custom, customProxyUrl: 'http://127.0.0.1:7890');
    final destination = Uri.https('api.github.com', '/');
    final systemRoute = AppNetworkProxy.findProxy(destination, system);
    expect(systemRoute, 'PROXY 127.0.0.1:7890');
    expect(AppNetworkProxy.findProxy(destination, direct), 'DIRECT');
    expect(AppNetworkProxy.findProxy(destination, custom), systemRoute);

    final systemResult = await testGitHubConnectivity(preferences: system);
    final customResult = await testGitHubConnectivity(preferences: custom);
    final directResult = await testGitHubConnectivity(preferences: direct);
    // Keep the optional live report free of proxy URLs and credentials.
    debugPrint('system: ${systemResult.statusCode}, '
        '${systemResult.elapsed.inMilliseconds}ms, ${systemResult.error}');
    debugPrint('custom: ${customResult.statusCode}, '
        '${customResult.elapsed.inMilliseconds}ms, ${customResult.error}');
    debugPrint('direct: ${directResult.statusCode}, '
        '${directResult.elapsed.inMilliseconds}ms, ${directResult.error}');
    expect(systemResult.reachable, isTrue);
    expect(customResult.reachable, isTrue);
  },
      skip: !Platform.isWindows ||
          Platform.environment['DAN_PLAYER_PROXY_LIVE_TEST'] != '1',
      timeout: const Timeout(Duration(seconds: 40)));
}
