import 'dart:async';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/online/app_network_proxy.dart';
import 'package:dan_player/online/network_proxy_preferences.dart';
import 'package:dan_player/online/windows_system_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('custom proxy input accepts only an unauthenticated HTTP authority', () {
    expect(NetworkProxyPreferences.normalizeCustomProxy('127.0.0.1:7890'),
        'http://127.0.0.1:7890');
    expect(NetworkProxyPreferences.normalizeCustomProxy('http://proxy:8080'),
        'http://proxy:8080');
    expect(NetworkProxyPreferences.normalizeCustomProxy('[::1]:7890'),
        'http://[::1]:7890');
    for (final invalid in [
      'proxy',
      'proxy:0',
      'proxy:65536',
      'http://proxy:8080/',
      'http://proxy:8080/path',
      'http://user:password@proxy:8080',
      'https://proxy:8080',
      'socks5://proxy:1080',
      'proxy:8080?key=1',
    ]) {
      expect(NetworkProxyPreferences.normalizeCustomProxy(invalid), isNull,
          reason: invalid);
    }
  });

  test('stored malformed custom proxies recover to system mode', () {
    final parsed = NetworkProxyPreferences.fromMap(
        {'mode': 'custom', 'customProxyUrl': 'socks5://proxy:1080'});
    expect(parsed.mode, NetworkProxyMode.system);
    expect(parsed.customProxyUrl, isNull);
    final valid = NetworkProxyPreferences.fromMap(const NetworkProxyPreferences(
            mode: NetworkProxyMode.custom, customProxyUrl: 'http://proxy:7890')
        .toMap());
    expect(valid.mode, NetworkProxyMode.custom);
    expect(valid.customProxyUrl, 'http://proxy:7890');
  });

  test('equivalent proxy selections keep cache and notifier keys stable', () {
    const first = NetworkProxyPreferences(
        mode: NetworkProxyMode.custom,
        customProxyUrl: 'http://127.0.0.1:7890');
    const same = NetworkProxyPreferences(
        mode: NetworkProxyMode.custom,
        customProxyUrl: 'http://127.0.0.1:7890');
    const changed = NetworkProxyPreferences(
        mode: NetworkProxyMode.custom,
        customProxyUrl: 'http://127.0.0.1:7891');
    expect(first, same);
    expect(first.hashCode, same.hashCode);
    final keys = <NetworkProxyPreferences>{first};
    keys.add(same);
    keys.add(changed);
    expect(keys, hasLength(2));
  });

  test('live policy and native stream policy bypass loopback destinations', () {
    const custom = NetworkProxyPreferences(
        mode: NetworkProxyMode.custom, customProxyUrl: 'http://127.0.0.1:7890');
    final remote = Uri.https('api.github.com', '/');
    expect(AppNetworkProxy.findProxy(remote, custom), 'PROXY 127.0.0.1:7890');
    expect(bassProxyForUrl(remote, custom), '127.0.0.1:7890');
    expect(bassProxyForUrl(remote, const NetworkProxyPreferences()), '');
    expect(
        bassProxyForUrl(remote,
            const NetworkProxyPreferences(mode: NetworkProxyMode.direct)),
        isNull);
    for (final host in ['localhost', '127.0.0.1', '[::1]']) {
      final local = Uri.parse('http://$host:8080/song');
      expect(AppNetworkProxy.findProxy(local, custom), 'DIRECT');
      expect(bassProxyForUrl(local, custom), isNull);
    }
  });

  test('Windows static proxy honors scheme selection and bypass list', () {
    const list = 'http=http-proxy:8080;https=secure-proxy:8443';
    expect(
        proxyForWindowsConfiguration(
            Uri.https('api.github.com', '/'), list, '*.internal;<local>'),
        'PROXY secure-proxy:8443');
    expect(
        proxyForWindowsConfiguration(
            Uri.http('music.internal', '/'), list, '*.internal;<local>'),
        'DIRECT');
    expect(
        proxyForWindowsConfiguration(
            Uri.http('intranet', '/'), list, '*.internal;<local>'),
        'DIRECT');
    expect(proxyForWindowsConfiguration(Uri.http('127.0.0.1', '/'), list, null),
        'DIRECT');
  });

  test('custom HTTP proxy actually carries app HttpClient requests', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final seen = Completer<Uri>();
    final subscription = server.listen((request) async {
      seen.complete(request.uri);
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
    });
    final client = AppNetworkProxy.createHttpClient(
      preferences: NetworkProxyPreferences(
          mode: NetworkProxyMode.custom,
          customProxyUrl: '127.0.0.1:${server.port}'),
    );
    try {
      final response = await (await client
              .getUrl(Uri.http('example.invalid', '/network-probe')))
          .close()
          .timeout(const Duration(seconds: 3));
      await response.drain<void>();
      expect(response.statusCode, HttpStatus.noContent);
      expect((await seen.future).path, '/network-probe');
    } finally {
      client.close(force: true);
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test('an existing pooled HttpClient uses the newly selected proxy', () async {
    final first = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final second = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final firstSubscription = first.listen((request) async {
      request.response.headers.set('x-proxy-id', 'first');
      await request.response.close();
    });
    final secondSubscription = second.listen((request) async {
      request.response.headers.set('x-proxy-id', 'second');
      await request.response.close();
    });
    final previous = AppSettings.instance.networkProxy.value;
    final client = AppNetworkProxy.createHttpClient();
    Future<String?> requestProxy() async {
      final response = await (await client
              .getUrl(Uri.http('example.invalid', '/switch-proxy')))
          .close()
          .timeout(const Duration(seconds: 3));
      await response.drain<void>();
      return response.headers.value('x-proxy-id');
    }

    try {
      AppSettings.instance.networkProxy.value = NetworkProxyPreferences(
          mode: NetworkProxyMode.custom,
          customProxyUrl: '127.0.0.1:${first.port}');
      expect(await requestProxy(), 'first');
      AppSettings.instance.networkProxy.value = NetworkProxyPreferences(
          mode: NetworkProxyMode.custom,
          customProxyUrl: '127.0.0.1:${second.port}');
      expect(await requestProxy(), 'second');
      AppSettings.instance.networkProxy.value =
          const NetworkProxyPreferences(mode: NetworkProxyMode.direct);
      expect(
          AppNetworkProxy.findProxy(Uri.http('example.invalid', '/'),
              AppSettings.instance.networkProxy.value),
          'DIRECT');
    } finally {
      AppSettings.instance.networkProxy.value = previous;
      client.close(force: true);
      await firstSubscription.cancel();
      await secondSubscription.cancel();
      await first.close(force: true);
      await second.close(force: true);
    }
  });

  test('Windows system proxy FFI returns a configured route or PAC marker', () {
    if (!Platform.isWindows) return;
    try {
      final route = WindowsSystemProxy.instance
          .findProxy(Uri.https('api.github.com', '/'));
      expect(route, anyOf('DIRECT', startsWith('PROXY ')));
    } on SystemAutoProxyUnsupported {
      expect(systemAutoProxyUnsupportedCode, 'system_pac_unsupported');
    }
  });
}
