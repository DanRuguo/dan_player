import 'package:dan_player/app_preference.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Future<LyricViewController> _open(WidgetTester tester) async {
  final settings =
      LyricViewController(preferences: NowPlayingPagePreference.fromMap({}))
        ..setFontSize(39);
  addTearDown(settings.dispose);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ChangeNotifierProvider.value(
        value: settings,
        child: const Align(
            alignment: Alignment.centerRight, child: LyricFontSizeMenu()),
      ),
    ),
  ));
  await tester.tap(find.byKey(const ValueKey('lyric-font-size-open')));
  await tester.pumpAndSettle();
  return settings;
}

void main() {
  testWidgets('a rejected secondary mouse click cannot own the next font drag',
      (tester) async {
    final settings = await _open(tester);
    final slider = find.byKey(const ValueKey('lyric-font-size-slider'));
    final secondary = await tester.startGesture(tester.getCenter(slider),
        pointer: 201,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton);
    await secondary.up();
    await tester.pumpAndSettle();
    final primary =
        await tester.startGesture(tester.getCenter(slider), pointer: 101);
    await primary.moveBy(const Offset(42, 0));
    await tester.pump();
    final target = settings.fontDragPreviewSize;
    expect(target, greaterThan(39),
        reason:
            'A rejected mouse button must not block the next touch preview');
    await primary.up();
    await tester.pumpAndSettle();
    expect(settings.lyricFontSize, target);
    expect(settings.fontSizeAdjusting, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final cancelSecond in [false, true]) {
    testWidgets(
        'a second lyric font pointer ${cancelSecond ? 'cancel' : 'release'} preserves the active drag',
        (tester) async {
      final settings = await _open(tester);
      final slider = find.byKey(const ValueKey('lyric-font-size-slider'));
      final primary =
          await tester.startGesture(tester.getCenter(slider), pointer: 101);
      await primary.moveBy(const Offset(42, 0));
      await tester.pump();
      final preview = settings.fontDragPreviewSize;
      expect(preview, greaterThan(39));
      expect(settings.fontSizeAdjusting, isTrue);

      final secondary =
          await tester.startGesture(tester.getCenter(slider), pointer: 102);
      if (cancelSecond) {
        await secondary.cancel();
      } else {
        await secondary.up();
      }
      await tester.pump();
      expect(settings.fontSizeAdjusting, isTrue,
          reason: 'Only the pointer that began sizing can finish its preview');
      expect(settings.fontDragPreviewSize, preview);
      await primary.moveBy(const Offset(12, 0));
      await tester.pump();
      expect(settings.fontDragPreviewSize, greaterThan(preview!));
      expect(settings.lyricFontSize, 39);
      final target = settings.fontDragPreviewSize;
      await primary.up();
      await tester.pumpAndSettle();
      expect(settings.lyricFontSize, target);
      expect(settings.nowPlayingPagePref.lyricFontSize, target);
      expect(settings.fontDragPreviewSize, isNull);
      expect(settings.fontSizeAdjusting, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('cancelling the lyric font pointer discards its unsaved preview',
      (tester) async {
    final settings = await _open(tester);
    final slider = find.byKey(const ValueKey('lyric-font-size-slider'));
    final primary =
        await tester.startGesture(tester.getCenter(slider), pointer: 101);
    await primary.moveBy(const Offset(42, 0));
    await tester.pump();
    expect(settings.fontDragPreviewSize, greaterThan(39));
    await primary.cancel();
    await tester.pumpAndSettle();
    expect(settings.lyricFontSize, 39,
        reason: 'The cancelled draft must not reach saved preferences');
    expect(settings.nowPlayingPagePref.lyricFontSize, 39);
    expect(settings.fontDragPreviewSize, isNull);
    expect(settings.fontSizeAdjusting, isFalse);
    expect(tester.widget<Slider>(slider).value, 39);

    final next =
        await tester.startGesture(tester.getCenter(slider), pointer: 103);
    await next.moveBy(const Offset(-36, 0));
    await tester.pump();
    final target = settings.fontDragPreviewSize;
    expect(target, lessThan(39));
    await next.up();
    await tester.pumpAndSettle();
    expect(settings.lyricFontSize, target);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'closing the font menu discards a pointer released during its exit',
      (tester) async {
    final settings = await _open(tester);
    final slider = find.byKey(const ValueKey('lyric-font-size-slider'));
    final primary =
        await tester.startGesture(tester.getCenter(slider), pointer: 101);
    await primary.moveBy(const Offset(42, 0));
    await tester.pump();
    expect(settings.fontDragPreviewSize, greaterThan(39));
    await tester.tap(find.byKey(const ValueKey('lyric-font-size-open')));
    expect(settings.fontSizeAdjusting, isFalse);
    await primary.up();
    await tester.pumpAndSettle();
    expect(settings.lyricFontSize, 39,
        reason: 'Closing the preview must cancel it before the exit fade ends');
    expect(settings.nowPlayingPagePref.lyricFontSize, 39);
    await tester.tap(find.byKey(const ValueKey('lyric-font-size-open')));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).value, 39);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a cancelled font preview does not swallow an accessible change',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final settings = await _open(tester);
      final slider = find.byKey(const ValueKey('lyric-font-size-slider'));
      final primary =
          await tester.startGesture(tester.getCenter(slider), pointer: 101);
      await primary.moveBy(const Offset(42, 0));
      await tester.pump();
      await primary.cancel();
      await tester.pumpAndSettle();
      expect(settings.lyricFontSize, 39);
      SemanticsNode? target;
      bool findAction(SemanticsNode node) {
        if (node.getSemanticsData().hasAction(SemanticsAction.increase)) {
          target = node;
          return false;
        }
        node.visitChildren(findAction);
        return target == null;
      }

      findAction(tester.getSemantics(slider));
      expect(target, isNotNull);
      target!.owner!.performAction(target!.id, SemanticsAction.increase);
      await tester.pumpAndSettle();
      expect(settings.lyricFontSize, 40);
      expect(settings.nowPlayingPagePref.lyricFontSize, 40);
      expect(settings.fontSizeAdjusting, isFalse);
      expect(settings.fontDragPreviewSize, isNull);
      await tester.pumpWidget(const SizedBox());
    } finally {
      semantics.dispose();
    }
  });
}
