import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/page/settings_page/grouped_settings.dart';
import 'package:dan_player/page/settings_page/page.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Editor extends StatefulWidget {
  const _Editor({required this.label, required this.onMount});
  final String label;
  final VoidCallback onMount;
  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  final _text = TextEditingController();
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      TextField(key: ValueKey('editor-${widget.label}'), controller: _text);
}

Widget _host(List<SettingsSection> sections, {double scale = 1}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
            size: const Size(1000, 700)),
        child: Scaffold(
            body: AppEntranceScope(child: GroupedSettings(sections: sections))),
      ),
    );

List<SettingsSection> _sections({VoidCallback? first, VoidCallback? second}) =>
    [
      SettingsSection(
          id: 'one',
          title: '曲库与播放',
          icon: Icons.library_music,
          children: [
            _Editor(label: 'one', onMount: first ?? () {}),
            for (var index = 0; index < 16; index++)
              SizedBox(height: 70, child: Text('one-$index')),
          ]),
      SettingsSection(
          id: 'two',
          title: '外观与背景',
          icon: Icons.palette,
          children: [
            _Editor(label: 'two', onMount: second ?? () {}),
            for (var index = 0; index < 16; index++)
              SizedBox(height: 70, child: Text('two-$index')),
          ]),
    ];

Future<void> _select(WidgetTester tester, String id) async {
  final picker = find.byKey(const ValueKey('settings-category-picker'));
  if (picker.evaluate().isNotEmpty) {
    await tester.tap(picker);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(ValueKey('settings-category-$id')).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('touch scrolling reaches settings below the fold',
      (tester) async {
    await tester.pumpWidget(_host(_sections()));
    await tester.pumpAndSettle();
    final scroll = tester
        .widget<SingleChildScrollView>(
            find.byKey(const PageStorageKey('settings-scroll-one')))
        .controller!;
    await tester.dragFrom(const Offset(180, 520), const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(180));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'sections initialize lazily and keep unsaved input when returning',
      (tester) async {
    var first = 0;
    var second = 0;
    await tester.pumpWidget(
        _host(_sections(first: () => first++, second: () => second++)));
    await tester.pumpAndSettle();
    expect(first, 1);
    expect(second, 0);
    await tester.enterText(
        find.byKey(const ValueKey('editor-one')), 'not yet saved');
    await _select(tester, 'two');
    expect(first, 1);
    expect(second, 1);
    final selected = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('settings-category-two')));
    expect(selected.selected, isTrue);
    expect(selected.showCheckmark, isFalse,
        reason: 'Selection keeps its semantics/tint without masking its icon');
    await tester.enterText(
        find.byKey(const ValueKey('editor-two')), 'another draft');
    await _select(tester, 'one');
    expect(find.text('not yet saved'), findsOneWidget);
    expect(second, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'each section retains its own scroll offset and offscreen editors',
      (tester) async {
    await tester.pumpWidget(_host(_sections()));
    await tester.pumpAndSettle();
    final one = find.byKey(const PageStorageKey('settings-scroll-one'));
    await tester.enterText(find.byKey(const ValueKey('editor-one')), 'draft');
    final scrollOne = tester.widget<SingleChildScrollView>(one).controller!;
    FocusManager.instance.primaryFocus?.unfocus();
    // enterText schedules a caret-visibility scroll on the next frame. Settle
    // that edit/focus lifecycle before simulating a later user scroll.
    await tester.pumpAndSettle();
    scrollOne.jumpTo(420);
    await tester.pumpAndSettle();
    final offsetOne = scrollOne.offset;
    expect(offsetOne, greaterThan(300));
    await _select(tester, 'two');
    final two = find.byKey(const PageStorageKey('settings-scroll-two'));
    final scrollTwo = tester.widget<SingleChildScrollView>(two).controller!;
    scrollTwo.jumpTo(220);
    await tester.pumpAndSettle();
    final offsetTwo = scrollTwo.offset;
    await _select(tester, 'one');
    expect(scrollOne.offset, closeTo(offsetOne, .1));
    scrollOne.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('draft'), findsOneWidget);
    await _select(tester, 'two');
    expect(scrollTwo.offset, closeTo(offsetTwo, .1));
  });

  testWidgets(
      'inactive sections cannot tick, accept focus or duplicate semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(_sections()));
    await _select(tester, 'two');
    final hiddenContext = tester
        .element(find.byKey(const ValueKey('editor-one'), skipOffstage: false));
    expect(TickerMode.valuesOf(hiddenContext).enabled, isFalse);
    expect(Focus.of(hiddenContext).canRequestFocus, isFalse);
    expect(find.text('one-0'), findsNothing);
    expect(find.text('two-0'), findsOneWidget);
    expect(find.bySemanticsLabel('one-0'), findsNothing);
    semantics.dispose();
  });

  for (final width in [320.0, 520.0, 1200.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('category navigation fits $width at text $scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(_host(_sections(), scale: scale));
        await tester.pumpAndSettle();
        await _select(tester, 'two');
        expect(find.byKey(const ValueKey('editor-two')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('keyboard activation selects a category without replaying rows',
      (tester) async {
    await tester.pumpWidget(_host(_sections()));
    await tester.pumpAndSettle();
    final chip = find.byKey(const ValueKey('settings-category-two'));
    Focus.of(tester
            .element(find.descendant(of: chip, matching: find.text('外观与背景'))))
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-two')), findsOneWidget);
  });

  testWidgets(
      'real settings retain every existing entry and do not initialize audio',
      (tester) async {
    expect(PlayService.isInitialized, isFalse);
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();
    final grouped =
        tester.widget<GroupedSettings>(find.byType(GroupedSettings));
    final names = grouped.sections
        .expand((section) => section.children)
        .map((widget) => widget.runtimeType.toString())
        .toSet();
    expect(
        names,
        containsAll([
          'AudioLibraryEditor',
          'RefreshAudioLibraryTile',
          'RestoreSessionSwitch',
          'MusicSourceSettings',
          'DefaultLyricSourceControl',
          'LyricApiEditor',
          'DynamicThemeSwitch',
          'WindowBackdropInfo',
          'UseSystemThemeSwitch',
          'ThemeSelector',
          'ThemeModeControl',
          'SelectFontCombobox',
          'ArtistSeparatorEditor',
          'CreateIssueTile',
          'CheckForUpdate',
          'PlaybackSettings',
          'LyricExperienceSettings',
          'DesktopIntegrationSettings',
          'ShortcutSettings',
        ]));
    expect(PlayService.isInitialized, isFalse);
    expect(tester.takeException(), isNull);
  });
}
