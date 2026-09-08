import 'package:dan_player/component/bounded_tag_wrap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('whole tags fit two lines and omitted labels remain discoverable',
      (tester) async {
    final tags = ['First', 'Second', 'Third', 'Fourth', 'Fifth', '中文标签'];
    for (final scale in [1.0, 1.8]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Center(
                  child: SizedBox(
                      width: 170,
                      child: MediaQuery(
                          data: MediaQueryData(
                              textScaler: TextScaler.linear(scale)),
                          child: BoundedTagWrap(tags: tags)))))));
      expect(find.text('…'), findsOneWidget);
      final texts = tester.widgetList<Text>(find.byType(Text));
      expect(texts.every((t) => tags.contains(t.data) || t.data == '…'), true);
      final ys = tester
          .elementList(find.byType(Text))
          .map((e) => tester.getTopLeft(find.byWidget(e.widget)).dy)
          .toSet();
      expect(ys.length, lessThanOrEqualTo(2));
      expect(tester.widget<Tooltip>(find.byType(Tooltip)).message,
          tags.join(' · '));
      expect(tester.takeException(), isNull);
    }
  });
}
