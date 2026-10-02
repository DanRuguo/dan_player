import 'dart:async';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/ffmpeg_setup_card.dart';
import 'package:dan_player/component/loudness_analysis_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/library/loudness_analysis.dart';
import 'package:desktop_lyric/l10n/catalog_loudness_analysis.dart';
import 'package:desktop_lyric/l10n/ui_catalog.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/listening_status_fixture.dart';
import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String name) => find.byKey(ValueKey(name));

const _report = LoudnessReport(
    integratedLufs: -25,
    rangeLu: 6.8,
    samplePeakDb: -10.5,
    truePeakDb: -10,
    analyzedSeconds: 125.78);

class _Scan {
  final completion = Completer<LoudnessReport>();
  Audio? audio;
  LoudnessCancellation? cancellation;
  void Function(double)? progress;
  int calls = 0;
  Future<LoudnessReport> run(
      Audio item, LoudnessCancellation token, void Function(double) update) {
    calls++;
    audio = item;
    cancellation = token;
    progress = update;
    return completion.future;
  }

  void cancelled() {
    if (!completion.isCompleted) {
      completion.completeError(const LoudnessAnalysisException('已取消响度分析'));
    }
  }
}

class _CueAudio extends CategoryTestAudio {
  _CueAudio() : super('CUE 第三曲', path: _cue.identity);
  static const _cue = CueTrackReference(
      cuePath: 'D:/fixture/disc.cue',
      sourcePath: 'D:/fixture/disc.flac',
      number: 3,
      startFrame: 900,
      endFrame: 1800);
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
      ('Segoe UI Emoji', 'seguiemj.ttf'),
    ]) {
      final file = File('$windows/Fonts/${font.$2}');
      if (!await file.exists()) continue;
      await (FontLoader(font.$1)
            ..addFont(
                Future.value(ByteData.sublistView(await file.readAsBytes()))))
          .load();
    }
  });
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() {
    uiLanguage.value = UiLanguage.zh;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  final audio = CategoryTestAudio('月夜 — A long song title 마지막 밤의 선율 🎵',
      artist: 'Original artist', album: 'Original album');

  Future<void> mount(WidgetTester tester,
      {LoudnessAnalyze? analyze,
      Future<bool> Function()? ensureTools,
      Audio? item,
      double width = 1080,
      double scale = 1,
      Color seed = Colors.indigo,
      Brightness brightness = Brightness.light,
      GlobalKey? boundary}) async {
    sizePlaylistFeature(tester, width: width, height: 1080);
    final entry = Builder(
        builder: (context) => FilledButton(
            key: const ValueKey('open-loudness'),
            onPressed: () => showAppDialog<void>(
                context: context,
                builder: (_) => LoudnessAnalysisDialog(
                    audio: item ?? audio,
                    analyze: analyze,
                    ensureTools: ensureTools ?? () async => true)),
            child: const Text('Open')));
    await tester.pumpWidget(listeningStatusHost(entry,
        scale: scale, seed: seed, brightness: brightness, boundary: boundary));
    await tester.tap(_key('open-loudness'));
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester) async {
    await tester.ensureVisible(_key('loudness-start'));
    await tester.tap(_key('loudness-start'));
    await tester.pumpAndSettle();
  }

  test('all new messages have four languages and unchanged arguments', () {
    final argument = RegExp(r'\{\d+\}');
    for (final entry in catalogLoudnessAnalysis.entries) {
      expect(entry.value, hasLength(3), reason: entry.key);
      final expected =
          argument.allMatches(entry.key).map((match) => match[0]).toSet();
      for (var i = 0; i < 3; i++) {
        expect(entry.value[i].trim(), isNotEmpty, reason: entry.key);
        expect(
            argument
                .allMatches(entry.value[i])
                .map((match) => match[0])
                .toSet(),
            expected,
            reason: entry.key);
        expect(uiCatalog[entry.key]![i], entry.value[i], reason: entry.key);
        uiLanguage.value = UiLanguage.values[i + 1];
        expect(ui(entry.key), entry.value[i]);
      }
    }
  });

  testWidgets('checking tools never starts a scan until explicit start',
      (tester) async {
    final tools = Completer<bool>();
    final scan = _Scan();
    await mount(tester, analyze: scan.run, ensureTools: () => tools.future);
    expect(scan.calls, 0);
    expect(find.text(ui('正在检查音频工具…')), findsOneWidget);
    expect(
        tester.widget<FilledButton>(_key('loudness-start')).onPressed, isNull);
    tools.complete(true);
    await tester.pumpAndSettle();
    expect(scan.calls, 0);
    await start(tester);
    expect(scan.calls, 1);
    expect(scan.audio, same(audio));
    scan.completion.complete(_report);
    await tester.pumpAndSettle();
    expect(find.text('-25.0 LUFS'), findsOneWidget);
    expect(find.text('6.8 LU'), findsOneWidget);
    expect(find.text('-10.5 dBFS'), findsOneWidget);
    expect(find.text('-10.0 dBTP'), findsOneWidget);
    expect(find.text(ui('{0} 秒', ['125.78'])), findsOneWidget);
    expect(find.text(ui('分析整首源文件')), findsOneWidget);
    expect(scan.calls, 1);
  });

  testWidgets('missing tools show installation guidance without a scan',
      (tester) async {
    final scan = _Scan();
    await mount(tester, analyze: scan.run, ensureTools: () async => false);
    expect(find.byType(FfmpegSetupCard), findsOneWidget);
    expect(find.text(ui('安装音频工具')), findsOneWidget);
    expect(
        tester.widget<FilledButton>(_key('loudness-start')).onPressed, isNull);
    expect(scan.calls, 0);
  });

  testWidgets('online songs cannot start local analysis', (tester) async {
    final scan = _Scan();
    await mount(tester,
        analyze: scan.run, item: CategoryTestAudio('Online', online: true));
    expect(
        tester.widget<FilledButton>(_key('loudness-start')).onPressed, isNull);
    expect(scan.calls, 0);
  });

  testWidgets('target changes only the reference gain and copied report',
      (tester) async {
    final scan = _Scan();
    final original = AppSettings.instance.experience.value;
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    await mount(tester, analyze: scan.run);
    await start(tester);
    scan.completion.complete(_report);
    await tester.pumpAndSettle();
    expect(find.text('+7.0 dB'), findsOneWidget);
    await tester.tap(find.text('-14 LUFS'));
    await tester.pumpAndSettle();
    expect(find.text('+9.0 dB'), findsOneWidget);
    await tester.tap(_key('loudness-copy'));
    await tester.pumpAndSettle();
    expect(copied, contains('${ui('参考目标响度')}：-14 LUFS'));
    expect(copied, contains('+9.0 dB'));
    expect(copied, contains(audio.title));
    expect(copied, contains('-25.0 LUFS'));
    expect(copied, contains('6.8 LU'));
    expect(copied, contains('-10.5 dBFS'));
    expect(copied, contains('-10.0 dBTP'));
    expect(copied, contains('${ui('已分析时长')}：${ui('{0} 秒', ['125.78'])}'));
    expect(copied, contains(ui('测量原始音频，不含播放器音量、均衡器或变速处理。')));
    expect(find.text(ui('分析结果已复制')), findsOneWidget);
    expect(scan.calls, 1);
    expect(AppSettings.instance.experience.value, same(original));
    expect(audio.title, '月夜 — A long song title 마지막 밤의 선율 🎵');
  });

  testWidgets('copy failure keeps the completed report available',
      (tester) async {
    final scan = _Scan();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        throw PlatformException(code: 'clipboard-fixture');
      }
      return null;
    });
    await mount(tester, analyze: scan.run);
    await start(tester);
    scan.completion.complete(_report);
    await tester.pumpAndSettle();
    await tester.tap(_key('loudness-copy'));
    await tester.pumpAndSettle();
    expect(find.text(ui('无法复制分析结果，请重试')), findsOneWidget);
    expect(find.text('-25.0 LUFS'), findsOneWidget);
    expect(scan.calls, 1);
  });

  testWidgets('scan failure can retry without old progress publication',
      (tester) async {
    final first = _Scan(), second = _Scan();
    var calls = 0;
    await mount(tester,
        analyze: (item, token, update) =>
            (calls++ == 0 ? first : second).run(item, token, update));
    await start(tester);
    first.completion
        .completeError(const LoudnessAnalysisException('无法读取本地音频文件'));
    await tester.pumpAndSettle();
    expect(find.text(ui('无法读取本地音频文件')), findsOneWidget);
    await start(tester);
    second.progress!(.4);
    first.progress!(.9);
    first.progress!(double.nan);
    await tester.pump();
    expect(
        tester.widget<LinearProgressIndicator>(_key('loudness-progress')).value,
        .4);
    second.completion.complete(_report);
    await tester.pumpAndSettle();
    expect(find.text('-25.0 LUFS'), findsOneWidget);
    expect(find.text(ui('无法读取本地音频文件')), findsNothing);
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel rejects late success and enables a new explicit scan',
      (tester) async {
    final scan = _Scan();
    await mount(tester, analyze: scan.run);
    await start(tester);
    await tester.tap(_key('loudness-cancel'));
    await tester.pump();
    expect(scan.cancellation!.isCancelled, isTrue);
    scan.progress!(.9);
    await tester.pump();
    expect(
        tester.widget<LinearProgressIndicator>(_key('loudness-progress')).value,
        0);
    scan.completion.complete(_report);
    await tester.pumpAndSettle();
    expect(find.text(ui('已取消响度分析')), findsOneWidget);
    expect(find.text('-25.0 LUFS'), findsNothing);
    expect(tester.widget<FilledButton>(_key('loudness-start')).onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing cancels scan and ignores all late callbacks',
      (tester) async {
    final scan = _Scan();
    await mount(tester, analyze: scan.run);
    await start(tester);
    await tester.tap(_key('loudness-close'));
    await tester.pumpAndSettle();
    expect(scan.cancellation!.isCancelled, isTrue);
    scan.progress!(.7);
    scan.completion.complete(_report);
    await tester.pump();
    expect(find.byType(LoudnessAnalysisDialog), findsNothing);
    expect(find.text('-25.0 LUFS'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing during tool check ignores late readiness',
      (tester) async {
    final tools = Completer<bool>();
    final scan = _Scan();
    await mount(tester, analyze: scan.run, ensureTools: () => tools.future);
    await tester.tap(_key('loudness-close'));
    await tester.pumpAndSettle();
    tools.complete(true);
    await tester.pump();
    expect(scan.calls, 0);
    expect(find.byType(LoudnessAnalysisDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short silent CUE analysis is explicit about unavailable gain',
      (tester) async {
    final scan = _Scan();
    await mount(tester, analyze: scan.run, item: _CueAudio());
    await start(tester);
    scan.completion.complete(const LoudnessReport(
        integratedLufs: null,
        rangeLu: 0,
        samplePeakDb: null,
        truePeakDb: null,
        analyzedSeconds: .1));
    await tester.pumpAndSettle();
    expect(find.text(ui('分析当前 CUE 分轨')), findsOneWidget);
    expect(find.text(ui('低于响度门限')), findsOneWidget);
    expect(find.text(ui('静音')), findsNWidgets(2));
    expect(find.text(ui('无法估算')), findsOneWidget);
    expect(find.text(ui('音频过短、静音或低于响度门限，无法可靠估算整体响度增益。')), findsOneWidget);
    expect(find.textContaining('Infinity'), findsNothing);
    expect(find.textContaining('NaN'), findsNothing);
  });

  testWidgets('unknown reduced progress has no false percentage or idle ticker',
      (tester) async {
    final scan = _Scan();
    final semantics = tester.ensureSemantics();
    try {
      await mount(tester, analyze: scan.run);
      await start(tester);
      final owner = find.ancestor(
          of: _key('loudness-progress'),
          matching: find.byWidgetPredicate((widget) =>
              widget is Semantics && widget.properties.label == ui('正在分析响度…')));
      final data = tester.getSemantics(owner.first).getSemanticsData();
      expect(data.label, ui('正在分析响度…'));
      expect(data.value, isEmpty,
          reason: 'Unknown progress must not announce 0%');
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.transientCallbackCount, 0);
      scan.progress!(.25);
      scan.progress!(double.infinity);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<LinearProgressIndicator>(_key('loudness-progress'))
              .value,
          .25);
      expect(find.text(ui('正在分析响度：{0}%', [25])), findsOneWidget);
      await tester.tap(_key('loudness-close'));
      await tester.pumpAndSettle();
      scan.cancelled();
      await tester.pump();
    } finally {
      semantics.dispose();
    }
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets(
          'renders ${language.name} ${narrow ? 'narrow-large' : 'wide'}',
          (tester) async {
        uiLanguage.value = language;
        final boundary = GlobalKey();
        final scan = _Scan();
        final seed = narrow ? Colors.deepOrange : Colors.indigo;
        await mount(tester,
            analyze: scan.run,
            width: narrow ? 360 : 1080,
            scale: narrow ? 2 : 1,
            seed: seed,
            brightness: narrow ? Brightness.dark : Brightness.light,
            boundary: boundary);
        final prefix = '${language.name}-${narrow ? 'narrow-large' : 'wide'}';
        await capturePlaylistFeature(tester, boundary, '$prefix-ready');
        expect(tester.takeException(), isNull);
        await start(tester);
        await capturePlaylistFeature(tester, boundary, '$prefix-progress');
        scan.completion.complete(const LoudnessReport(
            integratedLufs: -20.4,
            rangeLu: 8.9,
            samplePeakDb: -.2,
            truePeakDb: .4,
            analyzedSeconds: 180.25));
        await tester.pumpAndSettle();
        await tester.ensureVisible(_key('loudness-target'));
        await tester.pumpAndSettle();
        expect(find.textContaining('-18 LUFS'), findsWidgets,
            reason: 'The selected reference remains visible in compact mode');
        await capturePlaylistFeature(tester, boundary, '$prefix-result');
        final scheme =
            Theme.of(tester.element(find.byType(LoudnessAnalysisDialog)))
                .colorScheme;
        for (final metric in tester.widgetList<SelectableText>(find.descendant(
            of: find.byType(LoudnessAnalysisDialog),
            matching: find.byType(SelectableText)))) {
          expect(metric.style!.color, scheme.primary);
        }
        final warning = find.text(ui('真峰值达到或超过 0 dBTP，请留意采样间峰值。'));
        expect(tester.widget<Text>(warning).style!.color, scheme.error);
        expect(find.byType(AppSegmentedControl<double>), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(_key('loudness-close'));
        await tester.tap(_key('loudness-close'));
        await tester.pumpAndSettle();
        expect(find.byType(LoudnessAnalysisDialog), findsNothing);
      });
    }
  }
}
