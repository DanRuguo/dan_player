import 'package:dan_player/component/seven_tone_spectrum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("renders seven-tone FFT levels", (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SevenToneSpectrum(
            levels: [0.1, 0.3, 0.5, 0.7, 0.9, 0.4, 0.2],
            color: Colors.teal,
          ),
        ),
      ),
    );

    expect(find.byType(SevenToneSpectrum), findsOneWidget);
    expect(find.bySemanticsLabel("歌曲实时七音频谱"), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets("respects reduced-motion preference", (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: SevenToneSpectrum(
            levels: [1, 1, 1, 1, 1, 1, 1],
            color: Colors.teal,
          ),
        ),
      ),
    );

    expect(find.byType(SevenToneSpectrum), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
