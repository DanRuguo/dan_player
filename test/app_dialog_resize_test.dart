import 'package:dan_player/component/app_dialog_resize.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> mount(WidgetTester tester,
      {required ValueNotifier<bool> expanded,
      required ValueNotifier<bool> motion,
      required ValueNotifier<bool> visible,
      bool host = true}) async {
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => ValueListenableBuilder<bool>(
            valueListenable: motion,
            builder: (_, enabled, motionChild) => MotionPreferencesScope(
                preferences: MotionPreferences(
                    disabled: enabled ? const {} : {MotionKind.layout}),
                child: ValueListenableBuilder<bool>(
                    valueListenable: visible,
                    builder: (_, shown, nestedChild) => TickerMode(
                        enabled: shown,
                        child: host
                            ? AppPresentationHost(child: child!)
                            : child!)))),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showAppDialog<void>(
                        context: context,
                        builder: (_) => AlertDialog(
                                title: const Text('Audio report'),
                                content: AppDialogResize(
                                    key: const ValueKey('resizing-content'),
                                    child: ValueListenableBuilder<bool>(
                                        valueListenable: expanded,
                                        builder: (_, more, fieldChild) =>
                                            SizedBox(
                                                width: 300,
                                                child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      TextFormField(
                                                          initialValue:
                                                              'draft'),
                                                      SizedBox(
                                                          height:
                                                              more ? 220 : 40),
                                                    ])))),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      child: const Text('Close'))
                                ])),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  for (final host in [false, true]) {
    testWidgets('dialog surface grows and shrinks progressively host=$host',
        (tester) async {
      final expanded = ValueNotifier(false),
          motion = ValueNotifier(true),
          visible = ValueNotifier(true);
      addTearDown(expanded.dispose);
      addTearDown(motion.dispose);
      addTearDown(visible.dispose);
      await mount(tester,
          expanded: expanded, motion: motion, visible: visible, host: host);
      Finder surface() => find
          .descendant(
              of: find.byType(AlertDialog), matching: find.byType(Material))
          .first;
      final original = tester.getSize(surface()).height;
      expanded.value = true;
      await tester.pump();
      expect(tester.getSize(surface()).height, closeTo(original, .01));
      await tester.pump(const Duration(milliseconds: 70));
      final intermediate = tester.getSize(surface()).height;
      expect(intermediate, greaterThan(original));
      await tester.pumpAndSettle();
      final large = tester.getSize(surface()).height;
      expect(intermediate, lessThan(large));
      expanded.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      expect(
          tester.getSize(surface()).height, inExclusiveRange(original, large));
      await tester.pumpAndSettle();
      expect(tester.getSize(surface()).height, closeTo(original, .01));
      expect(tester.takeException(), isNull);
    });
  }

  for (final interruption in ['setting', 'native', 'hidden']) {
    testWidgets(
        'resize interruption preserves form state and focus: $interruption',
        (tester) async {
      final expanded = ValueNotifier(false),
          motion = ValueNotifier(true),
          visible = ValueNotifier(true);
      addTearDown(expanded.dispose);
      addTearDown(motion.dispose);
      addTearDown(visible.dispose);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await mount(tester, expanded: expanded, motion: motion, visible: visible);
      await tester.enterText(find.byType(TextFormField), 'keep this draft');
      final state = tester.state<EditableTextState>(find.byType(EditableText));
      final focus = state.widget.focusNode;
      expect(focus.hasFocus, isTrue);
      expanded.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      final before =
          tester.getSize(find.byKey(const ValueKey('resizing-content'))).height;
      switch (interruption) {
        case 'setting':
          motion.value = false;
        case 'native':
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(reduceMotion: true);
        case 'hidden':
          visible.value = false;
      }
      await tester.pump();
      expect(
          tester.getSize(find.byKey(const ValueKey('resizing-content'))).height,
          greaterThan(before));
      expect(tester.state<EditableTextState>(find.byType(EditableText)),
          same(state));
      expect(state.widget.controller.text, 'keep this draft');
      expect(focus.hasFocus, isTrue);
      focus.unfocus();
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      // A hidden navigator also mutes its route transition. Resume visibility
      // before exercising the close button, as an actual window would.
      visible.value = true;
      await tester.pump();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialogResize), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
