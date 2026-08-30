import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/song_comment_association.dart';
// Pinned music_api exposes no public serializer. Reuse its implementation rather
// than copying cryptographic source; keep this adapter covered by request tests.
// ignore: implementation_imports
import 'package:music_api/src/utils/crypto.dart' show weApi;

enum SongCommentSort {
  hot('热门'),
  latest('最新');

  const SongCommentSort(this.label);
  final String label;
}

/// Captured platform identity, never a title/artist search or a local file path.
class SongCommentsTarget {
  const SongCommentsTarget._(this.provider, this.songId);
  final String provider;
  final String songId;

  String get sourceLabel => provider == 'qq' ? 'QQ音乐' : '网易云音乐';
  String get identity => '$provider:$songId';

  static SongCommentsTarget? fromIdentity(CommentSourceIdentity? identity) =>
      identity == null
          ? null
          : SongCommentsTarget._(identity.provider, identity.songId);

  @override
  bool operator ==(Object other) =>
      other is SongCommentsTarget && other.identity == identity;

  @override
  int get hashCode => identity.hashCode;
}

class SongCommentReply {
  const SongCommentReply({required this.author, required this.content});
  final String author;
  final String content;
}

class SongComment {
  const SongComment({
    required this.id,
    required this.author,
    required this.content,
    this.publishedAt,
    this.likeCount = 0,
    this.replies = const [],
  });
  final String id;
  final String author;
  final String content;
  final DateTime? publishedAt;
  final int likeCount;
  final List<SongCommentReply> replies;
}

class SongCommentsPage {
  SongCommentsPage({
    required List<SongComment> comments,
    required this.hasMore,
    required this.page,
    this.reportedTotal,
    this.reachedLimit = false,
  }) : comments = List.unmodifiable(comments);

  final List<SongComment> comments;
  final bool hasMore;
  final int page;
  final int? reportedTotal;
  final bool reachedLimit;
}

enum SongCommentsFailure {
  unavailable,
  network,
  timeout,
  denied,
  invalid,
  limit
}

class SongCommentsException implements Exception {
  const SongCommentsException(this.kind, this.message);
  final SongCommentsFailure kind;
  final String message;
  @override
  String toString() => message;
}

class SongCommentsCancelled implements Exception {
  const SongCommentsCancelled();
}

/// Cancels one dialog request only; it cannot cancel the music API's shared
/// search, artwork, lyric or playback HTTP requests.
class SongCommentsCancellation {
  final _cancelled = Completer<void>();
  final Set<void Function()> _listeners = {};
  bool get isCancelled => _cancelled.isCompleted;

  void cancel() {
    if (isCancelled) return;
    _cancelled.complete();
    for (final listener in List.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  void check() {
    if (isCancelled) throw const SongCommentsCancelled();
  }

  void Function() onCancel(void Function() listener) {
    if (isCancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
    return () => _listeners.remove(listener);
  }

  Future<T> race<T>(Future<T> operation) => Future.any([
        operation,
        _cancelled.future.then<T>((_) => throw const SongCommentsCancelled()),
      ]);
}

abstract interface class SongCommentsTransport {
  Future<Map<String, dynamic>> fetch(
    SongCommentsTarget target, {
    required SongCommentSort sort,
    required int page,
    required SongCommentsCancellation cancellation,
  });
}

/// Official HTTPS read endpoints only. No cookies, account token, remote script,
/// avatars, media, likes or comment-writing request is used by this transport.
class AnonymousSongCommentsTransport implements SongCommentsTransport {
  AnonymousSongCommentsTransport({HttpClient Function()? httpClientFactory})
      : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final HttpClient Function() _httpClientFactory;
  static const responseByteLimit = 1024 * 1024;

  @override
  Future<Map<String, dynamic>> fetch(
    SongCommentsTarget target, {
    required SongCommentSort sort,
    required int page,
    required SongCommentsCancellation cancellation,
  }) async {
    cancellation.check();
    final Uri uri;
    Object? jsonBody;
    Map<String, String>? form;
    if (target.provider == 'qq') {
      if (sort == SongCommentSort.latest) {
        uri = Uri.https(
            'c.y.qq.com', '/base/fcgi-bin/fcg_global_comment_h5.fcg', {
          'biztype': '1',
          'topid': target.songId,
          'cmd': '8',
          'pagenum': '$page',
          'pagesize': '${SongCommentsService.pageSize}',
          'lasthotcommentid': '',
          'domain': 'qq.com',
          'format': 'json',
        });
      } else {
        uri = Uri.https('u.y.qq.com', '/cgi-bin/musicu.fcg');
        jsonBody = {
          'comm': {
            'cv': 4747474,
            'ct': 24,
            'format': 'json',
            'inCharset': 'utf-8',
            'outCharset': 'utf-8',
            'notice': 0,
            'platform': 'yqq.json',
            'needNewCode': 1,
            'uin': 0,
          },
          'req': {
            'module': 'music.globalComment.CommentRead',
            'method': 'GetHotCommentList',
            'param': {
              'BizType': 1,
              'BizId': target.songId,
              'LastCommentSeqNo': '',
              'PageSize': SongCommentsService.pageSize,
              'PageNum': page,
              'HotType': 1,
              'WithAirborne': 0,
              'PicEnable': 1,
            },
          },
        };
      }
    } else {
      final kind = sort == SongCommentSort.hot ? 'hotcomments' : 'comments';
      uri = Uri.https(
          'music.163.com', '/weapi/v1/resource/$kind/R_SO_4_${target.songId}');
      // Reuse the already-pinned dependency's request-format serializer. This
      // carries no credential and neither decrypts nor requests protected audio.
      form = weApi({
        'rid': target.songId,
        'limit': SongCommentsService.pageSize,
        'offset': page * SongCommentsService.pageSize,
        'beforeTime': 0,
        'csrf_token': '',
      });
    }
    cancellation.check();
    final client = _httpClientFactory()
      ..connectionTimeout = SongCommentsService.requestTimeout;
    final removeListener =
        cancellation.onCancel(() => client.close(force: true));
    try {
      final request = jsonBody == null && form == null
          ? await client.getUrl(uri)
          : await client.postUrl(uri);
      cancellation.check();
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader,
          'Mozilla/5.0 DanPlayer/26.0.3 AnonymousComments');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
          HttpHeaders.refererHeader,
          target.provider == 'qq'
              ? 'https://y.qq.com/'
              : 'https://music.163.com/');
      if (form != null) {
        request.headers.contentType = ContentType(
            'application', 'x-www-form-urlencoded',
            charset: 'utf-8');
        request.write(Uri(queryParameters: form).query);
      } else if (jsonBody != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(jsonBody));
      }
      final response = await request.close();
      cancellation.check();
      if (const [401, 403, 429].contains(response.statusCode)) {
        throw const SongCommentsException(
            SongCommentsFailure.denied, '平台暂不允许匿名读取评论或请求过于频繁，请稍后重试。');
      }
      if (response.statusCode != HttpStatus.ok) {
        throw SongCommentsException(SongCommentsFailure.network,
            '评论服务返回 HTTP ${response.statusCode}，请稍后重试。');
      }
      if (response.contentLength > responseByteLimit) {
        throw const FormatException('Comment response exceeds limit');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        cancellation.check();
        if (bytes.length + chunk.length > responseByteLimit) {
          throw const FormatException('Comment response exceeds limit');
        }
        bytes.add(chunk);
      }
      cancellation.check();
      final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Comment response must be an object');
      }
      return decoded;
    } finally {
      removeListener();
      client.close(force: true);
    }
  }
}

class SongCommentsService {
  SongCommentsService({
    SongCommentsTransport? transport,
    Duration timeout = requestTimeout,
  })  : _transport = transport ?? AnonymousSongCommentsTransport(),
        _timeout = timeout;

  static final instance = SongCommentsService();
  static const pageSize = 20;
  static const maxPages = 10;
  static const requestTimeout = Duration(seconds: 12);
  final SongCommentsTransport _transport;
  final Duration _timeout;

  static bool canRead(Audio audio) => unavailableReason(audio) == null;

  static String? unavailableReason(Audio audio) {
    if (!audio.isOnline) {
      final store = SongCommentAssociationStore.instance;
      final association = store.associationFor(audio);
      final identity = store.identityFor(audio);
      if (identity != null) return null;
      if (association?.mode == SongCommentAssociationMode.followLyric) {
        return '当前选择了“跟随联网歌词”，但歌词来源没有可用于评论的 QQ音乐或网易云歌曲 ID。可以重新选择联网歌词，或独立指定歌曲。';
      }
      return '本地歌曲尚未关联评论来源。可以跟随当前联网歌词，或从搜索候选中独立指定一首平台歌曲。';
    }
    if (audio.onlineProvider == 'qq') {
      if ((audio.onlineNumericId ?? 0) <= 0) {
        return '这首 QQ音乐歌曲缺少平台数字 ID，暂时不能读取评论。请从联网搜索结果重新打开。';
      }
      return null;
    }
    if (audio.onlineProvider == 'netease') {
      if (!_positiveId(audio.onlineId)) {
        return '这首网易云音乐歌曲缺少有效的平台歌曲 ID，暂时不能读取评论。';
      }
      return null;
    }
    return '当前仅支持 QQ音乐和网易云音乐的公开只读评论。';
  }

  static SongCommentsTarget? targetFor(Audio audio) {
    if (!canRead(audio)) return null;
    if (audio.isLocal) {
      return SongCommentsTarget.fromIdentity(
        SongCommentAssociationStore.instance.identityFor(audio),
      );
    }
    return SongCommentsTarget._(
        audio.onlineProvider!,
        audio.onlineProvider == 'qq'
            ? '${audio.onlineNumericId}'
            : audio.onlineId!);
  }

  Future<SongCommentsPage> loadPage({
    required SongCommentsTarget target,
    required SongCommentSort sort,
    int page = 0,
    SongCommentsCancellation? cancellation,
  }) async {
    if (page < 0 || page >= maxPages) {
      throw const SongCommentsException(
          SongCommentsFailure.limit, '每个分类最多读取 200 条评论，已停止继续请求。');
    }
    final token = cancellation ?? SongCommentsCancellation();
    token.check();
    try {
      final response = await token
          .race(_transport.fetch(target,
              sort: sort, page: page, cancellation: token))
          .timeout(_timeout);
      token.check();
      return _parse(response, target, sort, page);
    } on TimeoutException {
      token.cancel();
      throw const SongCommentsException(
          SongCommentsFailure.timeout, '评论请求超时，请检查网络后重试。');
    } on SongCommentsCancelled {
      rethrow;
    } on SongCommentsException {
      token.check();
      rethrow;
    } on FormatException {
      token.check();
      throw const SongCommentsException(
          SongCommentsFailure.invalid, '平台返回的评论格式异常或内容过大，暂时无法读取，请稍后重试。');
    } catch (_) {
      token.check();
      throw const SongCommentsException(
          SongCommentsFailure.network, '评论加载失败，请检查网络连接后重试。');
    }
  }

  SongCommentsPage _parse(
      Map response, SongCommentsTarget target, SongCommentSort sort, int page) {
    final qq = target.provider == 'qq';
    final code = _number(response['code']);
    _checkCode(code, qq ? 0 : 200);
    final List rows;
    Object? more;
    int? total;
    if (!qq) {
      rows = _rows(
          response[sort == SongCommentSort.hot ? 'hotComments' : 'comments']);
      more = response[sort == SongCommentSort.hot ? 'hasMore' : 'more'];
      total = _number(response['total']);
    } else if (sort == SongCommentSort.latest) {
      final section = _map(response['comment']);
      rows = _rows(section['commentlist']);
      more = response['morecomment'];
      total = _number(section['commenttotal']);
      // This endpoint can return total=0 alongside real comments and more=1.
      // Do not advertise an invented zero or use it to disable pagination.
      if (total == 0 && rows.isNotEmpty) total = null;
    } else {
      final request = _map(response['req']);
      _checkCode(_number(request['code']), 0);
      final section = _map(_map(request['data'])['CommentList']);
      rows = _rows(section['Comments']);
      more = section['HasMore'];
      total = _number(section['Total']);
    }
    final comments = <SongComment>[];
    final seen = <String>{};
    for (final row in rows.take(pageSize)) {
      if (row is! Map) continue;
      final parsed = qq
          ? _qqComment(row, hot: sort == SongCommentSort.hot)
          : _neteaseComment(row);
      if (parsed != null && seen.add(parsed.id)) comments.add(parsed);
    }
    if (rows.isNotEmpty && comments.isEmpty) {
      throw const FormatException('No recognizable comments in nonempty page');
    }
    final serverHasMore = rows.isNotEmpty &&
        (_flag(more) ??
            (total != null && total > 0
                ? (page + 1) * pageSize < total
                : rows.length >= pageSize));
    final reachedLimit = serverHasMore && page + 1 >= maxPages;
    return SongCommentsPage(
      comments: comments,
      hasMore: serverHasMore && !reachedLimit,
      page: page,
      reportedTotal: total != null && total >= 0 ? total : null,
      reachedLimit: reachedLimit,
    );
  }
}

bool _positiveId(String? value) =>
    value != null &&
    RegExp(r'^[0-9]{1,20}$').hasMatch(value) &&
    BigInt.parse(value) > BigInt.zero;

void _checkCode(int? code, int expected) {
  if (code == expected) return;
  if (code == null) throw const FormatException('Missing response code');
  throw const SongCommentsException(
      SongCommentsFailure.denied, '平台暂时不提供这首歌曲的匿名评论，请稍后重试；不会尝试登录或绕过限制。');
}

Map _map(Object? value) {
  if (value is Map) return value;
  throw const FormatException('Missing comment section');
}

List _rows(Object? value) {
  if (value is List) return value;
  throw const FormatException('Missing comment list');
}

int? _number(Object? value) => switch (value) {
      int number => number,
      String text => int.tryParse(text),
      _ => null,
    };

bool? _flag(Object? value) => switch (value) {
      true || 1 || '1' || 'true' => true,
      false || 0 || '0' || 'false' => false,
      _ => null,
    };

String _text(Object? value) => value is String
    ? value.replaceAll('\r\n', '\n').replaceAll(r'\n', '\n').trim()
    : '';

String? _id(Object? value) {
  final id = value is String || value is int ? value.toString() : '';
  return _positiveId(id) ? id : null;
}

DateTime? _timestamp(Object? value, {bool seconds = false}) {
  final time = _number(value);
  if (time == null || time <= 0) return null;
  // Check before multiplying: native Dart's int64 arithmetic can wrap large
  // remote second values into a plausible but false date around the epoch.
  if (time > (seconds ? 8640000000000 : 8640000000000000)) return null;
  try {
    return DateTime.fromMillisecondsSinceEpoch(seconds ? time * 1000 : time);
  } on ArgumentError {
    return null;
  }
}

int _likes(Object? value) => (_number(value) ?? 0).clamp(0, 0x7fffffff);

SongComment? _neteaseComment(Map row) {
  final id = _id(row['commentId']);
  final text = _text(row['content']);
  if (id == null || text.isEmpty) return null;
  final user = row['user'];
  final author = user is Map ? _text(user['nickname']) : '';
  final replies = <SongCommentReply>[];
  final quoted = row['beReplied'];
  if (quoted is List) {
    for (final item in quoted.take(3)) {
      if (item is! Map) continue;
      final content = _text(item['content']);
      if (content.isEmpty) continue;
      final user = item['user'];
      final author = user is Map ? _text(user['nickname']) : '';
      replies.add(SongCommentReply(
          author: author.isEmpty ? '平台用户' : author, content: content));
    }
  }
  return SongComment(
    id: id,
    author: author.isEmpty ? '平台用户' : author,
    content: text,
    publishedAt: _timestamp(row['time']),
    likeCount: _likes(row['likedCount']),
    replies: List.unmodifiable(replies),
  );
}

SongComment? _qqComment(Map row, {required bool hot}) {
  final id = _id(row[hot ? 'CmId' : 'commentid']);
  final rootId = _id(row[hot ? 'SeqNo' : 'rootcommentid']) ?? id;
  final text = _text(row[hot ? 'Content' : 'rootcommentcontent']);
  if (id == null || text.isEmpty) return null;
  final author = _text(row[hot ? 'Nick' : 'rootcommentnick']);
  final replies = <SongCommentReply>[];
  final quoted = row[hot ? 'SubComments' : 'middlecommentcontent'];
  if (quoted is List) {
    for (final item in quoted.take(3)) {
      if (item is! Map) continue;
      final content = _text(item[hot ? 'Content' : 'subcommentcontent']);
      if (content.isEmpty) continue;
      final author = _text(item[hot ? 'Nick' : 'replynick']);
      replies.add(SongCommentReply(
          author: author.isEmpty ? '平台用户' : author, content: content));
    }
  }
  return SongComment(
    id: '$rootId:$id',
    author: author.isEmpty ? '平台用户' : author,
    content: text,
    // Latest feed activity can be a reply: its timestamp is not the root's.
    publishedAt: hot || rootId == id
        ? _timestamp(row[hot ? 'PubTime' : 'time'], seconds: true)
        : null,
    likeCount: _likes(row[hot ? 'PraiseNum' : 'praisenum']),
    replies: List.unmodifiable(replies),
  );
}
