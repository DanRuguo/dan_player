import 'dart:async';

import 'package:dan_player/background_image_store.dart';
import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/page/settings_page/background_settings.dart';
import 'package:dan_player/window_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _id = '${'a' * 64}.png';

class _Store extends BackgroundImageStore {
  _Store() : super(directory: () async => throw StateError('no filesystem'));
  int imports = 0;
  int reads = 0;
  int cleanups = 0;
  Object? failure;
  Future<ManagedBackgroundImage>? pending;
  Set<String> retained = {};

  @override
  Future<ManagedBackgroundImage> importFile(String sourcePath) async {
    imports++;
    if (failure != null) throw failure!;
    if (pending != null) return await pending!;
    return ManagedBackgroundImage(
        id: _id, name: '测试图片.png', width: 300, height: 200);
  }

  @override
  Future<ImageProvider?> imageFor(String? id) async {
    reads++;
    return null;
  }

  @override
  Future<int> removeUnused(Set<String> Function() retainedIds) async {
    cleanups++;
    retained = retainedIds();
    return 2;
  }
}

Widget _app({
  required ValueNotifier<BackgroundPreferences> preferences,
  required _Store store,
  FutureOr<String?> Function()? pick,
  Future<void> Function()? save,
  double scale = 1,
}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
            textScaler: TextScaler.linear(scale), disableAnimations: true),
        child: Scaffold(
            body: SingleChildScrollView(
                child: BackgroundSettingsPanel(
          preferences: preferences,
          status: ValueNotifier(const WindowBackdropStatus()),
          imageStore: store,
          pickImage: pick ?? () => 'D:/synthetic/picture.png',
          onSave: save ?? () async {},
        ))),
      ),
    );

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'default settings are passive and native background disables image motion',
      (tester) async {
    final preferences = ValueNotifier(const BackgroundPreferences());
    addTearDown(preferences.dispose);
    final store = _Store();
    var picks = 0;
    await tester.pumpWidget(_app(
        preferences: preferences,
        store: store,
        pick: () {
          picks++;
          return null;
        }));
    await tester.pumpAndSettle();
    expect(picks, 0);
    expect(store.imports, 0);
    expect(store.reads, 0);
    expect(
        tester
            .widget<SwitchListTile>(
                find.byKey(const ValueKey('background-motion')))
            .onChanged,
        isNull);
  });

  testWidgets(
      'cancelling the picker is not an error and does not launch a fallback picker',
      (tester) async {
    final preferences = ValueNotifier(const BackgroundPreferences());
    addTearDown(preferences.dispose);
    final store = _Store();
    var saves = 0;
    await tester.pumpWidget(_app(
        preferences: preferences,
        store: store,
        pick: () => null,
        save: () async {
          saves++;
        }));
    await _tap(tester, 'background-source-customImage');
    expect(preferences.value, const BackgroundPreferences());
    expect(store.imports, 0);
    expect(saves, 0);
    expect(
        find.byKey(const ValueKey('background-image-message')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid import preserves the previous source and saved identity',
      (tester) async {
    final preferences = ValueNotifier(const BackgroundPreferences());
    addTearDown(preferences.dispose);
    final store = _Store()..failure = const BackgroundImageException('图片损坏');
    var saves = 0;
    await tester.pumpWidget(_app(
        preferences: preferences,
        store: store,
        save: () async {
          saves++;
        }));
    await _tap(tester, 'background-pick-image');
    expect(preferences.value, const BackgroundPreferences());
    expect(saves, 0);
    expect(find.text('图片损坏'), findsOneWidget);
  });

  testWidgets(
      'successful import selects only the requested scene after validation',
      (tester) async {
    final preferences = ValueNotifier(const BackgroundPreferences());
    addTearDown(preferences.dispose);
    final store = _Store();
    var saves = 0;
    await tester.pumpWidget(_app(
        preferences: preferences,
        store: store,
        save: () async {
          saves++;
        }));
    await _tap(tester, 'background-scene-mini');
    await _tap(tester, 'background-pick-image');
    expect(preferences.value.main, const BackgroundPreferences().main);
    expect(
        preferences.value.nowPlaying, const BackgroundPreferences().nowPlaying);
    expect(preferences.value.mini.source, BackgroundSource.customImage);
    expect(preferences.value.mini.customImageId, _id);
    expect(preferences.value.mini.motion, isFalse);
    expect(saves, 1);
    expect(store.reads, 1);
    final motion = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('background-motion')));
    motion.onChanged!(true);
    await tester.pumpAndSettle();
    expect(preferences.value.mini.motion, isTrue);
    expect(store.reads, 1,
        reason: 'motion/veil changes do not reread the image');
  });

  testWidgets(
      'switching groups during an import does not apply it to the wrong scene',
      (tester) async {
    final preferences = ValueNotifier(const BackgroundPreferences());
    addTearDown(preferences.dispose);
    final pending = Completer<ManagedBackgroundImage>();
    final store = _Store()..pending = pending.future;
    await tester.pumpWidget(_app(preferences: preferences, store: store));
    await tester.tap(find.byKey(const ValueKey('background-pick-image')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('background-scene-mini')));
    await tester.pump();
    pending.complete(
        ManagedBackgroundImage(id: _id, name: 'a.png', width: 20, height: 20));
    await tester.pumpAndSettle();
    expect(preferences.value.main.customImageId, _id);
    expect(preferences.value.mini, const BackgroundPreferences().mini);
  });

  testWidgets('a later source choice invalidates a slow import',
      (tester) async {
    final preferences = ValueNotifier(const BackgroundPreferences());
    addTearDown(preferences.dispose);
    final pending = Completer<ManagedBackgroundImage>();
    final store = _Store()..pending = pending.future;
    await tester.pumpWidget(_app(preferences: preferences, store: store));
    await tester.tap(find.byKey(const ValueKey('background-pick-image')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('background-source-solid')));
    await tester.pump();
    pending.complete(
        ManagedBackgroundImage(id: _id, name: 'a.png', width: 20, height: 20));
    await tester.pumpAndSettle();
    expect(preferences.value.main.source, BackgroundSource.solid);
    expect(preferences.value.main.customImageId, isNull);
  });

  testWidgets('dispose while importing neither publishes state nor saves later',
      (tester) async {
    final preferences = ValueNotifier(const BackgroundPreferences());
    addTearDown(preferences.dispose);
    final pending = Completer<ManagedBackgroundImage>();
    final store = _Store()..pending = pending.future;
    var saves = 0;
    await tester.pumpWidget(_app(
        preferences: preferences,
        store: store,
        save: () async {
          saves++;
        }));
    await tester.tap(find.byKey(const ValueKey('background-pick-image')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(
        ManagedBackgroundImage(id: _id, name: 'a.png', width: 20, height: 20));
    await tester.pump();
    expect(preferences.value, const BackgroundPreferences());
    expect(saves, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failed settings save is visible; no automatic image cleanup runs',
      (tester) async {
    final preferences = ValueNotifier(const BackgroundPreferences());
    addTearDown(preferences.dispose);
    final store = _Store();
    await tester.pumpWidget(_app(
        preferences: preferences,
        store: store,
        save: () async => throw StateError('isolated save failure')));
    await _tap(tester, 'background-pick-image');
    expect(preferences.value.main.customImageId, _id);
    expect(find.byKey(const ValueKey('background-save-error')), findsOneWidget);
    expect(store.cleanups, 0);
  });

  testWidgets(
      'cleanup retains inactive scene references and clearing restores only its source',
      (tester) async {
    final image = BackgroundAppearance(
        source: BackgroundSource.customImage,
        customImageId: _id,
        customImageName: 'a.png');
    final preferences = ValueNotifier(BackgroundPreferences(
        main: image, mini: image.copyWith(source: BackgroundSource.desktop)));
    addTearDown(preferences.dispose);
    final store = _Store();
    await tester.pumpWidget(_app(preferences: preferences, store: store));
    await _tap(tester, 'background-clear-image');
    expect(preferences.value.main.customImageId, isNull);
    expect(preferences.value.main.source, BackgroundSource.desktop);
    await _tap(tester, 'background-clean-images');
    expect(store.retained, {_id});
    expect(preferences.value.mini.customImageId, _id);
  });

  testWidgets('custom image controls remain readable at 320px and 200% text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = ValueNotifier(BackgroundPreferences(
        main: BackgroundAppearance(
            source: BackgroundSource.customImage,
            customImageId: _id,
            customImageName: '很长的背景图片名称.png')));
    addTearDown(preferences.dispose);
    await tester
        .pumpWidget(_app(preferences: preferences, store: _Store(), scale: 2));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('background-motion')));
    expect(tester.takeException(), isNull);
    expect(find.text('轻缓动态背景'), findsOneWidget);
  });
}
