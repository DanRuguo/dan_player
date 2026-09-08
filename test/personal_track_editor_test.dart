import 'dart:io';
import 'package:dan_player/component/personal_library_dialog.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/music_category_fixtures.dart';

class _Store extends PersonalLibrary {
  _Store(this.data) : super(File('unused-editor-test'));
  final Map<String, PersonalTrack> data;
  List<String>? added, removed;
  bool? ratingChanged;
  int? savedRating;
  @override
  Future<Map<String, PersonalTrack>> snapshot() async => data;
  @override
  Future<void> apply(Iterable<Audio> targets,
      {bool changeRating = false,
      int? rating,
      bool changeTags = false,
      List<String> addTags = const [],
      List<String> removeTags = const []}) async {
    added = addTags;
    removed = removeTags;
    ratingChanged = changeRating;
    savedRating = rating;
  }
}

void main() {
  for (final batch in [false, true]) {
    testWidgets(
        'personal editor preloads pills and preserves untouched values batch=$batch',
        (tester) async {
      final a = CategoryTestAudio('a'), b = CategoryTestAudio('b');
      final store = _Store({
        a.stableTrackId: const PersonalTrack(rating: 4, tags: ['Night']),
        b.stableTrackId: const PersonalTrack(rating: 2, tags: ['Other'])
      });
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => PersonalTrackEditor(
                              targets: [a, if (batch) b], store: store)),
                      child: const Text('open'))))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('Night'), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
              .onPressed,
          isNull);
      expect(
          tester
              .widgetList<ChoiceChip>(find.byType(ChoiceChip))
              .where((c) => c.selected)
              .length,
          batch ? 0 : 1);
      await tester.tap(find.text('Night'));
      await tester.pumpAndSettle();
      expect(
          tester.widget<TextFormField>(find.byType(TextFormField)).initialValue,
          'Night');
      await tester.enterText(find.byType(TextFormField), 'Evening');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('Evening'), findsOneWidget);
      await tester.tap(find.text('添加标签'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Chorus');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final chip =
          tester.widget<InputChip>(find.widgetWithText(InputChip, 'Chorus'));
      chip.onDeleted!();
      await tester.pumpAndSettle();
      expect(find.text('Chorus'), findsNothing);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.added, ['Evening']);
      expect(store.removed, ['Night']);
      expect(store.ratingChanged, false);
      expect(tester.takeException(), isNull);
    });
  }
}
