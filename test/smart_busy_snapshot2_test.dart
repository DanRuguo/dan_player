import 'dart:async';
import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/smart_playlist_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/smart_playlist.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore extends SmartPlaylistStore {
  _MemoryStore() : super(File('unused-smart-busy-fixture'));
  final saved = <SmartPlaylist>[];
  final saving = Completer<void>();
  @override
  Future<List<SmartPlaylist>> list() async => List.of(saved);
  @override
  Future<void> upsert(SmartPlaylist rule) async {
    await saving.future;
    saved.add(rule);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (const String.fromEnvironment('DAN_SMART_BUSY_RENDER').isEmpty) return;
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    await (FontLoader('packages/material_symbols_icons/MaterialSymbolsOutlined')
          ..addFont(rootBundle.load(
              'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  for (final accessibility in [false, true]) {
    testWidgets(
        '${accessibility ? 'accessibility' : 'feedback preference'} stops loading preview and save tickers while keeping busy visible',
        (tester) async {
      final loading = Completer<SmartPlaylistStore>();
      final preview = Completer<List<Audio>>();
      final store = _MemoryStore();
      final statistics = PlaybackStatistics.inMemory();
      final changes = ValueNotifier(0);
      addTearDown(statistics.dispose);
      addTearDown(changes.dispose);
      var reduced = true;
      late StateSetter changeMotion;
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: applyAppControlTheme(ThemeData(
                fontFamily: danEmbeddedFontFamily,
                fontFamilyFallback: danFontFamilyFallback,
                colorScheme: ColorScheme.fromSeed(
                    seedColor: Colors.deepPurple, brightness: Brightness.dark),
                visualDensity: VisualDensity.compact)),
            builder: (context, child) => StatefulBuilder(
              builder: (context, setState) {
                changeMotion = setState;
                return UiLanguageScope(
                  child: MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(disableAnimations: accessibility && reduced),
                    child: MotionPreferencesScope(
                      preferences: const MotionPreferences()
                          .all(accessibility || !reduced),
                      child: child!,
                    ),
                  ),
                );
              },
            ),
            home: Scaffold(
                body: SmartPlaylistsDialog(
              loadStore: () => loading.future,
              statistics: statistics,
              libraryChanges: changes,
              library: () => [],
              evaluate: (_, __) => preview.future,
            )),
          )));

      Future<void> capture(String stage) async {
        const output = String.fromEnvironment('DAN_SMART_BUSY_RENDER');
        if (output.isEmpty || accessibility) return;
        await tester.ensureVisible(find.byKey(ValueKey('smart-$stage-busy')));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          try {
            final bytes =
                await image.toByteData(format: drawing.ImageByteFormat.png);
            final file = File('$output/$stage.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }

      Future<void> expectStatic(String key) async {
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey(key)), findsOneWidget);
        expect(
            find.descendant(
                of: find.byKey(ValueKey(key)),
                matching: find.byIcon(Icons.hourglass_top)),
            findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.binding.hasScheduledFrame, isFalse);
        await tester.pump(const Duration(seconds: 2));
        expect(tester.binding.hasScheduledFrame, isFalse);
      }

      Future<void> expectMotion(Type type) async {
        changeMotion(() => reduced = false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 240));
        expect(find.byType(type), findsOneWidget);
        expect(tester.binding.transientCallbackCount, greaterThan(0));
        expect(tester.binding.hasScheduledFrame, isTrue);
        changeMotion(() => reduced = true);
      }

      await expectStatic('smart-loading-busy');
      await capture('loading');
      await expectMotion(CircularProgressIndicator);
      await expectStatic('smart-loading-busy');
      loading.complete(store);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('smart-new')));
      await expectStatic('smart-preview-busy');
      await capture('preview');
      await expectMotion(LinearProgressIndicator);
      await expectStatic('smart-preview-busy');
      preview.complete([]);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('smart-name')), 'Busy fixture');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('smart-save')));
      await tester.tap(find.byKey(const ValueKey('smart-save')));
      await expectStatic('smart-saving-busy');
      await capture('saving');
      expect(
          tester.widget<PopScope>(find.byType(PopScope).last).canPop, isFalse);
      await expectMotion(LinearProgressIndicator);
      await expectStatic('smart-saving-busy');
      store.saving.complete();
      await tester.pumpAndSettle();
      expect(store.saved.single.name, 'Busy fixture');
      expect(find.byKey(const ValueKey('smart-saving-busy')), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
