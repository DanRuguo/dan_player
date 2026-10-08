import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric_display_coordinator.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/taskbar_lyric_service.dart';
import 'package:dan_player/taskbar_lyrics_publisher.dart';
import 'package:dan_player/theme_provider.dart';
import 'package:desktop_lyric/component/taskbar_lyric_row.dart';
import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_desktop_integration.dart';

class _Source extends TaskbarLyricSource {
  @override
  final Future<Lyric?> lyric = Future.value(PlainLyric('Hello 歌詞 かな 한글'));
  @override
  int get generation => 1;
  @override
  int get session => 1;
  @override
  bool get hasTrack => true;
  @override
  double position = 0;
  @override
  bool playing = true;
  void changed() => notifyListeners();
}

class _Policies extends ValueNotifier<AppFontPolicy> {
  _Policies(super.value);
  bool get listening => hasListeners;
}

AppFontPolicy _policy(UiLanguage language, {bool shared = false}) {
  AppFontFace face(int index) => appBundledFonts[index].withPath(
      'J:/temp/codex/software/danplayer/tool/qa-local/font-management-oct8/native/fixture-${appBundledFonts[index].id}.font');
  return AppFontPolicy(
      language: language,
      mixedScripts: !shared,
      zh: face(shared ? 1 : 0),
      en: face(1),
      ja: face(shared ? 1 : 2),
      ko: face(shared ? 1 : 3),
      baseFallback: face(0));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('font snapshot retains position throttling and source ownership',
      () async {
    final source = _Source();
    final writes = <Map<String, Object>>[];
    var elapsed = Duration.zero;
    var policy = _policy(UiLanguage.zh);
    final publisher = TaskbarLyricsPublisher(
        source: source,
        elapsed: () => elapsed,
        appearance: () => TaskbarLyricAppearance(
            accent: 0xff123456,
            fontFamily: policy.uiFamily,
            fontPath: policy.uiFace.path!,
            fontPolicy: policy),
        send: (frame) async => writes.add(frame),
        onError: (error, _) => fail('$error'));
    addTearDown(() async {
      await publisher.close();
      source.dispose();
    });
    await flushDesktopEvents();
    final identity = writes.last['sourceIdentity'];
    final revision = writes.last['timelineRevision'];
    final initial = writes.length;
    final serialized = writes.last['fontPolicy'];
    expect(serialized, policy.toJson());
    for (var i = 1; i <= 10; ++i) {
      elapsed = Duration(milliseconds: i * 20);
      source.position = i / 50;
      // Equivalent snapshots can be recreated by the appearance factory.
      policy = _policy(UiLanguage.zh);
      source.changed();
      await flushDesktopEvents();
    }
    expect(writes, hasLength(initial));
    elapsed = const Duration(milliseconds: 420);
    source.position = .42;
    source.changed();
    await flushDesktopEvents();
    expect(writes, hasLength(initial + 1));
    expect(identical(writes.last['fontPolicy'], serialized), isTrue);
    policy = _policy(UiLanguage.ko, shared: true);
    publisher.refresh();
    await flushDesktopEvents();
    expect(writes.last['fontPolicy'], policy.toJson());
    expect(writes.last['sourceIdentity'], identity);
    expect(writes.last['timelineRevision'], revision);
  });

  test('tray and taskbar share policy updates and unsubscribe on dispose',
      () async {
    final native = FakeDesktopNative();
    final playback = FakeDesktopPlayback();
    final preferences =
        ValueNotifier(const PlayerExperiencePreferences(taskbarLyrics: true));
    final ready = ValueNotifier(true);
    final rendering = ValueNotifier<Object?>(null);
    final policies = _Policies(_policy(UiLanguage.ja));
    final theme = ThemeProvider.forTesting(
        seedColor: Colors.blue,
        dynamicThemeEnabled: () => false,
        loadArtwork: (_) async => null,
        extractScheme: (_, brightness) async => ColorScheme.fromSeed(
            seedColor: Colors.blue, brightness: brightness));
    var sourceCalls = 0;
    final taskbar = TaskbarLyricService(
        preferences: preferences,
        playbackReady: ready,
        rendering: rendering,
        createSource: () {
          sourceCalls++;
          return _Source();
        },
        coordinator: LyricDisplayCoordinator(),
        savePreferences: () async {});
    final integration = DesktopIntegration.forTesting(
        native: native,
        window: FakeDesktopWindow(native),
        playback: playback,
        preferences: preferences,
        taskbarLyrics: taskbar,
        themeProvider: theme,
        syncAppearance: true,
        fontPolicy: policies);
    addTearDown(() async {
      await integration.dispose();
      theme.dispose();
      preferences.dispose();
      ready.dispose();
      rendering.dispose();
      playback.dispose();
      policies.dispose();
    });
    await integration.initialize(onExit: () async {});
    await flushDesktopEvents();
    Map<String, Object> latest(String method) =>
        native.calls.lastWhere((call) => call.$1 == method).$2!;
    expect(latest('configure')['fontPolicy'], policies.value.toJson());
    expect(latest('setTaskbarLyrics')['fontPolicy'], policies.value.toJson());
    final sourceIdentity = latest('setTaskbarLyrics')['sourceIdentity'];
    final before = native.calls.where((call) => call.$1 == 'configure').length;
    policies.value = _policy(UiLanguage.ja);
    await flushDesktopEvents();
    expect(native.calls.where((call) => call.$1 == 'configure'),
        hasLength(before));
    policies.value = _policy(UiLanguage.en, shared: true);
    await flushDesktopEvents();
    expect(latest('configure')['fontPolicy'], policies.value.toJson());
    expect(latest('setTaskbarLyrics')['fontPolicy'], policies.value.toJson());
    expect(latest('setTaskbarLyrics')['fontFamily'], policies.value.uiFamily);
    expect(latest('setTaskbarLyrics')['fontPath'], policies.value.uiFace.path);
    expect(latest('setTaskbarLyrics')['sourceIdentity'], sourceIdentity);
    expect(sourceCalls, 1);
    await integration.dispose();
    final disposedCalls = native.calls.length;
    policies.value = _policy(UiLanguage.zh);
    await flushDesktopEvents();
    expect(native.calls, hasLength(disposedCalls));
    expect(policies.listening, isFalse);
  });

  test('disabled taskbar font policy never opens a lyric source', () async {
    final native = FakeDesktopNative();
    final playback = FakeDesktopPlayback();
    final preferences = ValueNotifier(const PlayerExperiencePreferences());
    final ready = ValueNotifier(true);
    final rendering = ValueNotifier<Object?>(null);
    final policies = ValueNotifier(_policy(UiLanguage.zh));
    var sourceCalls = 0;
    final taskbar = TaskbarLyricService(
        preferences: preferences,
        playbackReady: ready,
        rendering: rendering,
        createSource: () {
          sourceCalls++;
          return _Source();
        },
        coordinator: LyricDisplayCoordinator(),
        savePreferences: () async {});
    final integration = DesktopIntegration.forTesting(
        native: native,
        window: FakeDesktopWindow(native),
        playback: playback,
        preferences: preferences,
        taskbarLyrics: taskbar,
        fontPolicy: policies);
    addTearDown(() async {
      await integration.dispose();
      playback.dispose();
      preferences.dispose();
      ready.dispose();
      rendering.dispose();
      policies.dispose();
    });
    await integration.initialize(onExit: () async {});
    policies.value = _policy(UiLanguage.ko);
    await flushDesktopEvents();
    expect(sourceCalls, 0);
    for (final call
        in native.calls.where((call) => call.$1 == 'setTaskbarLyrics')) {
      expect(call.$2, {'enabled': false, 'text': ''});
    }
  });

  for (final language in UiLanguage.values) {
    test('taskbar fit uses actual ${language.code} mixed font paragraph',
        () async {
      final policy = AppFontPolicy.defaults(language: language);
      await ensureAppFontsLoaded(policy);
      const text = 'Hello e\u0301 歌詞かな 한글';
      const style = TextStyle(height: 1.25, fontWeight: FontWeight.w700);
      const scaler = TextScaler.linear(2);
      final size = taskbarLyricFontSize(text,
          style: style,
          scaler: scaler,
          direction: TextDirection.ltr,
          width: 230,
          height: 40,
          preferred: 36,
          minimum: 10,
          fontPolicy: policy);
      final painter = TextPainter(
          text: appFontSpan(text,
              style: style.copyWith(fontSize: size), policy: policy),
          maxLines: 1,
          textScaler: scaler,
          textDirection: TextDirection.ltr)
        ..layout();
      try {
        expect(painter.width, lessThanOrEqualTo(230));
        expect(painter.height, lessThanOrEqualTo(40));
        expect(size, lessThan(36));
      } finally {
        painter.dispose();
      }
    });
  }
}
