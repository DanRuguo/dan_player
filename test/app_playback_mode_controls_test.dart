import 'package:dan_player/component/app_playback_mode_controls.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'support/playback_mode_fixture.dart';

Widget host(PlaybackModeFixture service,
        {Brightness brightness = Brightness.light,
        double scale = 1,
        bool secondPlain = false}) =>
    MaterialApp(
      theme: ThemeData(
          useMaterial3: true,
          visualDensity: VisualDensity.compact,
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.orange, brightness: brightness)),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale), disableAnimations: true),
          child: UiLanguageScope(child: child!)),
      home: Scaffold(
          body: Column(children: [
        AppPlaybackModeControls(playbackService: service),
        AppPlaybackModeControls(playbackService: service, plain: secondPlain),
      ])),
    );

Finder button(String name) => find.byKey(ValueKey('playback-mode-$name'));

void main() {
  testWidgets(
      'joined and lyric views share shuffle and all three repeat states',
      (tester) async {
    final service = PlaybackModeFixture();
    addTearDown(service.dispose);
    await tester.pumpWidget(host(service, secondPlain: true));
    await tester.tap(button('shuffle').first);
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<IconButton>(button('shuffle'))
            .every((item) => item.isSelected == true),
        isTrue);
    for (final mode in [PlayMode.loop, PlayMode.singleLoop, PlayMode.forward]) {
      await tester.tap(button('repeat').last);
      await tester.pumpAndSettle();
      expect(service.playMode.value, mode);
      expect(service.shuffle.value, isTrue);
      final repeats = tester.widgetList<IconButton>(button('repeat')).toList();
      for (final repeat in repeats) {
        expect(repeat.isSelected, mode != PlayMode.forward);
      }
      expect((repeats.first.icon as Icon).icon,
          mode == PlayMode.singleLoop ? Symbols.repeat_one : Symbols.repeat);
      expect(
          (repeats.last.icon as Icon).icon,
          switch (mode) {
            PlayMode.forward => Symbols.repeat,
            PlayMode.loop => Symbols.repeat_on,
            PlayMode.singleLoop => Symbols.repeat_one_on,
          });
    }
    service.setPlayMode(PlayMode.singleLoop);
    await tester.tap(button('shuffle').last);
    await tester.pumpAndSettle();
    expect(service.shuffle.value, isFalse);
    expect(service.playMode.value, PlayMode.singleLoop);
    expect(service.calls, [
      'shuffle:true',
      'repeat:loop',
      'repeat:singleLoop',
      'repeat:forward',
      'repeat:singleLoop',
      'shuffle:false'
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'lyrics stay transparent with separate hit areas and state glyphs',
      (tester) async {
    final service = PlaybackModeFixture();
    addTearDown(service.dispose);
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
          host(service, brightness: brightness, scale: 3, secondPlain: true));
      for (final active in [false, true]) {
        service.shuffle.value = active;
        service.playMode.value = active ? PlayMode.loop : PlayMode.forward;
        await tester.pumpAndSettle();
        final plain = find.byType(AppPlaybackModeControls).last;
        expect(tester.getSize(plain), const Size(96, 44));
        expect(find.descendant(of: plain, matching: find.byType(ClipRRect)),
            findsNothing);
        final shuffle = tester.widget<IconButton>(button('shuffle').last);
        final repeat = tester.widget<IconButton>(button('repeat').last);
        expect((shuffle.icon as Icon).icon,
            active ? Symbols.shuffle_on : Symbols.shuffle);
        expect((repeat.icon as Icon).icon,
            active ? Symbols.repeat_on : Symbols.repeat);
        final scheme = Theme.of(tester.element(plain)).colorScheme;
        for (final control in [shuffle, repeat]) {
          expect(tester.getSize(find.byWidget(control)), const Size(44, 44));
          for (final states in [
            <WidgetState>{},
            {WidgetState.selected}
          ]) {
            expect(control.style!.backgroundColor!.resolve(states),
                Colors.transparent);
            expect(control.style!.side!.resolve(states), BorderSide.none);
            expect(control.style!.foregroundColor!.resolve(states),
                scheme.primary);
          }
        }
        expect(
            tester.getRect(button('repeat').last).left -
                tester.getRect(button('shuffle').last).right,
            8);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('passive waiting view does not construct a native player',
      (tester) async {
    expect(PlayService.playbackReady.value, isFalse);
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AppPlaybackModeControls())));
    expect(PlayService.playbackReady.value, isFalse);
    expect(tester.widget<IconButton>(button('shuffle')).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'narrow English large-text controls keep theme colors and hit areas',
      (tester) async {
    tester.view.physicalSize = const Size(160, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previousLanguage = uiLanguage.value;
    uiLanguage.value = UiLanguage.en;
    addTearDown(() => uiLanguage.value = previousLanguage);
    final service = PlaybackModeFixture();
    addTearDown(service.dispose);
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(host(service, brightness: brightness, scale: 3));
      await tester.pumpAndSettle();
      final context = tester.element(button('shuffle').first);
      final scheme = Theme.of(context).colorScheme;
      final height = appToolbarControlHeight(context);
      for (final element in find.byType(IconButton).evaluate()) {
        final control = element.widget as IconButton;
        expect(tester.getSize(find.byWidget(control)), Size(44, height));
        expect(control.tooltip, isNotEmpty);
        expect(control.style!.foregroundColor!.resolve({}), scheme.primary);
        expect(control.style!.backgroundColor!.resolve({WidgetState.selected}),
            scheme.primaryContainer);
      }
      expect(
          tester.getSize(find.byType(AppPlaybackModeControls).first).width, 89);
      expect(tester.takeException(), isNull);
    }
  });
}
