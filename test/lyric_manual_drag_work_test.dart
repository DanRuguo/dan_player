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
          for (var index = 0; index < 100; index++)
            LrcLine(Duration(seconds: index * 5), 'Line $index',
                isBlank: false, length: const Duration(seconds: 5)),
        ]);
}

void main() {
  testWidgets('continued touch dragging retains row widgets and follow grace',
      (tester) async {
    final settings = LyricViewController();
    addTearDown(settings.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Material(
            child: Center(
                child: SizedBox(
                    width: 420,
                    height: 480,
                    child: ChangeNotifierProvider.value(
                        value: settings,
                        child: VerticalLyricScrollView(
                            lyric: _Lyrics(),
                            positionStream: const Stream.empty(),
                            readPosition: () => 100,
                            onSeek: (_) {})))))));
    await tester.pumpAndSettle();
    final scroll = find.byKey(const ValueKey('vertical-lyric-scroll'));
    final controller = tester.widget<CustomScrollView>(scroll).controller!;
    final followedOffset = controller.offset;
    final gesture = await tester.startGesture(tester.getCenter(scroll));
    await gesture.moveBy(const Offset(0, -32));
    await tester.pump();
    await tester.pump();
    var rowBuilds = 0;
    final previousRebuild = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previousRebuild?.call(element, builtOnce);
      if (element.widget is LyricFollowEffects) rowBuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previousRebuild);
    final dragStartOffset = controller.offset;
    for (var index = 0; index < 8; index++) {
      await gesture.moveBy(const Offset(0, -6));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.offset, greaterThan(dragStartOffset + 40));
    expect(rowBuilds, 0,
        reason:
            'A continuing gesture only changes scroll paint, not 100 row configurations');
    await tester.pump(LyricMotion.manualScrollGrace);
    final heldOffset = controller.offset;
    expect(heldOffset, greaterThan(followedOffset + 40),
        reason: 'Holding the finger must not restart automatic following');
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pump(LyricMotion.manualScrollGrace);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(followedOffset, .1));
    expect(tester.takeException(), isNull);
  });
}
