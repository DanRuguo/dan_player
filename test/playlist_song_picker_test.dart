import 'package:dan_player/component/playlist_song_picker.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Audio _audio(String id, String title) => Audio.online(
      provider: 'qq',
      id: id,
      title: title,
      artist: '虚构歌手',
      album: '虚构专辑',
      duration: 120,
    );

Widget _app({
  required List<Audio> library,
  List<Audio> selected = const [],
  double scale = 1,
  Brightness brightness = Brightness.light,
}) =>
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal, brightness: brightness),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(scale),
        ),
        child: UiLanguageScope(child: child!),
      ),
      home: Scaffold(
        body: PlaylistSongPicker(
          library: library,
          existingPaths: const {},
          selectedAudios: selected,
          replaceSelection: true,
        ),
      ),
    );

List<String> _rowPaths(WidgetTester tester) => [
      for (final row
          in tester.widgetList<CheckboxListTile>(find.byType(CheckboxListTile)))
        ((row.key! as ValueKey<String>).value)
            .substring('playlist-pick-'.length),
    ];

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _openSort(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('playlist-song-sort')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  testWidgets(
      'initially unselected candidates stay first while checks change and search remains',
      (tester) async {
    _size(tester, const Size(900, 760));
    final selected = _audio('selected', '最先输入的已选歌曲');
    final beta = _audio('beta', 'Beta');
    final alpha = _audio('alpha', 'Alpha');
    await tester.pumpWidget(
        _app(library: [selected, beta, alpha], selected: [selected]));
    await tester.pumpAndSettle();

    expect(find.text('选择当前搜索结果'), findsNothing);
    expect(_rowPaths(tester), [alpha.path, beta.path, selected.path]);
    await tester.tap(find.byKey(ValueKey('playlist-pick-${beta.path}')));
    await tester.pumpAndSettle();
    expect(_rowPaths(tester), [alpha.path, beta.path, selected.path],
        reason: 'checking a candidate must not move it under the pointer');

    await tester.enterText(
        find.byKey(const ValueKey('playlist-song-search')), 'alpha');
    await tester.pumpAndSettle();
    expect(_rowPaths(tester), [alpha.path]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared field/direction UI sorts each stable candidate partition',
      (tester) async {
    _size(tester, const Size(900, 760));
    final selected = _audio('selected', 'A selected');
    final firstTie = _audio('first-tie', 'Same');
    final beta = _audio('beta', 'Beta');
    final secondTie = _audio('second-tie', 'Same');
    await tester.pumpWidget(_app(
      library: [selected, firstTie, beta, secondTie],
      selected: [selected],
    ));
    await tester.pumpAndSettle();

    expect(_rowPaths(tester),
        [beta.path, firstTie.path, secondTie.path, selected.path]);
    expect(find.text('名称 · 升序'), findsOneWidget);

    await _openSort(tester);
    await tester
        .tap(find.byKey(const ValueKey('app-sort-direction-descending')));
    await tester.pumpAndSettle();
    expect(_rowPaths(tester),
        [firstTie.path, secondTie.path, beta.path, selected.path],
        reason: 'equal names retain source order even when descending');
    expect(find.text('名称 · 降序'), findsOneWidget);

    await _openSort(tester);
    await tester
        .tap(find.byKey(const ValueKey('playlist-picker-sort-original')));
    await tester.pumpAndSettle();
    expect(_rowPaths(tester),
        [firstTie.path, beta.path, secondTie.path, selected.path]);
    expect(find.text('乐库顺序'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'narrow 200% picker keeps centered localized controls and theme color in $brightness',
        (tester) async {
      _size(tester, const Size(507, 320));
      final audio = _audio('one', '完全虚构的很长候选歌曲名称');
      await tester
          .pumpWidget(_app(library: [audio], scale: 2, brightness: brightness));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final dialog = find.byType(Dialog);
      final title = find.text('更改所选歌曲');
      expect(tester.getRect(title).center.dx,
          closeTo(tester.getRect(dialog).center.dx, .01));
      expect(
          find.byKey(const ValueKey('playlist-song-search')), findsOneWidget);
      expect(find.byKey(const ValueKey('playlist-song-sort')), findsOneWidget);
      expect(find.text('选择当前搜索结果'), findsNothing);
      final scheme = Theme.of(tester.element(dialog)).colorScheme;
      final sortIcon = find
          .descendant(
              of: find.byKey(const ValueKey('playlist-song-sort')),
              matching: find.byType(Icon))
          .first;
      expect(IconTheme.of(tester.element(sortIcon)).color, scheme.primary);

      await tester.enterText(
          find.byKey(const ValueKey('playlist-song-search')), '完全虚构');
      for (final entry in const {
        UiLanguage.en: 'Change selected tracks',
        UiLanguage.ja: '選択した曲を変更',
        UiLanguage.ko: '선택한 곡 변경',
      }.entries) {
        uiLanguage.value = entry.key;
        await tester.pumpAndSettle();
        expect(find.text(entry.value), findsOneWidget);
        expect(
            tester
                .widget<EditableText>(find.descendant(
                    of: find.byKey(const ValueKey('playlist-song-search')),
                    matching: find.byType(EditableText)))
                .controller
                .text,
            '完全虚构');
        expect(tester.takeException(), isNull);
      }
      uiLanguage.value = UiLanguage.zh;
      await tester.pumpAndSettle();
      final sort = find.byKey(const ValueKey('playlist-song-sort'));
      await tester.ensureVisible(sort);
      await tester.pumpAndSettle();
      await tester.tap(sort);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('app-sort-direction-ascending')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('playlist-picker-sort-name')),
          findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await tester.drag(
          find.byKey(const ValueKey('playlist-song-picker-scroll')),
          const Offset(0, -400));
      await tester.pumpAndSettle();
      final row = find.byKey(ValueKey('playlist-pick-${audio.path}'));
      expect(row, findsOneWidget);
      final scrollBounds = tester
          .getRect(find.byKey(const ValueKey('playlist-song-picker-scroll')));
      final visible = tester.getRect(row).intersect(scrollBounds);
      expect(visible.isEmpty, isFalse);
      await tester.tapAt(visible.center);
      uiLanguage.value = UiLanguage.en;
      await tester.pumpAndSettle();
      expect(find.text('Save selection (1 tracks)'), findsOneWidget);
      expect(find.byType(PlaylistSongPicker), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
