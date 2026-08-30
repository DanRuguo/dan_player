import 'package:dan_player/component/playlist_header.dart';
import 'package:dan_player/component/playlist_toolbar.dart';
import 'package:dan_player/page/page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app({
  required List<String> calls,
  double textScale = 1,
  String title = 'GAL',
  Brightness brightness = Brightness.light,
  bool selecting = false,
}) {
  return MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo, brightness: brightness),
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: true,
      ),
      child: child!,
    ),
    home: Scaffold(
      body: PageScaffold(
        title: title,
        actions: const [],
        headerPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        header: PlaylistHeader(
          title: title,
          subtitle: '162 个直接项目 · 162 首歌曲（含子歌单）',
          coverBuilder: (size) => const ColoredBox(color: Colors.indigo),
          breadcrumbs: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              TextButton.icon(
                key: const ValueKey('test-breadcrumb-root'),
                onPressed: () => calls.add('root'),
                icon: const Icon(Icons.library_music_outlined),
                label: const Text('全部歌单'),
              ),
              const Icon(Icons.chevron_right),
              TextButton(onPressed: null, child: Text(title)),
            ]),
          ),
          actions: PlaylistToolbar(
            isRoot: false,
            alignment: WrapAlignment.start,
            selecting: selecting,
            selectedCount: 1,
            hasItems: true,
            canPlay: true,
            onCreate: () => calls.add('create'),
            onAddSongs: () => calls.add('addSongs'),
            onPlayAll: () => calls.add('play'),
            onStartSelection: () => calls.add('select'),
            onEndSelection: () => calls.add('done'),
            onSelectAll: () => calls.add('all'),
            onRemoveSelected: () => calls.add('remove'),
            onSortChanged: (_) => calls.add('sort'),
            onToggleView: () => calls.add('view'),
          ),
        ),
        body: ListView.builder(
          key: const ValueKey('test-song-list'),
          itemCount: 20,
          itemBuilder: (_, index) => ListTile(
            key: ValueKey('test-song-$index'),
            title: Text('歌曲 $index'),
          ),
        ),
      ),
    ),
  );
}

Finder _key(String key) => find.byKey(ValueKey(key));

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
        'wide ${brightness.name} header places large art beside actions',
        (tester) async {
      final calls = <String>[];
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final dpr in [1.0, 1.25, 1.5, 2.0]) {
        tester.view.devicePixelRatio = dpr;
        tester.view.physicalSize = Size(920 * dpr, 720 * dpr);
        await tester.pumpWidget(_app(calls: calls, brightness: brightness));
        await tester.pumpAndSettle();
        final cover = tester.getRect(_key('playlist-header-cover'));
        final title = tester.getRect(_key('playlist-header-title'));
        final actions = tester.getRect(find.byType(PlaylistToolbar));
        final play = tester.getRect(_key('playlist-play-all'));
        final list = tester.getRect(_key('test-song-list'));
        expect(cover.size, const Size.square(112));
        expect(title.left - cover.right, 20);
        expect(play.left, title.left);
        expect(actions.top, greaterThan(title.bottom));
        expect(cover.center.dy, closeTo((title.top + actions.bottom) / 2, 3));
        expect(list.top, lessThanOrEqualTo(200));
        expect(list.top - actions.bottom, inInclusiveRange(0, 24));
        expect(tester.takeException(), isNull);
      }
      await tester.tap(_key('playlist-play-all'));
      await tester.tap(_key('test-breadcrumb-root'));
      expect(calls, ['play', 'root']);
    });
  }

  for (final width in [280.0, 360.0, 540.0, 760.0]) {
    testWidgets('$width wide header keeps controls and songs usable at 200%',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 480);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final calls = <String>[];
      const title = '很长的歌单名称 · 交响乐与游戏原声合集';
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(calls: calls, textScale: 2, title: title));
      await tester.pumpAndSettle();
      final header = tester.getRect(_key('page-custom-header-scroll'));
      final songs = tester.getRect(_key('test-song-list'));
      expect(songs.height, greaterThanOrEqualTo((480 - 16) * .4 - .1));
      expect(header.bottom, closeTo(songs.top, .01));
      final coverSize = tester.getSize(_key('playlist-header-cover'));
      expect(coverSize.width, greaterThanOrEqualTo(72));
      expect(coverSize.width, coverSize.height);
      expect(find.byTooltip(title), findsWidgets);
      expect(find.bySemanticsLabel(title), findsWidgets);
      await tester.ensureVisible(_key('playlist-view-toggle'));
      await tester.pumpAndSettle();
      final view = tester.getRect(_key('playlist-view-toggle'));
      expect(view.center.dy, inInclusiveRange(header.top, header.bottom));
      await tester.tap(_key('playlist-view-toggle'));
      expect(calls, ['view']);
      await tester.drag(_key('test-song-list'), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  testWidgets('switching selection does not remount the enlarged artwork',
      (tester) async {
    tester.view.physicalSize = const Size(960, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final calls = <String>[];
    await tester.pumpWidget(_app(calls: calls));
    final cover = tester.element(_key('playlist-header-cover'));
    await tester.pumpWidget(_app(calls: calls, selecting: true));
    await tester.pumpAndSettle();
    expect(tester.element(_key('playlist-header-cover')), same(cover));
    await tester.tap(_key('playlist-end-selection'));
    expect(calls, ['done']);
    expect(tester.takeException(), isNull);
  });
}
