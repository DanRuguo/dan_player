import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_sort_button.dart';
import 'package:dan_player/component/playlist_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playback_mode_fixture.dart';

const _toolbarKey = ValueKey('toolbar-under-test');
const _boundsKey = ValueKey('toolbar-bounds');
const _switcherKey = ValueKey('playlist-toolbar-switcher');

class _Fixture {
  _Fixture() {
    addTearDown(playback.dispose);
  }
  final playback = PlaybackModeFixture();
  bool isRoot = true;
  bool selecting = false;
  int selectedCount = 0;
  bool hasItems = true;
  bool canPlay = true;
  bool editingEnabled = true;
  bool gridView = false;
  PlaylistSortMode sortMode = PlaylistSortMode.custom;
  bool addSongs = true;
  bool management = true;
  bool resetCover = true;
  bool albums = true;
  bool help = true;
  bool releaseTools = false;
  final calls = <String>[];

  Widget toolbar() => PlaylistToolbar(
        key: _toolbarKey,
        playbackService: playback,
        isRoot: isRoot,
        selecting: selecting,
        selectedCount: selectedCount,
        hasItems: hasItems,
        canPlay: canPlay,
        editingEnabled: editingEnabled,
        sortMode: sortMode,
        gridView: gridView,
        onCreate: () => calls.add('create'),
        onAddSongs: addSongs ? () => calls.add('addSongs') : null,
        onStartSelection: () => calls.add('startSelection'),
        onEndSelection: () => calls.add('endSelection'),
        onSelectAll: () => calls.add('selectAll'),
        onRemoveSelected: () => calls.add('removeSelected'),
        onSortChanged: (mode) => calls.add('sort:${mode.name}'),
        onToggleView: () => calls.add('view'),
        onRename: management ? () => calls.add('rename') : null,
        onEditSongs: management ? () => calls.add('editSongs') : null,
        onChangeCover: management ? () => calls.add('cover') : null,
        onResetCover:
            management && resetCover ? () => calls.add('reset') : null,
        onOpenAlbums: albums ? () => calls.add('albums') : null,
        albumCount: 23,
        onHelp: help ? () => calls.add('help') : null,
        onImportCue: releaseTools ? () => calls.add('importCue') : null,
        onOpenSmartPlaylists:
            releaseTools ? () => calls.add('smartPlaylists') : null,
      );
}

Widget _app(
  _Fixture fixture, {
  double width = 720,
  double textScale = 1,
  bool reduced = false,
  bool tickerEnabled = true,
  Brightness brightness = Brightness.light,
  VisualDensity? visualDensity,
  TextStyle? labelStyle,
}) =>
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        visualDensity: visualDensity,
        textTheme:
            labelStyle == null ? null : TextTheme(labelLarge: labelStyle),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: brightness,
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduced,
        ),
        child: TickerMode(enabled: tickerEnabled, child: child!),
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(8),
          child: Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              key: _boundsKey,
              width: width,
              child: fixture.toolbar(),
            ),
          ),
        ),
      ),
    );

Finder _key(String value) => find.byKey(ValueKey(value));

Finder _control(String value) => find
    .descendant(
      of: _key(value),
      matching: find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton || widget is IconButton),
      matchRoot: true,
    )
    .first;

bool _enabled(WidgetTester tester, String key) {
  final widget = tester.widget(_control(key));
  return switch (widget) {
    ButtonStyleButton() => widget.onPressed != null,
    IconButton() => widget.onPressed != null,
    _ => throw StateError('Not a toolbar button: $key'),
  };
}

ButtonStyle _style(WidgetTester tester, String key) {
  final widget = tester.widget(_control(key));
  return switch (widget) {
    ButtonStyleButton() => widget.style!,
    IconButton() => widget.style!,
    _ => throw StateError('Not a toolbar button: $key'),
  };
}

Finder _menuItems() =>
    find.byWidgetPredicate((widget) => widget is PopupMenuItem);

Future<void> _open(WidgetTester tester, String key) async {
  await tester.tap(_control(key));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, Finder item) async {
  await tester.ensureVisible(item);
  await tester.tap(item);
  await tester.pumpAndSettle();
}

Future<void> _dismiss(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

void _expectTouchTargets(WidgetTester tester) {
  final controls = find.descendant(
    of: find.byKey(_toolbarKey),
    matching: find.byWidgetPredicate(
        (widget) => widget is ButtonStyleButton || widget is IconButton),
  );
  for (final element in controls.evaluate()) {
    final size = tester.getSize(find.byWidget(element.widget));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  }
  for (final element in _menuItems().evaluate()) {
    final size = tester.getSize(find.byWidget(element.widget));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(48));
  }
}

void main() {
  testWidgets(
      'CUE and smart playlist entries are reachable in empty root and detail menus',
      (tester) async {
    final fixture = _Fixture()
      ..releaseTools = true
      ..hasItems = false
      ..canPlay = false;
    for (final root in [true, false]) {
      fixture
        ..isRoot = root
        ..editingEnabled = true;
      await tester.pumpWidget(_app(fixture, reduced: true));
      await tester.pumpAndSettle();
      await _open(tester, 'playlist-current-settings');
      await _choose(tester, _key('playlist-import-cue'));
      await _open(tester, 'playlist-current-settings');
      await _choose(tester, _key('playlist-smart-playlists'));
      fixture.editingEnabled = false;
      await tester.pumpWidget(_app(fixture, reduced: true));
      await tester.pumpAndSettle();
      await _open(tester, 'playlist-current-settings');
      expect(tester.widget<PopupMenuItem>(_key('playlist-import-cue')).enabled,
          isFalse);
      expect(
          tester
              .widget<PopupMenuItem>(_key('playlist-smart-playlists'))
              .enabled,
          isTrue);
      await _choose(tester, _key('playlist-smart-playlists'));
      expect(tester.takeException(), isNull);
    }
    expect(fixture.calls, [
      'importCue',
      'smartPlaylists',
      'smartPlaylists',
      'importCue',
      'smartPlaylists',
      'smartPlaylists'
    ]);
  });

  for (final mode in ['root', 'detail', 'selection']) {
    for (final brightness in Brightness.values) {
      testWidgets(
          '$mode has equal painted control heights in ${brightness.name}',
          (tester) async {
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final fixture = _Fixture()
          ..isRoot = mode == 'root'
          ..selecting = mode == 'selection'
          ..selectedCount = 12345;
        for (final dpr in [1.0, 1.25, 1.5, 2.0]) {
          tester.view.devicePixelRatio = dpr;
          tester.view.physicalSize = Size(1100 * dpr, 1100 * dpr);
          for (final scale in [1.0, 1.25, 1.5, 2.0]) {
            await tester.pumpWidget(_app(fixture,
                width: 980,
                textScale: scale,
                reduced: true,
                brightness: brightness,
                visualDensity: VisualDensity.compact));
            await tester.pumpAndSettle();
            final keys = mode == 'selection'
                ? [
                    'playlist-remove-selected',
                    'playlist-select-all',
                    'playlist-end-selection',
                  ]
                : [
                    mode == 'root'
                        ? 'playlist-create'
                        : 'playback-mode-shuffle',
                    if (mode == 'detail') 'playlist-add-menu',
                    'playlist-sort',
                    'playlist-view-toggle',
                    'playlist-current-settings',
                  ];
            final heights = <double>[];
            for (final key in keys) {
              final control = _control(key);
              final material = find
                  .descendant(
                    of: control,
                    matching: find.byType(Material),
                  )
                  .first;
              final paintedRect = tester.getRect(material);
              heights.add(paintedRect.height);
              expect(tester.getSize(control).height, paintedRect.height);
              expect(_style(tester, key).visualDensity, VisualDensity.standard);
              if (key == 'playlist-view-toggle' ||
                  key == 'playlist-current-settings') {
                expect(paintedRect.width, paintedRect.height);
              }
              for (final element in find
                  .descendant(of: control, matching: find.byType(Text))
                  .evaluate()) {
                final textRect = tester.getRect(find.byWidget(element.widget));
                expect(textRect.top, greaterThanOrEqualTo(paintedRect.top));
                expect(textRect.bottom, lessThanOrEqualTo(paintedRect.bottom));
              }
            }
            expect(heights, everyElement(closeTo(heights.first, .01)),
                reason: '$mode, DPR=$dpr, text=$scale');
            expect(heights.first, greaterThanOrEqualTo(44));
            expect(tester.takeException(), isNull);
          }
        }
      });
    }
  }

  testWidgets('large custom font grows every control without clipping labels',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(_Fixture()..isRoot = false,
        textScale: 2,
        width: 360,
        reduced: true,
        labelStyle: const TextStyle(fontSize: 22, height: 1.7)));
    await tester.pumpAndSettle();
    final keys = [
      'playback-mode-shuffle',
      'playlist-add-menu',
      'playlist-sort',
      'playlist-view-toggle',
      'playlist-current-settings',
    ];
    final height = tester.getSize(_control(keys.first)).height;
    expect(height, greaterThan(80));
    for (final key in keys) {
      final bounds = tester.getRect(_control(key));
      expect(bounds.height, closeTo(height, .01));
      for (final element in find
          .descendant(of: _control(key), matching: find.byType(Text))
          .evaluate()) {
        final textRect = tester.getRect(find.byWidget(element.widget));
        expect(textRect.top, greaterThanOrEqualTo(bounds.top));
        expect(textRect.bottom, lessThanOrEqualTo(bounds.bottom));
      }
    }
    expect(tester.takeException(), isNull);
  });

  test('all public sort modes have distinct readable Chinese labels', () {
    expect(PlaylistSortMode.values.take(8).map((mode) => mode.label), [
      '自定义',
      '名称升序',
      '名称降序',
      '艺术家',
      '专辑',
      '最新添加',
      '最近修改',
      '歌曲数量',
    ]);
    expect(PlaylistSortMode.values.map((mode) => mode.label).toSet().length,
        PlaylistSortMode.values.length);
    for (final mode in PlaylistSortMode.values) {
      if (mode.direction != null) {
        expect(mode.baseMode.withDirection(mode.direction!), mode);
      }
    }
  });

  testWidgets('root omits playback modes and retains library actions',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(_app(fixture));
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(find.byType(IconButton), findsNWidgets(2));
    expect(_key('playback-mode-shuffle'), findsNothing);
    expect(_key('playback-mode-repeat'), findsNothing);
    expect(_key('playlist-play-all'), findsNothing);
    expect(_key('playlist-start-selection'), findsNothing);
    expect(_key('playlist-open-albums'), findsNothing);
    expect(find.byTooltip('更多'), findsOneWidget);
    expect(find.byTooltip('排序：自定义'), findsOneWidget);
    await tester.tap(_control('playlist-create'));
    await tester.tap(_control('playlist-view-toggle'));
    expect(fixture.calls, ['create', 'view']);
    _expectTouchTargets(tester);
    await tester.pumpAndSettle();
  });

  testWidgets('root more menu preserves selection, albums and help',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(_app(fixture));
    for (final (key, event) in [
      ('playlist-start-selection', 'startSelection'),
      ('playlist-open-albums', 'albums'),
      ('playlist-help', 'help'),
    ]) {
      await _open(tester, 'playlist-current-settings');
      expect(find.text('浏览全部专辑 · 23'), findsOneWidget);
      expect(find.text('重命名'), findsNothing);
      _expectTouchTargets(tester);
      await _choose(tester, _key(key));
      expect(fixture.calls.last, event);
    }
    expect(fixture.calls.length, 3);
  });

  testWidgets('root sort excludes track-only modes and reports current choice',
      (tester) async {
    final fixture = _Fixture()..sortMode = PlaylistSortMode.modified;
    await tester.pumpWidget(_app(fixture));
    expect(find.text('修改时间 · 降序'), findsOneWidget);
    await _open(tester, 'playlist-sort');
    expect(
        tester
            .widgetList<PopupMenuItem>(_menuItems())
            .where((item) => item.enabled),
        hasLength(7));
    expect(_key('playlist-sort-artist'), findsNothing);
    expect(_key('playlist-sort-album'), findsNothing);
    expect(
      find.descendant(
        of: _key('playlist-sort-modified'),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    await _choose(tester, _key('playlist-sort-nameAscending'));
    expect(fixture.calls, ['sort:nameDescending']);
  });

  testWidgets('detail exposes mode controls and groups both add operations',
      (tester) async {
    final fixture = _Fixture()..isRoot = false;
    await tester.pumpWidget(_app(fixture));
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNWidgets(2));
    expect(_key('playlist-add-songs'), findsNothing);
    expect(_key('playlist-create'), findsNothing);
    await tester.tap(_control('playback-mode-shuffle'));
    expect(fixture.playback.calls, ['shuffle:true']);
    for (final (key, event) in [
      ('playlist-add-songs', 'addSongs'),
      ('playlist-create', 'create'),
    ]) {
      await _open(tester, 'playlist-add-menu');
      expect(find.text('添加歌曲'), findsOneWidget);
      expect(find.text('新建子歌单'), findsOneWidget);
      _expectTouchTargets(tester);
      await _choose(tester, _key(key));
      expect(fixture.calls.last, event);
    }
    expect(fixture.calls, ['addSongs', 'create']);
  });

  testWidgets('detail more menu keeps every management callback',
      (tester) async {
    final fixture = _Fixture()..isRoot = false;
    await tester.pumpWidget(_app(fixture));
    for (final (label, event) in [
      ('多选', 'startSelection'),
      ('重命名', 'rename'),
      ('更改所选歌曲', 'editSongs'),
      ('更改歌单封面', 'cover'),
      ('恢复默认封面', 'reset'),
      ('操作说明', 'help'),
    ]) {
      await _open(tester, 'playlist-current-settings');
      expect(_key('playlist-open-albums'), findsNothing);
      await _choose(tester, find.text(label));
      expect(fixture.calls.last, event);
    }
    expect(fixture.calls.length, 6);
  });

  testWidgets('optional actions are absent rather than deceptive dead entries',
      (tester) async {
    final fixture = _Fixture()
      ..isRoot = false
      ..addSongs = false
      ..management = false
      ..help = false;
    await tester.pumpWidget(_app(fixture));
    await _open(tester, 'playlist-add-menu');
    expect(_menuItems(), findsOneWidget);
    expect(find.text('添加歌曲'), findsNothing);
    await _dismiss(tester);
    await _open(tester, 'playlist-current-settings');
    expect(_menuItems(), findsOneWidget);
    expect(find.text('多选'), findsOneWidget);
    await _dismiss(tester);
    fixture
      ..management = true
      ..resetCover = false;
    await tester.pumpWidget(_app(fixture));
    await _open(tester, 'playlist-current-settings');
    expect(find.text('更改歌单封面'), findsOneWidget);
    expect(find.text('恢复默认封面'), findsNothing);
    await _dismiss(tester);
  });

  testWidgets(
      'detail exposes every field and both directions without transforming data',
      (tester) async {
    final fixture = _Fixture()..isRoot = false;
    for (final mode in PlaylistSortMode.values) {
      fixture.sortMode = mode;
      await tester.pumpWidget(_app(fixture, reduced: true));
      await _open(tester, 'playlist-sort');
      final sort = tester.widget<AppSortButton<PlaylistSortMode>>(
          find.byType(AppSortButton<PlaylistSortMode>));
      expect(sort.options, hasLength(17));
      await _choose(tester, _key('playlist-sort-${mode.baseMode.name}'));
      expect(fixture.calls.last, 'sort:${mode.name}');
      if (mode.direction != null) {
        final reverse = mode.direction == SortDirection.ascending
            ? SortDirection.descending
            : SortDirection.ascending;
        await _open(tester, 'playlist-sort');
        await _choose(tester, _key('app-sort-direction-${reverse.name}'));
        expect(fixture.calls.last, 'sort:${mode.withDirection(reverse).name}');
      }
    }
  });

  testWidgets('selection replaces the toolbar with three scoped actions',
      (tester) async {
    final fixture = _Fixture()
      ..selecting = true
      ..selectedCount = 3;
    await tester.pumpWidget(_app(fixture));
    expect(find.text('移除所选（3）'), findsOneWidget);
    expect(find.text('全选当前层'), findsOneWidget);
    expect(_key('playlist-current-settings'), findsNothing);
    expect(_key('playlist-sort'), findsNothing);
    expect(_key('playlist-create'), findsNothing);
    for (final key in [
      'playlist-remove-selected',
      'playlist-select-all',
      'playlist-end-selection',
    ]) {
      await tester.tap(_control(key));
    }
    expect(fixture.calls, ['removeSelected', 'selectAll', 'endSelection']);
    _expectTouchTargets(tester);
    await tester.pumpAndSettle();
  });

  testWidgets('zero selected disables removal but still allows selection exit',
      (tester) async {
    final fixture = _Fixture()..selecting = true;
    await tester.pumpWidget(_app(fixture));
    expect(_enabled(tester, 'playlist-remove-selected'), isFalse);
    expect(_enabled(tester, 'playlist-select-all'), isTrue);
    expect(_enabled(tester, 'playlist-end-selection'), isTrue);
    await tester.tap(_control('playlist-remove-selected'));
    expect(fixture.calls, isEmpty);
    fixture.hasItems = false;
    await tester.pumpWidget(_app(fixture));
    expect(_enabled(tester, 'playlist-select-all'), isFalse);
    await tester.tap(_control('playlist-end-selection'));
    expect(fixture.calls, ['endSelection']);
    await tester.pumpAndSettle();
  });

  testWidgets('read-only detail disables editing without disabling listening',
      (tester) async {
    final fixture = _Fixture()
      ..isRoot = false
      ..editingEnabled = false;
    await tester.pumpWidget(_app(fixture));
    expect(_enabled(tester, 'playback-mode-shuffle'), isTrue);
    expect(_enabled(tester, 'playlist-add-menu'), isFalse);
    expect(_enabled(tester, 'playlist-sort'), isFalse);
    expect(_enabled(tester, 'playlist-view-toggle'), isTrue);
    await tester.tap(_control('playback-mode-shuffle'));
    expect(fixture.playback.calls, ['shuffle:true']);
    await tester.tap(_control('playlist-view-toggle'));
    await _open(tester, 'playlist-current-settings');
    for (final element in _menuItems().evaluate()) {
      final item = element.widget as PopupMenuItem;
      expect(item.enabled, item.key == const ValueKey('playlist-help'));
    }
    await tester.tap(find.text('重命名'));
    await tester.pump();
    expect(fixture.calls, ['view']);
    await _choose(tester, _key('playlist-help'));
    expect(fixture.calls.last, 'help');
  });

  testWidgets('read-only root still permits modes, albums and help',
      (tester) async {
    final fixture = _Fixture()..editingEnabled = false;
    await tester.pumpWidget(_app(fixture));
    expect(_enabled(tester, 'playlist-create'), isFalse);
    expect(_enabled(tester, 'playlist-sort'), isFalse);
    await _open(tester, 'playlist-current-settings');
    expect(_key('playlist-play-all'), findsNothing);
    expect(
        tester.widget<PopupMenuItem>(_key('playlist-start-selection')).enabled,
        isFalse);
    expect(tester.widget<PopupMenuItem>(_key('playlist-open-albums')).enabled,
        isTrue);
    await _choose(tester, _key('playlist-open-albums'));
    expect(fixture.calls, ['albums']);
  });

  testWidgets('read-only selection retains an always available exit',
      (tester) async {
    final fixture = _Fixture()
      ..selecting = true
      ..selectedCount = 2
      ..editingEnabled = false;
    await tester.pumpWidget(_app(fixture));
    expect(_enabled(tester, 'playlist-remove-selected'), isFalse);
    expect(_enabled(tester, 'playlist-select-all'), isFalse);
    expect(_enabled(tester, 'playlist-end-selection'), isTrue);
    await tester.tap(_control('playlist-end-selection'));
    expect(fixture.calls, ['endSelection']);
    await tester.pumpAndSettle();
  });

  testWidgets(
      'empty root permits mode presets and create but disables sorting and selection',
      (tester) async {
    final fixture = _Fixture()
      ..hasItems = false
      ..canPlay = false;
    await tester.pumpWidget(_app(fixture));
    expect(_enabled(tester, 'playlist-create'), isTrue);
    expect(_enabled(tester, 'playlist-sort'), isFalse);
    expect(_key('playback-mode-shuffle'), findsNothing);
    expect(_key('playback-mode-repeat'), findsNothing);
    expect(fixture.playback.calls, isEmpty);
    expect(fixture.calls, isEmpty);
    await _open(tester, 'playlist-current-settings');
    expect(_key('playlist-play-all'), findsNothing);
    expect(
        tester.widget<PopupMenuItem>(_key('playlist-start-selection')).enabled,
        isFalse);
    await _dismiss(tester);
  });

  testWidgets('a policy change while more is open rejects an obsolete edit',
      (tester) async {
    final fixture = _Fixture()..isRoot = false;
    await tester.pumpWidget(_app(fixture));
    await _open(tester, 'playlist-current-settings');
    fixture.editingEnabled = false;
    await tester.pumpWidget(_app(fixture));
    await _choose(tester, find.text('重命名'));
    expect(fixture.calls, isEmpty);
    expect(_menuItems(), findsNothing);
  });

  testWidgets('a policy change while sort is open rejects the stale choice',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(_app(fixture));
    await _open(tester, 'playlist-sort');
    fixture.editingEnabled = false;
    await tester.pumpWidget(_app(fixture));
    await _choose(tester, _key('playlist-sort-newest'));
    expect(fixture.calls, isEmpty);
  });

  testWidgets(
      'removing an optional callback while open cannot invoke its snapshot',
      (tester) async {
    final fixture = _Fixture()..isRoot = false;
    await tester.pumpWidget(_app(fixture));
    await _open(tester, 'playlist-current-settings');
    fixture.resetCover = false;
    await tester.pumpWidget(_app(fixture));
    await _choose(tester, find.text('恢复默认封面'));
    expect(fixture.calls, isEmpty);
  });

  testWidgets(
      'a popup from the normal mode cannot dispatch during selection entry',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(_app(fixture));
    await _open(tester, 'playlist-current-settings');
    fixture.selecting = true;
    await tester.pumpWidget(_app(fixture));
    // The outgoing toolbar is still mounted for its 220ms transition, and the
    // popup itself lives outside that subtree in Navigator's overlay.
    expect(_key('playlist-create'), findsOneWidget);
    expect(_key('playlist-open-albums'), findsOneWidget);
    await _choose(tester, _key('playlist-open-albums'));
    expect(fixture.calls, isEmpty);
    expect(_key('playlist-remove-selected'), findsOneWidget);
  });

  testWidgets('a root popup cannot dispatch its old target during detail entry',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(_app(fixture));
    await _open(tester, 'playlist-current-settings');
    fixture.isRoot = false;
    await tester.pumpWidget(_app(fixture));
    expect(_key('playlist-open-albums'), findsOneWidget);
    await _choose(tester, _key('playlist-open-albums'));
    expect(fixture.calls, isEmpty);
    expect(_key('playlist-add-menu'), findsOneWidget);
  });

  testWidgets('menus support keyboard activation and Escape dismissal',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(_app(fixture));
    final focus = Focus.of(tester.element(find
        .descendant(
          of: _control('playlist-current-settings'),
          matching: find.byType(Icon),
        )
        .first));
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_key('playlist-open-albums'), findsOneWidget);
    await _dismiss(tester);
    expect(_menuItems(), findsNothing);
    expect(fixture.calls, isEmpty);
  });

  testWidgets('hover and press use subtle theme state layers and shared shapes',
      (tester) async {
    await tester.pumpWidget(_app(_Fixture()..isRoot = false));
    for (final key in [
      'playlist-add-menu',
      'playlist-sort',
      'playlist-view-toggle',
      'playlist-current-settings',
    ]) {
      final style = _style(tester, key);
      expect(style.shape!.resolve({}), AppShape.control);
      expect(style.minimumSize!.resolve({}), const Size(44, 44));
      expect(style.animationDuration, AppMotion.quick);
      expect(style.overlayColor!.resolve({WidgetState.hovered})!.a,
          closeTo(.08, .01));
      expect(style.overlayColor!.resolve({WidgetState.pressed})!.a,
          closeTo(.13, .01));
      expect(style.overlayColor!.resolve({WidgetState.disabled})!.a, 0);
    }
    expect(
      find.ancestor(
        of: find.byKey(_toolbarKey),
        matching: find.byType(ScaleTransition),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'mode transition removes old actions from hit testing and semantics',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(_app(fixture));
    await tester.pumpAndSettle();
    fixture.selecting = true;
    await tester.pumpWidget(_app(fixture));
    await tester.pump(const Duration(milliseconds: 40));
    expect(_key('playlist-create'), findsOneWidget);
    expect(_key('playlist-remove-selected'), findsOneWidget);
    expect(
      find.ancestor(
        of: _key('playlist-create'),
        matching: find.byWidgetPredicate(
            (widget) => widget is IgnorePointer && widget.ignoring),
      ),
      findsWidgets,
    );
    expect(
      find.ancestor(
        of: _key('playlist-create'),
        matching: find.byWidgetPredicate(
            (widget) => widget is ExcludeFocus && widget.excluding),
      ),
      findsWidgets,
    );
    expect(
      find.ancestor(
        of: _key('playlist-create'),
        matching: find.byWidgetPredicate(
            (widget) => widget is ExcludeSemantics && widget.excluding),
      ),
      findsWidgets,
    );
    await tester.pumpAndSettle();
    expect(_key('playlist-create'), findsNothing);
    expect(_key('playlist-end-selection'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('count changes update text without replaying the entire toolbar',
      (tester) async {
    final fixture = _Fixture()
      ..selecting = true
      ..selectedCount = 1;
    await tester.pumpWidget(_app(fixture));
    await tester.pumpAndSettle();
    fixture.selectedCount = 27;
    await tester.pumpWidget(_app(fixture));
    final transitions = find.descendant(
        of: find.byKey(_switcherKey), matching: find.byType(FadeTransition));
    expect(transitions, findsOneWidget);
    expect(tester.widget<FadeTransition>(transitions).opacity.value, 1);
    expect(find.text('移除所选（27）'), findsOneWidget);
    expect(find.text('移除所选（1）'), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets(
      'reduced motion changes modes immediately and removes style tweening',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(_app(fixture, reduced: true));
    expect(find.byKey(_switcherKey), findsNothing);
    expect(_style(tester, 'playlist-create').animationDuration, Duration.zero);
    fixture.selecting = true;
    await tester.pumpWidget(_app(fixture, reduced: true));
    expect(_key('playlist-create'), findsNothing);
    expect(_key('playlist-remove-selected'), findsOneWidget);
    expect(_style(tester, 'playlist-remove-selected').animationDuration,
        Duration.zero);
  });

  testWidgets(
      'enabling reduced motion mid-transition finishes outgoing controls',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(_app(fixture));
    fixture.selecting = true;
    await tester.pumpWidget(_app(fixture));
    await tester.pump(const Duration(milliseconds: 40));
    expect(_key('playlist-create'), findsOneWidget);
    await tester.pumpWidget(_app(fixture, reduced: true));
    expect(find.byKey(_switcherKey), findsNothing);
    expect(_key('playlist-create'), findsNothing);
    expect(_key('playlist-remove-selected'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final feature in ['disableAnimations', 'reduceMotion']) {
    testWidgets('platform $feature is respected with a custom MediaQuery',
        (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(
        disableAnimations: feature == 'disableAnimations',
        reduceMotion: feature == 'reduceMotion',
      );
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pumpWidget(_app(_Fixture()));
      expect(find.byKey(_switcherKey), findsNothing);
      expect(
          _style(tester, 'playlist-create').animationDuration, Duration.zero);
    });
  }

  testWidgets('a live platform preference change ends the mode transition',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(_app(fixture));
    fixture.selecting = true;
    await tester.pumpWidget(_app(fixture));
    await tester.pump(const Duration(milliseconds: 40));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    expect(find.byKey(_switcherKey), findsNothing);
    expect(_key('playlist-create'), findsNothing);
    expect(_key('playlist-end-selection'), findsOneWidget);
  });

  testWidgets('inactive ticker scopes render controls in their final state',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(_app(fixture, tickerEnabled: false));
    expect(find.byKey(_switcherKey), findsNothing);
    fixture.selecting = true;
    await tester.pumpWidget(_app(fixture, tickerEnabled: false));
    expect(_key('playlist-create'), findsNothing);
    expect(_key('playlist-end-selection'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('quick mode changes and disposal leave no orphaned animation',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(_app(fixture));
    fixture.isRoot = false;
    await tester.pumpWidget(_app(fixture));
    await tester.pump(const Duration(milliseconds: 30));
    fixture.selecting = true;
    await tester.pumpWidget(_app(fixture));
    await tester.pump(const Duration(milliseconds: 30));
    fixture.selecting = false;
    await tester.pumpWidget(_app(fixture));
    await tester.pumpAndSettle();
    expect(_key('playlist-add-menu'), findsOneWidget);
    expect(_key('playlist-remove-selected'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  for (final reduced in [false, true]) {
    testWidgets('popup uses the shared motion duration (reduced=$reduced)',
        (tester) async {
      await tester.pumpWidget(_app(_Fixture(), reduced: reduced));
      await _open(tester, 'playlist-sort');
      final route =
          ModalRoute.of(tester.element(_key('playlist-sort-custom')))!;
      expect(
          route.transitionDuration, reduced ? Duration.zero : AppMotion.quick);
      final material = find.ancestor(
        of: _key('playlist-sort-custom'),
        matching: find.byType(Material),
      );
      expect(
        tester.widgetList<Material>(material).any((widget) =>
            widget.shape == AppShape.control && widget.elevation == 4),
        isTrue,
      );
      await _dismiss(tester);
    });
  }

  testWidgets(
      'disposing the toolbar with an open menu safely drops its callback',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(_app(fixture));
    await _open(tester, 'playlist-current-settings');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(fixture.calls, isEmpty);
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      for (final mode in ['root', 'detail', 'selection']) {
        testWidgets(
            '$mode wraps at narrow widths with ${brightness.name} theme and ${scale}x text',
            (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(800, 1000);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final fixture = _Fixture()
            ..isRoot = mode == 'root'
            ..selecting = mode == 'selection'
            ..selectedCount = 1234567;
          for (final width in [224.0, 280.0, 360.0, 600.0]) {
            await tester.pumpWidget(_app(
              fixture,
              width: width,
              textScale: scale,
              reduced: true,
              brightness: brightness,
            ));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull,
                reason: '$mode, $width logical pixels, $scale scale');
            final bounds = tester.getRect(find.byKey(_boundsKey));
            for (final element in find
                .descendant(
                  of: find.byKey(_toolbarKey),
                  matching: find.byWidgetPredicate((widget) =>
                      widget is ButtonStyleButton || widget is IconButton),
                )
                .evaluate()) {
              final rect = tester.getRect(find.byWidget(element.widget));
              expect(rect.left, greaterThanOrEqualTo(bounds.left - .01));
              expect(rect.right, lessThanOrEqualTo(bounds.right + .01));
            }
            _expectTouchTargets(tester);
            if (mode != 'selection') {
              for (final menu in [
                'playlist-sort',
                'playlist-current-settings',
                if (mode == 'detail') 'playlist-add-menu',
              ]) {
                await _open(tester, menu);
                expect(tester.takeException(), isNull,
                    reason: '$menu, $width logical pixels, $scale scale');
                _expectTouchTargets(tester);
                await _dismiss(tester);
              }
            }
          }
        });
      }
    }
  }

  testWidgets(
      'a real narrow viewport keeps long labels accessible at 200 percent',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(248, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final semantics = tester.ensureSemantics();
    final fixture = _Fixture()
      ..selecting = true
      ..selectedCount = 123456789;
    await tester.pumpWidget(_app(fixture, textScale: 2, reduced: true));
    expect(find.byTooltip('移除所选（123456789）'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('移除所选（123456789）')), findsWidgets);
    expect(
        MediaQuery.textScalerOf(
                tester.element(_control('playlist-end-selection')))
            .scale(14),
        28);
    _expectTouchTargets(tester);
    expect(tester.takeException(), isNull);
    fixture
      ..selecting = false
      ..isRoot = false;
    await tester.pumpWidget(_app(fixture, textScale: 2, reduced: true));
    for (final menu in [
      'playlist-sort',
      'playlist-current-settings',
      'playlist-add-menu',
    ]) {
      await _open(tester, menu);
      _expectTouchTargets(tester);
      expect(tester.takeException(), isNull);
      await _dismiss(tester);
    }
    semantics.dispose();
  });
}
