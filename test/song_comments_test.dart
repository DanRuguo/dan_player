import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/online/song_comments.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/song_comments_fixtures.dart';

Matcher failure(SongCommentsFailure kind) =>
    throwsA(isA<SongCommentsException>()
        .having((error) => error.kind, 'kind', kind)
        .having(
            (error) => error.message.isNotEmpty, 'readable message', isTrue));

Future<SongCommentsPage> read(
  SongCommentsService service, {
  String provider = 'netease',
  SongCommentSort sort = SongCommentSort.hot,
  int page = 0,
  SongCommentsCancellation? cancellation,
}) =>
    service.loadPage(
        target:
            SongCommentsService.targetFor(commentAudio(provider: provider))!,
        sort: sort,
        page: page,
        cancellation: cancellation);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('availability is exact ID based, never title based or local path based',
      () {
    expect(SongCommentsService.canRead(localCommentAudio()), isFalse);
    expect(SongCommentsService.targetFor(localCommentAudio()), isNull);
    expect(
        SongCommentsService.canRead(
            commentAudio(provider: 'qq', numericId: null)),
        isFalse);
    expect(
        SongCommentsService.canRead(
            commentAudio(provider: 'qq', numericId: -1)),
        isFalse);
    expect(SongCommentsService.canRead(commentAudio(provider: 'unknown')),
        isFalse);
    for (final id in [
      '',
      '0',
      '-1',
      'song-name',
      '123/456',
      'https://example.com',
      ' 123',
      '9' * 21
    ]) {
      expect(SongCommentsService.canRead(commentAudio(id: id)), isFalse,
          reason: id);
    }
    expect(
        SongCommentsService.targetFor(commentAudio())!.identity, 'netease:123');
    expect(
        SongCommentsService.targetFor(
                commentAudio(provider: 'qq', id: 'songmid'))!
            .identity,
        'qq:456');
    expect(SongCommentsService.targetFor(commentAudio()),
        isNot(SongCommentsService.targetFor(commentAudio(id: '124'))));
  });

  test('constructor and availability never start network requests', () {
    final transport =
        FakeCommentsTransport((_) => throw StateError('must not request'));
    SongCommentsService(transport: transport);
    SongCommentsService.canRead(commentAudio());
    SongCommentsService.unavailableReason(localCommentAudio());
    expect(transport.requests, isEmpty);
  });

  test(
      'QQ latest uses the exact numeric ID over HTTPS with no auth or redirects',
      () async {
    final client =
        _Client(_Response.json(qqLatestComments([qqLatestComment(1)])));
    final service = SongCommentsService(
        transport:
            AnonymousSongCommentsTransport(httpClientFactory: () => client));
    await read(service, provider: 'qq', sort: SongCommentSort.latest, page: 2);
    expect(client.method, 'GET');
    expect(client.uri!.scheme, 'https');
    expect(client.uri!.host, 'c.y.qq.com');
    expect(client.uri!.path, '/base/fcgi-bin/fcg_global_comment_h5.fcg');
    expect(client.uri!.queryParameters, containsPair('topid', '456'));
    expect(client.uri!.queryParameters, containsPair('pagenum', '2'));
    expect(client.uri!.queryParameters, containsPair('cmd', '8'));
    expect(client.request.followRedirects, isFalse);
    expect(client.request.headers.values.keys, isNot(contains('cookie')));
    expect(
        client.request.headers.values.keys, isNot(contains('authorization')));
    expect(client.closed, isTrue);
  });

  test('QQ hot uses only the public read method, not comment or like writes',
      () async {
    final client = _Client(_Response.json(qqHotComments([qqHotComment(1)])));
    final service = SongCommentsService(
        transport:
            AnonymousSongCommentsTransport(httpClientFactory: () => client));
    await read(service, provider: 'qq', page: 3);
    expect(client.method, 'POST');
    expect(client.uri, Uri.https('u.y.qq.com', '/cgi-bin/musicu.fcg'));
    final body = jsonDecode(client.request.body.toString()) as Map;
    expect(body['comm']['uin'], 0);
    expect(body['req']['module'], 'music.globalComment.CommentRead');
    expect(body['req']['method'], 'GetHotCommentList');
    expect(body['req']['param']['BizId'], '456');
    expect(body['req']['param']['PageNum'], 3);
    expect(body['req']['param']['PageSize'], 20);
    expect(client.request.headers.values.keys, isNot(contains('cookie')));
    expect(client.closed, isTrue);
  });

  for (final sort in SongCommentSort.values) {
    test(
        'NetEase ${sort.name} uses pinned request encoding and sends no cookie',
        () async {
      final client = _Client(
          _Response.json(neteaseComments([neteaseComment(1)], sort: sort)));
      final service = SongCommentsService(
          transport:
              AnonymousSongCommentsTransport(httpClientFactory: () => client));
      await read(service, sort: sort);
      final kind = sort == SongCommentSort.hot ? 'hotcomments' : 'comments';
      expect(client.method, 'POST');
      expect(client.uri,
          Uri.https('music.163.com', '/weapi/v1/resource/$kind/R_SO_4_123'));
      final form = Uri.splitQueryString(client.request.body.toString());
      expect(form.keys.toSet(), {'params', 'encSecKey'});
      expect(form.values.every((value) => value.isNotEmpty), isTrue);
      expect(client.request.headers.contentType!.mimeType,
          'application/x-www-form-urlencoded');
      expect(client.request.headers.values.keys, isNot(contains('cookie')));
      expect(
          client.request.headers.values.keys, isNot(contains('authorization')));
      expect(client.closed, isTrue);
    });
  }

  test(
      'NetEase parser preserves long selectable text and bounded inline quotes',
      () async {
    final row = neteaseComment(7,
        content: '${'长评论 ' * 600}\n<script>not executable</script>')
      ..['beReplied'] = List.generate(
          8,
          (i) => {
                'content': '引用$i',
                'user': {'nickname': '作者$i'}
              });
    final transport = FakeCommentsTransport(
        (_) => neteaseComments([row], more: true, total: 1234));
    final result = await read(SongCommentsService(transport: transport));
    final comment = result.comments.single;
    expect(comment.id, '7');
    expect(comment.author, '测试用户 7');
    expect(comment.content, row['content']);
    expect(comment.publishedAt!.millisecondsSinceEpoch, 1700000000000);
    expect(comment.likeCount, 5);
    expect(comment.replies, hasLength(3));
    expect(result.reportedTotal, 1234);
    expect(result.hasMore, isTrue);
    expect(() => result.comments.clear(), throwsUnsupportedError);
    expect(() => comment.replies.clear(), throwsUnsupportedError);
  });

  test(
      'QQ latest keeps complete nickname and avoids dating root with reply time',
      () async {
    final row = qqLatestComment(2, rootId: 1, content: r'第一行\n第二行')
      ..['middlecommentcontent'] = [
        {'replynick': '完整回复者', 'subcommentcontent': '回复正文'}
      ];
    final transport = FakeCommentsTransport(
        (_) => qqLatestComments([row], more: true, total: 0));
    final result = await read(SongCommentsService(transport: transport),
        provider: 'qq', sort: SongCommentSort.latest);
    expect(result.comments.single.id, '1:2');
    expect(result.comments.single.author, '完整昵称 2');
    expect(result.comments.single.content, '第一行\n第二行');
    expect(result.comments.single.publishedAt, isNull);
    expect(result.comments.single.replies.single.author, '完整回复者');
    expect(result.reportedTotal, isNull);
    expect(result.hasMore, isTrue);
  });

  test('QQ hot handles string IDs, real seconds, and plain inline replies',
      () async {
    final row = qqHotComment(9)
      ..['SubComments'] = [
        {'Nick': '回复者', 'Content': '回复'}
      ];
    final transport = FakeCommentsTransport((_) => qqHotComments([row]));
    final result =
        await read(SongCommentsService(transport: transport), provider: 'qq');
    expect(result.comments.single.id, '1009:9');
    expect(result.comments.single.publishedAt!.millisecondsSinceEpoch,
        1700000000000);
    expect(result.comments.single.likeCount, 7);
    expect(result.comments.single.replies.single.content, '回复');
  });

  for (final sort in [SongCommentSort.hot, SongCommentSort.latest]) {
    test('QQ ${sort.name} accepts current opaque comment IDs and deduplicates',
        () async {
      const opaque = '1!mQ8MxfPOoL1FDVd8YQgZzk4NZxID28zSXzS63Rzn0xG.test-*';
      final hot = sort == SongCommentSort.hot;
      final row = hot ? qqHotComment(1) : qqLatestComment(1);
      row[hot ? 'CmId' : 'commentid'] = opaque;
      row[hot ? 'SeqNo' : 'rootcommentid'] =
          hot ? '1274150547095562240' : opaque;
      final invalid = Map<String, dynamic>.of(row)
        ..[hot ? 'CmId' : 'commentid'] = 'bad\nidentifier';
      final response = hot
          ? qqHotComments([row, row, invalid])
          : qqLatestComments([row, row, invalid]);
      final result = await read(
        SongCommentsService(transport: FakeCommentsTransport((_) => response)),
        provider: 'qq',
        sort: sort,
      );
      expect(result.comments, hasLength(1));
      expect(result.comments.single.id, endsWith(':$opaque'));
      expect(result.comments.single.content,
          row[hot ? 'Content' : 'rootcommentcontent']);
      expect(result.comments.single.publishedAt, isNotNull);
    });
  }

  test('QQ remote seconds cannot wrap into a fake epoch date', () async {
    for (final sort in SongCommentSort.values) {
      final transport = FakeCommentsTransport((_) {
        if (sort == SongCommentSort.hot) {
          return qqHotComments(
              [qqHotComment(1)..['PubTime'] = '18446744073709552']);
        }
        return qqLatestComments(
            [qqLatestComment(1)..['time'] = '18446744073709552']);
      });
      final result = await read(SongCommentsService(transport: transport),
          provider: 'qq', sort: sort);
      expect(result.comments.single.publishedAt, isNull);
    }
  });

  test('invalid optional fields are tolerated without inventing user or time',
      () async {
    final row = neteaseComment(1)
      ..['time'] = '9999999999999999999'
      ..['likedCount'] = -10
      ..['user'] = null
      ..['beReplied'] = 'invalid';
    final transport = FakeCommentsTransport((_) => neteaseComments([row]));
    final result = await read(SongCommentsService(transport: transport));
    expect(result.comments.single.author, '平台用户');
    expect(result.comments.single.publishedAt, isNull);
    expect(result.comments.single.likeCount, 0);
    expect(result.comments.single.replies, isEmpty);
  });

  test(
      'duplicate IDs within a page are removed, malformed rows do not replace real ones',
      () async {
    final response = neteaseComments([
      neteaseComment(1),
      neteaseComment(1),
      {'commentId': 'bad'},
      neteaseComment(2)
    ]);
    final transport = FakeCommentsTransport((_) => response);
    final result = await read(SongCommentsService(transport: transport));
    expect(result.comments.map((comment) => comment.id), ['1', '2']);
  });

  test('empty success differs from broken/missing comment response', () async {
    final transport = FakeCommentsTransport((_) => neteaseComments([]));
    final service = SongCommentsService(transport: transport);
    final empty = await read(service);
    expect(empty.comments, isEmpty);
    expect(empty.hasMore, isFalse);
    for (final invalid in <Map<String, dynamic>>[
      {},
      {'code': 200},
      {'code': 200, 'hotComments': null},
      neteaseComments([
        {'commentId': 0, 'content': 'invalid ID'}
      ]),
    ]) {
      transport.handler = (_) => invalid;
      await expectLater(read(service), failure(SongCommentsFailure.invalid));
    }
  });

  test('business denial is a retryable error, never an empty success',
      () async {
    final transport = FakeCommentsTransport(
        (_) => {'code': 301, 'message': 'login required'});
    await expectLater(read(SongCommentsService(transport: transport)),
        failure(SongCommentsFailure.denied));
    transport.handler = (_) => {
          'code': 0,
          'req': {'code': 401}
        };
    await expectLater(
        read(SongCommentsService(transport: transport), provider: 'qq'),
        failure(SongCommentsFailure.denied));
  });

  test('maximum page and response row limits bound requests and memory',
      () async {
    final transport = FakeCommentsTransport((_) => neteaseComments(
        List.generate(40, (i) => neteaseComment(i + 1)),
        more: true));
    final service = SongCommentsService(transport: transport);
    final last = await read(service, page: 9);
    expect(last.comments, hasLength(20));
    expect(last.hasMore, isFalse);
    expect(last.reachedLimit, isTrue);
    for (final page in [-1, 10, 1000]) {
      await expectLater(
          read(service, page: page), failure(SongCommentsFailure.limit));
    }
    expect(transport.requests, hasLength(1));
  });

  test('precancelled request opens no client', () async {
    var opened = 0;
    final service = SongCommentsService(
        transport: AnonymousSongCommentsTransport(httpClientFactory: () {
      opened++;
      return _Client(_Response.json(neteaseComments([])));
    }));
    final token = SongCommentsCancellation()..cancel();
    await expectLater(read(service, cancellation: token),
        throwsA(isA<SongCommentsCancelled>()));
    expect(opened, 0);
  });

  test('cancelled request settles promptly and never cancels another request',
      () async {
    final first = Completer<Map<String, dynamic>>();
    final second = Completer<Map<String, dynamic>>();
    final transport = FakeCommentsTransport(
        (request) => request.page == 0 ? first.future : second.future);
    final service = SongCommentsService(transport: transport);
    final token = SongCommentsCancellation();
    final a = read(service, cancellation: token);
    final b = read(service, page: 1);
    final cancelled = expectLater(a, throwsA(isA<SongCommentsCancelled>()));
    token.cancel();
    await cancelled;
    expect(transport.requests.last.cancellation.isCancelled, isFalse);
    second.complete(neteaseComments([neteaseComment(2)]));
    expect((await b).comments.single.id, '2');
    first.complete(neteaseComments([neteaseComment(1)]));
  });

  test(
      'timeout closes the request and reports a readable timeout, not cancellation',
      () async {
    final response = Completer<HttpClientResponse>();
    final client = _Client(null, response: response.future);
    final service = SongCommentsService(
      transport:
          AnonymousSongCommentsTransport(httpClientFactory: () => client),
      timeout: const Duration(milliseconds: 10),
    );
    await expectLater(read(service), failure(SongCommentsFailure.timeout));
    expect(client.closed, isTrue);
    response.complete(_Response.json(neteaseComments([])));
  });

  test('cancel during body streaming closes only that owned HTTP client',
      () async {
    final stream = StreamController<List<int>>();
    final response = _Response([], stream: stream.stream);
    final client = _Client(response);
    final service = SongCommentsService(
        transport:
            AnonymousSongCommentsTransport(httpClientFactory: () => client));
    final token = SongCommentsCancellation();
    final result = expectLater(read(service, cancellation: token),
        throwsA(isA<SongCommentsCancelled>()));
    await Future<void>.delayed(Duration.zero);
    token.cancel();
    await result;
    expect(client.closed, isTrue);
    await stream.close();
  });

  for (final status in [401, 403, 429, 302, 500]) {
    test('HTTP $status neither follows redirects nor silently empties comments',
        () async {
      final client = _Client(_Response([], status: status));
      final service = SongCommentsService(
          transport:
              AnonymousSongCommentsTransport(httpClientFactory: () => client));
      await expectLater(
          read(service),
          failure([401, 403, 429].contains(status)
              ? SongCommentsFailure.denied
              : SongCommentsFailure.network));
      expect(client.closed, isTrue);
      expect(client.requests, 1);
    });
  }

  for (final knownLength in [true, false]) {
    test(
        'oversized ${knownLength ? 'declared' : 'streamed'} response is rejected',
        () async {
      const limit = AnonymousSongCommentsTransport.responseByteLimit;
      final client = _Client(_Response(
          knownLength ? [] : List.filled(limit + 1, 32),
          length: knownLength ? limit + 1 : -1));
      final service = SongCommentsService(
          transport:
              AnonymousSongCommentsTransport(httpClientFactory: () => client));
      await expectLater(read(service), failure(SongCommentsFailure.invalid));
      expect(client.closed, isTrue);
    });
  }

  test(
      'bad JSON, nonobject JSON and socket failure have explicit failure kinds',
      () async {
    for (final body in ['not json', '[]', '']) {
      final client = _Client(_Response(utf8.encode(body)));
      final service = SongCommentsService(
          transport:
              AnonymousSongCommentsTransport(httpClientFactory: () => client));
      await expectLater(read(service), failure(SongCommentsFailure.invalid));
      expect(client.closed, isTrue);
    }
    final transport =
        FakeCommentsTransport((_) => throw const SocketException('offline'));
    await expectLater(read(SongCommentsService(transport: transport)),
        failure(SongCommentsFailure.network));
  });
}

class _Client implements HttpClient {
  _Client(_Response? value, {Future<HttpClientResponse>? response})
      : request = _Request(response ?? Future.value(value!));
  final _Request request;
  Uri? uri;
  String? method;
  int requests = 0;
  bool closed = false;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    uri = url;
    method = 'GET';
    requests++;
    return request;
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    uri = url;
    method = 'POST';
    requests++;
    return request;
  }

  @override
  void close({bool force = false}) => closed = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.response);
  final Future<HttpClientResponse> response;
  final body = StringBuffer();
  @override
  final _Headers headers = _Headers();
  @override
  bool followRedirects = true;
  @override
  void write(Object? object) => body.write(object);
  @override
  Future<HttpClientResponse> close() => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  final values = <String, Object>{};
  @override
  ContentType? contentType;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      values[name.toLowerCase()] = value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(List<int> bytes,
      {int? length, int status = 200, Stream<List<int>>? stream})
      : contentLength = length ?? bytes.length,
        statusCode = status,
        _stream = stream ?? Stream.value(bytes);
  factory _Response.json(Map<String, dynamic> data) =>
      _Response(utf8.encode(jsonEncode(data)));
  final Stream<List<int>> _stream;
  @override
  final int contentLength;
  @override
  final int statusCode;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      _stream.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
