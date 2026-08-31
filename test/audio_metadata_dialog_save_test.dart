import 'dart:async';

import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/audio_metadata_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_metadata_update.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/metadata_test_audio.dart';

void main() {
  late BuildContext pageContext;
  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (_, child) => AppPresentationHost(child: child!),
      home: Scaffold(body: Builder(builder: (context) {
        pageContext = context;
        return const SizedBox.expand();
      })),
    ));
  }

  testWidgets('saving disables repeat actions and cannot be dismissed',
      (tester) async {
    await mount(tester);
    final audio = MetadataTestAudio();
    final gate = Completer<Audio>();
    var saves = 0;
    final result =
        showEditAudioMetadataDialog(pageContext, audio, saveMetadata: (_, __) {
      saves++;
      return gate.future;
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(saves, 1);
    expect(find.text('正在写入'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.ancestor(
                of: find.text('正在写入'), matching: find.byType(FilledButton)))
            .onPressed,
        isNull);
    expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .every((field) => field.enabled == false),
        isTrue);
    await Navigator.of(pageContext).maybePop();
    await tester.pump();
    expect(find.text('编辑歌曲信息'), findsOneWidget);
    gate.complete(audio);
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'disposed dialog does not cancel a committed save or use old context',
      (tester) async {
    await mount(tester);
    final audio = MetadataTestAudio();
    final native = Completer<String>();
    var synced = false;
    final coordinator = AudioMetadataEditCoordinator(
        write: (_, __) => native.future,
        synchronize: (_, __) async {
          synced = true;
        });
    unawaited(showEditAudioMetadataDialog(pageContext, audio,
        saveMetadata: coordinator.apply));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField).at(1), 'Saved after disposal');
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    native.complete('D:/metadata-fixture/renamed.mp3');
    await tester.pump();
    await tester.pump();
    expect(synced, isTrue);
    expect(audio.path, endsWith('/renamed.mp3'));
    expect(audio.title, 'Saved after disposal');
    expect(tester.takeException(), isNull);
  });

  testWidgets('post-commit warning keeps edited fields and allows retry',
      (tester) async {
    await mount(tester);
    final audio = MetadataTestAudio();
    var writes = 0;
    var syncs = 0;
    final coordinator = AudioMetadataEditCoordinator(write: (_, __) async {
      writes++;
      return 'D:/metadata-fixture/new.mp3';
    }, synchronize: (_, __) async {
      if (++syncs == 1) throw StateError('fixture');
    });
    final result = showEditAudioMetadataDialog(pageContext, audio,
        saveMetadata: coordinator.apply);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'new.mp3');
    await tester.enterText(find.byType(TextField).at(1), 'Changed');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('编辑歌曲信息'), findsOneWidget);
    expect(find.textContaining('歌曲文件已保存'), findsOneWidget);
    expect(find.textContaining('更新歌曲信息失败'), findsNothing);
    expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        'Changed');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    expect(writes, 1);
    expect(syncs, 2);
    expect(tester.takeException(), isNull);
  });
}
