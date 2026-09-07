import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/online/qq_public_search.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final netease in [false, true]) {
    final provider = netease ? 'NetEase' : 'QQ';

    test('$provider trickle response cannot extend the whole request deadline',
        () {
      fakeAsync((clock) {
        final harness = _Harness(netease: netease, mode: _Mode.trickle);
        final result = _Result(harness.search());
        clock.flushMicrotasks();
        clock.elapse(const Duration(milliseconds: 900));
        expect(result.done, isFalse);
        expect(harness.clients.single.chunks, greaterThan(1));

        // NetEase retains its one bounded retry. Every attempt has its own
        // deadline, even when response chunks keep arriving without a gap.
        clock.elapse(const Duration(milliseconds: 1400));
        expect(result.done, isTrue);
        expect(
            result.error, netease ? _timedOutSearch : isA<TimeoutException>());
        expect(harness.clients, hasLength(netease ? 2 : 1));
        expect(harness.clients.every((client) => client.forceClosed), isTrue);
        expect(clock.periodicTimerCount, 0);
      });
    });

    for (final mode in [_Mode.pendingHeaders, _Mode.trickle]) {
      test('$provider cancellation during ${mode.name} closes without retry',
          () {
        fakeAsync((clock) {
          final harness = _Harness(netease: netease, mode: mode);
          final token = OnlineSearchCancellation();
          final result = _Result(harness.search(cancellation: token));
          clock.flushMicrotasks();
          if (mode == _Mode.trickle) {
            clock.elapse(const Duration(milliseconds: 250));
            expect(harness.clients.single.chunks, greaterThan(0));
          }
          token.cancel();
          clock.flushMicrotasks();
          expect(result.done, isTrue);
          expect(result.error, _cancelledSearch);
          expect(harness.clients.single.forceClosed, isTrue);
          clock.elapse(const Duration(seconds: 5));
          expect(harness.clients, hasLength(1));
          expect(clock.periodicTimerCount, 0);
        });
      });
    }

    test('$provider pre-cancelled search never creates a client', () {
      fakeAsync((clock) {
        final harness = _Harness(netease: netease, mode: _Mode.success);
        final result = _Result(
            harness.search(cancellation: OnlineSearchCancellation()..cancel()));
        clock.flushMicrotasks();
        expect(result.error, _cancelledSearch);
        expect(harness.clients, isEmpty);
      });
    });

    test('$provider cancelling an old search leaves a fresh search usable', () {
      fakeAsync((clock) {
        final harness = _Harness(netease: netease, mode: _Mode.pendingHeaders);
        final token = OnlineSearchCancellation();
        final old = _Result(harness.search(cancellation: token));
        clock.flushMicrotasks();
        harness.mode = _Mode.success;
        final fresh =
            _Result(harness.search(cancellation: OnlineSearchCancellation()));
        token.cancel();
        clock.flushMicrotasks();
        expect(old.error, _cancelledSearch);
        expect(fresh.done, isTrue);
        expect(fresh.error, isNull);
        expect(harness.clients, hasLength(2));
        expect(harness.clients.every((client) => client.forceClosed), isTrue);
        clock.elapse(const Duration(seconds: 5));
        expect(harness.clients, hasLength(2));
      });
    });
  }

  test('NetEase cancellation during retry backoff never opens the retry', () {
    fakeAsync((clock) {
      final harness = _Harness(netease: true, mode: _Mode.transientError);
      final token = OnlineSearchCancellation();
      final result = _Result(harness.search(cancellation: token));
      clock.flushMicrotasks();
      expect(harness.clients.single.forceClosed, isTrue);
      expect(result.done, isFalse);
      token.cancel();
      clock.flushMicrotasks();
      expect(result.error, _cancelledSearch);
      clock.elapse(const Duration(seconds: 5));
      expect(harness.clients, hasLength(1));
    });
  });
}

final _cancelledSearch = isA<OnlineMusicException>()
    .having((error) => error.kind, 'kind', OnlineMusicFailureKind.unavailable);
final _timedOutSearch = isA<OnlineMusicException>()
    .having((error) => error.kind, 'kind', OnlineMusicFailureKind.timeout);

enum _Mode { trickle, pendingHeaders, transientError, success }

class _Result {
  _Result(Future<Object> future) {
    future.then<void>((_) => done = true, onError: (Object caught) {
      error = caught;
      done = true;
    });
  }

  bool done = false;
  Object? error;
}

class _Harness {
  _Harness({required this.netease, required this.mode});
  final bool netease;
  _Mode mode;
  final clients = <_Client>[];

  _Client _createClient() {
    final client = _Client(mode, netease: netease);
    clients.add(client);
    return client;
  }

  Future<Object> search({OnlineSearchCancellation? cancellation}) {
    if (netease) {
      return OnlineMusicService.forNeteaseTransportTesting(
        httpClientFactory: _createClient,
        requestTimeout: const Duration(seconds: 1),
        retryDelay: const Duration(milliseconds: 220),
      ).search('Synthetic test', cancellation: cancellation);
    }
    return QqPublicSearchTransport(
      httpClientFactory: _createClient,
      requestTimeout: const Duration(seconds: 1),
    ).search('Synthetic test', 20, cancellation: cancellation);
  }
}

class _Client implements HttpClient {
  _Client(this.mode, {required bool netease}) {
    final body = StreamController<List<int>>();
    _body = body;
    if (mode == _Mode.pendingHeaders) return;
    response.complete(_Response(body.stream,
        status: mode == _Mode.transientError ? 500 : 200));
    if (mode == _Mode.trickle) {
      body.onListen = () {
        _chunks = Timer.periodic(const Duration(milliseconds: 100), (_) {
          chunks++;
          body.add([32]);
        });
      };
    } else {
      body.add(utf8.encode(jsonEncode(netease
          ? {
              'code': 200,
              'result': {'songs': []}
            }
          : {
              'code': 0,
              'data': {
                'song': {'list': []}
              }
            })));
      unawaited(body.close());
    }
  }

  final _Mode mode;
  final response = Completer<HttpClientResponse>();
  late final StreamController<List<int>> _body;
  Timer? _chunks;
  int chunks = 0;
  bool forceClosed = false;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _Request(response.future);

  @override
  Future<HttpClientRequest> postUrl(Uri url) async => _Request(response.future);

  @override
  void close({bool force = false}) {
    if (!force || forceClosed) return;
    forceClosed = true;
    _chunks?.cancel();
    if (mode == _Mode.pendingHeaders && !response.isCompleted) {
      response.completeError(const HttpException('Synthetic forced close'));
    }
    if (!_body.isClosed) {
      if (_body.hasListener) {
        _body.addError(const HttpException('Synthetic forced close'));
      }
      unawaited(_body.close());
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.response);
  final Future<HttpClientResponse> response;

  @override
  final HttpHeaders headers = _Headers();

  @override
  bool followRedirects = true;

  @override
  void write(Object? object) {}

  @override
  Future<HttpClientResponse> close() => response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  @override
  ContentType? contentType;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this._stream, {required int status}) : statusCode = status;
  final Stream<List<int>> _stream;

  @override
  int get contentLength => -1;

  @override
  final int statusCode;

  @override
  final HttpHeaders headers = _Headers();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      _stream.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
