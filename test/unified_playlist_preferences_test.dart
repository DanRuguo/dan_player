import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;
  late File preferenceFile;
  late ContentView? previousRootView;
  late ContentView? previousDetailView;
  late PlaylistViewMode? previousRootLayout;
  late PlaylistViewMode? previousDetailLayout;
  late int previousStartPage;
  late Map<String, String> previousSortModes;

  setUp(() async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
    final parent =
        await Directory(path.join(Directory.current.path, 'build', 'test-data'))
            .create(recursive: true);
    root = await parent.createTemp('unified-preferences-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => root.path);
    final data = await getAppDataDir();
    expect(path.isWithin(root.path, data.path), isTrue);
    preferenceFile = File(path.join(data.path, 'app_preference.json'));
    final preferences = AppPreference.instance;
    previousRootView = preferences.unifiedPlaylistsView;
    previousDetailView = preferences.unifiedPlaylistDetailsView;
    previousRootLayout = preferences.unifiedPlaylistsLayout;
    previousDetailLayout = preferences.unifiedPlaylistDetailsLayout;
    previousStartPage = preferences.startPage;
    previousSortModes = Map.of(preferences.unifiedPlaylistSortModes);
  });

  tearDown(() async {
    AppPreference.instance
      ..unifiedPlaylistsView = previousRootView
      ..unifiedPlaylistDetailsView = previousDetailView
      ..unifiedPlaylistsLayout = previousRootLayout
      ..unifiedPlaylistDetailsLayout = previousDetailLayout
      ..startPage = previousStartPage;
    AppPreference.instance.unifiedPlaylistSortModes
      ..clear()
      ..addAll(previousSortModes);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    final resolved = await root.resolveSymbolicLinks();
    final parent =
        await Directory(path.join(Directory.current.path, 'build', 'test-data'))
            .resolveSymbolicLinks();
    if (!path.isWithin(parent, resolved) ||
        !path.basename(resolved).startsWith('unified-preferences-')) {
      throw StateError('Refusing to remove an unverified test fixture');
    }
    await Directory(resolved).delete(recursive: true);
  });

  test('unified layout choices round trip without replacing legacy preferences',
      () async {
    final source = AppPreference()
      ..unifiedPlaylistsView = ContentView.table
      ..unifiedPlaylistDetailsView = ContentView.list
      ..startPage = 2;
    source.collectionsPagePref =
        PagePreference(2, SortOrder.decending, ContentView.list);
    source.collectionDetailPagePref =
        PagePreference(5, SortOrder.ascending, ContentView.table);
    final rootBefore = source.collectionsPagePref.toMap();
    final detailBefore = source.collectionDetailPagePref.toMap();
    await source.save();
    final stored = jsonDecode(await preferenceFile.readAsString()) as Map;
    expect(stored['collectionsPagePref'], rootBefore);
    expect(stored['collectionDetailPagePref'], detailBefore);
    await AppPreference.read();
    expect(AppPreference.instance.unifiedPlaylistsView, ContentView.table);
    expect(AppPreference.instance.unifiedPlaylistDetailsView, ContentView.list);
    expect(AppPreference.instance.collectionsPagePref.toMap(), rootBefore);
    expect(
        AppPreference.instance.collectionDetailPagePref.toMap(), detailBefore);
    expect(AppPreference.instance.startPage, 2);
  });

  test(
      'older preferences without playlist keys still restore the old startup index',
      () async {
    final source = AppPreference()..startPage = 2;
    source.collectionsPagePref.contentView = ContentView.table;
    source.collectionDetailPagePref.contentView = ContentView.table;
    await source.save();
    final legacy = jsonDecode(await preferenceFile.readAsString()) as Map;
    for (final key in [
      'playlistsPagePref',
      'playlistDetailPagePref',
      'unifiedPlaylistsView',
      'unifiedPlaylistDetailsView',
      'unifiedPlaylistSortModes',
    ]) {
      legacy.remove(key);
    }
    await preferenceFile.writeAsString(jsonEncode(legacy));
    AppPreference.instance
      ..startPage = 0
      ..unifiedPlaylistsView = null
      ..unifiedPlaylistDetailsView = null;
    await AppPreference.read();
    expect(AppPreference.instance.startPage, 2);
    expect(AppPreference.instance.unifiedPlaylistsView, isNull);
    expect(AppPreference.instance.unifiedPlaylistSortModes, isEmpty);
    expect(AppPreference.instance.collectionsPagePref.contentView,
        ContentView.table);
    expect(AppPreference.instance.collectionDetailPagePref.contentView,
        ContentView.table);
  });

  test('per-level sorting preferences round trip independently of old order',
      () async {
    final source = AppPreference();
    source.unifiedPlaylistSortModes.addAll({
      'root': 'songCount',
      'playlist:parent-id': 'custom',
      'playlist:child-id': 'nameAscending',
    });
    final oldDetailPreference = source.collectionDetailPagePref.toMap();
    await source.save();
    await AppPreference.read();
    expect(AppPreference.instance.unifiedPlaylistSortModes,
        source.unifiedPlaylistSortModes);
    expect(AppPreference.instance.collectionDetailPagePref.toMap(),
        oldDetailPreference);
  });

  test('all three layouts persist independently without changing legacy fields',
      () async {
    for (final rootLayout in PlaylistViewMode.values) {
      for (final detailLayout in PlaylistViewMode.values) {
        final source = AppPreference()
          ..unifiedPlaylistsView = ContentView.table
          ..unifiedPlaylistDetailsView = ContentView.list
          ..unifiedPlaylistsLayout = rootLayout
          ..unifiedPlaylistDetailsLayout = detailLayout;
        await source.save();
        final stored = jsonDecode(await preferenceFile.readAsString()) as Map;
        expect(stored['unifiedPlaylistsLayout'], rootLayout.name);
        expect(stored['unifiedPlaylistDetailsLayout'], detailLayout.name);
        expect(stored['unifiedPlaylistsView'], 'table');
        expect(stored['unifiedPlaylistDetailsView'], 'list');
        await AppPreference.read();
        expect(AppPreference.instance.unifiedPlaylistsLayout, rootLayout);
        expect(
            AppPreference.instance.unifiedPlaylistDetailsLayout, detailLayout);
        expect(AppPreference.instance.unifiedPlaylistsView, ContentView.table);
        expect(AppPreference.instance.unifiedPlaylistDetailsView,
            ContentView.list);
      }
    }
  });

  test('old or malformed three-way layout keys fall back to saved list/grid',
      () async {
    await (AppPreference()
          ..unifiedPlaylistsView = ContentView.table
          ..unifiedPlaylistDetailsView = ContentView.list)
        .save();
    final stored = jsonDecode(await preferenceFile.readAsString()) as Map;
    for (final invalid in [null, 'future-layout', 4, false, <String>[]]) {
      stored['unifiedPlaylistsLayout'] = invalid;
      stored.remove('unifiedPlaylistDetailsLayout');
      await preferenceFile.writeAsString(jsonEncode(stored));
      AppPreference.instance
        ..unifiedPlaylistsLayout = PlaylistViewMode.circular
        ..unifiedPlaylistDetailsLayout = PlaylistViewMode.circular;
      await AppPreference.read();
      expect(AppPreference.instance.unifiedPlaylistsLayout, isNull);
      expect(AppPreference.instance.unifiedPlaylistDetailsLayout, isNull);
      expect(
          PlaylistViewMode.resolve(null,
              legacy: AppPreference.instance.unifiedPlaylistsView!.name),
          PlaylistViewMode.grid);
      expect(
          PlaylistViewMode.resolve(null,
              legacy: AppPreference.instance.unifiedPlaylistDetailsView!.name),
          PlaylistViewMode.list);
    }
  });

  test('malformed optional sort entries do not prevent reading valid settings',
      () async {
    final source = AppPreference()..startPage = 2;
    await source.save();
    final stored = jsonDecode(await preferenceFile.readAsString()) as Map;
    stored['unifiedPlaylistSortModes'] = {
      'root': 'custom',
      'playlist:wrong-type': ['nameAscending'],
      'playlist:future-value': 'some-future-sort',
    };
    await preferenceFile.writeAsString(jsonEncode(stored));
    await AppPreference.read();
    expect(AppPreference.instance.startPage, 2);
    expect(AppPreference.instance.unifiedPlaylistSortModes, {
      'root': 'custom',
      'playlist:future-value': 'some-future-sort',
    });
  });
}
