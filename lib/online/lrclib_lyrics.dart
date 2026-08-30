import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

typedef LrclibHttpClientFactory = HttpClient Function();

class LrclibException implements Exception {
  const LrclibException(
    this.message, {
    this.retryable = false,
    this.statusCode,
  });

  final String message;
  final bool retryable;
  final int? statusCode;

  @override
  String toString() => message;
}

class LrclibRecord {
  const LrclibRecord({
    required this.id,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    required this.durationSeconds,
    required this.instrumental,
    this.plainLyrics,
    this.syncedLyrics,
  });

  final int id;
  final String trackName;
  final String artistName;
  final String albumName;
  final double durationSeconds;
  final bool instrumental;
  final String? plainLyrics;
  final String? syncedLyrics;

  bool get hasLyrics =>
      !instrumental && (syncedLyrics != null || plainLyrics != null);

  Map<String, Object?> toJson() => {
        'id': id,
        'trackName': trackName,
        'artistName': artistName,
        'albumName': albumName,
        'duration': durationSeconds,
        'instrumental': instrumental,
        'plainLyrics': plainLyrics,
        'syncedLyrics': syncedLyrics,
      };
}

/// Anonymous read-only access to LRCLIB's documented search/get endpoints.
///
/// The transport never sends cookies, account identifiers, or audio data.
class LrclibLyricsTransport {
  LrclibLyricsTransport({LrclibHttpClientFactory? httpClientFactory})
      : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  static const _timeout = Duration(seconds: 12);
  static const _responseByteLimit = 2 * 1024 * 1024;

  final LrclibHttpClientFactory _httpClientFactory;

  Future<List<LrclibRecord>> search({
    required String trackName,
    String? artistName,
    String? albumName,
    int limit = 20,
  }) async {
    final title = trackName.trim();
    if (title.isEmpty) return const [];
    final uri = Uri.https('lrclib.net', '/api/search', {
      'track_name': title,
      if (artistName?.trim().isNotEmpty == true)
        'artist_name': artistName!.trim(),
      if (albumName?.trim().isNotEmpty == true) 'album_name': albumName!.trim(),
    });
    final payload = await _getJson(uri);
    return parseLrclibSearchPayload(payload, limit: limit);
  }

  Future<LrclibRecord?> getById(int id) async {
    if (id <= 0) return null;
    final uri = Uri.https('lrclib.net', '/api/get/$id');
    final payload = await _getJson(uri);
    return parseLrclibRecordPayload(payload);
  }

  Future<Object?> _getJson(Uri uri) async {
    final client = _httpClientFactory()..connectionTimeout = _timeout;
    try {
      final request = await client.getUrl(uri).timeout(_timeout);
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'DanPlayer/26.0.3 (anonymous read-only lyrics)',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(_timeout);
      final status = response.statusCode;
      if (status == 408 || status == 429 || status >= 500) {
        throw LrclibException(
          'LRCLIB 服务暂时不可用（HTTP $status）',
          retryable: true,
          statusCode: status,
        );
      }
      if (status == HttpStatus.notFound) return null;
      if (status != HttpStatus.ok) {
        throw LrclibException(
          'LRCLIB 请求失败（HTTP $status）',
          statusCode: status,
        );
      }
      if (response.contentLength > _responseByteLimit) {
        throw const LrclibException('LRCLIB 响应过大，已停止解析');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(_timeout)) {
        if (bytes.length + chunk.length > _responseByteLimit) {
          throw const LrclibException('LRCLIB 响应过大，已停止解析');
        }
        bytes.add(chunk);
      }
      try {
        return jsonDecode(utf8.decode(bytes.takeBytes()));
      } on FormatException {
        throw LrclibException(
          'LRCLIB 返回了无法解析的响应',
          statusCode: status,
        );
      }
    } finally {
      client.close(force: true);
    }
  }
}

List<LrclibRecord> parseLrclibSearchPayload(
  Object? payload, {
  int limit = 20,
}) {
  if (payload is! List) {
    throw const LrclibException('LRCLIB 搜索响应缺少记录列表');
  }
  final records = <LrclibRecord>[];
  for (final value in payload) {
    if (records.length >= limit.clamp(1, 20)) break;
    final record = parseLrclibRecordPayload(value);
    if (record != null && record.hasLyrics) records.add(record);
  }
  return records;
}

LrclibRecord? parseLrclibRecordPayload(Object? payload) {
  if (payload is! Map) return null;
  final id = _positiveInt(payload['id']);
  final trackName = _text(payload['trackName']);
  if (id == null || trackName == null) return null;
  final plain = _text(payload['plainLyrics']);
  final synced = _text(payload['syncedLyrics']);
  return LrclibRecord(
    id: id,
    trackName: trackName,
    artistName: _text(payload['artistName']) ?? '',
    albumName: _text(payload['albumName']) ?? '',
    durationSeconds: _nonNegativeDouble(payload['duration']) ?? 0,
    instrumental: payload['instrumental'] == true,
    plainLyrics: plain,
    syncedLyrics: synced,
  );
}

String? _text(Object? value) {
  if (value is! String) return null;
  final result = value.trim();
  return result.isEmpty || result.toLowerCase() == 'null' ? null : result;
}

int? _positiveInt(Object? value) {
  final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
  return parsed != null && parsed > 0 ? parsed : null;
}

double? _nonNegativeDouble(Object? value) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  return parsed != null && parsed.isFinite && parsed >= 0 ? parsed : null;
}
