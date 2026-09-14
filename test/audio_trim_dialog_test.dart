import 'dart:async';
import 'package:dan_player/component/audio_trim_dialog.dart';
import 'package:dan_player/library/audio_trim.dart';
import 'package:dan_player/library/audio_trim_preview.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/music_category_fixtures.dart';

class FakeTrimPreview extends AudioTrimPreview {
  bool _playing = false;
  final selections = <(double, double)>[];
  int stops = 0;
  @override
  bool get playing => _playing;
  @override
  bool get loading => false;
  @override
  String? get error => null;
  @override
  Future<void> play(double start, double end) async {
    selections.add((start, end));
    _playing = true;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    stops++;
    _playing = false;
    notifyListeners();
  }
}

const trimTestInfo = AudioTrimInfo(
    duration: 123.456,
    formatLabel: 'MP3',
    outputExtension: '.mp3',
    canOverwrite: true);

void main() {
  setUp(() => uiLanguage.value = UiLanguage.zh);

  test('native errors use localized messages without internal codes or paths',
      () {
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      final tags = audioTrimErrorMessage(StateError(
          'AnyhowException(TRIM_TAGS_UNSUPPORTED|C:/private/source.mp3)'));
      expect(tags, isNot(contains('TRIM_')));
      expect(tags, isNot(contains('private')));
      expect(tags, ui('无法完整保留原标签或封面。可关闭继承原歌曲信息，并另存副本。'));
      expect(audioTrimErrorMessage(StateError('TRIM_SOURCE_CHANGED|detail')),
          ui('原歌曲在裁剪期间发生变化，请关闭窗口后重新打开。'));
      expect(audioTrimErrorMessage(StateError('native internal detail')),
          ui('未完成裁剪。'));
    }
  });

  Future<void> open(
    WidgetTester tester, {
    required FakeTrimPreview preview,
    required AudioTrimSaver save,
    FutureOr<String?> Function()? pickDirectory,
    AudioTrimInfo info = trimTestInfo,
  }) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UiLanguageScope(
        child: MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => showDialog(
                            context: context,
                            builder: (_) => AudioTrimDialog(
                                audio: CategoryTestAudio('Example',
                                    path: 'J:/test/music/Example.mp3'),
                                inspect: (_) async => info,
                                save: save,
                                preview: preview,
                                pickDirectory: pickDirectory)),
                        child: const Text('Open')))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  FilledButton saveButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const ValueKey('trim-save')));

  testWidgets('unchanged inherited metadata leaves native tags untouched',
      (tester) async {
    AudioTrimRequest? saved;
    await open(tester, preview: FakeTrimPreview(),
        save: (_, request, {onProgress, cancellation}) async {
      saved = request;
      return AudioTrimResult(path: request.destinationPath, duration: 123.456);
    });
    await tester.tap(find.byKey(const ValueKey('trim-save')));
    await tester.pumpAndSettle();
    expect(saved?.preserveMetadata, isTrue);
    expect(saved?.title, isNull);
    expect(saved?.artist, isNull);
    expect(saved?.album, isNull);
  });

  testWidgets(
      'precise selection, preview, alternate directory and metadata form reach request',
      (tester) async {
    final preview = FakeTrimPreview();
    AudioTrimRequest? saved;
    await open(tester,
        preview: preview,
        pickDirectory: () => 'J:/other songs',
        save: (_, request, {onProgress, cancellation}) async {
          saved = request;
          return AudioTrimResult(
              path: request.destinationPath,
              duration: request.endSeconds - request.startSeconds);
        });
    await tester.enterText(
        find.byKey(const ValueKey('trim-start')), '1:02.125');
    await tester.enterText(find.byKey(const ValueKey('trim-end')), '1:07.250');
    await tester.pump();
    expect(find.textContaining('0:05.125'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('trim-preview')));
    await tester.pump();
    expect(preview.selections, [(62.125, 67.25)]);
    await tester.ensureVisible(find.byKey(const ValueKey('trim-other-folder')));
    await tester.tap(find.byKey(const ValueKey('trim-other-folder')));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('trim-edit-metadata')));
    await tester.tap(find.byKey(const ValueKey('trim-edit-metadata')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('trim-title')));
    await tester.enterText(
        find.byKey(const ValueKey('trim-title')), 'Edited ♪ 标题');
    await tester.tap(find.byKey(const ValueKey('trim-save')));
    await tester.pumpAndSettle();
    expect(saved?.startSeconds, 62.125);
    expect(saved?.endSeconds, 67.25);
    expect(saved?.destinationPath.replaceAll('\\', '/'),
        'J:/other songs/Example - 裁剪.mp3');
    expect(saved?.title, 'Edited ♪ 标题');
    expect(saved?.artist, isNull);
    expect(saved?.album, isNull);
    expect(saved?.preserveMetadata, isTrue);
    expect(saved?.overwrite, isFalse);
    expect(preview.playing, isFalse);
    expect(find.textContaining('片段已保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'invalid ranges cannot save and correcting them preserves millisecond accuracy',
      (tester) async {
    final preview = FakeTrimPreview();
    await open(tester,
        preview: preview,
        save: (_, request, {onProgress, cancellation}) async =>
            AudioTrimResult(path: request.destinationPath, duration: 2));
    for (final pair in [
      ('1:50', '1:00'),
      ('-1', '10'),
      ('0', '124'),
      ('1', '1.01'),
      ('text', '50')
    ]) {
      await tester.enterText(find.byKey(const ValueKey('trim-start')), pair.$1);
      await tester.enterText(find.byKey(const ValueKey('trim-end')), pair.$2);
      await tester.pump();
      expect(saveButton(tester).onPressed, isNull);
    }
    await tester.enterText(find.byKey(const ValueKey('trim-start')), '0.125');
    await tester.enterText(find.byKey(const ValueKey('trim-end')), '2.500');
    await tester.pump();
    expect(saveButton(tester).onPressed, isNotNull);
    final slider =
        tester.widget<RangeSlider>(find.byKey(const ValueKey('trim-range')));
    expect(slider.values, const RangeValues(.125, 2.5));
    await tester.tap(find.byKey(const ValueKey('trim-cancel')));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'overwrite requires explicit acknowledgement and preserves chosen metadata option',
      (tester) async {
    final preview = FakeTrimPreview();
    AudioTrimRequest? saved;
    await open(tester, preview: preview,
        save: (_, request, {onProgress, cancellation}) async {
      saved = request;
      return AudioTrimResult(path: request.destinationPath, duration: 123.456);
    });
    await tester.ensureVisible(find.byKey(const ValueKey('trim-overwrite')));
    await tester.tap(find.byKey(const ValueKey('trim-overwrite')));
    await tester.pumpAndSettle();
    expect(saveButton(tester).onPressed, isNull);
    await tester.ensureVisible(find.byKey(const ValueKey('trim-acknowledge')));
    await tester.tap(find.byKey(const ValueKey('trim-acknowledge')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('trim-metadata')));
    await tester.tap(find.byKey(const ValueKey('trim-metadata')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('trim-save')));
    await tester.pumpAndSettle();
    expect(saved?.overwrite, isTrue);
    expect(saved?.preserveMetadata, isFalse);
    expect(saved?.title, 'Example');
    expect(saved?.artist, 'Artist');
    expect(saved?.album, 'Album');
    expect(saved?.destinationPath, 'J:/test/music/Example.mp3');
  });

  testWidgets(
      'cancelled folder picker does not invoke a native fallback; invalid filename disables save',
      (tester) async {
    final preview = FakeTrimPreview();
    var picked = 0;
    await open(tester,
        preview: preview,
        pickDirectory: () {
          picked++;
          return null;
        },
        save: (_, request, {onProgress, cancellation}) async =>
            AudioTrimResult(path: request.destinationPath, duration: 123));
    await tester.ensureVisible(find.byKey(const ValueKey('trim-other-folder')));
    await tester.tap(find.byKey(const ValueKey('trim-other-folder')));
    await tester.pumpAndSettle();
    expect(picked, 1);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const ValueKey('trim-filename')));
    await tester.enterText(
        find.byKey(const ValueKey('trim-filename')), '../wrong.mp3');
    await tester.pump();
    expect(saveButton(tester).onPressed, isNull);
    await tester.enterText(
        find.byKey(const ValueKey('trim-filename')), '错名.wav');
    await tester.pump();
    expect(saveButton(tester).onPressed, isNull);
  });

  testWidgets(
      'commit disables cancel and warnings remain visible after a successful save',
      (tester) async {
    final preview = FakeTrimPreview();
    final completion = Completer<AudioTrimResult>();
    await open(tester, preview: preview,
        save: (_, request, {onProgress, cancellation}) {
      cancellation!.beginCommit();
      onProgress?.call(.94);
      return completion.future;
    });
    await tester.tap(find.byKey(const ValueKey('trim-save')));
    await tester.pump();
    expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('trim-cancel')))
            .onPressed,
        isNull);
    expect(find.text('正在保存…'), findsOneWidget);
    completion.complete(const AudioTrimResult(
        path: 'J:/saved.mp3',
        duration: 123,
        libraryUpdated: false,
        warning: '歌曲已保存，但曲库刷新未完成，请刷新曲库；不要重复覆盖'));
    await tester.pumpAndSettle();
    expect(find.textContaining('不要重复覆盖'), findsOneWidget);
  });

  testWidgets('backend errors stay localized in the form and allow retry',
      (tester) async {
    final preview = FakeTrimPreview();
    await open(tester, preview: preview,
        save: (_, request, {onProgress, cancellation}) async {
      throw const AudioTrimException('exists', '此文件名已存在，请换一个名称保存副本');
    });
    await tester.tap(find.byKey(const ValueKey('trim-save')));
    await tester.pumpAndSettle();
    expect(find.text('此文件名已存在，请换一个名称保存副本'), findsOneWidget);
    expect(saveButton(tester).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
