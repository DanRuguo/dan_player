import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/play_service/desktop_lyric_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:desktop_lyric/appearance_palette_app.dart';
import 'package:desktop_lyric/appearance_palette_bridge.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/desktop_lyric_theme_transition.dart';
import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/message.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/desktop_lyric_test_support.dart';
import 'support/palette_test_bridge.dart';

AppFontPolicy _policy(String name, {UiLanguage language = UiLanguage.en}) {
  AppFontFace face(String suffix) => AppFontFace(
      id: '$name-$suffix',
      family: 'QA$name$suffix',
      nativeFamily: '$name $suffix');
  return AppFontPolicy(
      language: language,
      mixedScripts: true,
      zh: face('zh'),
      en: face('en'),
      ja: face('ja'),
      ko: face('ko'));
}

InitArgsMessage _initial(AppFontPolicy? policy) => InitArgsMessage(
    true, 'title', 'artist', 'album', false, 0xff2266aa, 0xffffffff, 0xff000000,
    language: 'en', fontPolicy: policy);

ThemeChangedMessage _theme(AppFontPolicy? policy) =>
    ThemeChangedMessage(0xff2266aa, 0xffffffff, 0xff000000, fontPolicy: policy);

Map<String, Object?> _snapshot(AppFontPolicy policy,
        {int session = 1, int revision = 1}) =>
    {
      'session': session,
      'revision': revision,
      'editAck': 0,
      'appearance': DesktopLyricAppearance.defaults.toJson(),
      'darkMode': false,
      'primary': 0xff2266aa,
      'surfaceContainer': 0xffffffff,
      'onSurface': 0xff000000,
      'language': policy.language.code,
      'fontPolicy': policy.toJson(),
      'fontFamily': policy.uiFamily,
      'fontFamilyFallback': policy.fallback,
      'saveError': null,
      'layoutError': null,
    };

class _FontProcess extends Fake implements Process {
  final _input = StreamController<List<int>>();
  final _exit = Completer<int>();
  final bytes = <int>[];
  late final input = IOSink(_input.sink, encoding: utf8);
  _FontProcess() {
    _input.stream.listen(bytes.addAll);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalLanguage = uiLanguage.value;
  tearDown(() => uiLanguage.value = originalLanguage);

  test('font policy initial and theme JSON preserve all script choices', () {
    final policy = _policy('chosen', language: UiLanguage.ja);
    expect(
        InitArgsMessage.fromJson(_initial(policy).toJson()).fontPolicy, policy);
    final json = jsonDecode(_theme(policy).buildMessageJson()) as Map;
    expect(
        ThemeChangedMessage.fromJson(Map<String, dynamic>.from(json['message']))
            .fontPolicy,
        policy);
    final oldInitial = _initial(null).toJson()..remove('fontPolicy');
    expect(InitArgsMessage.fromJson(oldInitial).fontPolicy, isNull);
    expect(
        ThemeChangedMessage.fromJson(
            {'primary': 1, 'surfaceContainer': 2, 'onSurface': 3}).fontPolicy,
        isNull);
  });

  test('initial desktop state waits for ready faces and keeps media time',
      () async {
    final gate = Completer<void>();
    final clock =
        PlaybackClock(automaticTicks: false, nowMilliseconds: () => 100);
    final controller = DesktopLyricController.detached(
        clock: clock, ensureFontsLoaded: (_) => gate.future);
    addTearDown(controller.dispose);
    final policy = _policy('initial');
    controller.applyInitialState(_initial(policy));
    expect(controller.fontPolicy.value, isNot(policy));
    expect(controller.isPlaying.value, isTrue);
    var ready = false;
    final preparing = controller.fontsReady.then((_) => ready = true);
    await Future<void>.delayed(Duration.zero);
    expect(ready, isFalse);
    gate.complete();
    await preparing;
    expect(controller.fontPolicy.value, policy);
    expect(clock.positionMilliseconds, 0);
  });

  test('late desktop font load cannot replace newer request or legacy colors',
      () async {
    final first = _policy('first'), second = _policy('second');
    final gates = {first: Completer<void>(), second: Completer<void>()};
    final controller = DesktopLyricController.detached(
        clock: PlaybackClock(automaticTicks: false),
        ensureFontsLoaded: (policy) => gates[policy]!.future);
    addTearDown(controller.dispose);
    controller.handleMessage(_theme(first).buildMessageJson());
    final initialWait = controller.fontsReady;
    controller.handleMessage(_theme(second).buildMessageJson());
    gates[first]!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(controller.fontPolicy.value, isNot(first));
    gates[second]!.complete();
    await initialWait;
    expect(controller.fontPolicy.value, second);
    controller
        .handleMessage(const ThemeChangedMessage(1, 2, 3).buildMessageJson());
    expect(controller.theme.value.primary, 1);
    expect(controller.fontPolicy.value, second);
  });

  test('re-selecting ready desktop policy cancels pending font ownership',
      () async {
    final gate = Completer<void>();
    final controller = DesktopLyricController.detached(
        clock: PlaybackClock(automaticTicks: false),
        ensureFontsLoaded: (_) => gate.future);
    addTearDown(controller.dispose);
    final ready = controller.fontPolicy.value;
    controller.handleMessage(_theme(_policy('cancelled')).buildMessageJson());
    controller.handleMessage(_theme(ready).buildMessageJson());
    await controller.fontsReady;
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(controller.fontPolicy.value, ready);
  });

  test('desktop failed font load retains last usable face and permits retry',
      () async {
    var attempts = 0;
    final policy = _policy('retry');
    final controller = DesktopLyricController.detached(
        clock: PlaybackClock(automaticTicks: false),
        ensureFontsLoaded: (_) async {
          if (++attempts == 1) {
            throw const FileSystemException('QA missing font');
          }
        });
    addTearDown(controller.dispose);
    final before = controller.fontPolicy.value;
    controller.handleMessage(_theme(policy).buildMessageJson());
    await controller.fontsReady;
    expect(controller.fontPolicy.value, before);
    controller.handleMessage(_theme(policy).buildMessageJson());
    await controller.fontsReady;
    expect(attempts, 2);
    expect(controller.fontPolicy.value, policy);
  });

  test('font load finishing after desktop dispose cannot notify', () async {
    final gate = Completer<void>();
    final controller = DesktopLyricController.detached(
        clock: PlaybackClock(automaticTicks: false),
        ensureFontsLoaded: (_) => gate.future);
    var updates = 0;
    controller.fontPolicy.addListener(() => updates++);
    controller.handleMessage(_theme(_policy('closed')).buildMessageJson());
    controller.dispose();
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(updates, 0);
  });

  test('main helper spawn and replay use latest font policy without BASS',
      () async {
    final before = _policy('spawn'), after = _policy('after');
    var policy = before;
    final process = _FontProcess();
    final gate = Completer<Process>();
    Map<String, dynamic>? initial;
    final readiness = ValueNotifier(false);
    final service = DesktopLyricService(PlayService.instance,
        playbackReady: readiness,
        executableExists: (_) => true,
        readFontPolicy: () => policy,
        startProcess: (_, args) {
          initial = jsonDecode(args.last) as Map<String, dynamic>;
          return gate.future;
        },
        saveAppearance: () async {});
    addTearDown(() async {
      service.dispose();
      readiness.dispose();
      await process.input.close();
    });
    final starting = service.startDesktopLyric();
    expect(AppFontPolicy.fromJson(initial!['fontPolicy']), before);
    policy = after;
    gate.complete(process);
    await starting;
    final messages = await process.messages();
    final latest =
        messages.lastWhere((value) => value['type'] == 'ThemeChangedMessage');
    expect(AppFontPolicy.fromJson(latest['message']['fontPolicy']), after);
    expect(PlayService.playbackReady.value, isFalse);
  });

  test('palette host publishes ready font choices instead of fixed defaults',
      () async {
    final controller = DesktopLyricController.detached(
        clock: PlaybackClock(automaticTicks: false),
        ensureFontsLoaded: (_) async {});
    final layout = DesktopLyricWindowLayout(adapter: FakeDesktopLyricWindow());
    final channel = PaletteLoopbackChannel('test/font_host');
    final calls = <MethodCall>[];
    channel.request = (call) async {
      calls.add(call);
      return null;
    };
    final host = DesktopLyricPaletteHost(
        controller: controller, layout: layout, channel: channel);
    addTearDown(() {
      host.dispose();
      controller.dispose();
      layout.dispose();
    });
    final policy = _policy('palette', language: UiLanguage.ko);
    controller.handleMessage(_theme(policy).buildMessageJson());
    await controller.fontsReady;
    final opening = host.open();
    await Future<void>.delayed(Duration.zero);
    final snapshot =
        calls.firstWhere((call) => call.method == 'open').arguments as Map;
    expect(AppFontPolicy.fromJson(snapshot['fontPolicy']), policy);
    expect(snapshot['fontFamily'], policy.uiFamily);
    final changed = _policy('live', language: UiLanguage.ja);
    controller.handleMessage(_theme(changed).buildMessageJson());
    await controller.fontsReady;
    await Future<void>.delayed(Duration.zero);
    expect(
        AppFontPolicy.fromJson((calls
            .lastWhere((call) => call.method == 'update')
            .arguments as Map)['fontPolicy']),
        changed);
    await channel
        .receiver!(MethodCall('closed', {'session': snapshot['session']}));
    await opening;
  });

  test('palette initialization awaits own engine font loading without echo',
      () async {
    final gate = Completer<void>();
    final channel = PaletteLoopbackChannel('test/font_palette_initial');
    var edits = 0;
    channel.request = (call) async {
      if (call.method == 'edit') edits++;
      return null;
    };
    final client = DesktopLyricPaletteClient(
        channel: channel, ensureFontsLoaded: (_) => gate.future);
    addTearDown(client.dispose);
    final policy = _policy('palette-initial');
    var ready = false;
    final initializing = client
        .initialize(initialSnapshot: _snapshot(policy))
        .then((_) => ready = true);
    await Future<void>.delayed(Duration.zero);
    expect(ready, isFalse);
    expect(client.fontFamily, isNot(policy.uiFamily));
    gate.complete();
    await initializing;
    expect(client.fontPolicy, policy);
    expect(client.fontFamily, policy.uiFamily);
    expect(edits, 0);
  });

  test('palette late old-session font cannot replace a new presentation',
      () async {
    final old = _policy('old-panel'), current = _policy('new-panel');
    final gates = {old: Completer<void>(), current: Completer<void>()};
    final client = DesktopLyricPaletteClient(
        channel: PaletteLoopbackChannel('test/font_palette_session'),
        ensureFontsLoaded: (policy) => gates[policy]!.future);
    addTearDown(client.dispose);
    client.applySnapshot(_snapshot(old));
    client.suspend();
    client.applySnapshot(_snapshot(current, session: 2), beginSession: true);
    gates[current]!.complete();
    await client.fontsReady;
    gates[old]!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(client.fontPolicy, current);
    expect(client.fontFamily, current.uiFamily);
    expect(client.active, isTrue);
  });

  testWidgets('palette ready fonts reach actual UI theme and script scope',
      (tester) async {
    final client = DesktopLyricPaletteClient(
        channel: PaletteLoopbackChannel('test/font_palette_theme'),
        ensureFontsLoaded: (_) async {});
    addTearDown(client.dispose);
    final policy = _policy('actual-theme', language: UiLanguage.ja);
    await client.initialize(initialSnapshot: _snapshot(policy));
    await tester.pumpWidget(DesktopLyricAppearanceApp(client: client));
    await tester.pumpAndSettle();
    final context =
        tester.element(find.byKey(const ValueKey('desktop-appearance-close')));
    expect(Theme.of(context).textTheme.bodyMedium!.fontFamily, policy.uiFamily);
    expect(AppFontScope.of(context), policy);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('color transition preserves immediate same-color font changes',
      (tester) async {
    ThemeChangedMessage? shown;
    Widget host(ThemeChangedMessage colors) => MaterialApp(
        home: DesktopLyricThemeTransition(
            colors: colors,
            builder: (_, value, __) {
              shown = value;
              return const SizedBox();
            }));
    final first = _policy('color-first'), second = _policy('color-second');
    await tester.pumpWidget(host(_theme(first)));
    await tester.pumpWidget(host(_theme(second)));
    expect(shown!.fontPolicy, second);
    await tester.pumpWidget(host(ThemeChangedMessage(
        0xff992255, 0xff333333, 0xffeeeeee,
        fontPolicy: first)));
    await tester.pump(const Duration(milliseconds: 70));
    expect(shown!.fontPolicy, first);
    expect(shown!.primary, isNot(0xff992255));
    await tester.pumpAndSettle();
    expect(shown!.fontPolicy, first);
    expect(shown!.primary, 0xff992255);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
