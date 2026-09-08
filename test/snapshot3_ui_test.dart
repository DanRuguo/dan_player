import 'dart:io';
import 'dart:ui' as drawing;
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/personal_library_dialog.dart';
import 'package:dan_player/component/playlist_management_dialog.dart';
import 'package:dan_player/component/smart_condition_editor.dart';
import 'package:dan_player/component/listening_tools_dialog.dart';
import 'package:dan_player/component/eq_presets_dialog.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/library/smart_condition.dart';
import 'package:dan_player/play_service/named_queue_store.dart';
import 'package:dan_player/play_service/eq_preset_store.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _Personal extends PersonalLibrary {
  _Personal() : super(File('unused-test-store'));
  @override
  Future<Map<String, PersonalTrack>> snapshot() async => {
        Audio.fromMap({'path': r'J:\synthetic\Canon.wav'}).stableTrackId:
            const PersonalTrack(
                rating: 4, tags: ['Night', 'Chorus · 副歌 · サビ · 후렴', 'Favorite'])
      };
}

class _Eq extends EqPresetStore {
  _Eq() : super(File('unused-test-store'));
  @override
  Future<List<Map<String, dynamic>>> list() async => [
        {
          'id': 'one',
          'name': 'Night · 夜の音楽 · 밤의 음악',
          'gains': List.filled(10, 0.0)
        }
      ];
}

class _Queues extends NamedQueueStore {
  _Queues() : super(File('unused-test-store'));
  @override
  Future<List<Map<String, dynamic>>> list() async => [
        {
          'id': 'one',
          'name': 'Morning · 朝の音楽 · 아침 음악',
          'queue': ['a', 'b']
        }
      ];
}

class _Playback extends Fake implements PlaybackService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const export = String.fromEnvironment('DAN_S3_RENDER');
  setUpAll(() async {
    for (final font in [
      (danEmbeddedFontFamily, 'assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      )
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    final korean = File('C:/Windows/Fonts/malgun.ttf');
    if (await korean.exists()) {
      final bytes = await korean.readAsBytes();
      await (FontLoader('Malgun Gothic')
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }
  });
  for (final language in UiLanguage.values) {
    for (final scenario in ['light', 'dark', 'narrow']) {
      final dark = scenario != 'light';
      for (final page in [
        'personal',
        'columns',
        'conditions',
        'queues',
        'eq',
        'trash'
      ]) {
        testWidgets('$page ${language.name} $scenario', (tester) async {
          uiLanguage.value = language;
          tester.view.physicalSize = scenario == 'narrow'
              ? const Size(380, 560)
              : const Size(720, 760);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(() => uiLanguage.value = UiLanguage.zh);
          final scheme = ColorScheme.fromSeed(
              seedColor: dark ? Colors.deepOrange : Colors.teal,
              brightness: dark ? Brightness.dark : Brightness.light);
          final theme = Entry(welcome: false).fromSchemeAndFontFamily(
              colorScheme: scheme, fontFamily: danEmbeddedFontFamily);
          final capture = GlobalKey();
          final originalTrash = List<Map<String, dynamic>>.of(playlistTrash);
          addTearDown(() => playlistTrash
            ..clear()
            ..addAll(originalTrash));
          if (page == 'trash') {
            playlistTrash
              ..clear()
              ..add({
                'id': 'qa-trash',
                'deletedAt': 1788825600000,
                'playlist': {'name': 'Night · 夜の音楽 · 밤의 음악'}
              });
          }
          Widget content = switch (page) {
            'personal' => PersonalTrackEditor(store: _Personal(), targets: [
                Audio.fromMap({
                  'path': r'J:\synthetic\Canon.wav',
                  'title': 'Canon · 卡农 · カノン · 캐논',
                  'artist': 'QA Artist',
                  'album': 'QA Album',
                  'duration': 120,
                  'created': 123
                })
              ]),
            'columns' =>
              PlaylistPresentationDialog(playlist: Playlist('QA Playlist', {})),
            'conditions' => AlertDialog(
                title: Text(ui('筛选规则'), textAlign: TextAlign.center),
                content: SizedBox(
                    width: 560,
                    child: SingleChildScrollView(
                        child: SmartConditionEditor(
                            value: const SmartCondition.group([
                              SmartCondition.term(
                                  SmartField.ratingAtLeast, '4'),
                              SmartCondition.group([
                                SmartCondition.term(
                                    SmartField.personalTag, 'Night')
                              ], any: true),
                            ]),
                            onChanged: (_) {})))),
            'trash' => const PlaylistTrashDialog(),
            'queues' =>
              NamedQueuesDialog(service: _Playback(), store: _Queues()),
            _ => EqPresetsDialog(service: _Playback(), store: _Eq()),
          };
          await tester.pumpWidget(RepaintBoundary(
              key: capture,
              child: UiLanguageScope(
                  child: MaterialApp(
                theme: theme,
                debugShowCheckedModeBanner: false,
                locale: language.locale,
                supportedLocales: UiLanguage.values.map((l) => l.locale),
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(scenario == 'narrow'
                            ? 1.5
                            : dark
                                ? 1.8
                                : 1)),
                    child: child!),
                home: Scaffold(
                    backgroundColor: scheme.surfaceContainer,
                    body: Builder(
                        builder: (context) => TextButton(
                              onPressed: () => showAppDialog<void>(
                                  context: context, builder: (_) => content),
                              child: const Text('Open review dialog'),
                            ))),
              ))));
          await tester.tap(find.text('Open review dialog'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final icon
              in tester.widgetList<IconButton>(find.byType(IconButton))) {
            final color = (icon.style?.foregroundColor ??
                    theme.iconButtonTheme.style!.foregroundColor)!
                .resolve({});
            expect(color, scheme.primary);
            expect(icon.tooltip, isNotNull);
          }
          if (scenario == 'narrow' &&
              ['eq', 'queues', 'trash'].contains(page)) {
            final action = find.byTooltip(ui(page == 'trash' ? '永久移除' : '删除'));
            await tester.ensureVisible(action);
            await tester.pumpAndSettle();
            expect(action.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
          if (export.isNotEmpty) {
            await tester.runAsync(() async {
              final image = await (capture.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
              final data =
                  await image.toByteData(format: drawing.ImageByteFormat.png);
              final file = File('$export/$page-${language.name}-$scenario.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
          if (page == 'personal') {
            await tester.ensureVisible(find.text('Night'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Night'));
            await tester.pumpAndSettle();
            expect(find.text(ui('删除')).hitTestable(), findsOneWidget);
            expect(find.text(ui('确定')).hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
            if (export.isNotEmpty)
              await tester.runAsync(() async {
                final image = await (capture.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
                final data =
                    await image.toByteData(format: drawing.ImageByteFormat.png);
                await File('$export/edit-tag-${language.name}-$scenario.png')
                    .writeAsBytes(data!.buffer.asUint8List());
                image.dispose();
              });
          }
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
