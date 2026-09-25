import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/page/settings_page/settings_busy_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {bool reduceMotion = false, bool feedback = true}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: MotionPreferencesScope(
          preferences: MotionPreferences(
              disabled: feedback ? const {} : const {MotionKind.feedback}),
          child: Scaffold(body: child),
        ),
      ),
    );

void main() {
  testWidgets('raw indeterminate spinner keeps scheduling reduced-motion frames',
      (tester) async {
    await tester.pumpWidget(
        _host(const CircularProgressIndicator(), reduceMotion: true));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final reduced in [true, false]) {
    testWidgets(
        reduced
            ? 'system reduced motion keeps static busy feedback'
            : 'animation switch keeps static busy feedback', (tester) async {
      await tester.pumpWidget(_host(
          const Column(children: [
            SettingsBusyIndicator.circular(),
            SettingsBusyIndicator.linear(),
            SettingsBusyIndicator.linear(progress: .4),
          ]),
          reduceMotion: reduced,
          feedback: reduced));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.hourglass_top), findsNWidgets(2));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final progress = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator));
      expect(progress.value, .4);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }

  testWidgets('normal motion preserves indeterminate progress styles',
      (tester) async {
    await tester.pumpWidget(_host(const Column(children: [
      SettingsBusyIndicator.circular(),
      SettingsBusyIndicator.linear(),
    ])));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_top), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
