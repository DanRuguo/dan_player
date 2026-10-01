import 'package:dan_player/app_preference.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Lyrics extends Lyric {
  _Lyrics()
      : super([
          for (var index = 0; index < 60; index++)
            LrcLine(Duration(seconds: index * 5), 'Line $index',
                isBlank: false, length: const Duration(seconds: 5)),
        ]);
}

Future<ScrollController> _mount(WidgetTester tester) async {
  final settings =
      LyricViewController(preferences: NowPlayingPagePreference.fromMap({}));
  addTearDown(settings.dispose);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 420,
          height: 480,
          child: ChangeNotifierProvider.value(
            value: settings,
            child: VerticalLyricScrollView(
                lyric: _Lyrics(),
                positionStream: const Stream.empty(),
                readPosition: () => 90,
                onSeek: (_) {}),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return tester
      .widget<CustomScrollView>(
          find.byKey(const ValueKey('vertical-lyric-scroll')))
      .controller!;
}

void main() {
  testWidgets('the remaining finger holds lyrics after the first is cancelled',
      (tester) async {
    final controller = await _mount(tester);
    final followed = controller.offset;
    final scroll = find.byKey(const ValueKey('vertical-lyric-scroll'));
    final primary =
        await tester.startGesture(tester.getCenter(scroll), pointer: 101);
    await primary.moveBy(const Offset(0, -60));
    await tester.pump();
    await primary.moveBy(const Offset(0, -60));
    await tester.pump();
    final held = controller.offset;
    expect(held, greaterThan(followed + 40));
    final secondary = await tester.startGesture(
        tester.getCenter(scroll) + const Offset(70, 0),
        pointer: 102);
    await primary.cancel();
    await tester.pump();
    await tester.pump(LyricMotion.manualScrollGrace);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(held, .1));
    expect(find.byKey(const ValueKey('lyric-return-current')), findsOneWidget);
    await secondary.cancel();
    await tester.pumpAndSettle();
    await tester.pump(LyricMotion.manualScrollGrace);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(followed, .1));
    expect(find.byKey(const ValueKey('lyric-return-current')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a second cancelled pointer cannot release a held lyric scroll',
      (tester) async {
    final controller = await _mount(tester);
    final scroll = find.byKey(const ValueKey('vertical-lyric-scroll'));
    final primary =
        await tester.startGesture(tester.getCenter(scroll), pointer: 101);
    await primary.moveBy(const Offset(0, -60));
    await tester.pump();
    await primary.moveBy(const Offset(0, -60));
    await tester.pump();
    final held = controller.offset;
    final secondary = await tester.startGesture(
        tester.getCenter(scroll) + const Offset(70, 0),
        pointer: 102);
    await secondary.cancel();
    await tester.pump();
    await tester.pump(LyricMotion.manualScrollGrace);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(held, .1),
        reason:
            'The first finger still owns the viewport after the grace time');
    expect(find.byKey(const ValueKey('lyric-return-current')), findsOneWidget);
    await primary.up();
    await tester.pumpAndSettle();
    await tester.pump(LyricMotion.manualScrollGrace);
    await tester.pumpAndSettle();
    expect(controller.offset, lessThan(held - 40));
    expect(find.byKey(const ValueKey('lyric-return-current')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'cancelling the owning lyric pointer resumes following after grace',
      (tester) async {
    final controller = await _mount(tester);
    final followed = controller.offset;
    final scroll = find.byKey(const ValueKey('vertical-lyric-scroll'));
    final primary =
        await tester.startGesture(tester.getCenter(scroll), pointer: 101);
    await primary.moveBy(const Offset(0, -60));
    await tester.pump();
    await primary.moveBy(const Offset(0, -60));
    await tester.pump();
    expect(controller.offset, greaterThan(followed + 40));
    await primary.cancel();
    await tester.pumpAndSettle();
    await tester.pump(LyricMotion.manualScrollGrace);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(followed, .1));
    expect(find.byKey(const ValueKey('lyric-return-current')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
