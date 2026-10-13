import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/component/settings_section_visibility.dart';
import 'package:dan_player/page/settings_page/background_settings.dart';
import 'package:dan_player/window_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

const _backgrounds = BackgroundPreferences(
  main: BackgroundAppearance(source: BackgroundSource.artwork),
);

SemanticsNode _adjustmentNode(WidgetTester tester, Finder slider) {
  SemanticsNode? result;
  void visit(SemanticsNode node) {
    if (node.getSemanticsData().hasAction(SemanticsAction.decrease)) {
      result = node;
      return;
    }
    node.visitChildren((child) {
      visit(child);
      return result == null;
    });
  }

  visit(tester.getSemantics(slider));
  expect(result, isNotNull, reason: 'Use the actual Slider adjustment action.');
  return result!;
}

void main() {
  for (final setting in ['opacity', 'blur']) {
    testWidgets('held background $setting cannot transfer to another scene',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final preferences = ValueNotifier(_backgrounds);
      final status = ValueNotifier(const WindowBackdropStatus());
      addTearDown(preferences.dispose);
      addTearDown(status.dispose);
      var saves = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BackgroundSettingsPanel(
              preferences: preferences,
              status: status,
              onSave: () async => saves++,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final slider = find.byKey(ValueKey('background-$setting'));
      final primary =
          await tester.startGesture(tester.getCenter(slider), pointer: 11);
      await primary.moveBy(const Offset(35, 0));
      await tester.pump();
      expect(preferences.value.main, isNot(_backgrounds.main),
          reason: 'The original scene must keep its immediate preview.');
      expect(saves, 0);

      // A second physical touch can select a scene while the slider retains
      // its original recognizer. Both scenes expose the same enabled slider.
      await tester.tap(
          find.byKey(const ValueKey('background-scene-nowPlaying')),
          pointer: 22);
      await tester.pump();
      final switched = preferences.value;
      await primary.moveBy(const Offset(100, 0));
      await tester.pump();
      expect(preferences.value, switched,
          reason: 'Remaining movement belongs to the retired main scene.');
      await primary.up();
      await tester.pumpAndSettle();
      expect(preferences.value, switched);
      expect(saves, 0, reason: 'The old release cannot save a new scene.');
      expect(tester.takeException(), isNull);
    });
  }

  for (final change in ['preferences', 'hidden section']) {
    testWidgets('held background input retires on $change', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final first = ValueNotifier(_backgrounds);
      final next = ValueNotifier(_backgrounds);
      final status = ValueNotifier(const WindowBackdropStatus());
      addTearDown(first.dispose);
      addTearDown(next.dispose);
      addTearDown(status.dispose);
      var preferences = first;
      var visible = true;
      var saves = 0;
      late StateSetter update;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(builder: (context, setState) {
            update = setState;
            // Hidden visual updates may remain enabled by user preference.
            // Settings category visibility still revokes input ownership.
            return SettingsSectionVisibility(
              visible: visible,
              child: SingleChildScrollView(
                child: BackgroundSettingsPanel(
                  preferences: preferences,
                  status: status,
                  onSave: () async => saves++,
                ),
              ),
            );
          }),
        ),
      ));
      await tester.pumpAndSettle();
      final slider = find.byKey(const ValueKey('background-opacity'));
      final primary =
          await tester.startGesture(tester.getCenter(slider), pointer: 11);
      await primary.moveBy(const Offset(35, 0));
      await tester.pump();
      final preview = first.value;
      expect(preview.main, isNot(_backgrounds.main));
      update(() {
        if (change == 'preferences') {
          preferences = next;
        } else {
          visible = false;
        }
      });
      await tester.pump();
      if (change == 'hidden section') {
        update(() => visible = true);
        await tester.pump();
      }
      await primary.moveBy(const Offset(100, 0));
      await tester.pump();
      await primary.up();
      await tester.pumpAndSettle();
      expect(first.value, preview);
      expect(next.value, _backgrounds);
      expect(saves, 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final outcome in ['release', 'cancel', 'source', 'dispose']) {
    testWidgets('background physical $outcome preserves its own preview',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final preferences = ValueNotifier(_backgrounds);
      final status = ValueNotifier(const WindowBackdropStatus());
      addTearDown(preferences.dispose);
      addTearDown(status.dispose);
      var saves = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BackgroundSettingsPanel(
              preferences: preferences,
              status: status,
              onSave: () async => saves++,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final slider = find.byKey(const ValueKey('background-opacity'));
      final primary =
          await tester.startGesture(tester.getCenter(slider), pointer: 11);
      await primary.moveBy(const Offset(35, 0));
      await tester.pump();
      final preview = preferences.value.main.opacity;
      expect(preview, isNot(_backgrounds.main.opacity));
      expect(saves, 0);

      if (outcome == 'source') {
        await tester.tap(
            find.byKey(const ValueKey('background-source-desktop')),
            pointer: 22);
        await tester.pump();
        await primary.moveBy(const Offset(100, 0));
        await tester.pump();
      } else if (outcome == 'dispose') {
        await tester.pumpWidget(const SizedBox.shrink());
      }
      if (outcome == 'cancel' || outcome == 'dispose') {
        await primary.cancel();
      } else {
        await primary.up();
      }
      await tester.pumpAndSettle();
      expect(preferences.value.main.opacity, preview);
      expect(saves, outcome == 'release' || outcome == 'source' ? 1 : 0,
          reason: 'A source selection saves itself; an old drag cannot save.');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('secondary slider touch cannot replace the primary drag',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final preferences = ValueNotifier(_backgrounds);
    final status = ValueNotifier(const WindowBackdropStatus());
    addTearDown(preferences.dispose);
    addTearDown(status.dispose);
    var saves = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BackgroundSettingsPanel(
            preferences: preferences,
            status: status,
            onSave: () async => saves++,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final slider = find.byKey(const ValueKey('background-opacity'));
    final center = tester.getCenter(slider);
    final primary = await tester.startGesture(center, pointer: 11);
    await primary.moveBy(const Offset(35, 0));
    await tester.pump();
    final preview = preferences.value;
    final secondary = await tester.startGesture(center, pointer: 22);
    await secondary.moveBy(const Offset(-100, 0));
    await secondary.cancel();
    await tester.pump();
    expect(preferences.value, preview);
    expect(saves, 0);
    await primary.moveBy(const Offset(35, 0));
    await tester.pump();
    expect(preferences.value.main.opacity, lessThan(preview.main.opacity));
    await primary.up();
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(tester.takeException(), isNull);
  });

  for (final pending in [false, true]) {
    testWidgets('background semantics preserves held input pending=$pending',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final semantics = tester.ensureSemantics();
      try {
        final preferences = ValueNotifier(_backgrounds);
        final status = ValueNotifier(const WindowBackdropStatus());
        addTearDown(preferences.dispose);
        addTearDown(status.dispose);
        var saves = 0;
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(children: [
                BackgroundSettingsPanel(
                  preferences: preferences,
                  status: status,
                  onSave: () async => saves++,
                ),
                const SizedBox(height: 1800),
              ]),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        final slider = find.byKey(const ValueKey('background-opacity'));
        final primary =
            await tester.startGesture(tester.getCenter(slider), pointer: 11);
        if (!pending) await primary.moveBy(const Offset(35, 0));
        await tester.pump();
        if (pending) {
          expect(preferences.value, _backgrounds,
              reason: 'The real scroll arena has not accepted slider start.');
        }
        final preview = preferences.value;
        final node = _adjustmentNode(tester, slider);
        node.owner!.performAction(node.id, SemanticsAction.decrease);
        await tester.pump();
        expect(preferences.value, preview,
            reason: 'Nested semantics cannot change the physical preview.');
        expect(saves, 0);

        await primary.moveBy(const Offset(35, 0));
        await tester.pump();
        final moved = preferences.value.main.opacity;
        expect(moved, lessThan(preview.main.opacity),
            reason: 'The original physical touch must still be able to move.');
        await primary.up();
        await tester.pumpAndSettle();
        expect(saves, 1);
        final idle = _adjustmentNode(tester, slider);
        idle.owner!.performAction(idle.id, SemanticsAction.decrease);
        await tester.pumpAndSettle();
        expect(preferences.value.main.opacity, greaterThan(moved));
        expect(saves, 2,
            reason: 'Idle semantics retains its existing save path.');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
      }
    });
  }
}
