import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_checkbox_menu_button.dart';
import 'package:dan_player/lyric/japanese_reading_preferences.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_reading_tools.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/settings_page/lyric_experience_settings.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:desktop_lyric/component/lyric_letter_spacing_control.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'lyric_letter_spacing_render_test.dart' show loadLetterSpacingFonts;
import 'support/playlist_feature_fixture.dart';

const _slider = ValueKey('fixture-spacing-slider');

Widget _control(ValueNotifier<double> value, List<double> commits,
        {ValueNotifier<bool>? hidden, bool ticker = true}) =>
    playlistFeatureHost(Center(
        child: SizedBox(
            width: 320,
            child: TickerMode(
                enabled: ticker,
                child: ValueListenableBuilder(
                    valueListenable: value,
                    builder: (_, current, __) => LyricLetterSpacingControl(
                        id: 'fixture-spacing',
                        value: current,
                        hidden: hidden,
                        onChanged: (next) {
                          commits.add(next);
                          value.value = next;
                        }))))));

void _semanticChange(
    WidgetTester tester, Finder finder, SemanticsAction action) {
  SemanticsNode? target;
  void visit(SemanticsNode node) {
    if (node.getSemanticsData().hasAction(action)) {
      target = node;
      return;
    }
    node.visitChildren((child) {
      visit(child);
      return target == null;
    });
  }

  visit(tester.getSemantics(finder));
  expect(target, isNotNull, reason: 'Use the real Slider adjustment action');
  target!.owner!.performAction(target!.id, action);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadLetterSpacingFonts();
    await loadPlaylistFeatureFonts();
  });

  testWidgets('spacing thumb draft shapes and saves only at release',
      (tester) async {
    final value = ValueNotifier(6.0);
    addTearDown(value.dispose);
    final commits = <double>[];
    await tester.pumpWidget(_control(value, commits));
    final gesture =
        await tester.startGesture(tester.getCenter(find.byKey(_slider)));
    await gesture.moveBy(const Offset(64, 0));
    await tester.pump();
    expect(tester.widget<Slider>(find.byKey(_slider)).value, greaterThan(6));
    expect(value.value, 6);
    expect(commits, isEmpty);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(commits, hasLength(1));
    expect(value.value, commits.single);
    await tester.tap(find.byKey(const ValueKey('fixture-spacing-reset')));
    await tester.pumpAndSettle();
    expect(value.value, 0);
    expect(commits, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
      'secondary semantic cycle cannot commit the spacing pointer draft',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final value = ValueNotifier(6.0);
      addTearDown(value.dispose);
      final commits = <double>[];
      await tester.pumpWidget(_control(value, commits));
      final finder = find.byKey(_slider);
      final gesture = await tester.startGesture(tester.getCenter(finder));
      await gesture.moveBy(const Offset(48, 0));
      await tester.pump();
      final draft = tester.widget<Slider>(finder).value;
      expect(draft, greaterThan(6));
      _semanticChange(tester, finder, SemanticsAction.increase);
      await tester.pump();
      expect(value.value, 6);
      expect(commits, isEmpty);
      expect(tester.widget<Slider>(finder).value, draft);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(commits, [draft]);
      _semanticChange(tester, finder, SemanticsAction.decrease);
      await tester.pumpAndSettle();
      expect(commits, hasLength(2));
      expect(value.value, lessThan(draft));
    } finally {
      semantics.dispose();
    }
  });

  for (final cancel in ['hidden', 'ticker', 'pointer', 'external']) {
    testWidgets(
        'spacing $cancel interruption discards draft and permits a fresh touch',
        (tester) async {
      final value = ValueNotifier(6.0), hidden = ValueNotifier(false);
      addTearDown(value.dispose);
      addTearDown(hidden.dispose);
      final commits = <double>[];
      await tester.pumpWidget(_control(value, commits, hidden: hidden));
      final gesture =
          await tester.startGesture(tester.getCenter(find.byKey(_slider)));
      await gesture.moveBy(const Offset(48, 0));
      await tester.pump();
      switch (cancel) {
        case 'hidden':
          hidden.value = true;
        case 'ticker':
          await tester.pumpWidget(
              _control(value, commits, hidden: hidden, ticker: false));
        case 'pointer':
          await gesture.cancel();
        case 'external':
          value.value = 2;
      }
      await tester.pump();
      if (cancel != 'pointer') await gesture.up();
      await tester.pumpAndSettle();
      expect(commits, isEmpty);
      expect(value.value, cancel == 'external' ? 2 : 6);
      hidden.value = false;
      value.value = 6;
      await tester.pumpWidget(_control(value, commits, hidden: hidden));
      await tester.pumpAndSettle();
      final fresh =
          await tester.startGesture(tester.getCenter(find.byKey(_slider)));
      await fresh.moveBy(const Offset(-48, 0));
      await fresh.up();
      await tester.pumpAndSettle();
      expect(commits, hasLength(1));
      expect(value.value, lessThan(6));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'spacing settings persist one shared value and retry a failed write',
      (tester) async {
    final appearance = ValueNotifier(
        DesktopLyricAppearance.defaults.copyWith(lyricLetterSpacing: 6));
    final readings = ValueNotifier(const JapaneseReadingPreferences());
    final experience = ValueNotifier(const PlayerExperiencePreferences());
    addTearDown(appearance.dispose);
    addTearDown(readings.dispose);
    addTearDown(experience.dispose);
    var writes = 0;
    final initiallyInitialized = PlayService.isInitialized;
    await tester.pumpWidget(playlistFeatureHost(SingleChildScrollView(
        child: LyricExperienceSettings(
            appearance: appearance,
            japaneseReadings: readings,
            preferences: experience,
            persist: () async {
              writes++;
              if (writes == 1) throw StateError('fixture write failed');
            }))));
    await tester.pumpAndSettle();
    expect(writes, 0);
    final slider =
        find.byKey(const ValueKey('settings-lyric-letter-spacing-slider'));
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(64, 0));
    await tester.pump();
    expect(writes, 0);
    expect(appearance.value.lyricLetterSpacing, 6);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(appearance.value.lyricLetterSpacing, greaterThan(6));
    final retry = find.byKey(const ValueKey('lyric-experience-retry'));
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(writes, 2);
    expect(retry, findsNothing);
    expect(PlayService.isInitialized, initiallyInitialized);
  });

  for (final language in UiLanguage.values) {
    for (final width in [1000.0, 360.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
            'spacing and Japanese settings ${language.code} width=$width scale=$scale remain complete and reachable',
            (tester) async {
          sizePlaylistFeature(tester, width: width, height: 850);
          final previous = uiLanguage.value;
          uiLanguage.value = language;
          addTearDown(() => uiLanguage.value = previous);
          final appearance = ValueNotifier(DesktopLyricAppearance.defaults);
          final readings = ValueNotifier(const JapaneseReadingPreferences());
          final experience = ValueNotifier(const PlayerExperiencePreferences());
          addTearDown(appearance.dispose);
          addTearDown(readings.dispose);
          addTearDown(experience.dispose);
          var writes = 0;
          final boundary = GlobalKey();
          await tester.pumpWidget(playlistFeatureHost(
              AppFontScope(
                  policy: AppFontPolicy.defaults(language: language),
                  child: UiLanguageScope(
                      child: SingleChildScrollView(
                          child: LyricExperienceSettings(
                              appearance: appearance,
                              japaneseReadings: readings,
                              preferences: experience,
                              persist: () async {
                                writes++;
                              })))),
              boundary: boundary,
              textScale: scale));
          await tester.pumpAndSettle();
          final reset =
              find.byKey(const ValueKey('settings-lyric-letter-spacing-reset'));
          await tester.ensureVisible(reset);
          await tester.pumpAndSettle();
          expect(tester.getRect(reset).left, greaterThanOrEqualTo(0));
          expect(tester.getRect(reset).right, lessThanOrEqualTo(width));
          expect(find.text(ui('歌词字间距')), findsOneWidget);
          await capturePlaylistFeature(tester, boundary,
              'lyric-spacing-${language.code}-${width.toInt()}-${scale.toInt()}');
          final japanese =
              find.byKey(const ValueKey('japanese-reading-auto-switch'));
          await tester.ensureVisible(japanese);
          await tester.pumpAndSettle();
          final tile = tester.widget<SwitchListTile>(japanese);
          expect((tile.title as Text).data, ui('自动生成日语假名'));
          final renderedSubtitle = tester.widget<Text>(find.descendant(
              of: find.byWidget(tile.subtitle!), matching: find.byType(Text)));
          expect(renderedSubtitle.data,
              ui('优先显示已缓存的假名；未缓存时，自动联网开启则优先联网并在失败时回退离线，关闭则使用离线字典。保留已有注音和原歌词。'));
          final rect = tester.getRect(japanese);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
          expect(rect.height, greaterThanOrEqualTo(48));
          await capturePlaylistFeature(tester, boundary,
              'japanese-reading-${language.code}-${width.toInt()}-${scale.toInt()}');
          await tester.tap(japanese);
          await tester.pumpAndSettle();
          expect(readings.value.enabled, isTrue);
          expect(appearance.value.lyricLetterSpacing, 0);
          expect(writes, 1);
          await tester.pumpWidget(const SizedBox.shrink());
          expect(tester.takeException(), isNull);
          expect(tester.binding.transientCallbackCount, 0);
        });
      }
    }
  }

  testWidgets(
      'real font menu reaches spacing and commits without changing either font size',
      (tester) async {
    sizePlaylistFeature(tester, width: 360, height: 600);
    final appearance = ValueNotifier(
        DesktopLyricAppearance.defaults.copyWith(lyricLetterSpacing: 6));
    var writes = 0;
    final controller = LyricViewController(
        preferences: NowPlayingPagePreference.fromMap({}),
        appearance: appearance,
        persistAppearance: () async {
          writes++;
        });
    addTearDown(controller.dispose);
    addTearDown(appearance.dispose);
    final primary = controller.lyricFontSize,
        translation = controller.translationFontSize;
    await tester.pumpWidget(playlistFeatureHost(ChangeNotifierProvider.value(
        value: controller,
        child: const Align(
            alignment: Alignment.centerRight, child: LyricFontSizeMenu()))));
    await tester.tap(find.byKey(const ValueKey('lyric-font-size-open')));
    await tester.pumpAndSettle();
    final slider =
        find.byKey(const ValueKey('lyric-font-letter-spacing-slider'));
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    expect(tester.getRect(slider).right, lessThanOrEqualTo(360));
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(-48, 0));
    await tester.pump();
    expect(writes, 0);
    expect(controller.lyricLetterSpacing, 6);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(controller.lyricLetterSpacing, lessThan(6));
    expect(controller.lyricFontSize, primary);
    expect(controller.translationFontSize, translation);
    final focus = tester.widget<FocusableActionDetector>(find
        .descendant(of: slider, matching: find.byType(FocusableActionDetector))
        .first);
    focus.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape,
        physicalKey: PhysicalKeyboardKey.escape);
    // Closing leaves a finite scrollbar fade before the mounted menu is idle.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(slider, findsNothing,
        reason: 'Escape actually closes the font menu');
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
      'Japanese display menu uses the current navigator and can hide while busy',
      (tester) async {
    final appearance = ValueNotifier(DesktopLyricAppearance.defaults);
    final controller = LyricViewController(
        preferences: NowPlayingPagePreference.fromMap({}),
        appearance: appearance);
    final busy = ValueNotifier(false);
    controller.toggleJapaneseReading();
    addTearDown(controller.dispose);
    addTearDown(appearance.dispose);
    addTearDown(busy.dispose);
    final future = Future.value(PlainLyric('夜空を読む'));
    var requests = 0, changes = 0;
    NavigatorState? navigator;
    await tester.pumpWidget(playlistFeatureHost(LyricReadingMenu(
        controller: controller,
        readLyric: () => future,
        japaneseReadingsBusy: busy,
        onToggleJapaneseReading: (owner) async {
          changes++;
          navigator = owner;
          controller.toggleJapaneseReading();
          if (controller.showJapaneseReading) {
            requests++;
            busy.value = true;
          }
        })));
    final opener = find.byKey(const ValueKey('lyric-reading-tools'));
    await tester.tap(opener);
    await tester.pumpAndSettle();
    final action = find.byKey(const ValueKey('lyric-show-japanese-reading'));
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    expect(tester.widget<AppCheckboxMenuButton>(action).onChanged, isNotNull);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(changes, 1);
    expect(controller.showJapaneseReading, isTrue);
    expect(navigator!.mounted, isTrue);
    await tester.tap(opener);
    await tester.pumpAndSettle();
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    expect(tester.widget<AppCheckboxMenuButton>(action).onChanged, isNotNull);
    expect(find.text(ui('显示日语假名')), findsOneWidget);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(changes, 2);
    expect(requests, 1, reason: 'Hiding cannot start a second generation.');
    expect(controller.showJapaneseReading, isFalse);
    expect(busy.value, isTrue);
    busy.value = false;
    await tester.tap(opener);
    await tester.pumpAndSettle();
    expect(tester.widget<AppCheckboxMenuButton>(action).onChanged, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape,
        physicalKey: PhysicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final language in UiLanguage.values) {
    testWidgets(
        'font spacing popup ${language.code} at 360px 200 percent preserves complete labels and prior controls',
        (tester) async {
      sizePlaylistFeature(tester, width: 360, height: 600);
      final previous = uiLanguage.value;
      uiLanguage.value = language;
      addTearDown(() => uiLanguage.value = previous);
      final appearance = ValueNotifier(DesktopLyricAppearance.defaults);
      final controller = LyricViewController(
          preferences: NowPlayingPagePreference.fromMap({}),
          appearance: appearance,
          persistAppearance: () async {});
      addTearDown(controller.dispose);
      addTearDown(appearance.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(playlistFeatureHost(
          AppFontScope(
              policy: AppFontPolicy.defaults(language: language),
              child: ChangeNotifierProvider.value(
                  value: controller,
                  child: const Align(
                      alignment: Alignment.centerRight,
                      child: LyricFontSizeMenu()))),
          boundary: boundary,
          textScale: 2));
      final opener = find.byKey(const ValueKey('lyric-font-size-open'));
      await tester.tap(opener);
      await tester.pumpAndSettle();
      final slider =
          find.byKey(const ValueKey('lyric-font-letter-spacing-slider'));
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      final reset =
          find.byKey(const ValueKey('lyric-font-letter-spacing-reset'));
      await tester.ensureVisible(reset);
      await tester.pumpAndSettle();
      for (final key in ['歌词字间距', '恢复默认字间距']) {
        final finder = find.text(ui(key));
        final text = tester.widget<Text>(finder);
        expect(text.maxLines, isNull);
        expect(text.overflow, isNot(TextOverflow.ellipsis));
        final paragraph = tester.renderObject<RenderParagraph>(finder);
        final boxes = paragraph.getBoxesForSelection(TextSelection(
            baseOffset: ui(key).length - 1, extentOffset: ui(key).length));
        expect(boxes, isNotEmpty,
            reason: 'The last translated glyph is laid out');
        final contentBounds = tester.getRect(
            find.ancestor(of: slider, matching: find.byType(Padding)).first);
        for (final box in boxes) {
          // Engine selection advances are quantized; observe the actual menu
          // paint boundary, rather than its fractional intrinsic text width.
          final left = paragraph.localToGlobal(Offset(box.left, box.top)).dx;
          final right = paragraph.localToGlobal(Offset(box.right, box.top)).dx;
          expect(left, greaterThanOrEqualTo(contentBounds.left));
          expect(right, lessThanOrEqualTo(contentBounds.right));
        }
      }
      expect(tester.getRect(reset).right, lessThanOrEqualTo(360));
      await capturePlaylistFeature(
          tester, boundary, 'font-spacing-${language.code}-360-2');
      final exact = find.byKey(const ValueKey('lyric-font-size-exact'));
      await tester.ensureVisible(exact);
      await tester.pumpAndSettle();
      expect(exact.hitTestable(), findsOneWidget);
      final focus = tester.widget<FocusableActionDetector>(find
          .descendant(
              of: slider, matching: find.byType(FocusableActionDetector))
          .first);
      focus.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape,
          physicalKey: PhysicalKeyboardKey.escape);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(slider, findsNothing);
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    });
  }
}
