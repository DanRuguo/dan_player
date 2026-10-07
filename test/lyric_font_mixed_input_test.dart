import 'package:dan_player/app_preference.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _sliderKey = ValueKey('lyric-font-size-slider');

class _Fixture {
  _Fixture() {
    addTearDown(controller.dispose);
    addTearDown(hidden.dispose);
  }

  final preferences = NowPlayingPagePreference.fromMap({})..lyricFontSize = 39;
  late final controller = LyricViewController(preferences: preferences);
  final hidden = ValueNotifier(false);

  Widget app() => MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider.value(
            value: controller,
            child: Align(
                alignment: Alignment.centerRight,
                child: LyricFontSizeMenu(hidden: hidden)),
          ),
        ),
      );

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const ValueKey('lyric-font-size-open')));
    await tester.pumpAndSettle();
  }

  Future<TestGesture> drag(WidgetTester tester) async {
    final gesture = await tester
        .startGesture(tester.getCenter(find.byKey(_sliderKey)), pointer: 7);
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(controller.fontDragPreviewSize, greaterThan(39));
    expect(controller.fontSizeAdjusting, isTrue);
    expect(preferences.lyricFontSize, 39);
    return gesture;
  }
}

SemanticsNode _adjustmentNode(WidgetTester tester, SemanticsAction action) {
  SemanticsNode? result;
  void visit(SemanticsNode node) {
    if (node.getSemanticsData().hasAction(action)) {
      result = node;
      return;
    }
    node.visitChildren((child) {
      visit(child);
      return result == null;
    });
  }

  visit(tester.getSemantics(find.byKey(_sliderKey)));
  expect(result, isNotNull, reason: 'Use the real Slider adjustment action');
  return result!;
}

Future<void> _adjust(WidgetTester tester, SemanticsAction action) async {
  final node = _adjustmentNode(tester, action);
  node.owner!.performAction(node.id, action);
  await tester.pump();
}

double _draft(WidgetTester tester) =>
    tester.widget<Slider>(find.byKey(_sliderKey)).value;

Future<void> _focusSlider(WidgetTester tester) async {
  final focus = tester.widget<FocusableActionDetector>(find
      .descendant(
          of: find.byKey(_sliderKey),
          matching: find.byType(FocusableActionDetector))
      .first);
  focus.focusNode!.requestFocus();
  await tester.pump();
}

void main() {
  for (final action in [SemanticsAction.increase, SemanticsAction.decrease]) {
    testWidgets('held font touch retains its draft through ${action.name}',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final fixture = _Fixture();
      await fixture.open(tester);
      final gesture = await fixture.drag(tester);
      var released = false;
      try {
        final draft = _draft(tester);
        await _adjust(tester, action);
        expect(fixture.preferences.lyricFontSize, 39);
        expect(fixture.controller.fontSizeAdjusting, isTrue);
        expect(fixture.controller.fontDragPreviewSize, draft);
        expect(_draft(tester), draft);
        await gesture.moveBy(const Offset(18, 0));
        await tester.pump();
        final moved = _draft(tester);
        expect(moved, greaterThan(draft));
        await gesture.up();
        released = true;
        await tester.pumpAndSettle();
        expect(fixture.preferences.lyricFontSize, moved);
        expect(fixture.controller.fontSizeAdjusting, isFalse);
        expect(fixture.controller.fontDragPreviewSize, isNull);
        await _adjust(tester, action);
        await tester.pumpAndSettle();
        expect(fixture.preferences.lyricFontSize,
            moved + (action == SemanticsAction.increase ? 1 : -1));
        expect(fixture.controller.fontSizeAdjusting, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        if (!released) await gesture.cancel();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        semantics.dispose();
      }
    });
  }

  for (final key in [
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowLeft,
  ]) {
    testWidgets('held font touch excludes ${key.keyLabel} until release',
        (tester) async {
      final fixture = _Fixture();
      await fixture.open(tester);
      await _focusSlider(tester);
      final gesture = await fixture.drag(tester);
      var released = false;
      try {
        final draft = _draft(tester);
        await tester.sendKeyEvent(key);
        await tester.pump();
        expect(fixture.preferences.lyricFontSize, 39);
        expect(fixture.controller.fontSizeAdjusting, isTrue);
        expect(_draft(tester), draft);
        await gesture.moveBy(const Offset(18, 0));
        await tester.pump();
        final moved = _draft(tester);
        expect(moved, greaterThan(draft));
        await gesture.up();
        released = true;
        await tester.pumpAndSettle();
        expect(fixture.preferences.lyricFontSize, moved);
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(fixture.preferences.lyricFontSize,
            moved + (key == LogicalKeyboardKey.arrowRight ? 1 : -1));
        expect(tester.takeException(), isNull);
      } finally {
        if (!released) await gesture.cancel();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    });
  }

  testWidgets(
      'a nested font adjustment cannot make pointer cancellation persist',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final fixture = _Fixture();
    await fixture.open(tester);
    final gesture = await fixture.drag(tester);
    await _adjust(tester, SemanticsAction.increase);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(fixture.preferences.lyricFontSize, 39);
    expect(fixture.controller.fontSizeAdjusting, isFalse);
    expect(fixture.controller.fontDragPreviewSize, isNull);
    await _adjust(tester, SemanticsAction.increase);
    await tester.pumpAndSettle();
    expect(fixture.preferences.lyricFontSize, 40);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'restoring the window cannot let semantics revive a held old font drag',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final fixture = _Fixture();
    await fixture.open(tester);
    final gesture = await fixture.drag(tester);
    fixture.hidden.value = true;
    await tester.pump();
    fixture.hidden.value = false;
    await tester.pump();
    expect(fixture.controller.fontSizeAdjusting, isFalse);
    await _adjust(tester, SemanticsAction.increase);
    expect(fixture.preferences.lyricFontSize, 39);
    expect(fixture.controller.fontSizeAdjusting, isFalse);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fixture.preferences.lyricFontSize, 39);
    await _adjust(tester, SemanticsAction.increase);
    await tester.pumpAndSettle();
    expect(fixture.preferences.lyricFontSize, 40);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });
}
