import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/audio_selection_toolbar.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/page/audios_page.dart';
import 'package:dan_player/page/category_detail_page.dart';
import 'package:dan_player/page/uni_detail_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/page/uni_page_components.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/play_service/queue_edits.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

Widget _host(Widget child, {double scale = 1}) => MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale), disableAnimations: true),
        child: UiLanguageScope(child: child!),
      ),
      home: Scaffold(body: child),
    );

void main() {
  setUp(() => uiLanguage.value = UiLanguage.zh);

  test('visible selection follows display order and preserves hidden choices',
      () {
    final controller = MultiSelectController<String>();
    addTearDown(controller.dispose);
    controller.selectAll(['hidden', 'third', 'first']);
    expect(controller.selectedInOrder(['first', 'second', 'third']),
        ['first', 'third']);
    // Partial selection means select the rest; a second click clears only visible.
    controller.toggleAllVisible(['first', 'second', 'third']);
    expect(controller.selected, {'hidden', 'first', 'second', 'third'});
    controller.toggleAllVisible(['first', 'second', 'third']);
    expect(controller.selected, {'hidden'});
    controller.invertVisible(['first', 'second']);
    expect(controller.selected, {'hidden', 'first', 'second'});
    controller.invertVisible(['first']);
    expect(controller.selected, {'hidden', 'second'});
    controller.toggleAllVisible([]);
    expect(controller.selected, {'hidden', 'second'});
  });

  test('batch queue insertion preserves order, occurrences and current index',
      () {
    final original = ['same', 'middle', 'same', 'last'];
    final next = QueueEdit.insert(original, 2, ['a', 'b', 'a'], next: true);
    expect(next.items, ['same', 'middle', 'same', 'a', 'b', 'a', 'last']);
    expect(next.currentIndex, 2);
    final appended = QueueEdit.insert(original, 2, ['a', 'b'], next: false);
    expect(appended.items, ['same', 'middle', 'same', 'last', 'a', 'b']);
    expect(appended.currentIndex, 2);
    expect(original, ['same', 'middle', 'same', 'last']);
  });

  test('copy information retains occurrences, paths exclude online references',
      () {
    final local = CategoryTestAudio('Local', artist: 'Artist');
    final online = CategoryTestAudio('Online', online: true);
    expect(selectedTrackInfo([local, online, local]),
        'Local — Artist\r\nOnline — Artist\r\nLocal — Artist');
    expect(
        selectedLocalPaths([local, online, local]), [local.path, local.path]);
  });

  testWidgets('narrow large-text toolbar actions operate on visible selections',
      (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final first = CategoryTestAudio('First');
    final last = CategoryTestAudio('Last');
    final hidden = CategoryTestAudio('Hidden');
    final selection = MultiSelectController<Audio>()
      ..selectAll([last, hidden, first]);
    addTearDown(selection.dispose);
    List<Audio>? played;
    List<Audio>? exported;
    await tester.pumpWidget(_host(
      AudioMultiSelectionActions(
        controller: selection,
        contentList: [first, last],
        onPlay: (items) => played = items,
        onExport: (items) => exported = items,
      ),
      scale: 2,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('audio-selection-play')));
    await tester.pumpAndSettle();
    expect(played, [first, last]);
    await tester.tap(find.byKey(const ValueKey('audio-selection-more')));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('audio-selection-export')));
    await tester.tap(find.byKey(const ValueKey('audio-selection-export')));
    await tester.pumpAndSettle();
    expect(exported, [first, last]);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('audio-selection-toggle-all')));
    await tester.pumpAndSettle();
    expect(selection.selected, {hidden});
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('audio-selection-play')))
            .onPressed,
        isNull);
  });

  testWidgets('copy menu excludes online paths and has usable empty selection',
      (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final local = CategoryTestAudio('Local');
    await tester.pumpWidget(_host(AudioSelectionMenu(
        selected: [CategoryTestAudio('Online', online: true), local])));
    await tester.tap(find.byKey(const ValueKey('audio-selection-more')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
        find.byKey(const ValueKey('audio-selection-copy-paths')));
    await tester.tap(find.byKey(const ValueKey('audio-selection-copy-paths')));
    await tester.pumpAndSettle();
    expect(copied, [local.path]);
    await tester.pumpWidget(_host(const AudioSelectionMenu(selected: [])));
    await tester.tap(find.byKey(const ValueKey('audio-selection-more')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<MenuItemButton>(
                find.byKey(const ValueKey('audio-selection-copy-paths')))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<MenuItemButton>(
                find.byKey(const ValueKey('audio-selection-next')))
            .onPressed,
        isNull);
  });

  testWidgets(
      'library refresh retains controller and removes vanished selection',
      (tester) async {
    final library = AudioLibrary.instance;
    final original = library.audioCollection;
    final originalPref = AppPreference.instance.audiosPagePref;
    final first = CategoryTestAudio('First');
    final second = CategoryTestAudio('Second');
    library.audioCollection = [first, second];
    AppPreference.instance.audiosPagePref =
        PagePreference(0, SortOrder.ascending, ContentView.list);
    addTearDown(() {
      library.audioCollection = original;
      AppPreference.instance.audiosPagePref = originalPref;
    });
    await tester.pumpWidget(_host(const AudiosPage()));
    await tester.pumpAndSettle();
    final selection = tester
        .widget<UniPage<Audio>>(find.byType(UniPage<Audio>))
        .multiSelectController!;
    selection.useMultiSelectView(true);
    selection.selectAll([first, second]);
    await tester.pumpAndSettle();
    library.audioCollection = [second];
    AudioLibrary.changes.value++;
    await tester.pumpAndSettle();
    final refreshed = tester
        .widget<UniPage<Audio>>(find.byType(UniPage<Audio>))
        .multiSelectController;
    expect(refreshed, same(selection));
    expect(selection.enableMultiSelectView, isTrue);
    expect(selection.selected, {second});
    expect(tester.takeException(), isNull);
  });

  testWidgets('album detail filtering exposes only visible selected tracks',
      (tester) async {
    final first = CategoryTestAudio('First');
    final last = CategoryTestAudio('Last');
    final selection = MultiSelectController<Audio>()
      ..selectAll([last, first])
      ..useMultiSelectView(true);
    addTearDown(selection.dispose);
    await tester.pumpWidget(_host(UniDetailPage<String, Audio, String>(
      pref: PagePreference(0, SortOrder.ascending, ContentView.list),
      primaryContent: 'album',
      primaryPic: Future.value(),
      backgroundPic: Future.value(),
      picShape: PicShape.rrect,
      title: 'Album',
      subtitle: '',
      secondaryContent: [first, last],
      secondaryContentBuilder: (_, audio, __, ___, ____) => Text(audio.title),
      tertiaryContentTitle: '',
      tertiaryContent: const [],
      tertiaryContentBuilder: (_, item, __, ___) => Text(item),
      secondaryContentSearchText: (audio) => audio.title,
      enableShufflePlay: false,
      enableSortMethod: false,
      enableSortOrder: false,
      enableSecondaryContentViewSwitch: false,
      multiSelectController: selection,
      enableMultiSelectAddToPlaylist: true,
    )));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<AudioSelectionToolbar>(find.byType(AudioSelectionToolbar))
            .selected,
        [first, last]);
    await tester.enterText(
        find.byKey(const ValueKey('uni-detail-search')), 'Last');
    await tester.pumpAndSettle();
    final toolbar = tester
        .widget<AudioSelectionToolbar>(find.byType(AudioSelectionToolbar));
    expect(toolbar.selected, [last]);
    expect(toolbar.hiddenSelectionCount, 1);
    toolbar.onToggleAll();
    await tester.pumpAndSettle();
    expect(selection.selected, {first});
  });

  testWidgets('category selected playback respects current filtered order',
      (tester) async {
    final first = CategoryTestAudio('First');
    final last = CategoryTestAudio('Last');
    final tracks = <Audio>[first, last];
    final group =
        MusicCategories(tracks).groups(MusicCategoryKind.artist).single;
    List<Audio>? played;
    await tester.pumpWidget(_host(CategoryDetailPage(
      kind: MusicCategoryKind.artist,
      groupId: group.id,
      audios: tracks,
      onPlay: (_, queue) => played = queue,
    )));
    await tester.pumpAndSettle();
    final selection = tester
        .widget<AudioTile>(find.byType(AudioTile).first)
        .multiSelectController! as MultiSelectController<Audio>;
    selection.selectAll([last, first]);
    selection.useMultiSelectView(true);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('category-track-search')), 'Last');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('audio-selection-play')));
    await tester.pumpAndSettle();
    expect(played, [last]);
    expect(tester.takeException(), isNull);
  });
}
