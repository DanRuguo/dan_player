import 'dart:io';

import 'package:dan_player/component/app_data_storage_card.dart';
import 'package:dan_player/component/folder_actions.dart';
import 'package:dan_player/data/folder_explorer.dart';
import 'package:dan_player/statistics/app_data_storage.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/playlist_feature_fixture.dart';

class _SnapshotScanner extends AppDataStorageScanner {
  const _SnapshotScanner(this.snapshot);
  final AppDataStorageSnapshot snapshot;
  @override
  Future<AppDataStorageSnapshot> scan(Directory directory) async => snapshot;
}

void main() {
  late Directory root;
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() async {
    root = await Directory(p.normalize(Directory.systemTemp.path))
        .createTemp('storage-tools-');
    for (final entry in {
      'covers/one.png': 10,
      'cache/online_lyrics/one.json': 20,
      'cache/song_comments/one/1.json': 30,
      'background-images/user.png': 40,
      'settings.json': 50,
      'lyric_documents.json': 60,
      'library_migrations/batch/before/index.json': 70,
      'updates/new.partial': 80
    }.entries) {
      final file = File(p.join(root.path, entry.key));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(List.filled(entry.value, 1));
    }
  });
  tearDown(() async {
    uiLanguage.value = UiLanguage.zh;
    await root.delete(recursive: true);
  });

  test(
      'totals match bytes and distinguish user work from rebuildable responses',
      () async {
    final stats = await const AppDataStorageScanner().scan(root);
    expect(stats.bytes, 360);
    expect(stats.files, 8);
    expect(stats.unreadable, 0);
    expect(stats.truncated, false);
    final parts = {for (final part in stats.parts) part.label: part.bytes};
    expect(parts['曲库与用户资料'], 110);
    expect(parts['自选图片与封面'], 40);
    expect(parts['迁移与恢复快照'], 70);
    expect(parts['联网歌词缓存'], 20);
    expect(parts['评论缓存'], 30);
    expect(stats.parts.firstWhere((part) => part.label == '封面缓存').paths,
        [p.join(root.path, 'covers')]);
  });

  test(
      'entry budget yields a marked partial snapshot instead of an unbounded scan',
      () async {
    final stats =
        await const AppDataStorageScanner(maximumEntries: 2).scan(root);
    expect(stats.truncated, true);
    expect(stats.files, lessThanOrEqualTo(2));
    expect(stats.bytes, lessThanOrEqualTo(360));
  });

  test('user imported playlist covers are grouped with chosen images', () {
    expect(AppDataStorageScanner.categoryFor(r'playlist-covers\my-cover.png'),
        '自选图片与封面');
  });

  test('comment cache hover groups all hashed children under song_comments',
      () async {
    final another = File(
        p.join(root.path, 'cache', 'song_comments', 'other-hash', '2.json'));
    await another.parent.create(recursive: true);
    await another.writeAsBytes([1, 2, 3, 4]);
    final stats = await const AppDataStorageScanner().scan(root);
    final comments = stats.parts.singleWhere((part) => part.label == '评论缓存');
    expect(comments.files, 2);
    expect(comments.bytes, 34);
    expect(comments.paths, [p.join(root.path, 'cache', 'song_comments')]);
  });

  test(
      'Explorer receives the complete directory as one argument without file-only reveal APIs',
      () async {
    final named = await Directory(p.join(root.path, '音 乐 (new)')).create();
    var launches = 0;
    await browseFolderInExplorer(named, launch: (executable, arguments) async {
      launches++;
      expect(p.basename(executable), 'explorer.exe');
      expect(arguments, [p.normalize(named.absolute.path)]);
    });
    expect(launches, 1);
  });

  for (final entry in [('mouse', 0), ('touch', 1), ('button', 2)]) {
    testWidgets(
        '${entry.$1} context entry preserves browse/move/statistics callbacks',
        (tester) async {
      var browse = 0, move = 0, statistics = 0;
      await tester.pumpWidget(playlistFeatureHost(Scaffold(
          body: Center(
              child: FolderActions(
                  directory: root,
                  onBrowse: () => browse++,
                  onMove: () => move++,
                  onStatistics: () => statistics++,
                  builder: (_, menu) => SizedBox(
                      key: const ValueKey('folder-input'),
                      width: 240,
                      height: 100,
                      child: IconButton(
                          key: const ValueKey('folder-more'),
                          onPressed: menu.open,
                          icon: const Icon(Icons.more_horiz))))))));
      Future<void> open() async {
        if (entry.$2 == 0) {
          final pointer = await tester.createGesture(
              kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
          await pointer.down(
              tester.getTopLeft(find.byKey(const ValueKey('folder-input'))) +
                  const Offset(12, 12));
          await pointer.up();
        } else if (entry.$2 == 1) {
          await tester.longPress(find.byKey(const ValueKey('folder-input')));
        } else {
          await tester.tap(find.byKey(const ValueKey('folder-more')));
        }
        await tester.pumpAndSettle();
      }

      await open();
      expect(find.text(ui('在文件资源管理器浏览')), findsOneWidget);
      await tester.tap(find.text(ui('在文件资源管理器浏览')));
      await tester.pumpAndSettle();
      await open();
      await tester.tap(find.text(ui('移动音乐文件夹')));
      await tester.pumpAndSettle();
      await open();
      await tester.tap(find.text(ui('查看占用统计')));
      await tester.pumpAndSettle();
      expect([browse, move, statistics], [1, 1, 1]);
      expect(tester.takeException(), isNull);
    });
  }

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets(
          '${language.code} ${narrow ? 'narrow large' : 'wide'} categorized usage uses readable names and hover paths',
          (tester) async {
        uiLanguage.value = language;
        final boundary = GlobalKey();
        final snapshot = await tester
            .runAsync(() => const AppDataStorageScanner().scan(root));
        tester.view.physicalSize = Size(narrow ? 520 : 1000, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(playlistFeatureHost(
            Scaffold(
                body: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: AppDataStorageCard(
                        directory: root,
                        scanner: _SnapshotScanner(snapshot!)))),
            textScale: narrow ? 1.8 : 1,
            boundary: boundary));
        await tester.runAsync(() async =>
            Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pumpAndSettle();
        expect(find.text(ui('曲库与用户资料')), findsOneWidget);
        expect(find.text(root.path), findsNothing);
        expect(
            find.byWidgetPredicate(
                (widget) => widget is Tooltip && widget.message == root.path),
            findsOneWidget);
        expect(tester.takeException(), isNull);
        await capturePlaylistFeature(tester, boundary,
            'storage-${language.code}-${narrow ? 'narrow' : 'wide'}');
      });
    }
  }
}
