import 'dart:async';

import 'package:dan_player/component/rectangle_progress_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('progress is finite, clamped and releases its subscription',
      (tester) async {
    var cancelled = false;
    final positions = StreamController<double>(
      sync: true,
      onCancel: () => cancelled = true,
    );
    addTearDown(positions.close);
    var length = 0.0;

    await tester.pumpWidget(MaterialApp(
      home: RectangleProgressIndicator(
        size: const Size(100, 4),
        positionStream: positions.stream,
        lengthProvider: () => length,
        child: const SizedBox(width: 100, height: 4),
      ),
    ));

    RectangleProgressPainter painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<RectangleProgressPainter>()
        .single;

    positions.add(10);
    expect(painter().progress.value, 0,
        reason: 'zero length must not publish NaN or infinity');

    length = 20;
    positions.add(30);
    expect(painter().progress.value, 1,
        reason: 'native position overshoot is bounded to the painted track');

    positions.add(-4);
    expect(painter().progress.value, 0);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(cancelled, isTrue);
  });
}
