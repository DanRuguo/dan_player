import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/play_service/desktop_lyric_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/message.dart' as msg;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

bool _hasListeners(ChangeNotifier notifier) {
  // This isolated lifecycle test intentionally checks subscription cleanup.
  // ignore: invalid_use_of_protected_member
  return notifier.hasListeners;
}

class _Process extends Fake implements Process {
  final _input = StreamController<List<int>>();
  final _output = StreamController<List<int>>();
  final _errors = StreamController<List<int>>();
  final _exit = Completer<int>();
  final bytes = <int>[];
  late final IOSink input;
  int kills = 0;

  _Process() {
    _input.stream.listen(bytes.addAll);
    input = IOSink(_input.sink, encoding: utf8);
  }

  @override
  IOSink get stdin => input;
  @override
  Stream<List<int>> get stdout => _output.stream;
  @override
  Stream<List<int>> get stderr => _errors.stream;
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
        .map((line) => Map<String, dynamic>.from(json.decode(line)))
        .toList();
  }

  Future<void> emit(msg.Message message) async {
    _output.add(utf8.encode(message.buildMessageJson()));
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> dispose() async {
    await input.close();
    // A pending launch was killed before listeners attached: close those
    // unlistened streams without awaiting their never-consumed done futures.
    unawaited(_output.close());
    unawaited(_errors.close());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('real facade shutdown waits for an already-running appearance save',
      () async {
    final preferences = AppSettings.instance.desktopLyricAppearance;
    final previous = preferences.value;
    final process = _Process();
    final ready = PlaybackReadiness();
    final saveGate = Completer<void>();
    var saves = 0;
    final facade = PlayService.forTesting(
        readiness: ready,
        createPlayback: (_) => throw StateError('must not initialize BASS'),
        createDesktopLyric: (owner) => DesktopLyricService(owner,
            executableExists: (_) => true,
            startProcess: (_, __) async => process,
            saveAppearance: () {
              saves++;
              return saveGate.future;
            }));
    final service = facade.desktopLyricService;
    await service.startDesktopLyric();
    await process.emit(msg.DesktopLyricAppearanceChangedMessage(
        DesktopLyricAppearance.defaults.copyWith(textOpacity: .4),
        revision: 1));
    final saving = service.flushAppearance();
    await Future<void>.delayed(Duration.zero);
    expect(saves, 1);
    var closed = false;
    final closing = facade.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(process.kills, 1);
    expect(closed, false,
        reason:
            'The facade must not finish while disk persistence is pending.');
    saveGate.complete();
    await saving;
    await closing;
    expect(closed, true);
    expect(saves, 1);
    preferences.value = previous;
    ready.dispose();
    await process.dispose();
  });

  test('appearance debounce persists latest snapshot once and reopens with it',
      () async {
    final preferences = AppSettings.instance.desktopLyricAppearance;
    final previous = preferences.value;
    final processes = [_Process(), _Process()];
    final initial = <Map<String, dynamic>>[];
    var saves = 0;
    var index = 0;
    final service = DesktopLyricService(
      PlayService.instance,
      executableExists: (_) => true,
      startProcess: (_, args) async {
        initial.add(jsonDecode(args.last) as Map<String, dynamic>);
        return processes[index++];
      },
      saveAppearance: () async {
        saves++;
      },
    );
    addTearDown(() async {
      service.dispose();
      preferences.value = previous;
      for (final process in processes) {
        await process.dispose();
      }
    });
    await service.startDesktopLyric();
    for (var revision = 1; revision <= 20; revision++) {
      await processes[0].emit(msg.DesktopLyricAppearanceChangedMessage(
          DesktopLyricAppearance.defaults.copyWith(
              textOpacity: .2 + revision * .02,
              lyricFontSize: 30,
              translationFontSize: 26,
              customColor: 0xffaabbcc,
              backgroundOpacity: .7,
              strokeEnabled: true),
          revision: revision));
    }
    expect(saves, 0);
    expect(preferences.value.textOpacity, closeTo(.6, 1e-9));
    await Future<void>.delayed(const Duration(milliseconds: 550));
    expect(saves, 1);
    final saved = (await processes[0].messages()).lastWhere(
        (message) => message['type'] == 'DesktopLyricAppearanceSavedMessage');
    expect(saved['message'], {'revision': 20, 'saved': true});
    service.killDesktopLyric();
    await service.startDesktopLyric();
    expect(initial.last['appearance'], preferences.value.toJson());
    await processes[0].emit(const msg.DesktopLyricAppearanceChangedMessage(
        DesktopLyricAppearance.defaults,
        revision: 100));
    expect(preferences.value.textOpacity, closeTo(.6, 1e-9),
        reason: 'Old process must not overwrite the new helper.');
    expect(PlayService.playbackReady.value, false);
  });

  test(
      'appearance close flushes debounce; old save result cannot reach new helper',
      () async {
    final preferences = AppSettings.instance.desktopLyricAppearance;
    final previous = preferences.value;
    final processes = [_Process(), _Process()];
    final save = Completer<void>();
    var saves = 0;
    var index = 0;
    final service = DesktopLyricService(PlayService.instance,
        executableExists: (_) => true,
        startProcess: (_, __) async => processes[index++],
        saveAppearance: () {
          saves++;
          return save.future;
        });
    addTearDown(() async {
      if (!save.isCompleted) save.complete();
      service.dispose();
      preferences.value = previous;
      for (final process in processes) {
        await process.dispose();
      }
    });
    await service.startDesktopLyric();
    await processes[0].emit(msg.DesktopLyricAppearanceChangedMessage(
        DesktopLyricAppearance.defaults.copyWith(textOpacity: .4),
        revision: 1));
    service.killDesktopLyric();
    await Future<void>.delayed(Duration.zero);
    expect(saves, 1);
    await service.startDesktopLyric();
    save.complete();
    await Future<void>.delayed(Duration.zero);
    expect(
        (await processes[1].messages()).where((message) =>
            message['type'] == 'DesktopLyricAppearanceSavedMessage'),
        isEmpty);
    expect(preferences.value.textOpacity, .4);
  });

  test(
      'appearance save failure is acknowledged and retry keeps the chosen value',
      () async {
    final preferences = AppSettings.instance.desktopLyricAppearance;
    final previous = preferences.value;
    final process = _Process();
    var fail = true;
    final service = DesktopLyricService(PlayService.instance,
        executableExists: (_) => true,
        startProcess: (_, __) async => process,
        saveAppearance: () async {
          if (fail) throw const FileSystemException('fixture failure');
        });
    addTearDown(() async {
      service.dispose();
      preferences.value = previous;
      await process.dispose();
    });
    await service.startDesktopLyric();
    final value =
        DesktopLyricAppearance.defaults.copyWith(backgroundOpacity: .7);
    await process
        .emit(msg.DesktopLyricAppearanceChangedMessage(value, revision: 1));
    await Future<void>.delayed(const Duration(milliseconds: 550));
    expect(
        (await process.messages()).lastWhere((message) =>
            message['type'] == 'DesktopLyricAppearanceSavedMessage')['message'],
        {'revision': 1, 'saved': false});
    expect(preferences.value, value);
    fail = false;
    await process
        .emit(msg.DesktopLyricAppearanceChangedMessage(value, revision: 2));
    await Future<void>.delayed(const Duration(milliseconds: 550));
    expect(
        (await process.messages()).lastWhere((message) =>
            message['type'] == 'DesktopLyricAppearanceSavedMessage')['message'],
        {'revision': 2, 'saved': true});
  });

  test(
      'dispose unsubscribes and is idempotent without constructing native playback',
      () async {
    final experience = AppSettings.instance.experience;
    final original = experience.value;
    final initialExperienceListeners = _hasListeners(experience);
    final ready = PlayService.playbackReady as ChangeNotifier;
    final initialReadyListeners = _hasListeners(ready);
    var starts = 0;
    final service = DesktopLyricService(
      PlayService.instance,
      executableExists: (_) => true,
      startProcess: (_, __) async {
        starts++;
        throw StateError('must not start');
      },
    );
    expect(PlayService.playbackReady.value, false);
    expect(_hasListeners(experience), true);
    expect(_hasListeners(ready), true);
    service.dispose();
    service.dispose();
    expect(_hasListeners(experience), initialExperienceListeners);
    expect(_hasListeners(ready), initialReadyListeners);
    experience.value =
        original.copyWith(desktopLyricVertical: !original.desktopLyricVertical);
    await service.startDesktopLyric();
    expect(starts, 0);
    expect(service.state, DesktopLyricState.stopped);
    expect(PlayService.playbackReady.value, false);
    experience.value = original;
  });

  test(
      'launch completed after dispose is killed and cannot recover or reattach',
      () async {
    final process = _Process();
    final pending = Completer<Process>();
    var starts = 0;
    final service = DesktopLyricService(
      PlayService.instance,
      executableExists: (_) => true,
      startProcess: (_, __) {
        starts++;
        return pending.future;
      },
    );
    addTearDown(() async {
      service.dispose();
      await process.dispose();
    });
    final launch = service.startDesktopLyric();
    expect(service.state, DesktopLyricState.starting);
    service.dispose();
    pending.complete(process);
    await launch;
    expect(process.kills, 1);
    expect(service.state, DesktopLyricState.stopped);
    expect(service.isRunning, false);
    expect(starts, 1);
    expect(PlayService.playbackReady.value, false);
  });

  test('same executable lyric startup sends orientation and clock without BASS',
      () async {
    final preferences = AppSettings.instance.experience;
    final original = preferences.value;
    preferences.value =
        original.copyWith(desktopLyricVertical: true, playbackRate: 1.75);
    final process = _Process();
    List<String>? arguments;
    String? launchedExecutable;
    String? checkedExecutable;
    final service = DesktopLyricService(
      PlayService.instance,
      executableExists: (executable) {
        checkedExecutable = executable;
        return true;
      },
      startProcess: (executable, args) async {
        launchedExecutable = executable;
        arguments = args;
        return process;
      },
    );
    addTearDown(() async {
      service.dispose();
      preferences.value = original;
      await process.dispose();
    });
    await service.startDesktopLyric();
    expect(service.isRunning, true);
    expect(PlayService.playbackReady.value, false);
    expect(checkedExecutable, Platform.resolvedExecutable);
    expect(launchedExecutable, Platform.resolvedExecutable);
    expect(arguments, hasLength(2));
    expect(arguments!.first, '--desktop-lyric');
    final init = json.decode(arguments!.last);
    expect(init['vertical'], true);
    expect(init['isPlaying'], false);
    final messages = await process.messages();
    expect(
        messages.any((message) =>
            message['type'] == 'DesktopLyricDisplayMessage' &&
            message['message']['vertical'] == true),
        true);
    final timeline = messages.lastWhere(
        (message) => message['type'] == 'PlaybackTimelineMessage')['message'];
    expect(timeline['positionMilliseconds'], 0);
    expect(timeline['playing'], false);
    expect(timeline['playbackRate'], 1);
  });

  test('ordinary close keeps preference subscription for a later reopen',
      () async {
    final preferences = AppSettings.instance.experience;
    final original = preferences.value;
    final processes = [_Process(), _Process()];
    var index = 0;
    final service = DesktopLyricService(
      PlayService.instance,
      executableExists: (_) => true,
      startProcess: (_, __) async => processes[index++],
    );
    addTearDown(() async {
      service.dispose();
      preferences.value = original;
      for (final process in processes) {
        await process.dispose();
      }
    });
    await service.startDesktopLyric();
    service.killDesktopLyric();
    expect(_hasListeners(preferences), true);
    preferences.value = original.copyWith(desktopLyricVertical: true);
    await service.startDesktopLyric();
    preferences.value = preferences.value.copyWith(desktopLyricVertical: false);
    final messages = await processes[1].messages();
    final direction = messages.lastWhere(
        (message) => message['type'] == 'DesktopLyricDisplayMessage');
    expect(direction['message']['vertical'], false);
    expect(index, 2);
    expect(PlayService.playbackReady.value, false);
  });
}
