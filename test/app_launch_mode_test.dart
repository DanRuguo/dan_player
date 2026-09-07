import 'dart:async';
import 'dart:convert';

import 'package:dan_player/app_launch_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'lyric process receives one intact JSON argument and never starts player',
      () async {
    final payload = jsonEncode({
      'title': '結想は花となる short ver. "OP"',
      'artist': '堀江晶太',
      'path': r'J:\Music with spaces\01.opus',
    });
    final arguments = [desktopLyricLaunchArgument, payload];
    List<String>? received;
    final ready = Completer<void>();
    var completed = false;
    final launching = dispatchAppLaunch(
      arguments,
      startPlayer: () => throw StateError('player initialization is forbidden'),
      startDesktopLyric: (args) {
        received = args;
        return ready.future;
      },
    ).then((_) => completed = true);
    expect(received, [payload]);
    expect(arguments, [desktopLyricLaunchArgument, payload]);
    await Future<void>.delayed(Duration.zero);
    expect(completed, false);
    ready.complete();
    await launching;
    expect(completed, true);
  });

  for (final arguments in <List<String>>[
    [],
    [r'J:\Music\01.opus'],
    ['--play', desktopLyricLaunchArgument],
  ]) {
    test('ordinary invocation starts only player: $arguments', () async {
      var starts = 0;
      await dispatchAppLaunch(
        arguments,
        startPlayer: () async => starts++,
        startDesktopLyric: (_) => throw StateError('unexpected lyric process'),
      );
      expect(starts, 1);
    });
  }

  test('invalid lyric startup never falls through to player initialization',
      () async {
    await expectLater(
      dispatchAppLaunch(
        [desktopLyricLaunchArgument, 'invalid JSON'],
        startPlayer: () => throw StateError('unexpected player startup'),
        startDesktopLyric: (args) async => jsonDecode(args.single),
      ),
      throwsFormatException,
    );
  });
}
