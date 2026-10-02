import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/listening_status_fixture.dart';
import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

class _Playback extends Fake implements PlaybackService {
  bool accepts = true;
  final requests = <({List<Audio> audios, bool next})>[];
  @override
  final resolvingAudioPath = ValueNotifier<String?>(null);
  @override
  bool enqueueAudios(List<Audio> audios, {bool next = false}) {
    requests.add((audios: List.of(audios), next: next));
    return accepts;
  }

  @override
  void addToNext(Audio audio) => requests.add((audios: [audio], next: true));
}

Future<void> _show(WidgetTester tester, Audio audio, _Playback service,
    {double width = 1000, double scale = 1, GlobalKey? capture}) async {
  sizePlaylistFeature(tester, width: width, height: 900);
  await tester.pumpWidget(listeningStatusHost(
      AppPresentationHost(
          child: ListView(padding: const EdgeInsets.all(16), children: [
        AudioTile(
            audioIndex: 0,
            playlist: [audio],
            columns: true,
            playbackService: service),
      ])),
      scale: scale,
      boundary: capture,
      brightness: width < 500 ? Brightness.dark : Brightness.light));
  await tester.pumpAndSettle();
  final trigger = find.byKey(ValueKey('audio-columns-menu-${audio.path}'));
  if (trigger.evaluate().isNotEmpty) {
    await tester.tap(trigger);
  } else {
    await tester.longPress(find.byType(AudioTile));
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final renderDirectory = Platform.environment['DAN_QUEUE_ACTION_RENDER_DIR'];
  final previousLanguage = uiLanguage.value;
  setUpAll(() async {
    await loadPlaylistFeatureFonts();
    if (renderDirectory == null) return;
    final qa = path.join(Directory.current.parent.path, 'tool', 'qa-local');
    if (!path.isWithin(qa, renderDirectory)) {
      throw StateError('Render output must stay in workspace QA');
    }
    await Directory(renderDirectory).create(recursive: true);
  });
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = previousLanguage);

  for (final online in [false, true]) {
    testWidgets(
        'play next is retained without the removed queue action online=$online',
        (tester) async {
      final service = _Playback();
      addTearDown(service.resolvingAudioPath.dispose);
      final audio = CategoryTestAudio('Selected', online: online);
      await _show(tester, audio, service);
      for (final label in ['按点选顺序播放', '本曲播放设置', '响度与峰值分析', '音频文件校验']) {
        expect(find.text(ui(label)), findsNothing);
      }
      final next = find.text(ui('下一首播放'));
      expect(next, findsOneWidget);
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(service.requests.single.audios, [same(audio)]);
      expect(service.requests.single.next, isTrue);
      expect(PlayService.hasFacade, isFalse);
      expect(tester.takeException(), isNull);
    });
    for (final accepts in [false, true]) {
      testWidgets('append ${online ? 'online' : 'local'} accepts=$accepts',
          (tester) async {
        final service = _Playback()..accepts = accepts;
        addTearDown(service.resolvingAudioPath.dispose);
        final audio = CategoryTestAudio('Selected', online: online);
        await _show(tester, audio, service);
        final action = find.byKey(ValueKey('audio-append-queue-${audio.path}'));
        expect(action, findsOneWidget);
        final item = tester.widget<MenuItemButton>(action);
        expect((item.leadingIcon! as Icon).icon, isNotNull);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(service.requests.single.audios, [same(audio)]);
        expect(service.requests.single.next, isFalse);
        expect(
            find.text(accepts ? ui('已加入播放队列：{0} 首', [1]) : ui('歌曲正在加载，请稍后重试')),
            findsOneWidget);
        expect(PlayService.hasFacade, isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets(
          'queue actions render ${language.name} ${narrow ? 'narrow' : 'wide'}',
          (tester) async {
        uiLanguage.value = language;
        final service = _Playback();
        addTearDown(service.resolvingAudioPath.dispose);
        final audio = CategoryTestAudio('Long title / 长标题 / 긴 제목 / 長い曲名');
        final capture = GlobalKey();
        await _show(tester, audio, service,
            width: narrow ? 320 : 1000,
            scale: narrow ? 2 : 1,
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
      });
    }
  }
}
