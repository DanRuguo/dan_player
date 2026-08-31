import 'dart:async';
import 'dart:io';

import 'package:dan_player/update/installer_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dan_player/installer_launcher_test');
  const hash =
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
  final installer = File(r'C:\fake\更新 installer.exe');
  late InstallerLauncher launcher;
  late List<MethodCall> calls;

  Future<void> launch(
          {File? file,
          String sha256 = hash,
          String version = '26.0.4-snapshot.1'}) =>
      launcher.launchForUpdate(
          installer: file ?? installer, sha256: sha256, version: version);

  setUp(() {
    launcher = InstallerLauncher(channel: channel, isWindows: () => true);
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test('only path, hash and version are sent; target and PID are native-owned',
      () async {
    await launch(sha256: hash.toUpperCase());
    expect(calls.single.method, 'launchForUpdate');
    expect(calls.single.arguments, {
      'path': installer.absolute.path,
      'sha256': hash,
      'version': '26.0.4-snapshot.1',
    });
    expect(launcher.isLaunching, isFalse);
  });

  test('ZIP and malformed hash/version fail before native invocation',
      () async {
    for (final operation in [
      () => launch(file: File(r'C:\fake\update.zip')),
      () => launch(sha256: '0' * 63),
      () => launch(sha256: 'x' * 64),
      () => launch(version: '1.2.3" /DIR=C:\\other'),
      () => launch(version: '1.2.3\n'),
    ]) {
      await expectLater(operation(), throwsA(isA<InstallerLaunchException>()));
    }
    expect(calls, isEmpty);
  });

  test('native READY is awaited and repeated clicks cannot launch twice',
      () async {
    final ready = Completer<bool>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return ready.future;
    });
    var completed = false;
    final first = launch().then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    expect(launcher.isLaunching, isTrue);
    await expectLater(
        launch(),
        throwsA(isA<InstallerLaunchException>()
            .having((error) => error.code, 'code', 'launch_busy')));
    expect(calls, hasLength(1));
    ready.complete(true);
    await first;
    expect(completed, isTrue);
    expect(launcher.isLaunching, isFalse);
  });

  for (final code in [
    'signature_untrusted',
    'publisher_mismatch',
    'hash_mismatch',
    'installer_not_ready',
    'start_failed',
    'launch_cancelled'
  ]) {
    test('$code is preserved and failed launch can be retried', () async {
      var attempts = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
        if (attempts++ == 0) {
          throw PlatformException(code: code, message: 'Safe failure');
        }
        return true;
      });
      await expectLater(
          launch(),
          throwsA(isA<InstallerLaunchException>()
              .having((error) => error.code, 'code', code)
              .having((error) => error.message, 'message', 'Safe failure')));
      expect(launcher.isLaunching, isFalse);
      await launch();
    });
  }

  test('null/false response cannot authorize application exit', () async {
    for (final response in [null, false]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => response);
      await expectLater(
          launch(),
          throwsA(isA<InstallerLaunchException>()
              .having((error) => error.code, 'code', 'launch_not_confirmed')));
    }
  });

  test('unsupported platform never calls native', () async {
    launcher = InstallerLauncher(channel: channel, isWindows: () => false);
    await expectLater(
        launch(),
        throwsA(isA<InstallerLaunchException>()
            .having((error) => error.code, 'code', 'unsupported_platform')));
    expect(calls, isEmpty);
  });
}
