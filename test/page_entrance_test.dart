import 'dart:typed_data';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/page/page_scaffold.dart';
import 'package:dan_player/page/uni_detail_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _entrance(Object identity) => find.byWidgetPredicate(
      (widget) => widget is AppEntrance && widget.identity == identity,
    );

double _opacity(WidgetTester tester, Object identity) => tester
    .widget<Opacity>(find
        .descendant(of: _entrance(identity), matching: find.byType(Opacity))
        .first)
    .opacity;

Widget _app(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: brightness,
        ),
      ),
      home: Scaffold(body: child),
    );

Future<Uint8List> _capture(WidgetTester tester, GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = (await image.toByteData())!;
      return Uint8List.fromList(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }))!;
}

Widget _listPage(PagePreference pref, List<String> items,
        {String subtitle = 'Fixture'}) =>
    UniPage<String>(
      pref: pref,
      title: 'Library',
      subtitle: subtitle,
      contentList: items,
      contentBuilder: (context, item, index, controller) => SizedBox(
        height: 64,
        child: Align(alignment: Alignment.centerLeft, child: Text(item)),
      ),
      enableShufflePlay: false,
      enableSortMethod: false,
      enableSortOrder: false,
      enableContentViewSwitch: true,
    );

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('$brightness backing stays opaque while page content enters',
        (tester) async {
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(_app(
        RepaintBoundary(
          key: boundaryKey,
          child: const PageScaffold(
            title: 'Library',
            actions: [],
            body: SizedBox.expand(),
          ),
        ),
        brightness: brightness,
      ));
      expect(_opacity(tester, ('page-header', 'Library')), 0);
      final first = await _capture(tester, boundaryKey);
      await tester.pumpAndSettle();
      final settled = await _capture(tester, boundaryKey);
      // The very first pixel is the static page surface, outside the header.
      expect(first.sublist(0, 4), settled.sublist(0, 4));
      expect(first[3], 255);
      expect(_opacity(tester, ('page-header', 'Library')), 1);
      expect(
          find.ancestor(
            of: find
                .descendant(
                  of: find.byType(PageScaffold),
                  matching: find.byType(ColoredBox),
                )
                .first,
            matching: find.byType(Opacity),
          ),
          findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('library scroll recycling and list-grid switches do not replay',
      (tester) async {
    final pref = PagePreference(0, SortOrder.ascending, ContentView.list);
    final items = List.generate(120, (index) => 'Track $index');
    await tester.pumpWidget(_app(_listPage(pref, items)));
    expect(_opacity(tester, ('uni-item', items.first)), 0);
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView));
    list.controller!.jumpTo(64 * 60);
    await tester.pumpAndSettle();
    expect(_entrance(('uni-item', items.first)), findsNothing);
    list.controller!.jumpTo(0);
    await tester.pump();
    expect(_opacity(tester, ('uni-item', items.first)), 1);
    await tester.tap(find.text('网格'));
    await tester.pump();
    expect(find.byType(GridView), findsOneWidget);
    expect(_opacity(tester, ('uni-item', items.first)), 1);
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app(_listPage(pref, items, subtitle: 'Updated')));
    expect(_opacity(tester, ('uni-item', items.first)), 1);
    expect(_opacity(tester, ('page-header', 'Library')), 1);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page rebuilds and responsive width changes keep visible groups',
      (tester) async {
    final pref = PagePreference(0, SortOrder.ascending, ContentView.table);
    final items = List.generate(8, (index) => 'Track $index');
    await tester.pumpWidget(_app(_listPage(pref, items)));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pump();
    expect(_opacity(tester, ('uni-item', items.first)), 1);
    expect(_opacity(tester, ('page-header', 'Library')), 1);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings controls retain state, interaction and layout',
      (tester) async {
    var enabled = false;
    late StateSetter change;
    await tester.pumpWidget(_app(AppEntranceScope(
      child: StatefulBuilder(builder: (context, setState) {
        change = setState;
        return Center(
          child: SizedBox(
            width: 400,
            child: SettingsTile(
              description: 'Animations',
              icon: Icons.animation,
              action: Switch(
                value: enabled,
                onChanged: (value) => setState(() => enabled = value),
              ),
            ),
          ),
        );
      }),
    )));
    expect(_opacity(tester, ('setting', 'Animations')), 0);
    final size = tester.getSize(find.byType(SettingsTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(enabled, isTrue);
    expect(_opacity(tester, ('setting', 'Animations')), 1);
    expect(tester.getSize(find.byType(SettingsTile)), size);
    change(() => enabled = false);
    await tester.pumpAndSettle();
    expect(_opacity(tester, ('setting', 'Animations')), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('album detail groups settle without touching artwork backing',
      (tester) async {
    final pref = PagePreference(0, SortOrder.ascending, ContentView.list);
    final noImage = Future<ImageProvider?>.value();
    Widget detail() => UniDetailPage<String, String, String>(
          pref: pref,
          primaryContent: 'Album',
          primaryPic: noImage,
          backgroundPic: noImage,
          picShape: PicShape.rrect,
          title: 'Album',
          subtitle: 'Artist',
          secondaryContent: const ['Track'],
          secondaryContentBuilder: (_, item, __, ___, ____) => Text(item),
          tertiaryContentTitle: 'Related',
          tertiaryContent: const ['Other album'],
          tertiaryContentBuilder: (_, item, __, ___) => Text(item),
          enableShufflePlay: false,
          enableSortMethod: false,
          enableSortOrder: false,
          enableSecondaryContentViewSwitch: true,
        );
    await tester.pumpWidget(_app(detail()));
    expect(_opacity(tester, 'detail-header'), 0);
    await tester.pumpAndSettle();
    expect(_opacity(tester, 'detail-header'), 1);
    expect(_opacity(tester, ('detail-secondary', 'Track')), 1);
    expect(_opacity(tester, ('detail-tertiary', 'Other album')), 1);
    expect(
        find.ancestor(
          of: find.byType(BackdropFilter),
          matching: find.byType(AppEntrance),
        ),
        findsNothing);
    await tester.pumpWidget(_app(detail()));
    expect(_opacity(tester, 'detail-header'), 1);
    await tester.tap(find.text('网格'));
    await tester.pump();
    expect(_opacity(tester, ('detail-secondary', 'Track')), 1);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
