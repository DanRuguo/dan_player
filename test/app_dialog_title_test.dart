import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/audio_metadata_dialog.dart';
import 'package:dan_player/component/playlist_name_dialog.dart';
import 'package:dan_player/component/playlist_song_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(507, 320);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _host(Widget child, {double scale = 1, Color color = Colors.teal}) =>
    MaterialApp(
      theme: ThemeData(
        colorSchemeSeed: color,
        dialogTheme: DialogThemeData(
          titleTextStyle: TextStyle(fontSize: 24, color: color),
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Scaffold(body: child),
    );

void _centered(WidgetTester tester, String title) {
  final label = find.text(title);
  expect(label, findsOneWidget);
  final text = tester.widget<Text>(label);
  expect(text.textAlign, TextAlign.center);
  final dialog = find.ancestor(of: label, matching: find.byType(Dialog)).first;
  expect(tester.getRect(label).center.dx,
      closeTo(tester.getRect(dialog).center.dx, .01));
  expect(tester.takeException(), isNull);
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('actual metadata title centers without centering fields $scale',
        (tester) async {
      _size(tester);
      late BuildContext pageContext;
      await tester.pumpWidget(_host(
        Builder(builder: (context) {
          pageContext = context;
          return const SizedBox.expand();
        }),
        scale: scale,
      ));
      final result = showEditAudioMetadataDialog(
          pageContext, CategoryTestAudio('Synthetic title'));
      await tester.pumpAndSettle();
      _centered(tester, '编辑歌曲信息');
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields, hasLength(4));
      expect(
          fields.every((field) => field.textAlign == TextAlign.start), isTrue);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });

    testWidgets(
        'selected-song title centers and list keeps its alignment $scale',
        (tester) async {
      _size(tester);
      await tester.pumpWidget(_host(
        PlaylistSongPicker(
          library: [CategoryTestAudio('List title')],
          existingPaths: const {},
          replaceSelection: true,
        ),
        scale: scale,
      ));
      await tester.pumpAndSettle();
      _centered(tester, '更改所选歌曲');
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.textAlign, TextAlign.start);
      await tester.scrollUntilVisible(find.text('List title'), 60,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text('List title')).textAlign, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('long dynamic title wraps in a short dialog at $scale',
        (tester) async {
      _size(tester);
      const title = '在“包含多个文字的演示歌单名称”下新建子歌单';
      await tester.pumpWidget(_host(
        const PlaylistNameDialog(title: title),
        scale: scale,
      ));
      await tester.pumpAndSettle();
      _centered(tester, title);
      expect(tester.widget<Text>(find.text(title)).maxLines, isNull);
      expect(find.text('取消').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('balanced title action stays clickable with large text $scale',
        (tester) async {
      _size(tester);
      var toggles = 0;
      await tester.pumpWidget(_host(
        AlertDialog(
          scrollable: true,
          title: AppDialogTitle(
            '均衡器',
            sideExtent: 64,
            trailing: Switch(value: true, onChanged: (_) => toggles++),
          ),
          content:
              const SizedBox(width: 300, child: Text('Content stays start')),
          actions: [TextButton(onPressed: () {}, child: const Text('完成'))],
        ),
        scale: scale,
      ));
      await tester.pumpAndSettle();
      _centered(tester, '均衡器');
      await tester.tap(find.byType(Switch));
      expect(toggles, 1);
      expect(tester.widget<Text>(find.text('Content stays start')).textAlign,
          isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('dialog title retains inherited theme and semantic label',
      (tester) async {
    final semantics = tester.ensureSemantics();
    Widget app(Color color) => _host(
          const AlertDialog(
            title: AppDialogTitle('Theme title'),
            content: Text('Body'),
          ),
          color: color,
        );
    try {
      for (final color in [Colors.teal, Colors.deepPurple]) {
        await tester.pumpWidget(app(color));
        await tester.pumpAndSettle();
        final label = find.text('Theme title');
        expect(tester.widget<Text>(label).style, isNull);
        expect(DefaultTextStyle.of(tester.element(label)).style.color, color);
        expect(find.bySemanticsLabel(RegExp('Theme title')), findsOneWidget);
        _centered(tester, 'Theme title');
      }
    } finally {
      semantics.dispose();
    }
  });
}
