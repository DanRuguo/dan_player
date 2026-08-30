import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/play_service/desktop_lyric_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThemeProcess extends Fake implements Process {
  final _input = StreamController<List<int>>();
  final _exit = Completer<int>();
  final bytes = <int>[];
  late final IOSink input;
  int kills = 0;

  _ThemeProcess() {
    _input.stream.listen(bytes.addAll);
    input = IOSink(_input.sink, encoding: utf8);
  }
  @override
  IOSink get stdin => input;
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  Future<int> get exitCode => _exit.future;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    kills++;
    if (!_exit.isCompleted) _exit.complete(0);
    return true;
  }

  Future<List<Map<String, dynamic>>> messages() async {
    await input.flush();
    await Future<void>.delayed(Duration.zero);
    return const LineSplitter()
        .convert(utf8.decode(bytes))
        .map((line) => Map<String, dynamic>.from(jsonDecode(line)))
        .toList();
  }
}

ThemeProvider _theme(ThemeMode mode) => ThemeProvider.forTesting(
      seedColor: Colors.teal,
      themeMode: mode,
      dynamicThemeEnabled: () => true,
      loadArtwork: (_) async => null,
      extractScheme: (_, brightness) async => ColorScheme.fromSeed(
          seedColor: Colors.orange, brightness: brightness),
    );

void _expectLatestTheme(
    List<Map<String, dynamic>> messages, ColorScheme scheme) {
  final theme =
      messages.lastWhere((m) => m['type'] == 'ThemeChangedMessage')['message'];
  expect(theme['primary'], scheme.primary.toARGB32());
  expect(theme['surfaceContainer'], scheme.surfaceContainer.toARGB32());
  expect(theme['onSurface'], scheme.onSurface.toARGB32());
  final mode = messages
      .lastWhere((m) => m['type'] == 'ThemeModeChangedMessage')['message'];
  expect(mode['darkMode'], scheme.brightness == Brightness.dark);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'palette and mode changed during Process.start are replayed after attach',
      () async {
    final theme = _theme(ThemeMode.light);
    final process = _ThemeProcess();
    final gate = Completer<Process>();
    Map<String, dynamic>? initial;
    final service = DesktopLyricService(
      PlayService.instance,
      executableExists: (_) => true,
      readTheme: () => theme.currScheme,
      startProcess: (_, args) {
        initial = jsonDecode(args.single) as Map<String, dynamic>;
        return gate.future;
      },
    );
    addTearDown(() async {
      service.dispose();
      theme.dispose();
      await process.input.close();
    });
    final starting = service.startDesktopLyric();
    final before = theme.currScheme;
    expect(service.state, DesktopLyricState.starting);
    theme.applyTheme(seedColor: Colors.deepPurple);
    theme.applyThemeMode(ThemeMode.dark);
    // The normal theme publisher cannot send while this process is starting.
    expect(await service.canSendMessage, isFalse);
    service.sendThemeMessage(theme.currScheme);
    service.sendThemeModeMessage(true);
    expect(process.bytes, isEmpty);
    gate.complete(process);
    await starting;
    expect(initial!['primary'], before.primary.toARGB32());
    expect(initial!['darkMode'], false);
    _expectLatestTheme(await process.messages(), theme.currScheme);
    expect(PlayService.playbackReady.value, false);
  });

  for (final brightness in Brightness.values) {
    test('system $brightness is used in initial arguments and theme replay',
        () async {
      binding.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(binding.platformDispatcher.clearPlatformBrightnessTestValue);
      final theme = _theme(ThemeMode.system);
      final process = _ThemeProcess();
      Map<String, dynamic>? initial;
      final service = DesktopLyricService(
        PlayService.instance,
        executableExists: (_) => true,
        readTheme: () => theme.currScheme,
        startProcess: (_, args) async {
          initial = jsonDecode(args.single) as Map<String, dynamic>;
          return process;
        },
      );
      addTearDown(() async {
        service.dispose();
        theme.dispose();
        await process.input.close();
      });
      await service.startDesktopLyric();
      expect(initial!['darkMode'], brightness == Brightness.dark);
      _expectLatestTheme(await process.messages(), theme.currScheme);
      expect(PlayService.playbackReady.value, false);
    });
  }

  test('system brightness changed during startup uses latest actual mode',
      () async {
    binding.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(binding.platformDispatcher.clearPlatformBrightnessTestValue);
    final theme = _theme(ThemeMode.system);
    final process = _ThemeProcess();
    final gate = Completer<Process>();
    final service = DesktopLyricService(
      PlayService.instance,
      executableExists: (_) => true,
      readTheme: () => theme.currScheme,
      startProcess: (_, __) => gate.future,
    );
    addTearDown(() async {
      service.dispose();
      theme.dispose();
      await process.input.close();
    });
    final starting = service.startDesktopLyric();
    binding.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    gate.complete(process);
    await starting;
    _expectLatestTheme(await process.messages(), theme.currScheme);
  });

  test('late cancelled helper cannot receive or replace restarted helper theme',
      () async {
    final theme = _theme(ThemeMode.light);
    final old = _ThemeProcess();
    final current = _ThemeProcess();
    final gate = Completer<Process>();
    var starts = 0;
    final service = DesktopLyricService(
      PlayService.instance,
      executableExists: (_) => true,
      readTheme: () => theme.currScheme,
      startProcess: (_, __) =>
          ++starts == 1 ? gate.future : Future.value(current),
    );
    addTearDown(() async {
      service.dispose();
      theme.dispose();
      await old.input.close();
      await current.input.close();
    });
    final oldStart = service.startDesktopLyric();
    service.killDesktopLyric();
    theme.applyTheme(seedColor: Colors.pink);
    theme.applyThemeMode(ThemeMode.dark);
    await service.startDesktopLyric();
    gate.complete(old);
    await oldStart;
    expect(old.kills, 1);
    expect(old.bytes, isEmpty);
    expect(service.isRunning, true);
    _expectLatestTheme(await current.messages(), theme.currScheme);
  });
}
