import 'package:dan_player/component/category_pointer_glow.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'category_pointer_glow_test.dart' as capture;

void main() {
  for (final shared in [false, true]) {
    testWidgets('live native reduce motion retires mounted glow shared=$shared',
        (tester) async {
      final boundary = GlobalKey();
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      Widget cover = RepaintBoundary(
          key: boundary,
          child: const SizedBox(
              width: 160,
              height: 200,
              child: CategoryPointerGlow(
                  child: ColoredBox(color: Color(0xff080c10)))));
      if (shared) cover = CoverPointerScope(child: cover);
      // Use the real MaterialApp MediaQuery, not a hand-edited reduced-motion
      // query. Native reduceMotion is a different flag from disableAnimations.
      await tester
          .pumpWidget(MaterialApp(home: Scaffold(body: Center(child: cover))));
      await tester.pumpAndSettle();
      final baseline = await capture.pixels(tester, boundary);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      final origin = tester.getTopLeft(find.byKey(boundary));
      await mouse.moveTo(origin + const Offset(80, 4));
      await tester.pumpAndSettle();
      expect(await capture.pixels(tester, boundary),
          isNot(orderedEquals(baseline)));

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      await tester.pumpAndSettle();
      expect(await capture.pixels(tester, boundary), orderedEquals(baseline),
          reason: 'A live system preference must retire already painted light');
      await mouse.moveTo(origin + const Offset(130, 4));
      await tester.pumpAndSettle();
      expect(await capture.pixels(tester, boundary), orderedEquals(baseline),
          reason: 'New hover must respect native reduceMotion immediately');
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      await tester.pumpAndSettle();
      await mouse.moveTo(origin + const Offset(80, 4));
      await tester.pumpAndSettle();
      expect(await capture.pixels(tester, boundary),
          isNot(orderedEquals(baseline)),
          reason: 'Fresh input can resume after the preference is restored');
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
