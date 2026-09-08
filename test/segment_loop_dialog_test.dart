import 'package:desktop_lyric/ui_language.dart';
import 'dart:async';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/now_playing_page/component/segment_loop_dialog.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/play_service/segment_loop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/music_category_fixtures.dart';

class _SegmentPlayback extends ChangeNotifier implements PlaybackService {
  @override
  Audio? nowPlaying = CategoryTestAudio('local');
  @override
  final segmentLoop = SegmentLoopController();
  @override
  final resolvingAudioPath = ValueNotifier<String?>(null);
  @override
  final isChangingOutput = ValueNotifier(false);
  @override
  double position = 10;
  @override
  double get length => 120;
  @override
  bool get canUseSegmentLoop =>
      nowPlaying?.isLocal == true && resolvingAudioPath.value == null;
  final clock = StreamController<double>.broadcast();
  @override
  Stream<double> get positionStream => clock.stream;
  @override
  void seek(double value) {
    segmentLoop.manualSeek(value);
    position = value;
    clock.add(value);
  }

  @override
  bool setSegmentLoopEnabled(bool enabled) {
    segmentLoop.setEnabled(enabled);
    return segmentLoop.enabled;
  }

  @override
  void dispose() {
    segmentLoop.dispose();
    resolvingAudioPath.dispose();
    isChangingOutput.dispose();
    clock.close();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('A-B controls allow seeking and disable while the track loads',
      (tester) async {
    final service = _SegmentPlayback();
    addTearDown(service.dispose);
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SegmentLoopDialog(service: service))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('segment-loop-set-a')));
    await tester.pumpAndSettle();
    expect(service.segmentLoop.start, 10);
    final slider = tester
        .widget<Slider>(find.byKey(const ValueKey('segment-loop-position')));
    slider.onChangeEnd!(30);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('segment-loop-set-b')));
    await tester.pumpAndSettle();
    expect(service.segmentLoop.end, 30);
    await tester.ensureVisible(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(service.segmentLoop.enabled, isTrue);
    service.resolvingAudioPath.value = 'pending';
    service.segmentLoop.clear();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('segment-loop-set-a')))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<Slider>(find.byKey(const ValueKey('segment-loop-position')))
            .onChanged,
        isNull);
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    testWidgets('A-B paired controls align in ${language.code}',
        (tester) async {
      uiLanguage.value = language;
      addTearDown(() => uiLanguage.value = UiLanguage.zh);
      final service = _SegmentPlayback();
      addTearDown(service.dispose);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: SegmentLoopDialog(service: service))));
      await tester.pumpAndSettle();
      final a =
          tester.getRect(find.byKey(const ValueKey('segment-loop-set-a')));
      final b =
          tester.getRect(find.byKey(const ValueKey('segment-loop-set-b')));
      final fields = find.byType(TextFormField);
      final first = tester.getRect(fields.at(0));
      final second = tester.getRect(fields.at(1));
      expect(a.width, b.width);
      expect(a.left, first.left);
      expect(b.right, second.right);
      expect(first.top, second.top);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('A-B dialog scrolls with large text in a small window',
      (tester) async {
    final service = _SegmentPlayback();
    addTearDown(service.dispose);
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SizedBox(
                width: 360,
                height: 360,
                child: SegmentLoopDialog(service: service)))));
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
