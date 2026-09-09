import 'dart:io';
import 'dart:ui' as drawing;
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/album_tile.dart';
import 'package:dan_player/component/batch_audio_metadata_dialog.dart';
import 'package:dan_player/component/cover_repair_dialog.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/batch_audio_metadata.dart';
import 'package:dan_player/library/cover_repair.dart';
import 'package:dan_player/library/category_cover_store.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/music_category_fixtures.dart';

const _root = r'J:\Music\ゲーム音楽・長いフォルダー名\as9-nine- ARTEISIA オリジナルサウンドトラック';
final _windows = TargetPlatformVariant.only(TargetPlatform.windows);
const _renderDirectory = String.fromEnvironment('DAN_PLAYER_UPDATE_RENDER_DIR');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dataFixture;
  setUpAll(() async {
    final root = Directory(
        '${Directory.current.parent.path}/tool/qa-2605-update/ui-batch');
    await root.create(recursive: true);
    dataFixture = await root.createTemp('render-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => dataFixture.path);
    await CategoryCoverStore.shared.load();
    final korean = File('${Platform.environment['WINDIR']}/Fonts/malgun.ttf');
    if (await korean.exists()) {
      await (FontLoader('Malgun Gothic')
            ..addFont(korean.readAsBytes().then(ByteData.sublistView)))
          .load();
    } else if (_renderDirectory.isNotEmpty) {
      fail(
          'Korean PNG export requires the existing Windows Malgun Gothic font.');
    }
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    await (FontLoader('packages/material_symbols_icons/MaterialSymbolsOutlined')
          ..addFont(rootBundle.load(
              'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf')))
        .load();
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    if (!dataFixture.absolute.path.startsWith(Directory(
            '${Directory.current.parent.path}/tool/qa-2605-update/ui-batch')
        .absolute
        .path)) {
      throw StateError('Invalid owned render fixture');
    }
    await dataFixture.delete(recursive: true);
  });
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  Future<GlobalKey> mount(WidgetTester tester, Widget dialog,
      {double width = 960,
      double scale = 1,
      bool dark = false,
      bool english = false,
      UiLanguage? language}) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    uiLanguage.value = language ?? (english ? UiLanguage.en : UiLanguage.zh);
    final theme = Entry(welcome: false).fromSchemeAndFontFamily(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xffa95839),
            brightness: dark ? Brightness.dark : Brightness.light),
        fontFamily: danEmbeddedFontFamily);
    final capture = GlobalKey();
    late BuildContext route;
    await tester.pumpWidget(UiLanguageScope(
        child: MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(
                    key: capture, child: AppPresentationHost(child: child!))),
            home: Builder(builder: (context) {
              route = context;
              return const Scaffold();
            }))));
    await tester.pump();
    showAppDialog<void>(context: route, builder: (_) => dialog);
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
    return capture;
  }

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    expect(tester.takeException(), isNull);
    if (_renderDirectory.isEmpty) return;
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final bytes =
            await image.toByteData(format: drawing.ImageByteFormat.png);
        final file = File('$_renderDirectory/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
      } finally {
        image.dispose();
      }
    });
  }

  List<Audio> audios() => [
        CategoryTestAudio('結想は花となる short ver. — とても長い曲名と追加の説明',
            artist: '堀江晶太',
            album: 'as9-nine- ARTEISIA Original Soundtrack',
            path: '$_root/01 結想は花となる.flac'),
        CategoryTestAudio('Good Time',
            artist: 'Owl City & Carly Rae Jepsen',
            album: 'Good Time',
            path: '$_root/02 Good Time.flac'),
        CategoryTestAudio('卡农',
            artist: 'Various Artists',
            album: 'Canon',
            path: '$_root/03 卡农.flac'),
      ];
  BatchAudioMetadata batchFor(List<Audio> songs) => BatchAudioMetadata(songs,
      inspect: (path) async {
        final audio = songs.firstWhere((audio) => audio.path == path);
        return MetadataFileSnapshot(
            fingerprint: '1_1',
            title: audio.title,
            artist: audio.artist,
            album: audio.album);
      },
      apply: (audio, edit) async => audio);

  testWidgets('production batch metadata mixed draft light', (tester) async {
    final batch = batchFor(audios());
    addTearDown(batch.dispose);
    final key = await mount(tester, BatchAudioMetadataDialog(batch: batch));
    expect(find.textContaining('多个值'), findsWidgets);
    expect(find.text('预览修改'), findsOneWidget);
    await capture(tester, key, 'metadata-mixed-light');
  }, variant: _windows);

  testWidgets('common fields stay equal height with either editor open',
      (tester) async {
    final batch = batchFor(audios());
    addTearDown(batch.dispose);
    final key = await mount(tester, BatchAudioMetadataDialog(batch: batch));
    for (final enabled in [(true, false), (false, true), (true, true)]) {
      final controls = find.byWidgetPredicate((widget) =>
          widget is Switch && widget.key.toString().contains('batch-toggle-'));
      for (var i = 0; i < 2; i++) {
        final desired = i == 0 ? enabled.$1 : enabled.$2;
        if (tester.widget<Switch>(controls.at(i)).value != desired) {
          await tester.tap(controls.at(i));
          await tester.pumpAndSettle();
        }
      }
      final artist =
          tester.getRect(find.byKey(const ValueKey('batch-common-艺术家')));
      final album =
          tester.getRect(find.byKey(const ValueKey('batch-common-专辑')));
      expect(artist.top, album.top);
      expect(artist.bottom, album.bottom);
      await capture(
          tester, key, 'metadata-aligned-${enabled.$1}-${enabled.$2}');
    }
  }, variant: _windows);

  for (final language in UiLanguage.values) {
    testWidgets(
        'common field content aligns with unequal metadata ${language.name}',
        (tester) async {
      final songs = [
        CategoryTestAudio('Short title',
            artist: '秋山裕和',
            album:
                '美少女万華鏡 –呪われし伝説の少女– Original Soundtrack / Extended Album Edition',
            path: '$_root/short.flac'),
        CategoryTestAudio('A much longer song title — とても長い曲名と追加の説明',
            artist: '秋山裕和',
            album:
                '美少女万華鏡 –呪われし伝説の少女– Original Soundtrack / Extended Album Edition',
            path: '$_root/long.flac'),
      ];
      final batch = batchFor(songs);
      addTearDown(batch.dispose);
      final key = await mount(tester, BatchAudioMetadataDialog(batch: batch),
          language: language, dark: language == UiLanguage.ko);
      for (final part in ['label', 'summary', 'toggle', 'common']) {
        final artist = tester.getRect(find.byKey(ValueKey('batch-$part-艺术家')));
        final album = tester.getRect(find.byKey(ValueKey('batch-$part-专辑')));
        expect(artist.top, album.top,
            reason: '$part must start at the same height');
        if (part != 'summary') expect(artist.bottom, album.bottom);
      }
      final shortSummary =
          tester.getRect(find.byKey(const ValueKey('batch-summary-艺术家')));
      final longSummary =
          tester.getRect(find.byKey(const ValueKey('batch-summary-专辑')));
      expect(longSummary.height, greaterThan(shortSummary.height));
      await capture(tester, key, 'metadata-unequal-${language.name}');
      await tester.tap(find.byKey(const ValueKey('batch-toggle-专辑')));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(
          tester, key, 'metadata-unequal-album-edit-${language.name}');
    }, variant: _windows);
  }

  for (final language in UiLanguage.values) {
    testWidgets('batch draft editing controls ${language.name}',
        (tester) async {
      final batch = batchFor(audios());
      addTearDown(batch.dispose);
      final key = await mount(tester, BatchAudioMetadataDialog(batch: batch),
          width: language == UiLanguage.zh ? 960 : 480,
          scale: language == UiLanguage.zh ? 1 : 1.4,
          dark: language == UiLanguage.ko,
          language: language);
      await tester.tap(find.byKey(const ValueKey('batch-toggle-艺术家')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Demo Artist');
      final titleToggle = find.byTooltip(ui('修改此曲标题')).first;
      await tester.ensureVisible(titleToggle);
      await tester.tap(titleToggle);
      await tester.pumpAndSettle();
      final titleField = find.byWidgetPredicate((widget) =>
          widget is TextField && widget.decoration?.labelText == ui('标题'));
      await tester.ensureVisible(titleField);
      await tester.enterText(titleField, 'Edited demo title');
      await tester.pumpAndSettle();
      await capture(tester, key, 'metadata-edit-${language.name}');
      await tester.tap(find.text(ui('预览修改')));
      await tester.pumpAndSettle();
      expect(batch.targets.first.edit?.title, 'Edited demo title');
      expect(batch.targets.first.edit?.artist, 'Demo Artist');
      expect(tester.takeException(), isNull);
    }, variant: _windows);
  }

  for (final narrow in [false, true]) {
    testWidgets(
        'production batch metadata preview ${narrow ? 'english narrow 200 percent' : 'dark long paths'}',
        (tester) async {
      final batch = batchFor(audios());
      addTearDown(batch.dispose);
      await batch.preview(
          BatchMetadataDraft(artist: 'Various Artists — サウンドトラック制作チーム'));
      final key = await mount(tester, BatchAudioMetadataDialog(batch: batch),
          width: narrow ? 420 : 960,
          scale: narrow ? 2 : 1,
          dark: !narrow,
          english: narrow);
      expect(find.byType(SelectableText), findsWidgets);
      await capture(tester, key,
          narrow ? 'metadata-preview-en-narrow-200' : 'metadata-preview-dark');
    }, variant: _windows);
  }

  for (final language in [UiLanguage.ja, UiLanguage.ko]) {
    testWidgets('production batch metadata preview ${language.name} narrow',
        (tester) async {
      final batch = batchFor(audios());
      addTearDown(batch.dispose);
      await batch
          .preview(BatchMetadataDraft(album: 'ARTEISIA Original Soundtrack'));
      final key = await mount(tester, BatchAudioMetadataDialog(batch: batch),
          width: 480,
          scale: 1.5,
          dark: language == UiLanguage.ko,
          language: language);
      await capture(tester, key, 'metadata-preview-${language.name}-narrow');
    }, variant: _windows);
  }

  for (final narrow in [false, true]) {
    testWidgets(
        'production cover repair summary ${narrow ? 'narrow large text' : 'dark'}',
        (tester) async {
      final repair = CoverRepair(audios(),
          repair: (target) async => target.audio!.title == 'Good Time'
              ? CoverRepairStatus.noArtwork
              : target.audio!.title == '卡农'
                  ? CoverRepairStatus.failed
                  : CoverRepairStatus.success);
      addTearDown(repair.dispose);
      await repair.run();
      final key = await mount(tester, CoverRepairDialog(repair: repair),
          width: narrow ? 420 : 900, scale: narrow ? 2 : 1, dark: !narrow);
      expect(find.text('仅重试失败项'), findsOneWidget);
      await capture(tester, key,
          narrow ? 'cover-summary-narrow-200' : 'cover-summary-dark');
    }, variant: _windows);
  }
  testWidgets(
      'production album results disambiguate same titles with owner subtitles',
      (tester) async {
    final first = CategoryTestAudio('first',
        artist: 'Artist A', album: '同名专辑 / Shared Album');
    final second =
        CategoryTestAudio('second', artist: 'Artist B', album: first.album);
    final key = await mount(
        tester,
        Dialog(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (final audio in [first, second])
                    AlbumTile(
                        album: Album(
                            name: audio.album,
                            albumArtist: audio.artist,
                            groupId: audio.albumIdentity.id)
                          ..works.add(audio))
                ]))),
        width: 600);
    expect(find.text('Artist A'), findsOneWidget);
    expect(find.text('Artist B'), findsOneWidget);
    await capture(tester, key, 'album-results-group-owner');
  }, variant: _windows);
}
