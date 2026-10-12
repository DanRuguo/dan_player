import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:desktop_lyric/appearance_controller.dart';
import 'package:desktop_lyric/component/desktop_lyric_text.dart';
import 'package:desktop_lyric/component/lyric_line_view.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/message.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

final _qa = p.join(Directory.current.parent.path, 'tool', 'qa-local',
    'kana-layout-feedback-oct11', 'ui', 'visibility');
const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');
const _window = MethodChannel('window_manager');
const _primary = ValueKey('desktop-primary-lyric');
const _canonical = LyricLineTimelineMessage(
    sequence: 7,
    lineIndex: 2,
    startMilliseconds: 1000,
    lengthMilliseconds: 6000,
    content: '夜空を読む',
    translation: 'Read the night sky',
    romanization: 'Authored romanization',
    japaneseReading: 'よぞらをよむ',
    japaneseReadingSpans: [
      DesktopJapaneseReadingSpan(start: 0, end: 2, text: 'よぞら')
    ],
    words: [
      DesktopLyricWord(1000, 2000, '夜空'),
      DesktopLyricWord(3000, 4000, 'を読む')
    ]);

class _Pipe {
  final input = StreamController<List<int>>(sync: true);
  int now = 1000;
  late final clock =
      PlaybackClock(nowMilliseconds: () => now, automaticTicks: false);
  late final helper = DesktopLyricController.detached(
      clock: clock,
      input: input.stream,
      sendMessage: (_) {},
      closeWindow: () async {},
      ensureFontsLoaded: (_) async {});

  void send(Message message) => sendRaw(message.buildMessageJson());
  void sendRaw(String frame) {
    // Feed the production UTF-8/LineSplitter pipe, including byte splits inside
    // Japanese graphemes. No direct apply/fromJson shortcuts stand in for IPC.
    for (var offset = 0, bytes = utf8.encode(frame);
        offset < bytes.length;
        offset += 11) {
      input.add(bytes.sublist(offset, math.min(offset + 11, bytes.length)));
    }
  }

  void initialize() {
    // Ensure the controller's listener exists before emitting stream events.
    helper;
    send(const NowPlayingChangedMessage('夜空', '歌手', '专辑'));
    send(const PlaybackTimelineMessage(7, 1500, true));
    send(_canonical);
  }

  Future<void> dispose() async {
    helper.dispose();
    await input.close();
  }
}

void main({bool onlyRender = false, String onlyCase = ''}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  bool selected(String name) => onlyCase.isEmpty || name.contains(onlyCase);
  void policyTest(String name, FutureOr<void> Function() body) {
    if (!onlyRender && selected(name)) test(name, body);
  }

  void renderingTest(String name, Future<void> Function(WidgetTester) body) {
    if (selected(name)) testWidgets(name, body);
  }

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUpAll(() async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
    expect(Directory.systemTemp.absolute.path.replaceAll('\\', '/'),
        contains('/tool/qa-local/'));
    await ensureAppFontsLoaded(AppFontPolicy.defaults(language: UiLanguage.ja));
  });

  policyTest(
      'main Japanese visibility persists through the real settings file and legacy reload',
      () async {
    final fixture = await Directory(_qa)
        .create(recursive: true)
        .then((directory) => directory.createTemp('settings-'));
    messenger.setMockMethodCallHandler(
        _pathProvider, (_) async => fixture.path);
    messenger.setMockMethodCallHandler(_window, (call) async {
      throw StateError(
          'Visibility must not query native window geometry: ${call.method}');
    });
    final settings = AppSettings.instance;
    final original = settings.desktopLyricAppearance.value;
    final originalLanguage = uiLanguage.value;
    final support = await getAppDataDir();
    expect(p.isWithin(_qa, support.absolute.path), isTrue);
    final settingsFile = File(p.join(support.path, 'settings.json'));
    final base = DesktopLyricAppearance.defaults.copyWith(
        lyricFontSize: 30, lyricLetterSpacing: 3, taskbarTranslation: true);
    settings.desktopLyricAppearance.value = base;
    final controller = LyricViewController(
        preferences: NowPlayingPagePreference.fromMap({}),
        appearance: settings.desktopLyricAppearance,
        persistAppearance: () => settings.saveSettings(
            throwOnError: true, captureWindowSize: false));
    addTearDown(() {
      controller.dispose();
      settings.desktopLyricAppearance.value = original;
      uiLanguage.value = originalLanguage;
      messenger.setMockMethodCallHandler(_pathProvider, null);
      messenger.setMockMethodCallHandler(_window, null);
    });
    for (final visible in [false, true]) {
      controller.toggleJapaneseReading();
      expect(controller.showJapaneseReading, visible);
      expect(
          settings.desktopLyricAppearance.value.showJapaneseReading, visible);
      await controller.persistJapaneseReadingVisibility();
      final json = jsonDecode(await settingsFile.readAsString()) as Map;
      expect(json['DesktopLyricAppearance']['showJapaneseReading'], visible);
      expect(json['DesktopLyricAppearance']['lyricLetterSpacing'], 3);
      expect(json['DesktopLyricAppearance']['taskbarTranslation'], isTrue);
      // Change the live value before reading the actual disk snapshot.
      settings.desktopLyricAppearance.value =
          base.copyWith(showJapaneseReading: !visible);
      await AppSettings.readFromJson();
      expect(controller.showJapaneseReading, visible);
      expect(settings.desktopLyricAppearance.value,
          base.copyWith(showJapaneseReading: visible));
    }
    final oldJson = jsonDecode(await settingsFile.readAsString()) as Map;
    (oldJson['DesktopLyricAppearance'] as Map).remove('showJapaneseReading');
    await settingsFile.writeAsString(jsonEncode(oldJson));
    controller.setShowJapaneseReading(false);
    await AppSettings.readFromJson();
    expect(controller.showJapaneseReading, isTrue,
        reason: 'Old settings retain the historical visible default.');
    expect(settings.desktopLyricAppearance.value, base);
  });

  renderingTest(
      'Japanese appearance IPC hides only ruby and keeps the live media identity',
      (tester) async {
    final pipe = _Pipe();
    addTearDown(pipe.dispose);
    pipe.initialize();
    await tester.pump();
    final helper = pipe.helper;
    final policy = AppFontPolicy.defaults(language: UiLanguage.ja);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
            fontFamily: policy.uiFamily, fontFamilyFallback: policy.fallback),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: AppFontScope(policy: policy, child: child!)),
        home: Scaffold(
            body: Provider<ThemeChangedMessage>.value(
                value: helper.theme.value,
                child: ChangeNotifierProvider<TextDisplayController>.value(
                    value: helper.appearance,
                    child: Center(
                        child: SizedBox(
                            width: 500,
                            height: 140,
                            child: LyricLineView(controller: helper))))))));
    await tester.pumpAndSettle();
    final detailed = helper.detailedLyricLine.value;
    final legacy = helper.lyricLine.value;
    final song = helper.nowPlaying.value;
    final revision = helper.playbackClock.revision;
    expect(detailed!.japaneseReadingSpans, hasLength(1));
    expect(tester.widget<DesktopLyricText>(find.byKey(_primary)).rubySpans,
        hasLength(1));
    for (var index = 0; index < 2; index++) {
      pipe.now += 50;
      final visible = index == 1;
      pipe.send(DesktopLyricAppearanceMessage(
          DesktopLyricAppearance.defaults
              .copyWith(showJapaneseReading: visible),
          revision: index + 1));
      await tester.pumpAndSettle();
      expect(helper.appearance.value.showJapaneseReading, visible);
      expect(tester.widget<DesktopLyricText>(find.byKey(_primary)).rubySpans,
          visible ? hasLength(1) : isEmpty);
      expect(helper.activeSequence, 7);
      expect(helper.detailedLyricLine.value, same(detailed));
      expect(helper.lyricLine.value, same(legacy));
      expect(helper.nowPlaying.value, same(song));
      expect(helper.playbackClock.revision, revision);
      expect(helper.playbackClock.positionMilliseconds, 1550 + index * 50);
      expect(helper.playbackClock.playing, isTrue);
      expect(find.byKey(const ValueKey('desktop-romanization-lyric')),
          findsOneWidget);
      expect(
          tester
              .widget<DesktopLyricText>(
                  find.byKey(const ValueKey('desktop-romanization-lyric')))
              .text,
          'Authored romanization');
      expect(helper.detailedLyricLine.value!.translation, 'Read the night sky');
      expect(helper.detailedLyricLine.value!.japaneseReading, 'よぞらをよむ');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  policyTest(
      'invalid and retired Japanese visibility pipe snapshots preserve the active state',
      () async {
    final pipe = _Pipe();
    addTearDown(pipe.dispose);
    pipe.initialize();
    final hidden =
        DesktopLyricAppearance.defaults.copyWith(showJapaneseReading: false);
    pipe.send(DesktopLyricAppearanceMessage(hidden, revision: 1));
    await Future<void>.delayed(Duration.zero);
    final detailed = pipe.helper.detailedLyricLine.value;
    final revision = pipe.clock.revision;
    expect(pipe.helper.appearance.value, hidden);
    for (final malformed in ['false', 0, null, <String>[]]) {
      pipe.sendRaw('${jsonEncode({
            'type': 'DesktopLyricAppearanceMessage',
            'message': {
              'revision': 99,
              'appearance': {
                ...hidden.toJson(),
                'showJapaneseReading': malformed
              }
            }
          })}\n');
      await Future<void>.delayed(Duration.zero);
      expect(pipe.helper.appearance.value, hidden);
      expect(pipe.helper.detailedLyricLine.value, same(detailed));
      expect(pipe.clock.revision, revision);
    }
    pipe.send(const DesktopLyricAppearanceMessage(
        DesktopLyricAppearance.defaults,
        revision: 0));
    await Future<void>.delayed(Duration.zero);
    expect(pipe.helper.appearance.value, hidden);
    // A rejected high revision must not poison the valid next snapshot.
    pipe.send(const DesktopLyricAppearanceMessage(
        DesktopLyricAppearance.defaults,
        revision: 2));
    await Future<void>.delayed(Duration.zero);
    expect(pipe.helper.appearance.value.showJapaneseReading, isTrue);
    expect(pipe.helper.detailedLyricLine.value, same(detailed));
    expect(pipe.helper.activeSequence, 7);
    expect(pipe.clock.revision, revision);
    expect(pipe.clock.positionMilliseconds, 1500);
    expect(pipe.clock.playing, isTrue);
  });
}
