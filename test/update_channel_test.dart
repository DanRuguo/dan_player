import 'dart:async';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/update/update_channel_preference.dart';
import 'package:dan_player/update/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github/github.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final version in ['26.0.4', '26.0.4-snapshot.1']) {
    test('implicit and explicit preview preference for $version', () {
      final implicit = UpdateChannelPreference.fromMap({});
      expect(implicit.includesPreviewsFor(version), version.contains('-'));
      expect(implicit.toMap(), isEmpty);
      for (final choice in [false, true]) {
        final decoded = UpdateChannelPreference.fromMap(
            UpdateChannelPreference(receivePreviews: choice).toMap());
        expect(decoded.includesPreviewsFor(version), choice);
      }
    });
  }

  test('invalid legacy preview values do not create explicit consent', () {
    for (final value in [null, 'true', 'false', [], {}, 2]) {
      final pref =
          UpdateChannelPreference.fromMap({'ReceivePreviewUpdates': value});
      expect(pref.receivePreviews, isNull);
      expect(pref.includesPreviewsFor('26.0.4'), isFalse);
    }
    expect(
        UpdateChannelPreference.fromMap({'ReceivePreviewUpdates': 0})
            .includesPreviewsFor('26.0.4-snapshot.1'),
        isFalse);
  });

  final service = UpdateService.forTesting(
    appDataDirectory: () => throw StateError('No disk access'),
    httpClientFactory: () => throw StateError('No network access'),
  );
  final releases = [
    Release(tagName: '26.0.5-snapshot.10', isPrerelease: true),
    Release(tagName: '26.0.4-snapshot.2'),
    Release(tagName: '26.0.4'),
    Release(tagName: '26.0.5-snapshot.2', isPrerelease: true),
    Release(tagName: '99.0.0', isDraft: true),
    Release(tagName: '30.0.0', isPrerelease: true),
    Release(tagName: 'bad-version'),
  ];

  test('stable channel cannot be replaced by a higher preview or draft', () {
    final selected = service.selectLatestRelease(releases,
        current: AppVersion.tryParse('26.0.3')!, includePreviews: false);
    expect(selected!.version.toString(), '26.0.4');
    expect(selected.isPreview, isFalse);
  });

  test('snapshot comparison is numeric, and suffix alone makes a preview', () {
    final selected = service.selectLatestRelease(releases.take(5),
        current: AppVersion.tryParse('26.0.4-snapshot.1')!,
        includePreviews: true);
    expect(selected!.version.toString(), '26.0.5-snapshot.10');
    expect(selected.isPreview, isTrue);
    final suffixOnly = service.selectLatestRelease([releases[1]],
        current: AppVersion.tryParse('26.0.4-snapshot.1')!,
        includePreviews: true);
    expect(suffixOnly!.isPreview, isTrue);
  });

  test('same-base stable supersedes preview and stable never downgrades', () {
    final current = AppVersion.tryParse('26.0.4-snapshot.10')!;
    expect(
        service
            .selectLatestRelease([releases[1], releases[2]],
                current: current, includePreviews: true)!
            .version
            .toString(),
        '26.0.4');
    expect(
        service.selectLatestRelease([releases[1]],
            current: AppVersion.tryParse('26.0.4')!, includePreviews: true),
        isNull);
  });

  test('missing installer keeps the release-page fallback', () {
    final update = service.selectLatestRelease([
      Release(tagName: '26.0.4', assets: [
        ReleaseAsset(
            name: 'source.zip',
            browserDownloadUrl: 'https://github.com/example/source.zip'),
      ])
    ], current: AppVersion.tryParse('26.0.3')!, includePreviews: false);
    expect(update, isNotNull);
    expect(update!.asset, isNull);
  });

  test('only same-version same-architecture project Setup is selected', () {
    final assets = [
      for (final name in [
        'random-setup-x64.exe',
        'DanPlayer.exe',
        'DanPlayer-26.0.4-windows-x64.zip',
        'DanPlayer-26.0.4.msix',
        'DanPlayer-26.0.5-Setup-x64.exe',
        'DanPlayer-26.0.4-Setup-arm64.exe',
        'DanPlayer-26.0.4-Setup-x64-QA.exe',
        'DanPlayer-26.0.4-Setup-x64.exe',
      ])
        ReleaseAsset(
            name: name, browserDownloadUrl: 'https://github.com/example/$name')
    ];
    expect(
        service
            .selectWindowsAsset(assets, version: '26.0.4', architecture: 'x64')!
            .name,
        'DanPlayer-26.0.4-Setup-x64.exe');
    expect(
        service.selectWindowsAsset(assets,
            version: '26.0.4', architecture: 'unknown'),
        isNull);
  });

  test('shared HTTP results preserve each concurrent caller channel', () async {
    final result = Completer<List<Release>>();
    var calls = 0;
    final shared = UpdateService.forTesting(
      appDataDirectory: () => throw StateError('No disk'),
      httpClientFactory: () => throw StateError('No network'),
      currentVersion: '26.0.3',
      releaseLoader: () {
        calls++;
        return result.future;
      },
    );
    final stable =
        shared.checkLatest(includePreviews: false, includeIgnored: true);
    final preview =
        shared.checkLatest(includePreviews: true, includeIgnored: true);
    result.complete(releases.take(5).toList());
    expect((await stable)!.version.toString(), '26.0.4');
    expect((await preview)!.version.toString(), '26.0.5-snapshot.10');
    expect(calls, 1);
  });

  test('failed checks release their original in-flight lock for retry',
      () async {
    var calls = 0;
    final retry = UpdateService.forTesting(
      appDataDirectory: () => throw StateError('No disk'),
      httpClientFactory: () => throw StateError('No network'),
      currentVersion: '26.0.3',
      releaseLoader: () async {
        if (++calls == 1) throw const SocketException('synthetic');
        return [Release(tagName: '26.0.4')];
      },
    );
    await expectLater(retry.checkLatest(includePreviews: false),
        throwsA(isA<UpdateException>()));
    expect(
        (await retry.checkLatest(includePreviews: false, includeIgnored: true))!
            .version
            .toString(),
        '26.0.4');
    expect(calls, 2);
  });

  test('ignore suppresses automatic only and failed persistence rolls back',
      () async {
    final previous = AppSettings.instance.ignoredUpdateVersion;
    addTearDown(() => AppSettings.instance.ignoredUpdateVersion = previous);
    AppSettings.instance.ignoredUpdateVersion = '26.0.4';
    final ignored = UpdateService.forTesting(
      appDataDirectory: () => throw StateError('No disk'),
      httpClientFactory: () => throw StateError('No network'),
      currentVersion: '26.0.3',
      releaseLoader: () async => [Release(tagName: '26.0.4')],
      savePreferences: () async => throw StateError('synthetic save failure'),
    );
    expect(await ignored.checkLatest(includePreviews: false), isNull);
    expect(
        await ignored.checkLatest(includePreviews: false, includeIgnored: true),
        isNotNull);
    await expectLater(
        ignored.ignoreVersion(const AppVersion(26, 0, 5)), throwsStateError);
    expect(AppSettings.instance.ignoredUpdateVersion, '26.0.4');
  });

  test('oversize numeric or empty prerelease tags are safely ignored', () {
    for (final tag in [
      '${'9' * 80}.0.4',
      '26.0.4-snapshot..1',
      '26.0.4-${'x' * 100}'
    ]) {
      expect(AppVersion.tryParse(tag), isNull);
    }
  });

  test('late old ignore failure cannot undo a newer same-version choice',
      () async {
    final previous = AppSettings.instance.ignoredUpdateVersion;
    addTearDown(() => AppSettings.instance.ignoredUpdateVersion = previous);
    AppSettings.instance.ignoredUpdateVersion = null;
    final pending = Completer<void>();
    final old = UpdateService.forTesting(
      appDataDirectory: () => throw StateError('No disk'),
      httpClientFactory: () => throw StateError('No network'),
      savePreferences: () => pending.future,
    );
    final attempt = expectLater(
        old.ignoreVersion(const AppVersion(26, 0, 4)), throwsStateError);
    await service.ignoreVersion(const AppVersion(26, 0, 4));
    pending.completeError(StateError('old save failure'));
    await attempt;
    expect(AppSettings.instance.ignoredUpdateVersion, '26.0.4');
  });

  test(
      'restart eligibility requires verified hash and exact installer identity',
      () {
    final update = AvailableUpdate(
        release: Release(tagName: '26.0.4'),
        version: const AppVersion(26, 0, 4),
        asset: ReleaseAsset(name: 'DanPlayer-26.0.4-Setup-x64.exe'));
    UpdateDownloadResult downloaded(
            {bool verified = true, String? name, String? digest}) =>
        UpdateDownloadResult(
            file: File(name ?? 'DanPlayer-26.0.4-Setup-x64.exe'),
            sha256Digest: digest ?? 'a' * 64,
            checksumVerified: verified);
    expect(downloaded().canInstall(update), isTrue);
    expect(downloaded(verified: false).canInstall(update), isFalse);
    expect(downloaded(digest: 'invalid').canInstall(update), isFalse);
    expect(
        downloaded(name: 'DanPlayer-26.0.5-Setup-x64.exe').canInstall(update),
        isFalse);
    expect(downloaded(name: 'portable.zip').canInstall(update), isFalse);
  });
}
