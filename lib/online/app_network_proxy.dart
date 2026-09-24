import 'dart:async';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/online/network_proxy_preferences.dart';
import 'package:dan_player/online/windows_system_proxy.dart';

class NetworkProxyProbeResult {
  const NetworkProxyProbeResult({
    required this.reachable,
    required this.elapsed,
    this.statusCode,
    this.error,
  });

  final bool reachable;
  final Duration elapsed;
  final int? statusCode;
  final String? error;
}

/// Applies one live policy to all Dart HttpClient users, including package:http,
/// Dio's IO adapter, artwork, lyrics, and update downloads.
class AppNetworkProxy {
  AppNetworkProxy._();

  static bool _installed = false;

  static void install() {
    if (_installed) return;
    HttpOverrides.global = _AppHttpOverrides(HttpOverrides.current);
    _installed = true;
  }

  static HttpClient createHttpClient({NetworkProxyPreferences? preferences}) {
    final client = HttpClient();
    configureHttpClient(client, preferences: preferences);
    return client;
  }

  static void configureHttpClient(HttpClient client,
      {NetworkProxyPreferences? preferences}) {
    client.findProxy = (url) =>
        findProxy(url, preferences ?? AppSettings.instance.networkProxy.value);
  }

  static String findProxy(Uri url, NetworkProxyPreferences preferences) {
    if (isLoopbackNetworkHost(url.host)) return 'DIRECT';
    switch (preferences.mode) {
      case NetworkProxyMode.direct:
        return 'DIRECT';
      case NetworkProxyMode.custom:
        final normalized = preferences.customProxyUrl == null
            ? null
            : NetworkProxyPreferences.normalizeCustomProxy(
                preferences.customProxyUrl!);
        if (normalized == null) {
          throw const FormatException('Invalid custom HTTP proxy');
        }
        final uri = Uri.parse(normalized);
        final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
        return 'PROXY $host:${uri.port}';
      case NetworkProxyMode.system:
        return WindowsSystemProxy.instance.findProxy(url);
    }
  }

  static Future<NetworkProxyProbeResult> testGitHubConnectivity({
    NetworkProxyPreferences? preferences,
    Duration timeout = const Duration(seconds: 8),
  }) =>
      _probeGitHub(preferences: preferences, timeout: timeout);
}

class _AppHttpOverrides extends HttpOverrides {
  _AppHttpOverrides(this.previous);

  final HttpOverrides? previous;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client =
        previous?.createHttpClient(context) ?? super.createHttpClient(context);
    AppNetworkProxy.configureHttpClient(client);
    return client;
  }
}

Future<NetworkProxyProbeResult> testGitHubConnectivity({
  NetworkProxyPreferences? preferences,
  Duration timeout = const Duration(seconds: 8),
}) =>
    AppNetworkProxy.testGitHubConnectivity(
        preferences: preferences, timeout: timeout);

Future<NetworkProxyProbeResult> _probeGitHub({
  NetworkProxyPreferences? preferences,
  required Duration timeout,
}) async {
  final watch = Stopwatch()..start();
  final client = AppNetworkProxy.createHttpClient(preferences: preferences);
  client.connectionTimeout = timeout;
  WindowsSystemProxy.instance.refresh();
  try {
    final result = await (() async {
      final request = await client.getUrl(Uri.https('api.github.com', '/'));
      request.headers.set(HttpHeaders.userAgentHeader, 'DanPlayer/26.0.6');
      request.headers
          .set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close();
      final githubResponse =
          response.headers.value('x-github-request-id') != null;
      await response.drain<void>();
      return (status: response.statusCode, githubResponse: githubResponse);
    })()
        .timeout(timeout);
    return NetworkProxyProbeResult(
      reachable: result.githubResponse,
      statusCode: result.status,
      elapsed: watch.elapsed,
      error: result.status == HttpStatus.ok && result.githubResponse
          ? null
          : 'GitHub HTTP ${result.status}',
    );
  } catch (error) {
    return NetworkProxyProbeResult(
      reachable: false,
      elapsed: watch.elapsed,
      error: error is SystemAutoProxyUnsupported
          ? systemAutoProxyUnsupportedCode
          : error.toString(),
    );
  } finally {
    client.close(force: true);
    watch.stop();
  }
}
