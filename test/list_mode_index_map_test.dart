import 'dart:collection';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/page/uni_detail_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountedList extends ListBase<int> {
  _CountedList() : _items = List.generate(2048, (index) => index);
  final List<int> _items;
  int reads = 0;

  @override
  int get length => _items.length;
  @override
  set length(int value) => _items.length = value;
  @override
  int operator [](int index) {
    reads++;
    return _items[index];
  }

  @override
  void operator []=(int index, int value) => _items[index] = value;
}

Widget _page(String kind, _CountedList items, ContentView view) {
  final preference = PagePreference(0, SortOrder.ascending, view);
  Widget tile(BuildContext context, int item, int index,
          MultiSelectController<int>? controller) =>
      Text('Item $item');
  Widget detailTile(BuildContext context, int item, int index,
          List<int> visible, MultiSelectController<int>? controller) =>
      Text('Item $item');
  if (kind == 'library') {
    return UniPage<int>(
      pref: preference,
      title: 'Library',
      contentList: items,
      contentBuilder: tile,
      enableShufflePlay: false,
      enableSortMethod: false,
      enableSortOrder: false,
      enableContentViewSwitch: false,
    );
  }
  return UniDetailPage<String, int, String>(
    pref: preference,
    primaryContent: 'Fixture',
    primaryPic: Future.value(null),
    backgroundPic: Future.value(null),
    picShape: PicShape.oval,
    title: 'Detail',
    subtitle: 'Synthetic only',
    secondaryContent: items,
    secondaryContentBuilder: detailTile,
    tertiaryContentTitle: '',
    tertiaryContent: const [],
    tertiaryContentBuilder: (_, item, index, controller) => Text(item),
    enableShufflePlay: false,
    enableSortMethod: false,
    enableSortOrder: false,
    enableSecondaryContentViewSwitch: false,
  );
}

void main() {
  for (final kind in ['library', 'detail']) {
    for (final view in ContentView.values) {
      testWidgets('$kind $view builds identity indices only for a grid',
          (tester) async {
        final items = _CountedList();
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Scaffold(body: _page(kind, items, view)),
        ));
        await tester.pumpAndSettle();
        if (view == ContentView.list) {
          expect(items.reads, lessThan(200),
              reason: 'A list needs only its visible/cache rows, not 2048 '
                  'reads for an unused grid identity map.');
        } else {
          expect(items.reads, greaterThanOrEqualTo(items.length),
              reason: 'Grid reordering still needs the complete identity map.');
        }
        expect(find.text('Item 0'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
