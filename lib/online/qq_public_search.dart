import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

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

/// Anonymous, read-only QQ search used when no account cookie is available.
///
/// The dependency's older `DoSearchForQQMusicMobile` request now commonly
/// returns business code 2001. The current mobile request requires a signature
/// over the exact JSON body. No cookie, login identifier, audio URL or paid
/// media key is sent by this transport.
class QqPublicSearchTransport {
  QqPublicSearchTransport({
    QqSearchHttpClientFactory? httpClientFactory,
    DateTime Function()? now,
  })  : _httpClientFactory = httpClientFactory ?? HttpClient.new,
        _now = now ?? DateTime.now;

  static const _timeout = Duration(seconds: 12);
  static const _responseByteLimit = 2 * 1024 * 1024;

  final QqSearchHttpClientFactory _httpClientFactory;
  final DateTime Function() _now;

  Future<List<QqPublicSong>> search(String rawQuery, int rawLimit) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return const [];
    final limit = rawLimit.clamp(1, 30).toInt();
    final searchId = _now().microsecondsSinceEpoch.toString();
    final body = jsonEncode({
      'comm': {
        'ct': '11',
        'cv': '14090508',
        'v': '14090508',
        'tmeAppID': 'qqmusic',
        'phonetype': 'Android',
        'os_ver': '12',
        'OpenUDID': '0',
        'QIMEI36': '0',
        'udid': '0',
        'chid': '0',
        'aid': '0',
        'oaid': '0',
        'taid': '0',
        'tid': '0',
        'wid': '0',
        'uid': '0',
        'sid': '0',
        'modeSwitch': '6',
        'teenMode': '0',
        'ui_mode': '2',
        'nettype': '1020',
      },
      'req': {
        'module': 'music.search.SearchCgiService',
        'method': 'DoSearchForQQMusicMobile',
        'param': {
          'search_type': 0,
          'searchid': searchId,
          'query': query,
          'page_num': 1,
          'num_per_page': limit,
          'highlight': 0,
          'nqc_flag': 0,
          'multi_zhida': 0,
          'cat': 2,
          'grp': 1,
          'sin': 0,
          'sem': 0,
        },
      },
    });
    final signature = qqSearchSignature(body);
    final uri = Uri.https(
      'u.y.qq.com',
      '/cgi-bin/musics.fcg',
      {'sign': signature},
    );
    final client = _httpClientFactory()..connectionTimeout = _timeout;
    try {
      final request = await client.postUrl(uri).timeout(_timeout);
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'QQMusic/14090508 (Android 12; DanPlayer 26.0.3)',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.contentType = ContentType.json;
      request.write(body);
      final response = await request.close().timeout(_timeout);
      final payload = await _readJsonResponse(response);
      return parseQqPublicSearchPayload(payload, limit: limit);
    } finally {
      client.close(force: true);
    }
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
    await for (final chunk in response.timeout(_timeout)) {
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

String qqSearchSignature(String body) {
  final hash = sha1.convert(utf8.encode(body)).toString();
  const firstIndexes = [23, 14, 6, 36, 16, 40, 7, 19];
  const secondIndexes = [16, 1, 32, 12, 19, 27, 8, 5];
  const scramble = [
    89,
    39,
    179,
    150,
    218,
    82,
    58,
    252,
    177,
    52,
    186,
    123,
    120,
    64,
    242,
    133,
    143,
    161,
    121,
    179,
  ];
  // The public web algorithm carries a historical index 40 although a SHA-1
  // hex digest ends at 39. JavaScript implementations append an empty value
  // for that slot; skip it explicitly instead of indexing past the Dart string.
  String pick(List<int> indexes) => indexes
      .where((index) => index >= 0 && index < hash.length)
      .map((index) => hash[index])
      .join();
  final first = pick(firstIndexes);
  final second = pick(secondIndexes);
  final mixed = Uint8List(scramble.length);
  for (var index = 0; index < scramble.length; index++) {
    final byte = int.parse(hash.substring(index * 2, index * 2 + 2), radix: 16);
    mixed[index] = scramble[index] ^ byte;
  }
  final middle = base64Encode(mixed).replaceAll(RegExp(r'[/\\+=]'), '');
  return 'zzc$first$middle$second'.toLowerCase();
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
  if (request is! Map) {
    throw const QqPublicSearchException('QQ音乐搜索响应缺少请求结果');
  }
  _requireCode(request['code'], expected: 0);
  final data = request['data'];
  final body = data is Map ? data['body'] : null;
  final rows = body is Map
      ? body['item_song'] ??
          (body['song'] is Map ? (body['song'] as Map)['list'] : null)
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
    final albumMid =
        albumRow is Map ? _text(albumRow['mid'] ?? albumRow['pmid']) : null;
    final file = row['file'];
    final mediaMid = file is Map
        ? _text(file['media_mid'] ?? file['mediaMid'])
        : _text(row['media_mid']);
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
