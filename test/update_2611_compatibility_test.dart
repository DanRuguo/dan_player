import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/taskbar_progress.dart';
import 'package:dan_player/update/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github/github.dart';
import 'package:path/path.dart' as path;

const _version = '26.1.1';
const _setupName = 'DanPlayer-$_version-Setup-x64.exe';
const _portableName = 'DanPlayer-$_version-windows-x64.zip';
const _assembled = '2026-10-08T08:00:00Z';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String? previousIgnored;
  setUp(() {
    previousIgnored = AppSettings.instance.ignoredUpdateVersion;
    AppSettings.instance.ignoredUpdateVersion = null;
  });
  tearDown(() {
    AppSettings.instance.ignoredUpdateVersion = previousIgnored;
  });

  for (final current in ['26.0.5', '26.0.6']) {
    for (final oldIgnore in [current, '$current@${'a' * 64}']) {
      final kind = oldIgnore == current ? 'version' : 'build';
      test('$current ignored $kind does not suppress the 26.1.1 upgrade',
          () async {
        AppSettings.instance.ignoredUpdateVersion = oldIgnore;
        var installedIdentityReads = 0;
        final release = _release();
        final service = _service(
          current: current,
          releases: [release],
          installedBuildLoader: () async {
            installedIdentityReads++;
            throw StateError('A higher version needs no old build identity');
          },
        );

        final update = await service.checkLatest(includePreviews: false);

        expect(update, isNotNull);
        expect(update!.release, same(release));
        expect(update.version.toString(), _version);
        expect(update.ignoreKey, _version);
        expect(update.isSameVersionReissue, isFalse);
        expect(installedIdentityReads, 0);
        expect(AppSettings.instance.ignoredUpdateVersion, oldIgnore);
      });
    }

    test('$current stable channel chooses 26.1.1 from mixed release shapes',
        () async {
      final stable = _release();
      final service = _service(current: current, releases: [
        _release(version: '26.1.2', prerelease: true),
        _release(version: '26.2.0-snapshot.1'),
        _release(version: '27.0.0', draft: true),
        stable,
        _release(version: '26.0.6-snapshot.2', prerelease: true),
      ]);

      final update = await service.checkLatest(includePreviews: false);

      expect(update!.release, same(stable));
      expect(update.isPreview, isFalse);
      expect(update.asset!.name, _setupName);
      expect(update.checksumAsset!.name, '$_setupName.sha256');
      expect(update.asset!.id, 103);
      expect(update.checksumAsset!.id, 104);
    });
  }

  test('explicit preview consent remains effective across the minor upgrade',
      () async {
    final preview = _release(version: '26.1.2-snapshot.1', prerelease: true);
    final service = _service(
      current: '26.0.6',
      releases: [_release(), preview],
    );

    final update = await service.checkLatest(includePreviews: true);

    expect(update!.release, same(preview));
    expect(update.isPreview, isTrue);
    expect(update.asset!.name, 'DanPlayer-26.1.2-snapshot.1-Setup-x64.exe');
  });

  test('the installed 26.1.1 build does not offer itself or older releases',
      () async {
    final service = _service(
      current: _version,
      releases: [
        _release(version: '26.0.6'),
        _release(),
        _release(version: '26.1.1-snapshot.2', prerelease: true),
      ],
      installedBuildLoader: () async => InstalledBuild(
        version: _version,
        sourceRevision: 'b' * 40,
        assembledUtc: DateTime.parse(_assembled),
      ),
    );

    expect(await service.checkLatest(includePreviews: true), isNull);
  });

  test('26.1.1 without a local build identity does not loop into self-update',
      () async {
    final service = _service(current: _version, releases: [_release()]);

    expect(await service.checkLatest(includePreviews: false), isNull);
  });

  test('26.1.1 selection follows version instead of release list chronology',
      () async {
    final older = _release(version: '26.0.6')
      ..publishedAt = DateTime.utc(2026, 10, 9);
    final next = _release()..publishedAt = DateTime.utc(2026, 10, 8);
    final service = _service(
      current: '26.0.5',
      releases: [older, next, _release(version: '26.0.5')],
    );

    final update = await service.checkLatest(includePreviews: false);

    expect(update!.release, same(next));
    expect(update.version.toString(), _version);
  });

  test('the x64-only 26.1.1 release keeps other architectures on manual page',
      () async {
    for (final architecture in ['arm64', 'x86', 'unknown']) {
      final service = _service(
        current: '26.0.6',
        releases: [_release()],
        architecture: architecture,
      );

      final update = await service.checkLatest(includePreviews: false);

      expect(update, isNotNull);
      expect(update!.asset, isNull);
      expect(update.checksumAsset, isNull);
      expect(update.release.htmlUrl,
          'https://github.com/DanRuguo/dan_player/releases/tag/v$_version');
    }
  });

  test('the four-asset 26.1.1 release verifies the setup companion checksum',
      () async {
    final qaRoot = path.normalize(path.absolute('..', 'tool', 'qa-local'));
    final fixtureRoot = await Directory(
      path.join(qaRoot, 'update-compatibility-tests'),
    ).create(recursive: true);
    final scratch = await fixtureRoot.createTemp('update-2611-');
    addTearDown(() async {
      final resolved = await scratch.resolveSymbolicLinks();
      expect(path.isWithin(qaRoot, resolved), isTrue);
      expect(path.basename(resolved), startsWith('update-2611-'));
      await scratch.delete(recursive: true);
      expect(TaskbarProgress.instance.value, isNull);
    });

    final payload = utf8.encode('Controlled 26.1.1 installer download fixture');
    final digest = sha256.convert(payload).toString();
    final release = _release(payloadSize: payload.length, installerSha: digest);
    final requested = <String>[];
    final service = UpdateService.forTesting(
      appDataDirectory: () async => scratch,
      currentVersion: '26.0.6',
      architecture: 'x64',
      releaseLoader: () async => [release],
      httpClientFactory: () => _FixtureHttpClient((uri) {
        requested.add(uri.pathSegments.last);
        if (uri.pathSegments.last == _setupName) {
          return _FixtureHttpResponse(payload);
        }
        if (uri.pathSegments.last == '$_setupName.sha256') {
          return _FixtureHttpResponse(utf8.encode('$digest  $_setupName\n'));
        }
        throw StateError('The portable checksum must not be requested: $uri');
      }),
    );

    final update = (await service.checkLatest(includePreviews: false))!;
    final result = await service.download(update);

    expect(requested, [_setupName, '$_setupName.sha256']);
    expect(result.checksumVerified, isTrue);
    expect(result.sha256Digest, digest);
    expect(result.canInstall(update), isTrue);
    expect(path.basename(result.file.path), _setupName);
    expect(await result.file.readAsBytes(), orderedEquals(payload));
    expect(path.isWithin(scratch.path, result.file.path), isTrue);
  });
}

UpdateService _service({
  required String current,
  required List<Release> releases,
  String architecture = 'x64',
  Future<InstalledBuild?> Function()? installedBuildLoader,
}) =>
    UpdateService.forTesting(
      appDataDirectory: () => throw StateError('No application data access'),
      httpClientFactory: () => throw StateError('No real network access'),
      currentVersion: current,
      architecture: architecture,
      installedBuildLoader: installedBuildLoader,
      releaseLoader: () async => releases,
    );

Release _release({
  String version = _version,
  bool prerelease = false,
  bool draft = false,
  int payloadSize = 40411520,
  String? installerSha,
}) {
  final setup = 'DanPlayer-$version-Setup-x64.exe';
  final portable = version == _version
      ? _portableName
      : 'DanPlayer-$version-windows-x64.zip';
  final base =
      'https://github.com/DanRuguo/dan_player/releases/download/v$version';
  ReleaseAsset asset(int id, String name, int size) => ReleaseAsset(
        id: id,
        name: name,
        size: size,
        state: 'uploaded',
        browserDownloadUrl: '$base/$name',
      );
  return Release(
    tagName: 'v$version',
    isPrerelease: prerelease,
    isDraft: draft,
    htmlUrl: 'https://github.com/DanRuguo/dan_player/releases/tag/v$version',
    body: '累计更新说明。\n${ReleaseBuildMarker.prefix}${jsonEncode({
          'version': version,
          'sourceRevision': 'b' * 40,
          'assembledUtc': _assembled,
          'installerAssetId': 103,
          'installerSize': payloadSize,
          'installerSha256': installerSha ?? 'c' * 64,
          'checksumAssetId': 104,
          'checksumSize': 97,
        })}${ReleaseBuildMarker.suffix}',
    // Keep the portable sum first, as older releases may use this asset order.
    assets: [
      asset(101, portable, 42233796),
      asset(102, 'SHA256SUMS', 99),
      asset(103, setup, payloadSize),
      asset(104, '$setup.sha256', 97),
    ],
  );
}

class _FixtureHttpClient implements HttpClient {
  _FixtureHttpClient(this.respond);

  final HttpClientResponse Function(Uri) respond;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FixtureHttpRequest(url, respond);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixtureHttpRequest implements HttpClientRequest {
  _FixtureHttpRequest(this.uri, this.respond);

  @override
  final Uri uri;
  final HttpClientResponse Function(Uri) respond;

  @override
  final HttpHeaders headers = _FixtureHttpHeaders();

  @override
  bool followRedirects = false;

  @override
  Future<HttpClientResponse> close() async => respond(uri);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixtureHttpHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixtureHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FixtureHttpResponse(this.bytes);

  final List<int> bytes;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => bytes.length;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  final HttpHeaders headers = _FixtureHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.value(bytes).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
