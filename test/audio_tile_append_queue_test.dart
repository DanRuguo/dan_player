import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/music_category_fixtures.dart';

class _Playback extends Fake implements PlaybackService {
  bool accepts = true;
  final requests = <({List<Audio> audios, bool next})>[];
  int starts = 0, playNexts = 0;

  @override
  final resolvingAudioPath = ValueNotifier<String?>(null);

  @override
  bool enqueueAudios(List<Audio> audios, {bool next = false}) {
    requests.add((audios: List.of(audios), next: next));
    return accepts;
  }

  @override
  void play(int index, List<Audio> audios) => starts++;

  @override
  void addToNext(Audio audio) => playNexts++;
}

Future<void> _show(WidgetTester tester, Audio audio, _Playback service,
    {double width = 1000,
    double scale = 1,
    Brightness brightness = Brightness.light,
    GlobalKey? capture}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  final theme = Entry(welcome: false).fromSchemeAndFontFamily(
      colorScheme:
          ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness),
      fontFamily: danEmbeddedFontFamily);
  await tester.pumpWidget(RepaintBoundary(
    key: capture,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale), disableAnimations: true),
        child: UiLanguageScope(child: AppPresentationHost(child: child!)),
      ),
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AudioTile(
              audioIndex: 1,
              playlist: [CategoryTestAudio('Unselected neighbor'), audio],
              columns: true,
              playbackService: service,
            ),
          ],
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  final trigger = find.byKey(ValueKey('audio-columns-menu-${audio.path}'));
  if (trigger.evaluate().isNotEmpty) {
    await tester.tap(trigger);
  } else {
    // The compact row retains its existing touch/secondary-click entry.
    await tester.longPress(find.byType(AudioTile));
  }
  await tester.pumpAndSettle();
}

void main() {
  final renderDirectory = Platform.environment['DAN_TILE_APPEND_RENDER_DIR'];
  final previousLanguage = uiLanguage.value;
  setUpAll(() async {
    if (renderDirectory == null) return;
    final qa = path.join(Directory.current.parent.path, 'tool', 'qa-local');
    if (!path.isWithin(qa, renderDirectory)) {
      throw StateError('Render output must stay in workspace QA');
    }
    await Directory(renderDirectory).create(recursive: true);
    for (final font in [
      (danEmbeddedFontFamily, 'packages/desktop_lyric/assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      ),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    // Match the production theme's actual Korean fallback, not missing glyphs.
    final korean = await File('C:/Windows/Fonts/malgun.ttf').readAsBytes();
    await (FontLoader('Malgun Gothic')
          ..addFont(Future.value(ByteData.sublistView(korean))))
        .load();
  });
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = previousLanguage);

  for (final online in [false, true]) {
    for (final accepts in [false, true]) {
      testWidgets(
          'single ${online ? 'online' : 'local'} append accepts=$accepts',
          (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = _Playback()..accepts = accepts;
        addTearDown(service.resolvingAudioPath.dispose);
        final audio = CategoryTestAudio('Selected', online: online);
        await _show(tester, audio, service);
        final action = find.byKey(ValueKey('audio-append-queue-${audio.path}'));
        expect(action, findsOneWidget);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(service.requests.single.audios, [same(audio)]);
        expect(service.requests.single.next, isFalse);
        expect(service.starts, 0,
            reason: 'The menu must not issue an extra play command.');
        expect(service.playNexts, 0,
            reason: 'Appending preserves the existing upcoming song.');
        expect(
            find.text(accepts ? ui('已加入播放队列：{0} 首', [1]) : ui('歌曲正在加载，请稍后重试')),
            findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(PlayService.hasFacade, isFalse,
            reason: 'The injected session must avoid native player creation.');
      });
    }
  }

  for (final language in UiLanguage.values) {
    testWidgets('append menu fits ${language.name} narrow and wide',
        (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      uiLanguage.value = language;
      final service = _Playback();
      addTearDown(service.resolvingAudioPath.dispose);
      final audio = CategoryTestAudio('Long title / 长标题 / 긴 제목 / 長い曲名');
      for (final narrow in [false, true]) {
        final capture = GlobalKey();
        await _show(tester, audio, service,
            width: narrow ? 320 : 1000,
            scale: narrow ? 2 : 1,
            brightness: narrow ? Brightness.dark : Brightness.light,
            capture: capture);
        final action = find.byKey(ValueKey('audio-append-queue-${audio.path}'));
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        expect(action.hitTestable(), findsOneWidget);
        final label =
            find.descendant(of: action, matching: find.text(ui('加入播放队尾')));
        expect(tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
            isFalse);
        final bounds = tester.getRect(action);
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(narrow ? 320 : 1000));
        expect(tester.takeException(), isNull);
        if (renderDirectory != null) {
          final boundary = capture.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image = await tester.runAsync(() => boundary.toImage());
          try {
            final bytes = await tester.runAsync(
                () => image!.toByteData(format: raster.ImageByteFormat.png));
            await tester.runAsync(() => File(path.join(renderDirectory,
                    '${language.name}-${narrow ? 'narrow' : 'wide'}.png'))
                .writeAsBytes(bytes!.buffer.asUint8List()));
          } finally {
            image!.dispose();
          }
        }
        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();
      }
    });
  }
}
