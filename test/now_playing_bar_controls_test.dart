import 'package:dan_player/component/now_playing_bar_controls.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => uiLanguage.value = UiLanguage.zh);
  for (final language in UiLanguage.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'bar controls translate and share theme $language/$brightness',
          (tester) async {
        uiLanguage.value = language;
        final calls = <String>[];
        var playing = false;
        await tester.pumpWidget(UiLanguageScope(
            child: MaterialApp(
                theme: ThemeData(
                    colorScheme: ColorScheme.fromSeed(
                        seedColor: Colors.teal, brightness: brightness)),
                home: StatefulBuilder(
                    builder: (context, setState) => Scaffold(
                        body: NowPlayingBarControls(
                            isPlaying: playing,
                            onPrevious: () => calls.add('previous'),
                            onPlayPause: () => setState(() {
                                  playing = !playing;
                                  calls.add('toggle');
                                }),
                            onNext: () => calls.add('next'),
                            onQueue: () => calls.add('queue')))))));
        expect(find.byTooltip(ui('播放')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('bar-play-pause')));
        await tester.pumpAndSettle();
        expect(find.byTooltip(ui('暂停')), findsOneWidget);
        for (final name in ['previous', 'next', 'queue']) {
          final button = find.byKey(ValueKey('bar-$name'));
          expect(tester.getSize(button), const Size.square(44));
          await tester.tap(button);
        }
        expect(calls, ['toggle', 'previous', 'next', 'queue']);
        final element = tester.element(find.byType(NowPlayingBarControls));
        final scheme = Theme.of(element).colorScheme;
        final next =
            tester.widget<IconButton>(find.byKey(const ValueKey('bar-next')));
        expect(next.style!.foregroundColor!.resolve({}), scheme.primary);
        expect(PlayService.isInitialized, isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('buffering disables only play while next remains available',
      (tester) async {
    var played = 0;
    var next = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: NowPlayingBarControls(
                isPlaying: false,
                isBuffering: true,
                showQueue: false,
                onPlayPause: () => played++,
                onNext: () => next++))));
    await tester.tap(find.byKey(const ValueKey('bar-play-pause')));
    await tester.tap(find.byKey(const ValueKey('bar-next')));
    expect(played, 0);
    expect(next, 1);
    expect(find.byKey(const ValueKey('bar-queue')), findsNothing);
  });
  for (final brightness in Brightness.values) {
    testWidgets('disabled play has distinct themed colors $brightness',
        (tester) async {
      final scheme =
          ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness);
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(colorScheme: scheme),
          home: const Scaffold(body: NowPlayingBarControls(isPlaying: false))));
      final button = tester
          .widget<IconButton>(find.byKey(const ValueKey('bar-play-pause')));
      expect(button.onPressed, isNull);
      expect(button.style!.backgroundColor!.resolve({WidgetState.disabled}),
          scheme.onSurface.withValues(alpha: .12));
      expect(button.style!.foregroundColor!.resolve({WidgetState.disabled}),
          scheme.onSurface.withValues(alpha: .38));
      expect(button.style!.backgroundColor!.resolve({}),
          scheme.primaryContainer.withValues(alpha: .86));
      expect(button.style!.foregroundColor!.resolve({}),
          scheme.onPrimaryContainer);
    });
  }
}
