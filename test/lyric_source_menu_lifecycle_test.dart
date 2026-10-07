import 'package:dan_player/page/now_playing_page/component/lyric_source_view.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _sourceButton = ValueKey('lyric-source-menu-button');
const _freshControls = ValueKey('fresh-lyric-controls');
const _outsideButton = ValueKey('outside-lyric-controls');

Widget _source() => LyricSourceMenuButton(
    enabled: true,
    showLocal: true,
    isLocal: true,
    onChooseDefault: () {},
    onOnline: () {},
    onLocal: () {});

Widget _surface(String id, Widget controls) => SizedBox(
      width: 320,
      height: 420,
      child: LyricControlsSurface(
        key: ValueKey(id),
        controls: controls,
        child: const SizedBox.expand(),
      ),
    );

Widget _app({required bool fresh, bool sibling = false, String? surfaceId}) =>
    MaterialApp(
      home: Scaffold(
        body: Column(children: [
          TextButton(
              key: _outsideButton,
              onPressed: () {},
              child: const Text('Outside lyrics')),
          Expanded(
            child: Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _surface(
                    surfaceId ?? (fresh ? 'fresh-surface' : 'old-surface'),
                    fresh
                        ? const IconButton(
                            key: _freshControls,
                            onPressed: null,
                            icon: Icon(Icons.tune))
                        : _source()),
                if (sibling)
                  _surface(
                      'sibling-surface',
                      const IconButton(
                          key: _freshControls,
                          onPressed: null,
                          icon: Icon(Icons.tune))),
              ]),
            ),
          ),
        ]),
      ),
    );

bool _visible(WidgetTester tester, Key key) => !tester
    .widget<IgnorePointer>(find
        .ancestor(of: find.byKey(key), matching: find.byType(IgnorePointer))
        .first)
    .ignoring;

Future<TestGesture> _openWithMouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: const Offset(5, 5));
  await mouse.moveTo(tester.getCenter(find.byKey(_sourceButton)));
  await tester.pump();
  await mouse.down(tester.getCenter(find.byKey(_sourceButton)));
  await mouse.up();
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('lyric-source-online')).hitTestable(),
      findsOneWidget);
  return mouse;
}

void main() {
  testWidgets('unmounting an open source menu cannot reveal a fresh toolbar',
      (tester) async {
    await tester.pumpWidget(_app(fresh: false));
    await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey('old-surface'))) +
            const Offset(20, 20));
    await tester.pump();
    await tester.tap(find.byKey(_sourceButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lyric-source-online')).hitTestable(),
        findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app(fresh: true));
    await tester.pumpAndSettle();
    expect(_visible(tester, _freshControls), isFalse,
        reason: 'Removing the old open menu releases only its surface');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an open source menu keeps its own toolbar after mouse exit',
      (tester) async {
    await tester.pumpWidget(_app(fresh: false));
    final mouse = await _openWithMouse(tester);
    await mouse.moveTo(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(_visible(tester, _sourceButton), isTrue);
    expect(find.byKey(const ValueKey('lyric-source-online')).hitTestable(),
        findsOneWidget);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing an open source control releases its mounted surface',
      (tester) async {
    await tester.pumpWidget(_app(fresh: false, surfaceId: 'retained-surface'));
    final surface =
        tester.element(find.byKey(const ValueKey('retained-surface')));
    final mouse = await _openWithMouse(tester);
    await mouse.moveTo(const Offset(5, 5));
    await tester.pump();
    await tester.pumpWidget(_app(fresh: true, surfaceId: 'retained-surface'));
    await tester.pumpAndSettle();
    expect(tester.element(find.byKey(const ValueKey('retained-surface'))),
        same(surface));
    expect(_visible(tester, _freshControls), isFalse);
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('source menu focus cannot reveal another mounted lyric surface',
      (tester) async {
    await tester.pumpWidget(_app(fresh: false, sibling: true));
    expect(_visible(tester, _freshControls), isFalse);
    final mouse = await _openWithMouse(tester);
    await mouse.moveTo(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(_visible(tester, _sourceButton), isTrue);
    expect(_visible(tester, _freshControls), isFalse);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'outside mouse input closes the menu and releases toolbar visibility',
      (tester) async {
    await tester.pumpWidget(_app(fresh: false));
    final mouse = await _openWithMouse(tester);
    await mouse.moveTo(const Offset(5, 5));
    await tester.pump();
    await mouse.down(const Offset(5, 5));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lyric-source-online')), findsNothing);
    expect(_visible(tester, _sourceButton), isFalse);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'keyboard can focus hidden source controls and Escape closes the menu',
      (tester) async {
    await tester.pumpWidget(_app(fresh: false));
    expect(_visible(tester, _sourceButton), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_visible(tester, _sourceButton), isTrue);
    // The surface itself is a focus stop between the outside button and its
    // mounted source control, just as for the existing reading-tool surface.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lyric-source-online')).hitTestable(),
        findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lyric-source-online')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
