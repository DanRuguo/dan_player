import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Features a custom provider explicitly declares.
///
/// Declaring [download] only describes the provider contract. It is not a
/// permission grant: callers must still require an authorized, resolved URL.
enum CustomMusicSourceCapability {
  search('search'),
  metadata('metadata'),
  cover('cover'),
  lyrics('lyrics'),
  comments('comments'),
  stream('stream'),
  download('download');

  const CustomMusicSourceCapability(this.id);

  final String id;

  static CustomMusicSourceCapability? fromId(Object? value) {
    if (value is! String) return null;
    for (final capability in values) {
      if (capability.id == value) return capability;
    }
    return null;
  }
}

/// Wire contract used by a profile. This must be explicit so the transport
/// never guesses a response schema from a URL or display name.
enum CustomMusicSourceProtocol {
  danSourceV1('dan-source-v1'),
  goMusicApi('go-music-api-v1'),
  legacyLyrics('legacy-lyrics');

  const CustomMusicSourceProtocol(this.id);

  final String id;

  static CustomMusicSourceProtocol? fromId(Object? value) {
    if (value is! String) return null;
    for (final protocol in values) {
      if (protocol.id == value) return protocol;
    }
    return null;
  }
}

/// The secret itself lives outside settings and backups.
enum CustomMusicSourceAuthenticationKind {
  bearerHeader('bearer-header'),
  apiKeyHeader('api-key-header'),
  apiKeyQuery('api-key-query');

  const CustomMusicSourceAuthenticationKind(this.id);

  final String id;

  static CustomMusicSourceAuthenticationKind? fromId(Object? value) {
    if (value is! String) return null;
    for (final kind in values) {
      if (kind.id == value) return kind;
    }
    return null;
  }
}

@immutable
class CustomMusicSourceAuthentication {
  const CustomMusicSourceAuthentication._({
    required this.kind,
    required this.credentialRef,
    required this.parameterName,
  });

  final CustomMusicSourceAuthenticationKind kind;

  /// A stable identifier for a future OS-protected credential entry, never the
  /// token/password itself. Keeping only this reference makes settings and
  /// cache backups safe to inspect and share.
  final String credentialRef;

  /// Header or query-parameter name, depending on [kind].
  final String parameterName;

  static CustomMusicSourceAuthentication? tryCreate({
    required CustomMusicSourceAuthenticationKind kind,
    required String credentialRef,
    String? parameterName,
  }) {
    final safeReference = _safeIdentifier(credentialRef, maximumLength: 128);
    if (safeReference == null) return null;
    final requestedName = parameterName?.trim();
    final defaultName = switch (kind) {
      CustomMusicSourceAuthenticationKind.bearerHeader => 'Authorization',
      CustomMusicSourceAuthenticationKind.apiKeyHeader => 'X-API-Key',
      CustomMusicSourceAuthenticationKind.apiKeyQuery => 'api_key',
    };
    final safeName = requestedName == null || requestedName.isEmpty
        ? defaultName
        : requestedName;
    if (!_isParameterName(safeName)) return null;
    return CustomMusicSourceAuthentication._(
      kind: kind,
      credentialRef: safeReference,
      parameterName: safeName,
    );
  }

  static CustomMusicSourceAuthentication? fromJson(Object? value) {
    if (value is! Map) return null;
    final kind = CustomMusicSourceAuthenticationKind.fromId(value['kind']);
    final reference = value['credentialRef'];
    if (kind == null || reference is! String) return null;
    return tryCreate(
      kind: kind,
      credentialRef: reference,
      parameterName: value['parameterName'] is String
          ? value['parameterName'] as String
          : null,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
        'kind': kind.id,
        'credentialRef': credentialRef,
        'parameterName': parameterName,
      };

  @override
  String toString() =>
      'CustomMusicSourceAuthentication(${kind.id}, credential: redacted)';

  @override
  bool operator ==(Object other) =>
      other is CustomMusicSourceAuthentication &&
      kind == other.kind &&
      credentialRef == other.credentialRef &&
      parameterName == other.parameterName;

  @override
  int get hashCode => Object.hash(kind, credentialRef, parameterName);
}

@immutable
class CustomMusicSourceProfile {
  const CustomMusicSourceProfile._({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.enabled,
    required this.protocol,
    required this.protocolVersion,
    required this.capabilities,
    required this.endpoints,
    required this.publicHeaders,
    required this.authentication,
  });

  static const int currentProtocolVersion = 1;
  static const String legacyLyricProfileId = 'legacy-lyric-api';

  final String id;
  final String name;
  final String baseUrl;
  final bool enabled;
  final CustomMusicSourceProtocol protocol;
  final int protocolVersion;
  final Set<CustomMusicSourceCapability> capabilities;

  /// Capability-specific absolute HTTP(S) URLs or paths relative to [baseUrl].
  final Map<CustomMusicSourceCapability, String> endpoints;

  /// Non-secret literal headers only. Authorization, cookies and API-key
  /// headers are rejected; use [authentication] with an external credential.
  final Map<String, String> publicHeaders;
  final CustomMusicSourceAuthentication? authentication;

  /// Stable provider key stored on online audio records without colliding with
  /// built-in identifiers such as `qq` and `netease`.
  String get providerId => 'custom:$id';

  static String? profileIdFromProvider(String? providerId) {
    const prefix = 'custom:';
    if (providerId == null || !providerId.startsWith(prefix)) return null;
    return _safeIdentifier(
      providerId.substring(prefix.length),
      maximumLength: 96,
    );
  }

  bool get isLegacyLyricProfile =>
      id == legacyLyricProfileId &&
      protocol == CustomMusicSourceProtocol.legacyLyrics;

  static String createId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return 'custom-${base64UrlEncode(bytes).replaceAll('=', '')}';
  }

  static CustomMusicSourceProfile? tryCreate({
    String? id,
    required String name,
    required String baseUrl,
    bool enabled = true,
    CustomMusicSourceProtocol protocol = CustomMusicSourceProtocol.danSourceV1,
    int protocolVersion = currentProtocolVersion,
    required Iterable<CustomMusicSourceCapability> capabilities,
    Map<CustomMusicSourceCapability, String> endpoints = const {},
    Map<String, String> publicHeaders = const {},
    CustomMusicSourceAuthentication? authentication,
  }) {
    final safeId = _safeIdentifier(id ?? createId(), maximumLength: 96);
    final safeName = _safeDisplayName(name);
    final safeBaseUrl = _safeHttpUrl(baseUrl);
    if (safeId == null || safeName == null || safeBaseUrl == null) return null;
    if (safeId == legacyLyricProfileId &&
        protocol != CustomMusicSourceProtocol.legacyLyrics) {
      return null;
    }
    if (protocolVersion < 1 || protocolVersion > currentProtocolVersion) {
      return null;
    }

    final safeCapabilities = Set<CustomMusicSourceCapability>.unmodifiable(
      capabilities,
    );
    if (safeCapabilities.isEmpty) return null;

    final safeEndpoints = <CustomMusicSourceCapability, String>{};
    for (final entry in endpoints.entries) {
      if (!safeCapabilities.contains(entry.key)) continue;
      final endpoint = _safeEndpoint(entry.value);
      if (endpoint != null) safeEndpoints[entry.key] = endpoint;
    }
    if (protocol == CustomMusicSourceProtocol.legacyLyrics &&
        (!safeCapabilities.contains(CustomMusicSourceCapability.lyrics) ||
            !safeEndpoints.containsKey(CustomMusicSourceCapability.lyrics))) {
      return null;
    }

    final safeHeaders = <String, String>{};
    for (final entry in publicHeaders.entries) {
      final name = entry.key.trim();
      final value = entry.value.trim();
      if (!_isHeaderName(name) ||
          _isSensitiveHeader(name) ||
          value.isEmpty ||
          value.length > 1024 ||
          value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
        continue;
      }
      safeHeaders[name] = value;
      if (safeHeaders.length >= 24) break;
    }

    return CustomMusicSourceProfile._(
      id: safeId,
      name: safeName,
      baseUrl: safeBaseUrl,
      enabled: enabled,
      protocol: protocol,
      protocolVersion: protocolVersion,
      capabilities: safeCapabilities,
      endpoints: Map.unmodifiable(safeEndpoints),
      publicHeaders: Map.unmodifiable(safeHeaders),
      authentication: authentication,
    );
  }

  static CustomMusicSourceProfile? legacyLyric(String? rawUrl) {
    final url = _safeHttpUrl(rawUrl);
    if (url == null) return null;
    final uri = Uri.parse(url);
    final base = uri.replace(path: '', query: null, fragment: null).toString();
    return tryCreate(
      id: legacyLyricProfileId,
      name: 'Legacy lyric API',
      baseUrl: base,
      protocol: CustomMusicSourceProtocol.legacyLyrics,
      capabilities: const {CustomMusicSourceCapability.lyrics},
      endpoints: {CustomMusicSourceCapability.lyrics: url},
    );
  }

  static CustomMusicSourceProfile? fromJson(Object? value) {
    if (value is! Map) return null;
    final rawId = value['id'];
    final rawName = value['name'];
    final rawBaseUrl = value['baseUrl'];
    final rawCapabilities = value['capabilities'];
    if (rawId is! String ||
        rawName is! String ||
        rawBaseUrl is! String ||
        rawCapabilities is! List) {
      return null;
    }
    final capabilities = <CustomMusicSourceCapability>{
      for (final item in rawCapabilities)
        if (CustomMusicSourceCapability.fromId(item) case final capability?)
          capability,
    };
    final endpoints = <CustomMusicSourceCapability, String>{};
    final rawEndpoints = value['endpoints'];
    if (rawEndpoints is Map) {
      for (final entry in rawEndpoints.entries) {
        final capability = CustomMusicSourceCapability.fromId(entry.key);
        if (capability != null && entry.value is String) {
          endpoints[capability] = entry.value as String;
        }
      }
    }
    final headers = <String, String>{};
    final rawHeaders = value['publicHeaders'];
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        if (entry.key is String && entry.value is String) {
          headers[entry.key as String] = entry.value as String;
        }
      }
    }
    final protocolVersion = value['protocolVersion'];
    final rawProtocol = value['protocol'];
    final protocol = rawProtocol == null
        ? CustomMusicSourceProtocol.danSourceV1
        : CustomMusicSourceProtocol.fromId(rawProtocol);
    if (protocol == null) return null;
    return tryCreate(
      id: rawId,
      name: rawName,
      baseUrl: rawBaseUrl,
      enabled: value['enabled'] is bool ? value['enabled'] as bool : true,
      protocol: protocol,
      protocolVersion:
          protocolVersion is int ? protocolVersion : currentProtocolVersion,
      capabilities: capabilities,
      endpoints: endpoints,
      publicHeaders: headers,
      authentication:
          CustomMusicSourceAuthentication.fromJson(value['authentication']),
    );
  }

  Map<String, Object> toJson() => <String, Object>{
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'enabled': enabled,
        'protocol': protocol.id,
        'protocolVersion': protocolVersion,
        'capabilities': <String>[
          for (final capability in CustomMusicSourceCapability.values)
            if (capabilities.contains(capability)) capability.id,
        ],
        if (endpoints.isNotEmpty)
          'endpoints': <String, String>{
            for (final capability in CustomMusicSourceCapability.values)
              if (endpoints[capability] case final endpoint?)
                capability.id: endpoint,
          },
        if (publicHeaders.isNotEmpty) 'publicHeaders': publicHeaders,
        if (authentication != null) 'authentication': authentication!.toJson(),
      };

  Uri? endpointFor(CustomMusicSourceCapability capability) {
    if (!capabilities.contains(capability)) return null;
    final endpoint = endpoints[capability];
    if (endpoint == null) return null;
    final parsed = Uri.tryParse(endpoint);
    if (parsed == null) return null;
    return parsed.hasScheme ? parsed : Uri.parse(baseUrl).resolveUri(parsed);
  }

  CustomMusicSourceProfile copyWith({
    String? name,
    String? baseUrl,
    bool? enabled,
    CustomMusicSourceProtocol? protocol,
    int? protocolVersion,
    Iterable<CustomMusicSourceCapability>? capabilities,
    Map<CustomMusicSourceCapability, String>? endpoints,
    Map<String, String>? publicHeaders,
    CustomMusicSourceAuthentication? authentication,
    bool clearAuthentication = false,
  }) =>
      tryCreate(
        id: id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        enabled: enabled ?? this.enabled,
        protocol: protocol ?? this.protocol,
        protocolVersion: protocolVersion ?? this.protocolVersion,
        capabilities: capabilities ?? this.capabilities,
        endpoints: endpoints ?? this.endpoints,
        publicHeaders: publicHeaders ?? this.publicHeaders,
        authentication:
            clearAuthentication ? null : authentication ?? this.authentication,
      ) ??
      this;

  /// Deliberately excludes endpoints, headers and credential references.
  @override
  String toString() => 'CustomMusicSourceProfile('
      'id: $id, protocol: ${protocol.id}/$protocolVersion, '
      'capabilities: ${capabilities.length})';

  @override
  bool operator ==(Object other) =>
      other is CustomMusicSourceProfile &&
      id == other.id &&
      name == other.name &&
      baseUrl == other.baseUrl &&
      enabled == other.enabled &&
      protocol == other.protocol &&
      protocolVersion == other.protocolVersion &&
      setEquals(capabilities, other.capabilities) &&
      mapEquals(endpoints, other.endpoints) &&
      mapEquals(publicHeaders, other.publicHeaders) &&
      authentication == other.authentication;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        baseUrl,
        enabled,
        protocol,
        protocolVersion,
        Object.hashAllUnordered(capabilities),
        Object.hashAllUnordered(
          endpoints.entries.map((entry) => Object.hash(entry.key, entry.value)),
        ),
        Object.hashAllUnordered(
          publicHeaders.entries
              .map((entry) => Object.hash(entry.key, entry.value)),
        ),
        authentication,
      );
}

class CustomMusicSourceProfileCodec {
  const CustomMusicSourceProfileCodec._();

  static const String backupFormat = 'dan-player-custom-music-sources';
  static const int formatVersion = 1;
  static const int maximumProfiles = 32;

  static Map<String, Object> encodeSettings(
          Iterable<CustomMusicSourceProfile> profiles) =>
      <String, Object>{
        'version': formatVersion,
        'profiles': <Map<String, Object>>[
          for (final profile in profiles.take(maximumProfiles))
            profile.toJson(),
        ],
      };

  static Map<String, Object> encodeBackup(
    Iterable<CustomMusicSourceProfile> profiles, {
    DateTime? createdAt,
  }) =>
      <String, Object>{
        'format': backupFormat,
        'version': formatVersion,
        'createdAt': (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
        'profiles': <Map<String, Object>>[
          for (final profile in profiles.take(maximumProfiles))
            profile.toJson(),
        ],
      };

  /// Decodes the settings envelope. An invalid envelope retains [fallback]. A
  /// recognized empty profile array deliberately clears custom sources.
  static List<CustomMusicSourceProfile> decodeSettings(
    Object? value, {
    String? legacyLyricApiUrl,
    Iterable<CustomMusicSourceProfile> fallback = const [],
  }) {
    final decoded = _decodeEnvelope(value);
    final profiles = value == null
        ? <CustomMusicSourceProfile>[]
        : decoded ?? List<CustomMusicSourceProfile>.of(fallback);
    _appendLegacyLyric(profiles, legacyLyricApiUrl);
    return List.unmodifiable(profiles.take(maximumProfiles));
  }

  /// Accepts the v1 multi-source backup and the old lyric-only `apis` backup.
  /// Invalid entries are skipped independently rather than rejecting good ones.
  static List<CustomMusicSourceProfile> decodeBackup(
    Object? value, {
    Iterable<CustomMusicSourceProfile> fallback = const [],
  }) {
    final modern = _decodeBackupEnvelope(value);
    if (modern != null) return List.unmodifiable(modern);
    final legacy = _decodeLegacyBackup(value);
    return List.unmodifiable(legacy ?? fallback);
  }

  static List<CustomMusicSourceProfile>? _decodeEnvelope(Object? value) {
    if (value is! Map || value['version'] != formatVersion) return null;
    return _decodeProfileList(value['profiles']);
  }

  static List<CustomMusicSourceProfile>? _decodeBackupEnvelope(Object? value) {
    if (value is! Map ||
        value['format'] != backupFormat ||
        value['version'] != formatVersion) {
      return null;
    }
    return _decodeProfileList(value['profiles']);
  }

  static List<CustomMusicSourceProfile>? _decodeProfileList(Object? value) {
    if (value is! List) return null;
    final profiles = <CustomMusicSourceProfile>[];
    final ids = <String>{};
    for (final item in value) {
      final profile = CustomMusicSourceProfile.fromJson(item);
      if (profile == null || !ids.add(profile.id)) continue;
      profiles.add(profile);
      if (profiles.length >= maximumProfiles) break;
    }
    return profiles;
  }

  static List<CustomMusicSourceProfile>? _decodeLegacyBackup(Object? value) {
    if (value is! Map) return null;
    final profiles = <CustomMusicSourceProfile>[];
    final urls = <String>{};

    void add(String? rawUrl, {String? name, bool current = false}) {
      final url = _safeHttpUrl(rawUrl);
      if (url == null || !urls.add(url)) return;
      final base = CustomMusicSourceProfile.legacyLyric(url);
      if (base == null) return;
      if (current) {
        profiles.add(base);
        return;
      }
      final digest = sha256.convert(utf8.encode(url)).toString();
      final profile = CustomMusicSourceProfile.tryCreate(
        id: 'legacy-lyric-${digest.substring(0, 20)}',
        name: _safeDisplayName(name ?? '') ?? 'Imported lyric API',
        baseUrl: base.baseUrl,
        protocol: CustomMusicSourceProtocol.legacyLyrics,
        capabilities: const {CustomMusicSourceCapability.lyrics},
        endpoints: base.endpoints,
      );
      if (profile != null) profiles.add(profile);
    }

    final current = value['currentLyricApiUrl'];
    if (current is String) add(current, current: true);
    final apis = value['apis'];
    if (apis is List) {
      for (final item in apis) {
        if (item is! Map ||
            (item['type'] != null && item['type'] != 'lyric') ||
            item['url'] is! String) {
          continue;
        }
        add(
          item['url'] as String,
          name: item['name'] is String ? item['name'] as String : null,
        );
        if (profiles.length >= maximumProfiles) break;
      }
    }
    return profiles.isEmpty ? null : profiles;
  }

  static void _appendLegacyLyric(
      List<CustomMusicSourceProfile> profiles, String? legacyUrl) {
    if (profiles.any((profile) => profile.isLegacyLyricProfile)) return;
    final legacy = CustomMusicSourceProfile.legacyLyric(legacyUrl);
    if (legacy != null) profiles.add(legacy);
  }
}

String? _safeIdentifier(String value, {required int maximumLength}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > maximumLength) return null;
  return RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(trimmed)
      ? trimmed
      : null;
}

String? _safeDisplayName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty ||
      trimmed.length > 120 ||
      trimmed.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    return null;
  }
  return trimmed;
}

String? _safeHttpUrl(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty || trimmed.length > 2048) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      !(uri.scheme == 'http' || uri.scheme == 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    return null;
  }
  return uri.toString();
}

String? _safeEndpoint(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > 2048 || trimmed.contains(r'\')) {
    return null;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.userInfo.isNotEmpty || uri.hasFragment) return null;
  if (uri.hasScheme) return _safeHttpUrl(trimmed);
  if (trimmed.startsWith('//') || uri.pathSegments.contains('..')) return null;
  return uri.toString();
}

bool _isParameterName(String value) =>
    value.length <= 80 && RegExp(r'^[A-Za-z][A-Za-z0-9_.-]*$').hasMatch(value);

bool _isHeaderName(String value) =>
    value.length <= 80 &&
    RegExp(r"^[!#\$%&'*+.^_`|~0-9A-Za-z-]+$").hasMatch(value);

bool _isSensitiveHeader(String value) {
  final normalized = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return normalized == 'authorization' ||
      normalized == 'proxyauthorization' ||
      normalized == 'cookie' ||
      normalized == 'setcookie' ||
      normalized.contains('apikey') ||
      normalized.contains('token') ||
      normalized.contains('secret') ||
      normalized.contains('password') ||
      normalized.contains('credential');
}
