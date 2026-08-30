import 'package:dan_player/library/audio_folder_sort.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/page/folders_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/page/uni_page_components.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

AudioFolder _folder(String path, {int modified = 0, int count = 0}) =>
    AudioFolder([
      for (var index = 0; index < count; index++)
        CategoryTestAudio('$path-$index')
    ], path, modified, 0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final direction in SortDirection.values) {
    test('folder paths ${direction.name} preserve equal-path occurrence order',
        () {
      final a = _folder('D:/Alpha');
      final equal = _folder('D:/Alpha');
      final z = _folder('D:/Zulu');
      final missing = _folder('');
      final original = [missing, a, z, equal];
      final result = List<AudioFolder>.of(original);
      sortAudioFoldersInPlace(result, AudioFolderSortField.path,
          direction: direction);
      expect(
          result,
          direction == SortDirection.ascending
              ? [a, equal, z, missing]
              : [z, a, equal, missing]);
      expect(original, [missing, a, z, equal]);
    });

    test(
        'folder time ${direction.name} keeps zero/negative unknowns last and stable',
        () {
      final a = _folder('D:/Alpha', modified: 10);
      final equal = _folder('D:/Equal', modified: 10);
      final z = _folder('D:/Zulu', modified: 20);
      final zero = _folder('D:/Zero');
      final negative = _folder('D:/Negative', modified: -1);
      final result = [zero, a, negative, z, equal];
      sortAudioFoldersInPlace(result, AudioFolderSortField.modified,
          direction: direction);
      expect(
          result,
          direction == SortDirection.ascending
              ? [a, equal, z, zero, negative]
              : [z, a, equal, zero, negative]);
    });

    test(
        'folder count ${direction.name} treats zero as valid and equal counts stably',
        () {
      final zero = _folder('D:/Empty');
      final one = _folder('D:/One', count: 1);
      final equal = _folder('D:/Equal', count: 1);
      final two = _folder('D:/Two', count: 2);
      final result = [one, zero, equal, two];
      sortAudioFoldersInPlace(result, AudioFolderSortField.songCount,
          direction: direction);
      expect(
          result,
          direction == SortDirection.ascending
              ? [zero, one, equal, two]
              : [two, one, equal, zero]);
      expect(one.audios, hasLength(1));
      expect(two.audios, hasLength(2));
      expect(PlayService.isInitialized, isFalse);
    });
  }

  testWidgets('folder page retains its three preference indexes',
      (tester) async {
    late UniPage<AudioFolder> page;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      page = const FoldersPage().build(context) as UniPage<AudioFolder>;
      return const SizedBox.shrink();
    })));
    expect(
        page.sortMethods!.map((method) => method.name), ['路径', '修改日期', '歌曲数量']);
    final unknown = _folder('D:/Unknown');
    final known = _folder('D:/Known', modified: 100);
    final result = [unknown, known];
    page.sortMethods![1].method(result, SortOrder.decending);
    expect(result, [known, unknown]);
    expect(PlayService.isInitialized, isFalse);
  });

  testWidgets(
      'direction-only options use segments and keep the legacy enum value',
      (tester) async {
    SortOrder? chosen;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Align(
      alignment: Alignment.topLeft,
      child: SortOrderSwitch<int>(
          sortOrder: SortOrder.ascending,
          setSortOrder: (value) => chosen = value),
    ))));
    final control = find.byType(SegmentedButton<SortOrder>);
    expect(control, findsOneWidget);
    expect(tester.getSize(control).height, greaterThanOrEqualTo(44));
    expect(find.byType(IconButton), findsNothing);
    await tester.tap(find.text('降序'));
    await tester.pumpAndSettle();
    expect(chosen, SortOrder.decending);
    expect(tester.takeException(), isNull);
  });
}
