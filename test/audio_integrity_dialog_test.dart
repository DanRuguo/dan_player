import 'dart:async';
import 'dart:io';

import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/audio_integrity_dialog.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/ffmpeg_setup_card.dart';
import 'package:dan_player/library/audio_integrity.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_trim.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:desktop_lyric/l10n/catalog_audio_integrity.dart';
import 'package:desktop_lyric/l10n/ui_catalog.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/listening_status_fixture.dart';
import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String value) => find.byKey(ValueKey(value));
const _report = AudioIntegrityReport(
    path: 'J:/QA/曲名 & track.wav',
    sha256: 'abcd0123456789efabcd0123456789efabcd0123456789efabcd0123456789ef',
    bytes: 12345678,
    decodedSeconds: 128.42);

class _Check {
  final completion = Completer<AudioIntegrityReport>();
  AudioTrimCancellation? token;
  void Function(AudioIntegrityProgress)? update;
  int calls = 0;
  Future<AudioIntegrityReport> run(Audio audio, AudioTrimCancellation token,
      void Function(AudioIntegrityProgress) update) {
    calls++;
    this.token = token;
    this.update = update;
    return completion.future;
  }
}

class _MenuPlayback extends Fake implements PlaybackService {
  @override
  final resolvingAudioPath = ValueNotifier<String?>(null);
}

class _CueAudio extends CategoryTestAudio {
  _CueAudio() : super('CUE track', path: _cue.identity);
  static const _cue = CueTrackReference(
      cuePath: 'J:/QA/disc.cue',
      sourcePath: 'J:/QA/disc.wav',
      number: 2,
      startFrame: 75,
      endFrame: 150);
  @override
  CueTrackReference get cueTrack => _cue;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadPlaylistFeatureFonts();
    final windows = Platform.environment['WINDIR'];
    if (windows == null) return;
    for (final font in [
      ('Segoe UI Symbol', 'seguisym.ttf'),
      ('Segoe UI Emoji', 'seguiemj.ttf')
    ]) {
      final file = File('$windows/Fonts/${font.$2}');
      if (!await file.exists()) continue;
      await (FontLoader(font.$1)
            ..addFont(
                Future.value(ByteData.sublistView(await file.readAsBytes()))))
          .load();
    }
  });
  tearDown(() {
    uiLanguage.value = UiLanguage.zh;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
  final audio = CategoryTestAudio('月夜 — A long song title 마지막 밤의 선율 🎵');
  Future<void> mount(WidgetTester tester,
      {AudioIntegrityInspect? inspect,
      Future<bool> Function()? tools,
      Audio? item,
      double width = 1080,
      double scale = 1,
      GlobalKey? boundary,
      bool narrow = false}) async {
    sizePlaylistFeature(tester, width: width, height: 1080);
    await tester.pumpWidget(listeningStatusHost(
        Builder(
            builder: (context) => FilledButton(
                key: const ValueKey('open-integrity'),
                onPressed: () => showAppDialog<void>(
                    context: context,
                    builder: (_) => AudioIntegrityDialog(
                        audio: item ?? audio,
                        inspect: inspect,
                        ensureTools: tools ?? () async => true)),
                child: const Text('Open'))),
        scale: scale,
        seed: narrow ? Colors.deepOrange : Colors.indigo,
        brightness: narrow ? Brightness.dark : Brightness.light,
        boundary: boundary));
    await tester.tap(_key('open-integrity'));
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester) async {
    await tester.ensureVisible(_key('integrity-start'));
    await tester.tap(_key('integrity-start'));
    await tester.pumpAndSettle();
  }

  test('all integrity messages are translated and routed through the catalog',
      () {
    for (final entry in catalogAudioIntegrity.entries) {
      expect(entry.value, hasLength(3));
      for (var i = 0; i < 3; i++) {
        expect(entry.value[i].trim(), isNotEmpty);
        expect(uiCatalog[entry.key]![i], entry.value[i]);
        uiLanguage.value = UiLanguage.values[i + 1];
        expect(ui(entry.key), entry.value[i]);
      }
    }
  });
  testWidgets('tool check does not start work until an explicit click',
      (tester) async {
    final tools = Completer<bool>();
    final check = _Check();
    await mount(tester, inspect: check.run, tools: () => tools.future);
    expect(check.calls, 0);
    expect(
        tester.widget<FilledButton>(_key('integrity-start')).onPressed, isNull);
    tools.complete(true);
    await tester.pumpAndSettle();
    expect(check.calls, 0);
    await start(tester);
    expect(check.calls, 1);
    check.completion.complete(_report);
    await tester.pumpAndSettle();
    expect(find.text(ui('解码检查通过')), findsOneWidget);
  });
  testWidgets('missing tools and remote songs cannot launch a file check',
      (tester) async {
    final check = _Check();
    await mount(tester, inspect: check.run, tools: () async => false);
    expect(find.byType(FfmpegSetupCard), findsOneWidget);
    expect(
        tester.widget<FilledButton>(_key('integrity-start')).onPressed, isNull);
    await tester.tap(_key('integrity-close'));
    await tester.pumpAndSettle();
    await mount(tester,
        inspect: check.run, item: CategoryTestAudio('Online', online: true));
    expect(
        tester.widget<FilledButton>(_key('integrity-start')).onPressed, isNull);
    expect(check.calls, 0);
  });
  testWidgets('closing cancels work and rejects late success and progress',
      (tester) async {
    final check = _Check();
    await mount(tester, inspect: check.run);
    await start(tester);
    await tester.tap(_key('integrity-close'));
    await tester.pumpAndSettle();
    expect(check.token!.isCancelled, isTrue);
    check
        .update!(const AudioIntegrityProgress(AudioIntegrityPhase.hashing, .8));
    check.completion.complete(_report);
    await tester.pump();
    expect(find.byType(AudioIntegrityDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'cancel rejects late success and retry rejects old generation progress',
      (tester) async {
    final first = _Check(), second = _Check();
    var calls = 0;
    await mount(tester,
        inspect: (audio, token, update) =>
            (calls++ == 0 ? first : second).run(audio, token, update));
    await start(tester);
    await tester.tap(_key('integrity-cancel'));
    await tester.pump();
    expect(first.token!.isCancelled, isTrue);
    first.completion.complete(_report);
    await tester.pumpAndSettle();
    expect(find.text(ui('已取消文件校验')), findsOneWidget);
    expect(find.text(ui('解码检查通过')), findsNothing);
    await start(tester);
    second
        .update!(const AudioIntegrityProgress(AudioIntegrityPhase.hashing, .4));
    first.update!(
        const AudioIntegrityProgress(AudioIntegrityPhase.decoding, .9));
    await tester.pump();
    expect(
        tester
            .widget<LinearProgressIndicator>(_key('integrity-progress'))
            .value,
        .4);
    second.completion.complete(_report);
    await tester.pumpAndSettle();
    expect(find.text(ui('解码检查通过')), findsOneWidget);
  });
  testWidgets('unknown progress has no fake percentage or idle animation',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final check = _Check();
    try {
      await mount(tester, inspect: check.run);
      await start(tester);
      expect(
          tester
              .widget<LinearProgressIndicator>(_key('integrity-progress'))
              .value,
          0);
      expect(find.textContaining('0%'), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      check.update!(
          const AudioIntegrityProgress(AudioIntegrityPhase.decoding, null));
      await tester.pump();
      expect(find.text(ui('正在检查音频解码…')), findsOneWidget);
      await tester.tap(_key('integrity-close'));
      await tester.pumpAndSettle();
      check.completion.complete(_report);
      await tester.pump();
    } finally {
      semantics.dispose();
    }
  });
  testWidgets(
      'copied report contains the exact hash, source, bytes and decoded duration',
      (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'];
      }
      return null;
    });
    await mount(tester, inspect: (_, __, ___) async => _report);
    await start(tester);
    await tester.tap(_key('integrity-copy'));
    await tester.pumpAndSettle();
    for (final value in [_report.path, _report.sha256, '12345678', '128.42']) {
      expect(copied, contains(value));
    }
    expect(copied, contains(ui('校验值用于核对文件副本；解码检查不代表已与原始文件比对。')));
  });
  testWidgets('closing during readiness ignores its late result',
      (tester) async {
    final tools = Completer<bool>();
    final check = _Check();
    await mount(tester, inspect: check.run, tools: () => tools.future);
    await tester.tap(_key('integrity-close'));
    await tester.pumpAndSettle();
    tools.complete(true);
    await tester.pump();
    expect(check.calls, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('late clipboard feedback cannot replace a restarted inspection',
      (tester) async {
    for (final failure in [false, true]) {
      final clipboard = Completer<void>();
      final next = _Check();
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') await clipboard.future;
        return null;
      });
      await mount(tester,
          inspect: (audio, token, update) => calls++ == 0
              ? Future.value(_report)
              : next.run(audio, token, update));
      await start(tester);
      await tester.tap(_key('integrity-copy'));
      await tester.pump();
      await start(tester);
      if (failure) {
        clipboard.completeError(PlatformException(code: 'clipboard-failure'));
      } else {
        clipboard.complete();
      }
      await tester.pumpAndSettle();
      expect(find.text(ui('文件校验结果已复制')), findsNothing);
      expect(find.text(ui('无法复制校验结果，请重试')), findsNothing);
      next.completion.complete(_report);
      await tester.pumpAndSettle();
      expect(find.text(ui('解码检查通过')), findsOneWidget);
      expect(find.text(ui('无法复制校验结果，请重试')), findsNothing);
      await tester.tap(_key('integrity-close'));
      await tester.pumpAndSettle();
    }
  });
  testWidgets('CUE explains the whole source scope', (tester) async {
    await mount(tester,
        inspect: (_, __, ___) async => _report, item: _CueAudio());
    expect(find.text(ui('校验 CUE 对应的整份源文件')), findsOneWidget);
    await start(tester);
    expect(find.text(ui('解码检查通过')), findsOneWidget);
  });
  testWidgets('song context menu omits tools reserved for the lyrics page',
      (tester) async {
    sizePlaylistFeature(tester, width: 360, height: 1080);
    final playback = _MenuPlayback();
    addTearDown(playback.resolvingAudioPath.dispose);
    for (final online in [false, true]) {
      final item = CategoryTestAudio('Track', online: online);
      await tester.pumpWidget(listeningStatusHost(
          AppPresentationHost(
              child: ListView(children: [
            AudioTile(
                audioIndex: 0,
                playlist: [item],
                columns: true,
                playbackService: playback)
          ])),
          scale: 2,
          brightness: Brightness.dark));
      await tester.pumpAndSettle();
      final trigger = find.byKey(ValueKey('audio-columns-menu-${item.path}'));
      if (trigger.evaluate().isNotEmpty) {
        await tester.tap(trigger);
      } else {
        await tester.longPress(find.byType(AudioTile));
      }
      await tester.pumpAndSettle();
      for (final label in ['本曲播放设置', '响度与峰值分析', '音频文件校验']) {
        expect(find.text(ui(label)), findsNothing);
      }
      expect(PlayService.hasFacade, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });
  testWidgets(
      'manual tool readiness respects feedback motion native reduction and hiding',
      (tester) async {
    final completion = Completer<bool>();
    final enabled = ValueNotifier(true);
    final visible = ValueNotifier(true);
    addTearDown(enabled.dispose);
    addTearDown(visible.dispose);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ValueListenableBuilder<bool>(
                  valueListenable: enabled,
                  builder: (context, motion, _) => MotionPreferencesScope(
                      preferences: MotionPreferences(
                          disabled: motion ? const {} : {MotionKind.feedback}),
                      child: ValueListenableBuilder<bool>(
                          valueListenable: visible,
                          builder: (context, visibility, _) => TickerMode(
                              enabled: visibility,
                              child: SingleChildScrollView(
                                  child: FfmpegSetupCard(
                                      onReady: () {},
                                      ensureTools: () =>
                                          completion.future)))))))));
      await tester.tap(find.text(ui('我已安装好')));
      await tester.pump(const Duration(seconds: 1));
      expect(
          tester
              .widget<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator))
              .value,
          isNull);
      enabled.value = false;
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator))
              .value,
          0);
      expect(find.textContaining('0%'), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      enabled.value = true;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator))
              .value,
          0);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      visible.value = false;
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator))
              .value,
          0);
      expect(tester.binding.transientCallbackCount, 0);
      completion.complete(false);
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
          find.text(ui('组件仍不可用。请检查网络、工具是否完整及目录权限，或手动安装后重试。')), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets(
          'integrity renders ${language.name} ${narrow ? 'narrow-large' : 'wide'}',
          (tester) async {
        uiLanguage.value = language;
        final boundary = GlobalKey();
        await mount(tester,
            inspect: (_, __, ___) async => _report,
            width: narrow ? 360 : 1080,
            scale: narrow ? 2 : 1,
            narrow: narrow,
            boundary: boundary);
        final prefix = '${language.name}-${narrow ? 'narrow-large' : 'wide'}';
        await capturePlaylistFeature(tester, boundary, '$prefix-ready');
        expect(tester.takeException(), isNull);
        await start(tester);
        await tester.ensureVisible(find.text(_report.sha256));
        await tester.pumpAndSettle();
        await capturePlaylistFeature(tester, boundary, '$prefix-result');
        final scheme =
            Theme.of(tester.element(find.byType(AudioIntegrityDialog)))
                .colorScheme;
        for (final text in tester.widgetList<SelectableText>(find.descendant(
            of: find.byType(AudioIntegrityDialog),
            matching: find.byType(SelectableText)))) {
          expect(text.style!.color, scheme.primary);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
