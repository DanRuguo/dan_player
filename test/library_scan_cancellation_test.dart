import 'dart:async';
import 'dart:io';
import 'dart:ui' as drawing;
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/library_refresh_progress.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/library_mutation_gate.dart';
import 'package:dan_player/library/library_refresh.dart';
import 'package:dan_player/src/rust/api/tag_reader.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('cancel waits for native exit, skips reload, and releases the gate once',
      () async {
    final source = StreamController<IndexActionState>();
    final gate = LibraryMutationGate();
    var cancels = 0, reloads = 0, releases = 0;
    final task = LibraryRefreshTask(
        gate: gate,
        scan: () => source.stream,
        cancelNative: () {
          cancels++;
          return 'cancelling';
        },
        releaseNative: () {
          releases++;
        },
        commit: () async {
          reloads++;
          return 0;
        });
    task.start();
    await task.requestCancel();
    await task.requestCancel();
    expect(task.phase, LibraryRefreshPhase.cancelling);
    expect(gate.isBusy, isTrue);
    expect(cancels, 1);
    expect(reloads, 0);
    source.addError(StateError('INDEX_SCAN_CANCELLED|fixture'));
    await source.close();
    await task.completed;
    expect(task.phase, LibraryRefreshPhase.cancelled);
    expect(task.error, isNull);
    expect(reloads, 0);
    expect(releases, 1);
    expect(gate.isBusy, isFalse);
    expect(LibraryRefreshTask.active.value, isNull);
    await gate.run(() async {});
  });

  test('commit wins a late cancel and reload retains the gate until finished',
      () async {
    final source = StreamController<IndexActionState>();
    final gate = LibraryMutationGate();
    final reload = Completer<int>();
    var reloads = 0;
    final task = LibraryRefreshTask(
        gate: gate,
        scan: () => source.stream,
        cancelNative: () => 'committing',
        commit: () {
          reloads++;
          return reload.future;
        });
    task.start();
    await task.requestCancel();
    expect(task.phase, LibraryRefreshPhase.committing);
    expect(task.canCancel, isFalse);
    await source.close();
    await Future<void>.delayed(Duration.zero);
    expect(gate.isBusy, isTrue);
    expect(reloads, 1);
    reload.complete(3);
    await task.completed;
    expect(task.phase, LibraryRefreshPhase.completed);
    expect(task.pendingMetadata, 3);
    expect(gate.isBusy, isFalse);
    expect(task.takeCompletionNotice(), isTrue);
    expect(task.takeCompletionNotice(), isFalse);
  });

  test('prepared cancellation does not dispatch native work', () async {
    var scans = 0, releases = 0;
    final task = LibraryRefreshTask(
        gate: LibraryMutationGate(),
        scan: () {
          scans++;
          return const Stream.empty();
        },
        cancelNative: () => 'cancelling',
        releaseNative: () {
          releases++;
        },
        commit: () async => throw StateError('must not reload'));
    await task.requestCancel();
    task.start();
    await task.completed;
    expect(scans, 0);
    expect(releases, 1);
    expect(task.phase, LibraryRefreshPhase.cancelled);
  });

  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    await (FontLoader('packages/material_symbols_icons/MaterialSymbolsOutlined')
          ..addFont(rootBundle.load(
              'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf')))
        .load();
    final koreanFont =
        File('${Platform.environment['WINDIR']}/Fonts/malgun.ttf');
    if (await koreanFont.exists()) {
      final bytes = await koreanFont.readAsBytes();
      await (FontLoader('Malgun Gothic')
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }
  });
  for (final scene in [
    (
      LibraryRefreshPhase.scanning,
      UiLanguage.zh,
      Brightness.light,
      const Size(820, 640),
      1.0
    ),
    (
      LibraryRefreshPhase.cancelling,
      UiLanguage.zh,
      Brightness.dark,
      const Size(600, 500),
      1.0
    ),
    (
      LibraryRefreshPhase.committing,
      UiLanguage.en,
      Brightness.light,
      const Size(400, 640),
      2.0
    ),
    (
      LibraryRefreshPhase.cancelled,
      UiLanguage.ja,
      Brightness.dark,
      const Size(430, 640),
      1.5
    ),
    (
      LibraryRefreshPhase.completed,
      UiLanguage.ko,
      Brightness.light,
      const Size(420, 640),
      1.5
    ),
    (
      LibraryRefreshPhase.failed,
      UiLanguage.zh,
      Brightness.dark,
      const Size(420, 500),
      2.0
    ),
  ]) {
    testWidgets(
        'scan progress production layout ${scene.$1.name} ${scene.$2.name}',
        (tester) async {
      tester.view.physicalSize = scene.$4;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      uiLanguage.value = scene.$2;
      addTearDown(() => uiLanguage.value = UiLanguage.zh);
      final source = StreamController<IndexActionState>();
      final task = LibraryRefreshTask(
          gate: LibraryMutationGate(),
          scan: () => source.stream,
          cancelNative: () => 'cancelling',
          commit: () async => 0)
        ..phase = scene.$1;
      final capture = GlobalKey();
      final theme = Entry(welcome: false).fromSchemeAndFontFamily(
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff9d583c), brightness: scene.$3),
          fontFamily: danEmbeddedFontFamily);
      await tester.pumpWidget(UiLanguageScope(
          child: MaterialApp(
              theme: theme,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scene.$5)),
                  child: child!),
              home: RepaintBoundary(
                  key: capture,
                  child: Scaffold(
                      body: Center(
                          child: Dialog(
                              insetPadding: const EdgeInsets.all(16),
                              child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(24),
                                  child: SizedBox(
                                      width: 440,
                                      child: LibraryRefreshProgress(
                                          task: task,
                                          onBackground: () {}))))))))));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(
          find.byKey(const ValueKey('library-refresh-phase')), findsOneWidget);
      const output = String.fromEnvironment('DAN_PLAYER_UPDATE_RENDER_DIR');
      if (output.isNotEmpty) {
        final boundary =
            capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            final bytes =
                await image.toByteData(format: drawing.ImageByteFormat.png);
            final file =
                File('$output/scan-${scene.$1.name}-${scene.$2.name}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
      await tester.pumpWidget(const SizedBox());
      await source.close();
      await tester.pump();
      await task.completed;
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }
}
