import 'dart:async';

import 'package:dan_player/component/app_dialog_resize.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/audio_integrity_dialog.dart';
import 'package:dan_player/component/loudness_analysis_dialog.dart';
import 'package:dan_player/library/audio_integrity.dart';
import 'package:dan_player/library/loudness_analysis.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/listening_status_fixture.dart';
import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);
  final audio = CategoryTestAudio('夜曲 — actual result content');

  Future<void> mount(WidgetTester tester, Widget child) async {
    sizePlaylistFeature(tester, width: 1000, height: 1100);
    await tester.pumpWidget(listeningStatusHost(Builder(
        builder: (context) => FilledButton(
            key: const ValueKey('open-analysis-resize'),
            onPressed: () => showAppDialog<void>(
                context: context,
                builder: (dialogContext) => MediaQuery(
                    data: MediaQuery.of(dialogContext)
                        .copyWith(disableAnimations: false),
                    child: MotionPreferencesScope(
                        preferences: const MotionPreferences(), child: child))),
            child: const Text('Open')))));
    await tester.tap(find.byKey(const ValueKey('open-analysis-resize')));
    await tester.pumpAndSettle();
    expect(find.byType(AppDialogResize), findsOneWidget);
  }

  Future<void> assertGrowing(
      WidgetTester tester, void Function() finish) async {
    final content = find
        .descendant(
            of: find.byType(AlertDialog), matching: find.byType(Material))
        .first;
    final before = tester.getSize(content).height;
    finish();
    await tester.pump();
    await tester.pump();
    await tester.pump(AppMotion.standard ~/ 2);
    final middle = tester.getSize(content).height;
    await tester.pumpAndSettle();
    final after = tester.getSize(content).height;
    expect(middle, greaterThan(before),
        reason: 'dialog heights before=$before middle=$middle after=$after');
    expect(middle, lessThan(after));
    expect(tester.takeException(), isNull);
  }

  testWidgets('loudness result grows content without resetting measurement',
      (tester) async {
    final result = Completer<LoudnessReport>();
    var calls = 0;
    await mount(
        tester,
        LoudnessAnalysisDialog(
            audio: audio,
            ensureTools: () async => true,
            analyze: (_, __, progress) {
              calls++;
              progress(.5);
              return result.future;
            }));
    await tester.tap(find.byKey(const ValueKey('loudness-start')));
    await tester.pumpAndSettle();
    await assertGrowing(
        tester,
        () => result.complete(const LoudnessReport(
            integratedLufs: -20,
            rangeLu: 4,
            samplePeakDb: -3,
            truePeakDb: -2,
            analyzedSeconds: 180)));
    expect(calls, 1);
    expect(find.text('-20.0 LUFS'), findsOneWidget);
    expect(find.byKey(const ValueKey('loudness-copy')).hitTestable(),
        findsOneWidget);
  });

  testWidgets('integrity result grows content with full selectable digest',
      (tester) async {
    final result = Completer<AudioIntegrityReport>();
    var calls = 0;
    await mount(
        tester,
        AudioIntegrityDialog(
            audio: audio,
            ensureTools: () async => true,
            inspect: (_, __, progress) {
              calls++;
              progress(const AudioIntegrityProgress(
                  AudioIntegrityPhase.decoding, .5));
              return result.future;
            }));
    await tester.tap(find.byKey(const ValueKey('integrity-start')));
    await tester.pumpAndSettle();
    const hash =
        'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
    await assertGrowing(
        tester,
        () => result.complete(const AudioIntegrityReport(
            path: 'J:/QA/source.wav',
            sha256: hash,
            bytes: 10000,
            decodedSeconds: 180)));
    expect(calls, 1);
    expect(find.text(hash), findsOneWidget);
    expect(find.byKey(const ValueKey('integrity-copy')).hitTestable(),
        findsOneWidget);
  });
}
