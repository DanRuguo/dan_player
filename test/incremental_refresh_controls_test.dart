import 'dart:async';
import 'dart:io';

import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/build_index_state_view.dart';
import 'package:dan_player/page/settings_page/other_settings.dart';
import 'package:dan_player/src/rust/api/tag_reader.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {double scale = 1}) => UiLanguageScope(
      child: MaterialApp(
          home: Scaffold(
              body: MediaQuery(
        data: MediaQueryData(
            textScaler: TextScaler.linear(scale), disableAnimations: true),
        child: AppEntranceScope(child: SingleChildScrollView(child: child)),
      ))),
    );

void main() {
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  Future<void> openFolderEditor(
      WidgetTester tester, Future<Directory> Function() load) async {
    await tester.pumpWidget(_host(Builder(
        builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AudioLibraryEditorDialog(loadIndexPath: load)),
            child: const Text('open-folder-editor')))));
    await tester.tap(find.text('open-folder-editor'));
    await tester.pumpAndSettle();
  }

  testWidgets('folder index directory failure restores cancel and retry',
      (tester) async {
    final first = Completer<Directory>();
    final second = Completer<Directory>();
    var calls = 0;
    await openFolderEditor(
        tester, () => ++calls == 1 ? first.future : second.future);
    expect(calls, 0, reason: 'only confirmation may begin directory I/O');
    await tester.tap(find.text(ui('确定')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, ui('取消')))
            .onPressed,
        isNull);
    first.completeError(const FileSystemException('synthetic denied'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, ui('取消')))
            .onPressed,
        isNotNull);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, ui('确定')))
            .onPressed,
        isNotNull);
    await tester.tap(find.text(ui('确定')));
    await tester.pumpAndSettle();
    expect(calls, 2);
    second.completeError(const FileSystemException('synthetic retry denied'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ui('取消')));
    await tester.pumpAndSettle();
    expect(find.byType(AudioLibraryEditorDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('folder directory synchronous failure does not trap dialog',
      (tester) async {
    await openFolderEditor(
        tester, () => throw StateError('synthetic path provider'));
    await tester.tap(find.text(ui('确定')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, ui('取消')))
            .onPressed,
        isNotNull);
    await tester.tap(find.text(ui('取消')));
    await tester.pumpAndSettle();
    expect(find.byType(AudioLibraryEditorDialog), findsNothing);
  });

  testWidgets(
      'folder directory late error after disposal does not update old context',
      (tester) async {
    final directory = Completer<Directory>();
    await openFolderEditor(tester, () => directory.future);
    await tester.tap(find.text(ui('确定')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    directory
        .completeError(const FileSystemException('synthetic late failure'));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('scan owns an immutable folder selection snapshot',
      (tester) async {
    final folders = ['D:/synthetic-original'];
    late List<String> submitted;
    final stream = StreamController<IndexActionState>();
    await tester.pumpWidget(_host(BuildIndexStateView(
      folders: folders,
      indexPath: Directory('D:/synthetic-index'),
      scan: (value, _, __) {
        submitted = value;
        return stream.stream;
      },
      whenIndexBuilt: () {},
    )));
    folders.add('D:/late-outgoing-list-action');
    expect(submitted, ['D:/synthetic-original']);
    expect(() => submitted.add('invalid'), throwsUnsupportedError);
    unawaited(stream.close());
    await tester.pump();
  });
  for (final language in UiLanguage.values) {
    for (final width in [320.0, 800.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
            'refresh actions ${language.code} width=$width scale=$scale',
            (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          uiLanguage.value = language;
          final modes = <bool>[];
          await tester.pumpWidget(_host(
              RefreshAudioLibraryTile(
                  onRefresh: (incremental) async => modes.add(incremental)),
              scale: scale));
          await tester.pumpAndSettle();
          expect(find.text(ui('增量刷新')), findsOneWidget);
          expect(find.text(ui('完整刷新')), findsOneWidget);
          for (final key in [
            'library-refresh-incremental',
            'library-refresh-full'
          ]) {
            final finder = find.byKey(ValueKey(key));
            await tester.ensureVisible(finder);
            await tester.tap(finder);
            await tester.pumpAndSettle();
            expect(tester.getRect(finder).left, greaterThanOrEqualTo(0));
            expect(tester.getRect(finder).right, lessThanOrEqualTo(width));
          }
          expect(modes, [true, false]);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('refresh guards concurrent actions and releases after completion',
      (tester) async {
    final gate = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(_host(RefreshAudioLibraryTile(onRefresh: (_) {
      calls++;
      return gate.future;
    })));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('library-refresh-incremental'));
    await tester.tap(button);
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('library-refresh-full')))
            .onPressed,
        isNull);
    expect(calls, 1);
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
  });

  testWidgets('refresh action remains keyboard reachable', (tester) async {
    final calls = <bool>[];
    await tester.pumpWidget(_host(
        RefreshAudioLibraryTile(onRefresh: (value) async => calls.add(value))));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(calls, [true]);
  });

  for (final incremental in [true, false]) {
    testWidgets('scan selects correct mode and completes once: $incremental',
        (tester) async {
      final stream = StreamController<IndexActionState>();
      var scans = 0;
      var completions = 0;
      await tester.pumpWidget(_host(BuildIndexStateView(
        folders: const ['D:/synthetic-only'],
        indexPath: Directory('D:/synthetic-index'),
        incremental: incremental,
        scan: (folders, directory, actual) {
          scans++;
          expect(actual, incremental);
          expect(folders, ['D:/synthetic-only']);
          return stream.stream;
        },
        whenIndexBuilt: () {
          completions++;
        },
      )));
      stream.add(const IndexActionState(progress: .5, message: ''));
      await tester.pump();
      await tester.pump();
      expect(find.text(ui('正在准备扫描')), findsOneWidget);
      unawaited(stream.close());
      await tester.pumpAndSettle();
      expect(completions, 1);
      expect(scans, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed scan cannot invoke completion/cache commit',
      (tester) async {
    var completions = 0;
    var failures = 0;
    await tester.pumpWidget(_host(BuildIndexStateView(
      folders: const [],
      indexPath: Directory('D:/synthetic-index'),
      incremental: true,
      scan: (_, __, ___) => Stream.error(StateError('synthetic scan error')),
      whenIndexBuilt: () => completions++,
      whenIndexFailed: (_, __) => failures++,
    )));
    await tester.pump();
    await tester.pump();
    expect(completions, 0);
    expect(failures, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('synchronous bridge failure is delivered through error callback',
      (tester) async {
    var failures = 0;
    await tester.pumpWidget(_host(BuildIndexStateView(
      folders: const [],
      indexPath: Directory('D:/synthetic-index'),
      scan: (_, __, ___) => throw StateError('synthetic init error'),
      whenIndexBuilt: () => fail('must not complete'),
      whenIndexFailed: (_, __) => failures++,
    )));
    await tester.pump();
    expect(failures, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'disposed scanner does not reload or call callbacks on late completion',
      (tester) async {
    final stream = StreamController<IndexActionState>();
    var callbacks = 0;
    await tester.pumpWidget(_host(BuildIndexStateView(
      folders: const [],
      indexPath: Directory('D:/synthetic-index'),
      scan: (_, __, ___) => stream.stream,
      whenIndexBuilt: () => callbacks++,
      whenIndexFailed: (_, __) => callbacks++,
    )));
    await tester.pumpWidget(const SizedBox());
    unawaited(stream.close());
    await tester.pump();
    expect(callbacks, 0);
    expect(tester.takeException(), isNull);
  });
}
