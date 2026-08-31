import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dan_player/update/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github/github.dart';
import 'package:path/path.dart' as path;

void main() {
  group('AppVersion', () {
    test('compares each numeric component instead of concatenating digits', () {
      final newer = AppVersion.tryParse('v26.0.10');
      final older = AppVersion.tryParse('26.0.3');

      expect(newer, isNotNull);
      expect(older, isNotNull);
      expect(newer!.compareTo(older!), greaterThan(0));
    });

    test('stable releases sort after pre-releases', () {
      final stable = AppVersion.tryParse('26.0.3');
      final candidate = AppVersion.tryParse('26.0.3-rc.2');

      expect(stable!.compareTo(candidate!), greaterThan(0));
      expect(candidate.toString(), '26.0.3-rc.2');
    });

    test('rejects malformed release tags', () {
      expect(AppVersion.tryParse('release-latest'), isNull);
      expect(AppVersion.tryParse('26.3'), isNull);
    });
  });

  group('update assets', () {
    test('prefers a Windows installer over source and portable archives', () {
      final selected = UpdateService.instance.selectWindowsAsset(
        [
          ReleaseAsset(
            name: 'source.zip',
            browserDownloadUrl: 'https://github.com/example/source.zip',
          ),
          ReleaseAsset(
            name: 'dan-player-portable.zip',
            browserDownloadUrl: 'https://github.com/example/portable.zip',
          ),
          ReleaseAsset(
            name: 'DanPlayer-26.0.4-Setup-x64.exe',
            browserDownloadUrl: 'https://github.com/example/setup.exe',
          ),
        ],
        architecture: 'x64',
      );

      expect(selected?.name, 'DanPlayer-26.0.4-Setup-x64.exe');
    });

    test('rejects non-Windows archives and the wrong architecture', () {
      final selected = UpdateService.instance.selectWindowsAsset(
        [
          ReleaseAsset(
            name: 'dan-player-macos-x64.zip',
            browserDownloadUrl: 'https://github.com/example/macos.zip',
          ),
          ReleaseAsset(
            name: 'dan-player-windows-arm64.zip',
            browserDownloadUrl: 'https://github.com/example/arm64.zip',
          ),
        ],
        architecture: 'x64',
      );

      expect(selected, isNull);
    });

    test('matches an exact companion checksum first', () {
      final selected = UpdateService.instance.selectChecksumAsset(
        [
          ReleaseAsset(
            name: 'checksums.txt',
            browserDownloadUrl: 'https://github.com/example/checksums.txt',
          ),
          ReleaseAsset(
            name: 'DanPlayer.exe.sha256',
            browserDownloadUrl:
                'https://github.com/example/DanPlayer.exe.sha256',
          ),
        ],
        'DanPlayer.exe',
      );

      expect(selected?.name, 'DanPlayer.exe.sha256');
    });

    test('x86_64 is never selected for a 32-bit process', () {
      expect(
          UpdateService.instance.selectWindowsAsset([
            ReleaseAsset(
                name: 'DanPlayer-windows-x86_64.exe',
                browserDownloadUrl: 'https://github.com/example/setup.exe'),
          ], architecture: 'x86'),
          isNull);
    });
  });

  group('download ownership and cancellation', () {
    late Directory scratch;

    setUp(() async {
      final root = Directory(
        path.join(Directory.current.path, 'build', 'update_service_tests'),
      );
      await root.create(recursive: true);
      scratch = await root.createTemp('case-');
    });

    tearDown(() async {
      if (await scratch.exists()) await scratch.delete(recursive: true);
    });

    test('a pre-cancelled download never creates a client or an artifact',
        () async {
      var clientsCreated = 0;
      var directoryRequests = 0;
      final service = UpdateService.forTesting(
        appDataDirectory: () async {
          directoryRequests++;
          return scratch;
        },
        httpClientFactory: () {
          clientsCreated++;
          return _FakeHttpClient((_, __) => _response(const [1]));
        },
      );
      final cancellation = UpdateDownloadCancellation()..cancel();

      await expectLater(
        service.download(_update(const [1]), cancellation: cancellation),
        _throwsCancellation,
      );

      expect(directoryRequests, 0);
      expect(clientsCreated, 0);
      expect(await scratch.list().toList(), isEmpty);
    });

    test('cancelling on the last payload chunk does not commit a package',
        () async {
      final payload = utf8.encode('complete payload');
      final cancellation = UpdateDownloadCancellation();
      final service = UpdateService.forTesting(
        appDataDirectory: () async => scratch,
        httpClientFactory: () => _FakeHttpClient((_, __) => _response(payload)),
      );

      await expectLater(
        service.download(
          _update(payload),
          cancellation: cancellation,
          onProgress: (progress) {
            if (progress.receivedBytes == payload.length) cancellation.cancel();
          },
        ),
        _throwsCancellation,
      );

      final files = await scratch.list(recursive: true).where((item) {
        return item is File;
      }).toList();
      expect(files, isEmpty);
    });

    test('cancelling an old checksum request cannot delete a newer download',
        () async {
      final payload = utf8.encode('verified update package');
      final checksum = utf8.encode(
        '${sha256.convert(payload)}  DanPlayer-windows-x64.exe\n',
      );
      final checksumStarted = Completer<void>();
      final heldChecksum = StreamController<List<int>>(
        onListen: () => checksumStarted.complete(),
      );
      var checksumRequests = 0;
      var cancelledChecksumClient = false;
      final service = UpdateService.forTesting(
        appDataDirectory: () async => scratch,
        httpClientFactory: () => _FakeHttpClient((uri, client) {
          if (!uri.path.endsWith('.sha256')) return _response(payload);
          checksumRequests++;
          if (checksumRequests > 1) return _response(checksum);
          client.onForceClose = () {
            cancelledChecksumClient = true;
            if (!heldChecksum.isClosed) {
              heldChecksum.addError(const HttpException('request cancelled'));
              unawaited(heldChecksum.close());
            }
          };
          return _FakeHttpResponse(
            heldChecksum.stream,
            contentLength: checksum.length,
          );
        }),
      );
      final cancellation = UpdateDownloadCancellation();
      final oldDownload = service.download(
        _update(payload, checksum: true),
        cancellation: cancellation,
      );
      final oldOutcome = expectLater(oldDownload, _throwsCancellation);
      await checksumStarted.future.timeout(const Duration(seconds: 5));

      final newer = await service.download(_update(payload, checksum: true));
      cancellation.cancel();
      await oldOutcome;

      expect(cancelledChecksumClient, isTrue);
      expect(newer.checksumVerified, isTrue);
      expect(await newer.file.readAsBytes(), orderedEquals(payload));
      final versionDirectory = Directory(
        path.join(scratch.path, 'updates', '26.0.4'),
      );
      final retainedDirectories =
          (await versionDirectory.list().toList()).whereType<Directory>();
      expect(retainedDirectories, hasLength(1));
      expect(
        path.equals(retainedDirectories.single.path, newer.file.parent.path),
        isTrue,
      );
      expect(
        await scratch
            .list(recursive: true)
            .where((item) => item.path.endsWith('.partial'))
            .toList(),
        isEmpty,
      );
    });

    test('checksum mismatch removes only the failed operation artifacts',
        () async {
      final payload = utf8.encode('payload with a deliberately wrong checksum');
      final badChecksum = utf8.encode(
        '${'0' * 64}  DanPlayer-windows-x64.exe\n',
      );
      final service = UpdateService.forTesting(
        appDataDirectory: () async => scratch,
        httpClientFactory: () => _FakeHttpClient(
          (uri, _) =>
              _response(uri.path.endsWith('.sha256') ? badChecksum : payload),
        ),
      );

      await expectLater(
        service.download(_update(payload, checksum: true)),
        throwsA(
          isA<UpdateException>().having(
            (error) => error.message,
            'message',
            contains('SHA-256 校验失败'),
          ),
        ),
      );
      expect(
        await scratch
            .list(recursive: true)
            .where((item) => item is File)
            .toList(),
        isEmpty,
      );
    });

    test('an HTTPS redirect cannot issue a downgraded HTTP request', () async {
      final requested = <Uri>[];
      final service = UpdateService.forTesting(
        appDataDirectory: () async => scratch,
        httpClientFactory: () => _FakeHttpClient((uri, _) {
          requested.add(uri);
          return _FakeHttpResponse(const Stream.empty(),
              contentLength: 0,
              statusCode: HttpStatus.found,
              redirectLocation: 'http://example.com/package.exe');
        }),
      );
      await expectLater(
          service.download(_update([1])), throwsA(isA<UpdateException>()));
      expect(requested, hasLength(1));
      expect(requested.single.scheme, 'https');
    });

    test('a checksum for a similarly named file is not accepted', () async {
      final payload = utf8.encode('package');
      final checksum = utf8.encode(
          '${sha256.convert(payload)}  DanPlayer-windows-x64.exe.blockmap\n');
      final service = UpdateService.forTesting(
        appDataDirectory: () async => scratch,
        httpClientFactory: () => _FakeHttpClient((uri, _) =>
            _response(uri.path.endsWith('.sha256') ? checksum : payload)),
      );
      await expectLater(
          service.download(_update(payload, checksum: true)),
          throwsA(isA<UpdateException>()
              .having((error) => error.message, 'message', contains('无法识别'))));
    });
  });
}

final _throwsCancellation = throwsA(
  isA<UpdateException>().having(
    (error) => error.message,
    'message',
    contains('已取消下载'),
  ),
);

AvailableUpdate _update(List<int> payload, {bool checksum = false}) {
  const name = 'DanPlayer-windows-x64.exe';
  const url = 'https://github.com/DanRuguo/dan_player/releases/download/'
      'v26.0.4/$name';
  return AvailableUpdate(
    release: Release(tagName: 'v26.0.4'),
    version: const AppVersion(26, 0, 4),
    asset: ReleaseAsset(
      name: name,
      browserDownloadUrl: url,
      size: payload.length,
    ),
    checksumAsset: checksum
        ? ReleaseAsset(
            name: '$name.sha256',
            browserDownloadUrl: '$url.sha256',
          )
        : null,
  );
}

_FakeHttpResponse _response(List<int> bytes) => _FakeHttpResponse(
      Stream<List<int>>.value(bytes),
      contentLength: bytes.length,
    );

typedef _ResponseFactory = FutureOr<_FakeHttpResponse> Function(
  Uri uri,
  _FakeHttpClient client,
);

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.respond);

  final _ResponseFactory respond;
  void Function()? onForceClose;
  bool closed = false;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    if (closed) throw const HttpException('client closed');
    return _FakeHttpRequest(this, url);
  }

  @override
  void close({bool force = false}) {
    if (closed) return;
    closed = true;
    if (force) onForceClose?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpRequest implements HttpClientRequest {
  _FakeHttpRequest(this.client, this.uri);

  final _FakeHttpClient client;

  @override
  final Uri uri;

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  Future<HttpClientResponse> close() async {
    if (client.closed) throw const HttpException('client closed');
    return client.respond(uri, client);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpHeaders implements HttpHeaders {
  _FakeHttpHeaders([Map<String, String>? values]) : values = values ?? {};
  final Map<String, String> values;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value.toString();
  }

  @override
  String? value(String name) => values[name.toLowerCase()];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpResponse(this.body,
      {required this.contentLength,
      this.statusCode = HttpStatus.ok,
      String? redirectLocation})
      : headers = _FakeHttpHeaders({
          if (redirectLocation != null)
            HttpHeaders.locationHeader: redirectLocation,
        });

  final Stream<List<int>> body;

  @override
  final int contentLength;

  @override
  final int statusCode;

  @override
  final HttpHeaders headers;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      body.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
