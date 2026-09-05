import 'dart:async';

import 'package:dan_player/windows_shell.dart';
import 'package:dan_player/page/settings_page/uninstall_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dan_player/windows_shell');
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
      'uninstall requires confirmation and cancellation starts no process',
      (tester) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return {'kind': 'installed', 'directory': r'C:\QA\Dan Player'};
    });
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: UninstallSettings())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('uninstall-or-open-folder')));
    await tester.pumpAndSettle();
    expect(find.text('退出并打开卸载向导'), findsOneWidget);
    expect(calls, ['installationInfo']);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(calls, ['installationInfo']);
  });

  testWidgets('portable copy opens its folder without invoking uninstall',
      (tester) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'installationInfo') {
        return {'kind': 'portable', 'directory': r'C:\QA\Portable'};
      }
      return null;
    });
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: UninstallSettings())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('uninstall-or-open-folder')));
    await tester.pumpAndSettle();
    expect(calls, ['installationInfo', 'openAppFolder']);
  });

  test(
      'cold activation waits for restored session, window actions remain available',
      () async {
    final calls = <String>[];
    final queue =
        ShellActionQueue(dispatch: (action) async => calls.add(action));
    await queue.accept('toggle');
    await queue.accept('next');
    await queue.accept('showMain');
    expect(calls, ['showMain']);
    await queue.libraryReady();
    expect(calls, ['showMain', 'toggle', 'next']);
    await queue.libraryReady();
    expect(calls, hasLength(3));
  });

  test(
      'unknown shell commands cannot trigger exit, uninstall or arbitrary actions',
      () async {
    final calls = <String>[];
    final queue =
        ShellActionQueue(dispatch: (action) async => calls.add(action));
    await queue.libraryReady();
    for (final action in [
      'exit',
      'uninstall',
      'next --delete',
      'toggle\u0000',
      ''
    ]) {
      await queue.accept(action);
    }
    expect(calls, isEmpty);
  });

  test('cold next waits for delayed source restoration exactly once', () async {
    final sourceOpened = Completer<void>();
    final calls = <String>[];
    String? selectedTrack;
    var restoreAttempts = 0;
    final queue = ShellActionQueue(
      preparePlayback: () async {
        restoreAttempts++;
        await sourceOpened.future;
        selectedTrack = 'saved track';
      },
      dispatch: (action) async {
        calls.add(action);
        if (action == 'next') {
          expect(selectedTrack, 'saved track');
          selectedTrack = 'next track';
        }
      },
    );
    await queue.accept('next');
    final ready = queue.libraryReady();
    expect(queue.libraryReady(), same(ready));
    var finished = false;
    final completion = ready.then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    await queue.accept('showMain');
    await queue.accept('showMini');
    expect(calls, ['showMain', 'showMini']);
    expect(finished, isFalse);
    expect(selectedTrack, isNull);

    sourceOpened.complete();
    await completion;
    expect(calls, ['showMain', 'showMini', 'next']);
    expect(selectedTrack, 'next track');
    expect(restoreAttempts, 1);
    await queue.libraryReady();
    expect(calls, hasLength(3));
  });

  test('failed cold restore releases queued and subsequent playback tasks',
      () async {
    final sourceOpened = Completer<void>();
    final calls = <String>[];
    String? selectedTrack;
    final queue = ShellActionQueue(
      preparePlayback: () => sourceOpened.future,
      dispatch: (action) async =>
          calls.add('$action:${selectedTrack ?? 'none'}'),
    );
    await queue.accept('next');
    final ready = queue.libraryReady();
    await Future<void>.delayed(Duration.zero);
    await queue.accept('showMain');
    expect(calls, ['showMain:none']);

    sourceOpened.completeError(StateError('saved file is unavailable'));
    await ready;
    expect(calls, ['showMain:none', 'next:none']);
    selectedTrack = 'manually selected track';
    await queue.accept('next');
    expect(calls.last, 'next:manually selected track');
  });

  test('a failed cold task does not discard later accepted tasks', () async {
    final calls = <String>[];
    final queue = ShellActionQueue(dispatch: (action) async {
      calls.add(action);
      if (action == 'toggle') throw StateError('device unavailable');
    });
    await queue.accept('toggle');
    await queue.accept('next');
    await expectLater(queue.libraryReady(), throwsStateError);
    expect(calls, ['toggle', 'next']);
    await queue.accept('previous');
    expect(calls.last, 'previous');
  });

  test(
      'commands are serialized and a failed action does not wedge later actions',
      () async {
    final first = Completer<void>();
    final calls = <String>[];
    final queue = ShellActionQueue(dispatch: (action) async {
      calls.add(action);
      if (action == 'previous') await first.future;
      if (action == 'toggle') throw StateError('device unavailable');
    });
    await queue.libraryReady();
    final previous = queue.accept('previous');
    final next = queue.accept('next');
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['previous']);
    first.complete();
    await Future.wait([previous, next]);
    await expectLater(queue.accept('toggle'), throwsStateError);
    await queue.accept('showMain');
    expect(calls, ['previous', 'next', 'toggle', 'showMain']);
  });
}
