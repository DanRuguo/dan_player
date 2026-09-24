import 'dart:io';

enum NetworkProxyMode { system, direct, custom }

bool isLoopbackNetworkHost(String host) {
  final lower = host.toLowerCase();
  return lower == 'localhost' ||
      lower.endsWith('.localhost') ||
      (InternetAddress.tryParse(host)?.isLoopback ?? false);
}

/// BASS accepts null for direct, an empty string for OS settings, and an
/// authority for a custom HTTP proxy.
String? bassProxyForUrl(Uri url, NetworkProxyPreferences preferences) {
  if (isLoopbackNetworkHost(url.host)) return null;
  switch (preferences.mode) {
    case NetworkProxyMode.direct:
      return null;
    case NetworkProxyMode.system:
      return '';
    case NetworkProxyMode.custom:
      final normalized = preferences.customProxyUrl == null
          ? null
          : NetworkProxyPreferences.normalizeCustomProxy(
              preferences.customProxyUrl!);
      if (normalized == null) {
        throw const FormatException('Invalid custom HTTP proxy');
      }
      final proxy = Uri.parse(normalized);
      final host = proxy.host.contains(':') ? '[${proxy.host}]' : proxy.host;
      return '$host:${proxy.port}';
  }
}

/// Application HTTP proxy policy. A custom proxy is an unauthenticated HTTP
/// forward proxy, including HTTPS requests made with CONNECT.
class NetworkProxyPreferences {
  const NetworkProxyPreferences({
    this.mode = NetworkProxyMode.system,
    this.customProxyUrl,
  });

  final NetworkProxyMode mode;
  final String? customProxyUrl;

  @override
  bool operator ==(Object other) =>
      other is NetworkProxyPreferences &&
      other.mode == mode &&
      other.customProxyUrl == customProxyUrl;

  @override
  int get hashCode => Object.hash(mode, customProxyUrl);

  NetworkProxyPreferences copyWith({
    NetworkProxyMode? mode,
    String? customProxyUrl,
  }) =>
      NetworkProxyPreferences(
        mode: mode ?? this.mode,
        customProxyUrl: customProxyUrl ?? this.customProxyUrl,
      );

  Map<String, Object?> toMap() => {
        'mode': mode.name,
        'customProxyUrl': customProxyUrl,
      };

  factory NetworkProxyPreferences.fromMap(Object? value) {
    if (value is! Map) return const NetworkProxyPreferences();
    final modeName = value['mode'];
    final mode = NetworkProxyMode.values.firstWhere(
      (candidate) => candidate.name == modeName,
      orElse: () => NetworkProxyMode.system,
    );
    final rawUrl = value['customProxyUrl'];
    final url = rawUrl is String ? normalizeCustomProxy(rawUrl) : null;
    return NetworkProxyPreferences(
      mode: mode == NetworkProxyMode.custom && url == null
          ? NetworkProxyMode.system
          : mode,
      customProxyUrl: url,
    );
  }

  /// Accepts `host:port` or `http://host:port` (also bracketed IPv6).
  /// Returns null for credentials, paths, HTTPS/SOCKS, or missing ports.
  static String? normalizeCustomProxy(String input) {
    final text = input.trim();
    if (text.isEmpty || text.contains(RegExp(r'\s'))) return null;
    final withScheme = text.contains('://') ? text : 'http://$text';
    final uri = Uri.tryParse(withScheme);
    if (uri == null ||
        uri.scheme != 'http' ||
        uri.host.isEmpty ||
        !uri.hasPort ||
        uri.port < 1 ||
        uri.port > 65535 ||
        uri.userInfo.isNotEmpty ||
        uri.path.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    final host = uri.host;
    final isIp = InternetAddress.tryParse(host) != null;
    if (!isIp &&
        (!RegExp(r'^[A-Za-z0-9.-]+$').hasMatch(host) ||
            host.startsWith('.') ||
            host.endsWith('.') ||
            host.contains('..'))) {
      return null;
    }
    return Uri(scheme: 'http', host: host, port: uri.port).toString();
  }
}
