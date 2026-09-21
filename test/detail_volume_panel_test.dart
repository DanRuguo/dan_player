import 'package:dan_player/component/detail_volume_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lyric volume sends drag targets before pointer release',
      (tester) async {
    var current = .5;
    final targets = <double>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DetailVolumeButton(
          readVolume: () => current,
          onChanged: (value) {
            current = value;
            targets.add(value);
          },
        ),
      ),
    ));
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    final slider = tester.getRect(find.byType(Slider));
    final gesture = await tester.startGesture(slider.center);
    await gesture.moveBy(const Offset(55, 0));
    await tester.pump();
    expect(targets, isNotEmpty);
    expect(current, greaterThan(.5));
    expect(find.text('${(current * 100).round()}%'), findsOneWidget);
    final high = current;
    await gesture.moveBy(const Offset(-85, 0));
    await tester.pump();
    expect(current, lessThan(high));
    expect(find.text('${(current * 100).round()}%'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
