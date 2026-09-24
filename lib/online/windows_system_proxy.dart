import 'dart:ffi' as native;
import 'dart:io';

import 'package:dan_player/online/network_proxy_preferences.dart';
import 'package:ffi/ffi.dart' as ffi;

const systemAutoProxyUnsupportedCode = 'system_pac_unsupported';

class SystemAutoProxyUnsupported implements Exception {
  const SystemAutoProxyUnsupported();

  @override
  String toString() => systemAutoProxyUnsupportedCode;
}

/// Reads the active Windows user's static proxy without changing OS settings.
/// PAC/WPAD resolution is deliberately not run in HttpClient.findProxy: the
/// WinHTTP resolver is synchronous and can block the Flutter UI for seconds.
class WindowsSystemProxy {
  WindowsSystemProxy._();

  static final instance = WindowsSystemProxy._();

  _WinHttp? _api;
  _ProxyConfiguration? _configuration;
  DateTime? _readAt;

  String findProxy(Uri url) {
    if (isLoopbackNetworkHost(url.host)) return 'DIRECT';
    if (!Platform.isWindows) {
      return HttpClient.findProxyFromEnvironment(url);
    }
    final now = DateTime.now();
    if (_configuration == null ||
        _readAt == null ||
        now.difference(_readAt!) >= const Duration(seconds: 10)) {
      _configuration = (_api ??= _WinHttp()).readConfiguration();
      _readAt = now;
    }
    final config = _configuration!;
    if (config.autoConfigUrl != null) {
      throw const SystemAutoProxyUnsupported();
    }
    // Windows often enables WPAD detection by default even when no PAC is
    // discoverable. Use an explicit static server when one exists; otherwise
    // retain direct access instead of disabling all app networking.
    if (config.autoDetect &&
        (config.proxy == null || config.proxy!.trim().isEmpty)) {
      return 'DIRECT';
    }
    return proxyForWindowsConfiguration(url, config.proxy, config.bypass);
  }

  void refresh() {
    _configuration = null;
    _readAt = null;
  }
}

/// Converts a static Windows/WinHTTP proxy list and bypass list to Dart's
/// findProxy result. Public so parser behavior can be checked without changing
/// the machine proxy.
String proxyForWindowsConfiguration(Uri url, String? proxy, String? bypass) {
  if (isLoopbackNetworkHost(url.host) ||
      proxy == null ||
      proxy.trim().isEmpty ||
      _matchesBypass(url.host, url.port, bypass)) {
    return 'DIRECT';
  }
  final entries =
      proxy.split(RegExp(r'[;\s]+')).where((part) => part.isNotEmpty);
  String? generic;
  String? matching;
  for (final entry in entries) {
    final equals = entry.indexOf('=');
    if (equals < 0) {
      generic ??= entry;
    } else if (entry.substring(0, equals).toLowerCase() == url.scheme) {
      matching = entry.substring(equals + 1);
      break;
    }
  }
  final chosen = matching ?? generic;
  if (chosen == null) {
    if (entries.any((entry) => entry.toLowerCase().startsWith('socks='))) {
      throw const FormatException('Unsupported Windows SOCKS proxy');
    }
    return 'DIRECT';
  }
  final parsed =
      Uri.tryParse(chosen.contains('://') ? chosen : 'http://$chosen');
  if (parsed == null ||
      parsed.scheme != 'http' ||
      parsed.host.isEmpty ||
      parsed.userInfo.isNotEmpty ||
      parsed.path.isNotEmpty ||
      parsed.hasQuery ||
      parsed.hasFragment) {
    throw const FormatException('Unsupported Windows proxy configuration');
  }
  final port = parsed.hasPort ? parsed.port : 80;
  if (port < 1 || port > 65535) {
    throw const FormatException('Invalid Windows proxy port');
  }
  final host = parsed.host.contains(':') ? '[${parsed.host}]' : parsed.host;
  return 'PROXY $host:$port';
}

bool _matchesBypass(String host, int port, String? list) {
  if (list == null || list.isEmpty) return false;
  final lowerHost = host.toLowerCase();
  for (final raw in list.split(RegExp(r'[;\s]+'))) {
    final pattern = raw.toLowerCase();
    if (pattern.isEmpty) continue;
    if (pattern == '<local>' && !lowerHost.contains('.')) return true;
    final regex = RegExp(
        '^${pattern.split('*').map(RegExp.escape).join('.*')}' r'$',
        caseSensitive: false);
    if (regex.hasMatch(lowerHost) || regex.hasMatch('$lowerHost:$port')) {
      return true;
    }
  }
  return false;
}

class _ProxyConfiguration {
  const _ProxyConfiguration({
    required this.autoDetect,
    this.autoConfigUrl,
    this.proxy,
    this.bypass,
  });

  final bool autoDetect;
  final String? autoConfigUrl;
  final String? proxy;
  final String? bypass;
}

final class _NativeProxyConfiguration extends native.Struct {
  @native.Int32()
  external int autoDetect;
  external native.Pointer<ffi.Utf16> autoConfigUrl;
  external native.Pointer<ffi.Utf16> proxy;
  external native.Pointer<ffi.Utf16> bypass;
}

class _WinHttp {
  _WinHttp() {
    final library = native.DynamicLibrary.open('winhttp.dll');
    final kernel = native.DynamicLibrary.open('kernel32.dll');
    _read = library.lookupFunction<
        native.Int32 Function(native.Pointer<_NativeProxyConfiguration>),
        int Function(native.Pointer<_NativeProxyConfiguration>)>(
      'WinHttpGetIEProxyConfigForCurrentUser',
    );
    _free = kernel.lookupFunction<
        native.Pointer<native.Void> Function(native.Pointer<native.Void>),
        native.Pointer<native.Void> Function(native.Pointer<native.Void>)>(
      'GlobalFree',
    );
    _getLastError =
        kernel.lookupFunction<native.Uint32 Function(), int Function()>(
            'GetLastError');
  }

  late final int Function(native.Pointer<_NativeProxyConfiguration>) _read;
  late final native.Pointer<native.Void> Function(native.Pointer<native.Void>)
      _free;
  late final int Function() _getLastError;

  _ProxyConfiguration readConfiguration() {
    final config = ffi.calloc<_NativeProxyConfiguration>();
    try {
      if (_read(config) == 0) {
        final code = _getLastError();
        if (code != 2) {
          throw SocketException('Windows proxy configuration failed ($code)');
        }
        return const _ProxyConfiguration(autoDetect: false);
      }
      return _ProxyConfiguration(
        autoDetect: config.ref.autoDetect != 0,
        autoConfigUrl: _stringOrNull(config.ref.autoConfigUrl),
        proxy: _stringOrNull(config.ref.proxy),
        bypass: _stringOrNull(config.ref.bypass),
      );
    } finally {
      _globalFree(config.ref.autoConfigUrl);
      _globalFree(config.ref.proxy);
      _globalFree(config.ref.bypass);
      ffi.calloc.free(config);
    }
  }

  void _globalFree(native.Pointer<ffi.Utf16> value) {
    if (value != native.nullptr) _free(value.cast<native.Void>());
  }

  String? _stringOrNull(native.Pointer<ffi.Utf16> value) {
    if (value == native.nullptr) return null;
    final text = value.toDartString();
    return text.isEmpty ? null : text;
  }
}
