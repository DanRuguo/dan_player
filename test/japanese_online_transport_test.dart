import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/lyric/japanese_online_readings.dart';
import 'package:dan_player/lyric/japanese_phonetic_channel.dart';
import 'package:dan_player/lyric/japanese_reading_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

class _LoopbackHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late JapaneseOnlineReadingAnalyzer analyzer;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    analyzer = JapaneseOnlineReadingAnalyzer(
        httpClientFactory: () => _LoopbackHttpOverrides().createHttpClient(null)
          ..findProxy = (_) => 'DIRECT',
        endpoint: Uri.http('127.0.0.1:${server.port}', '/jsonrpc'),
        timeout: const Duration(seconds: 2));
  });
  tearDown(() async {
    analyzer.cancel();
    await server.close(force: true);
  });

  test('real HTTP sends documented POST/header and reads bounded JSON',
      () async {
    final handled = Completer<void>();
    server.listen((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/jsonrpc');
      expect(request.headers.value(HttpHeaders.userAgentHeader),
          'Yahoo AppID: isolated-client');
      expect(request.headers.contentType?.mimeType, 'application/json');
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'jsonrpc': '2.0',
        'id': body['id'],
        'result': {
          'word': [
            {'surface': '夜空', 'furigana': 'よぞら'}
          ]
        }
      }));
      await request.response.close();
      handled.complete();
    });
    final result = await analyzer
        .analyze(['夜空'], clientId: 'isolated-client', stillCurrent: () => true);
    expect(result.available, isTrue);
    expect(result.words.single!.single.reading, 'よぞら');
    await handled.future;
  });

  test('redirects are rejected without forwarding the identifier', () async {
    var requests = 0;
    server.listen((request) async {
      requests++;
      await request.drain<void>();
      request.response.statusCode = 302;
      request.response.headers.set(HttpHeaders.locationHeader,
          'http://127.0.0.1:${server.port}/redirected');
      await request.response.close();
    });
    expect(
        (await analyzer.analyze(['夜空'],
                clientId: 'isolated-client', stillCurrent: () => true))
            .available,
        isFalse);
    expect(requests, 1);
  });

  test('streamed oversize response is bounded without a content length',
      () async {
    final done = Completer<void>();
    server.listen((request) async {
      try {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.contentLength = -1;
        request.response.add(List.filled(70 * 1024, 32));
        await request.response.close();
      } catch (_) {/* The bounded client closes the socket. */} finally {
        done.complete();
      }
    });
    expect(
        (await analyzer.analyze(['夜空'],
                clientId: 'isolated-client', stillCurrent: () => true))
            .available,
        isFalse);
    await done.future;
  });

  test('real in-flight socket is aborted on cancellation', () async {
    final received = Completer<void>();
    server.listen((request) async {
      await request.drain<void>();
      received.complete();
    });
    final pending = analyzer
        .analyze(['夜空'], clientId: 'isolated-client', stillCurrent: () => true);
    await received.future;
    analyzer.cancel();
    expect((await pending).available, isFalse);
  });

  test('automatic offline result is discarded after permission closes mid work',
      () async {
    var allowed = true;
    final native = Completer<JapanesePhoneticBatch>();
    final policy = JapaneseReadingAnalyzerPolicy(
        onlineAllowed: () => allowed,
        clientId: () => '',
        offline: (_) => native.future,
        cancelOffline: () {},
        hasDictionary: () async => true);
    final pending = policy.analyze(['夜空']);
    await Future<void>.delayed(Duration.zero);
    allowed = false;
    native.complete(const JapanesePhoneticBatch([
      [JapanesePhoneticWord('夜空', 'よぞら')]
    ]));
    expect((await pending).available, isFalse);
    policy.dispose();
  });
}
