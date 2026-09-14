import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dan_player/component/category_cover_flight.dart';

void main() {
  for (final sourceRadius in [0.0, 60.0]) {
    for (final targetRadius in [16.0, 40.0]) {
      testWidgets(
          'cover flies and changes shape $sourceRadius to $targetRadius',
          (tester) async {
        final nav = GlobalKey<NavigatorState>();
        Widget cover(double radius, double size) => SizedBox.square(
            dimension: size,
            child: CategoryCoverFlight(
                tag: 'cover',
                radius: radius,
                child: const ColoredBox(color: Colors.teal)));
        await tester.pumpWidget(MaterialApp(
            navigatorKey: nav,
            home: Scaffold(
                body: Align(
                    alignment: Alignment.bottomRight,
                    child: cover(sourceRadius, 120)))));
        nav.currentState!.push(MaterialPageRoute<void>(
            builder: (_) => Scaffold(
                body: Align(
                    alignment: Alignment.topLeft,
                    child: cover(targetRadius, 80)))));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        final flight = find.byType(ClipRRect);
        expect(flight, findsOneWidget);
        final radius =
            (tester.widget<ClipRRect>(flight).borderRadius as BorderRadius)
                .topLeft
                .x;
        expect(
            radius,
            greaterThan(
                sourceRadius < targetRadius ? sourceRadius : targetRadius));
        expect(
            radius,
            lessThan(
                sourceRadius > targetRadius ? sourceRadius : targetRadius));
        final center = tester.getCenter(flight);
        expect(center.dx, inExclusiveRange(40, 740));
        expect(center.dy, inExclusiveRange(40, 540));
        await tester.pumpAndSettle();
        nav.currentState!.pop();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 2));
        expect(tester.binding.hasScheduledFrame, isFalse);
      });
    }
  }
}
