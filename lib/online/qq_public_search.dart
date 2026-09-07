import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dan_player/online/online_http_request.dart';

typedef QqSearchHttpClientFactory = HttpClient Function();

class QqPublicSearchException implements Exception {
  const QqPublicSearchException(
    this.message, {
    this.retryable = false,
    this.serviceCode,
  });

  final String message;
  final bool retryable;
  final int? serviceCode;

  @override
  String toString() => message;
}

class QqPublicSong {
  const QqPublicSong({
    required this.title,
    required this.mid,
    this.numericId,
    this.artists = '',
    this.album = '',
    this.albumMid,
    this.mediaMid,
    this.durationSeconds = 0,
  });

  final String title;
  final String mid;
  final int? numericId;
  final String artists;
  final String album;
  final String? albumMid;
  final String? mediaMid;
  final int durationSeconds;

  Map<String, Object?> toMusicApiSearchRow() => {
        'id': numericId,
        'mid': mid,
        'name': title,
        'singer': [
          for (final name in artists
              .split(RegExp(r'[、/]'))
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty))
            {'name': name},
        ],
        'album': {'title': album, 'mid': albumMid},
        'file': {'media_mid': mediaMid},
        'interval': durationSeconds,
      };
}

/// Anonymous, read-only QQ search using the public client search endpoint.
/// The mobile MusicU route now returns code 2001 with a login feedback URL.
/// Keep the public endpoint's song IDs, media IDs and metadata together so
/// search, comments, lyrics and playback refer to the same selected song.
class QqPublicSearchTransport {
  QqPublicSearchTransport({
    QqSearchHttpClientFactory? httpClientFactory,
    this.requestTimeout = const Duration(seconds: 12),
  })  : assert(requestTimeout > Duration.zero),
        _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final Duration requestTimeout;
  static const _responseByteLimit = 2 * 1024 * 1024;
  final QqSearchHttpClientFactory _httpClientFactory;

  Future<List<QqPublicSong>> search(String rawQuery, int rawLimit,
      {OnlineHttpCancellation? cancellation}) async {
    cancellation?.check();
    final query = rawQuery.trim();
    if (query.isEmpty) return const [];
    final limit = rawLimit.clamp(1, 30).toInt();
    final uri = Uri.https('c.y.qq.com', '/soso/fcgi-bin/client_search_cp', {
      'format': 'json',
      'n': '$limit',
      'p': '1',
      'w': query,
      'cr': '1',
      'g_tk': '5381',
      't': '0',
    });
    return runBoundedOnlineRequest(
        createClient: _httpClientFactory,
        timeout: requestTimeout,
        cancellation: cancellation,
        request: (client) async {
          final request = await client.getUrl(uri);
          request.followRedirects = false;
          request.headers.set(HttpHeaders.userAgentHeader,
              'Mozilla/5.0 DanPlayer/26.0.4 PublicSearch');
          request.headers.set(HttpHeaders.acceptHeader, 'application/json');
          request.headers.set(HttpHeaders.refererHeader, 'https://y.qq.com/');
          final response = await request.close();
          final payload = await _readJsonResponse(response);
          return parseQqPublicSearchPayload(payload, limit: limit);
        });
  }

  Future<Object?> _readJsonResponse(HttpClientResponse response) async {
    final status = response.statusCode;
    if (status == 408 || status == 429 || status >= 500) {
      throw QqPublicSearchException(
        'QQ音乐搜索服务暂时不可用（HTTP $status）',
        retryable: true,
        serviceCode: status,
      );
    }
    if (status != HttpStatus.ok) {
      throw QqPublicSearchException(
        'QQ音乐搜索失败（HTTP $status）',
        serviceCode: status,
      );
    }
    if (response.contentLength > _responseByteLimit) {
      throw const QqPublicSearchException('QQ音乐搜索响应过大，已停止解析');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (bytes.length + chunk.length > _responseByteLimit) {
        throw const QqPublicSearchException('QQ音乐搜索响应过大，已停止解析');
      }
      bytes.add(chunk);
    }
    try {
      return jsonDecode(utf8.decode(bytes.takeBytes()));
    } on FormatException {
      throw QqPublicSearchException(
        'QQ音乐返回了无法解析的搜索响应',
        serviceCode: status,
      );
    }
  }
}

List<QqPublicSong> parseQqPublicSearchPayload(
  Object? payload, {
  int limit = 30,
}) {
  if (payload is! Map) {
    throw const QqPublicSearchException('QQ音乐返回了非对象搜索响应');
  }
  _requireCode(payload['code'], expected: 0);
  final request = payload['req'] ?? payload['req_1'];
  final publicData = payload['data'];
  if (request is! Map && publicData is! Map) {
    throw const QqPublicSearchException('QQ音乐搜索响应缺少请求结果');
  }
  if (request is Map) _requireCode(request['code'], expected: 0);
  final data = request is Map ? request['data'] : publicData;
  final body = data is Map ? data['body'] : null;
  final rows = body is Map
      ? body['item_song'] ??
          (body['song'] is Map ? (body['song'] as Map)['list'] : null)
      : data is Map && data['song'] is Map
          ? (data['song'] as Map)['list']
          : null;
  if (rows is! List) {
    throw const QqPublicSearchException('QQ音乐搜索响应缺少歌曲列表');
  }
  final result = <QqPublicSong>[];
  for (final raw in rows) {
    if (result.length >= limit) break;
    if (raw is! Map) continue;
    final nested =
        raw['track_info'] ?? raw['songInfo'] ?? raw['songinfo'] ?? raw['song'];
    final row = nested is Map ? nested : raw;
    final title = _text(row['name'] ?? row['title'] ?? row['songname']);
    final mid = _text(row['mid'] ?? row['songmid']);
    if (title == null || mid == null) continue;
    final singerRows = row['singer'] ?? row['singers'];
    final artists = singerRows is List
        ? singerRows
            .map((value) => value is Map ? _text(value['name']) : _text(value))
            .whereType<String>()
            .join('、')
        : _text(singerRows) ?? '';
    final albumRow = row['album'];
    final album = albumRow is Map
        ? _text(albumRow['name'] ?? albumRow['title']) ?? ''
        : _text(albumRow) ?? _text(row['albumname']) ?? '';
    final albumMid = albumRow is Map
        ? _text(albumRow['mid'] ?? albumRow['pmid'])
        : _text(row['albummid']);
    final file = row['file'];
    final mediaMid = file is Map
        ? _text(file['media_mid'] ?? file['mediaMid'])
        : _text(row['media_mid'] ?? row['strMediaMid']);
    result.add(QqPublicSong(
      title: title,
      mid: mid,
      numericId: _positiveInt(row['id'] ?? row['songid']),
      artists: artists,
      album: album,
      albumMid: albumMid,
      mediaMid: mediaMid,
      durationSeconds: _positiveInt(row['interval']) ?? 0,
    ));
  }
  return result;
}

void _requireCode(Object? raw, {required int expected}) {
  if (raw == null) return;
  final code = _integer(raw);
  if (code == expected) return;
  if (code == null) {
    throw const QqPublicSearchException('QQ音乐返回了无法识别的服务状态');
  }
  throw QqPublicSearchException(
    code == 2001 ? 'QQ音乐请求遇到临时服务状态（代码 2001）' : 'QQ音乐请求失败（服务代码 $code）',
    retryable: code == 2001 ||
        code == 408 ||
        code == 429 ||
        (code >= 500 && code <= 599),
    serviceCode: code,
  );
}

String? _text(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty || text.toLowerCase() == 'null' ? null : text;
}

int? _integer(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.toInt()) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

int? _positiveInt(Object? value) {
  final parsed = _integer(value);
  return parsed != null && parsed > 0 ? parsed : null;
}
