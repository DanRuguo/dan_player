import 'package:dan_player/category_presentation.dart';
import 'package:dan_player/component/category_tile_grid.dart';
import 'package:dan_player/library/category_cover_store.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

class _MemoryCovers extends CategoryCoverStore {
  _MemoryCovers()
      : super(
            dataDirectory: () async => throw StateError(
                'This layout fixture must not access storage'));

  @override
  Future<ImageProvider?> imageFor(MusicCategoryGroup group) =>
      SynchronousFuture(null);
}

void main() {
  for (final roundTrip in ['search', 'shape']) {
    testWidgets('saved rectangle gaps survive a $roundTrip round trip',
        (tester) async {
      final covers = _MemoryCovers();
      addTearDown(covers.dispose);
      final groups = MusicCategories([
        CategoryTestAudio('One', artist: 'First artist'),
        CategoryTestAudio('Two', artist: 'Second artist'),
      ]).groups(MusicCategoryKind.artist);
      final saved = {
        groups[0].persistenceKey: [4, 0, 0],
        groups[1].persistenceKey: [4, 2, 1],
      };
      var presentation = CategoryPresentation(
          shape: CategoryCoverShape.rounded, autoFill: false, layouts: saved);
      var filtered = false;
      var changes = 0;
      late StateSetter update;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                      width: 480,
                      height: 500,
                      child: StatefulBuilder(builder: (context, setState) {
                        update = setState;
                        return CustomScrollView(slivers: [
                          CategoryTileGrid(
                            groups: filtered ? [groups[1]] : groups,
                            presentation: presentation,
                            persistLayout: !filtered,
                            onChanged: (value) => setState(() {
                              presentation = value;
                              changes++;
                            }),
                            onOpen: (_) {},
                            covers: covers,
                            changing: const {},
                            onChangeCover: (_) {},
                            onRemoveCover: (_) {},
                            icon: Icons.album_outlined,
                          ),
                        ]);
                      }))))));
      await tester.pumpAndSettle();
      Rect rect(int index) => tester
          .getRect(find.byKey(ValueKey(('category-cover', groups[index].id))));
      final before = [rect(0), rect(1)];
      expect(before[1].top, greaterThan(before[0].bottom));
      expect(changes, 0);

      update(() {
        if (roundTrip == 'search') {
          filtered = true;
        } else {
          presentation =
              presentation.copyWith(shape: CategoryCoverShape.circle);
        }
      });
      await tester.pumpAndSettle();
      expect(presentation.layouts, saved);
      expect(changes, 0,
          reason:
              'Temporary projections must leave saved rectangle gaps alone');

      update(() {
        filtered = false;
        presentation = presentation.copyWith(shape: CategoryCoverShape.rounded);
      });
      await tester.pumpAndSettle();
      expect(rect(0), before[0]);
      expect(rect(1), before[1],
          reason:
              'Returning must restore the full rectangle layout by identity');
      expect(presentation.layouts, saved);
      expect(changes, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
