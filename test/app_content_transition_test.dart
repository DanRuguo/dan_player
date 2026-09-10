import 'package:dan_player/component/app_content_transition.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Object identity, {bool reduced = false, bool visible = true}) =>
    MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: TickerMode(
                enabled: visible,
                child: Scaffold(
                    body: AppContentTransition(
                        identity: identity, child: const TextField())))));

double _opacity(WidgetTester tester) => tester
    .widget<FadeTransition>(find
        .descendant(
            of: find.byType(AppContentTransition),
            matching: find.byType(FadeTransition))
        .first)
    .opacity
    .value;

void main() {
  testWidgets('section change uses standard timing and retains the child state',
      (tester) async {
    await tester.pumpWidget(_host('songs'));
    expect(_opacity(tester), 1);
    await tester.enterText(find.byType(TextField), 'Unsaved draft');
    final state = tester.state(find.byType(TextField));
    await tester.pumpWidget(_host('bookmarks'));
    expect(_opacity(tester), 0);
    await tester.pump(AppMotion.standard ~/ 2);
    expect(_opacity(tester), allOf(greaterThan(0), lessThan(1)));
    await tester.pump(AppMotion.standard ~/ 2);
    expect(_opacity(tester), 1);
    expect(tester.state(find.byType(TextField)), same(state));
    expect(find.text('Unsaved draft'), findsOneWidget);
    await tester.pumpWidget(_host('bookmarks'));
    expect(_opacity(tester), 1, reason: 'Ordinary rebuilds must not replay');
  });

  testWidgets('rapid changes never retain duplicate outgoing editors',
      (tester) async {
    await tester.pumpWidget(_host(0));
    for (var identity = 1; identity < 8; identity++) {
      await tester.pumpWidget(_host(identity));
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.byType(TextField), findsOneWidget);
    }
    await tester.pump(AppMotion.standard);
    expect(_opacity(tester), 1);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion and hidden sections settle without a ticker',
      (tester) async {
    await tester.pumpWidget(_host(0));
    await tester.pumpWidget(_host(1));
    await tester.pump(const Duration(milliseconds: 40));
    expect(_opacity(tester), lessThan(1));
    await tester.pumpWidget(_host(1, reduced: true));
    expect(_opacity(tester), 1);
    await tester.pumpWidget(_host(2, reduced: true));
    expect(_opacity(tester), 1);
    await tester.pumpWidget(_host(3, visible: false));
    expect(_opacity(tester), 1);
    await tester.pumpWidget(_host(3));
    expect(_opacity(tester), 1, reason: 'Showing a hidden tab must not replay');
  });
}
