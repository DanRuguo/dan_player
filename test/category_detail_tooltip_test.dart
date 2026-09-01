import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/page/category_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

void main() {
  testWidgets('category tracks avoid duplicate source tooltips',
      (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final local = CategoryTestAudio('Local song', artist: 'Shared artist');
    final online =
        CategoryTestAudio('Online song', artist: 'Shared artist', online: true);
    final songs = [local, online];
    final group =
        MusicCategories(songs).groups(MusicCategoryKind.artist).single;

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(
        body: CategoryDetailPage(
          kind: group.kind,
          groupId: group.id,
          initialGroup: group,
          audios: songs,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final messages = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((tooltip) => tooltip.message)
        .whereType<String>()
        .toList();
    expect(messages, isNot(contains('本地 · 本地')));
    expect(messages, isNot(contains('联网 · QQ音乐')));
    expect(messages, contains('联网音乐 · QQ音乐'),
        reason: 'the meaningful source tooltip owned by AudioTile remains');
    expect(tester.takeException(), isNull);
  });
}
