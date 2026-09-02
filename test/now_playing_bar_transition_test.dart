import 'package:dan_player/component/now_playing_bar_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _bar({required String identity, required String title}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 640,
          height: 96,
          child: NowPlayingBarRow(
            leading: const SizedBox.square(dimension: 48),
            title: title,
            subtitle: 'Artist · Album',
            identity: identity,
            controlsBuilder: (_) => const SizedBox(width: 180),
          ),
        ),
      ),
    );

void main() {
  testWidgets('song change retains outgoing and incoming bar content',
      (tester) async {
    await tester.pumpWidget(_bar(identity: 'first', title: 'First song'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_bar(identity: 'second', title: 'Second song'));
    await tester.pump();

    expect(find.text('First song'), findsOneWidget);
    expect(find.text('Second song'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('First song'), findsNothing);
    expect(find.text('Second song'), findsOneWidget);
  });
}
