import 'package:dan_player/app_preference.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Fixture {
  _Fixture() {
    addTearDown(disposeSettings);
    addTearDown(hidden.dispose);
    addTearDown(ticker.dispose);
    addTearDown(shown.dispose);
    addTearDown(source.dispose);
  }

  final settings =
      LyricViewController(preferences: NowPlayingPagePreference.fromMap({}))
        ..setFontSize(39);
  final hidden = ValueNotifier(false);
  final ticker = ValueNotifier(true);
  final shown = ValueNotifier(true);
  late final source = ValueNotifier(settings);
  ValueNotifier<bool>? replacementHidden;
  bool _settingsDisposed = false;

  void disposeSettings() {
    if (_settingsDisposed) return;
    _settingsDisposed = true;
    settings.dispose();
  }

  Widget app() => MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: source,
            builder: (_, controller, __) => ChangeNotifierProvider.value(
              value: controller,
              child: ValueListenableBuilder(
                valueListenable: shown,
                builder: (_, visible, __) => ValueListenableBuilder(
                  valueListenable: ticker,
                  builder: (_, enabled, __) => TickerMode(
                    enabled: enabled,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: visible
                          ? LyricFontSizeMenu(
                              hidden: replacementHidden ?? hidden)
                          : const SizedBox(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const ValueKey('lyric-font-size-open')));
    await tester.pumpAndSettle();
  }

  Future<TestGesture> drag(WidgetTester tester, {int pointer = 90}) async {
    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('lyric-font-size-slider'))),
        pointer: pointer);
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(source.value.fontDragPreviewSize,
        greaterThan(source.value.lyricFontSize));
    expect(source.value.fontSizeAdjusting, isTrue);
    return gesture;
  }
}

void _expectDiscarded(LyricViewController controller, {double size = 39}) {
  expect(controller.fontDragPreviewSize, isNull);
  expect(controller.fontSizeAdjusting, isFalse);
  expect(controller.lyricFontSize, size);
  expect(controller.nowPlayingPagePref.lyricFontSize, size);
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  for (final lifecycle in [
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  ]) {
    testWidgets('font drag is discarded immediately at $lifecycle',
        (tester) async {
      final fixture = _Fixture();
      await fixture.open(tester);
      final gesture = await fixture.drag(tester);
      tester.binding.handleAppLifecycleStateChanged(lifecycle);
      _expectDiscarded(fixture.settings);
      // A hidden HWND may not paint again before an old release arrives.
      await gesture.up();
      _expectDiscarded(fixture.settings);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Slider>(
                  find.byKey(const ValueKey('lyric-font-size-slider')))
              .value,
          39);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('native hidden notification releases a draft without a frame',
      (tester) async {
    final fixture = _Fixture();
    await fixture.open(tester);
    final gesture = await fixture.drag(tester);
    fixture.hidden.value = true;
    _expectDiscarded(fixture.settings);
    await gesture.up();
    fixture.hidden.value = false;
    await tester.pumpAndSettle();
    _expectDiscarded(fixture.settings);
    final next = await fixture.drag(tester, pointer: 91);
    final value = fixture.settings.fontDragPreviewSize;
    await next.up();
    await tester.pumpAndSettle();
    expect(fixture.settings.lyricFontSize, value);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('inactive remains visible and retains an unfinished font drag',
      (tester) async {
    final fixture = _Fixture();
    await fixture.open(tester);
    final gesture = await fixture.drag(tester);
    final value = fixture.settings.fontDragPreviewSize;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(fixture.settings.fontDragPreviewSize, value);
    expect(fixture.settings.fontSizeAdjusting, isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fixture.settings.lyricFontSize, value);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disabling the anchor ticker revokes its overlay font draft',
      (tester) async {
    final fixture = _Fixture();
    await fixture.open(tester);
    final gesture = await fixture.drag(tester);
    fixture.ticker.value = false;
    await tester.pump();
    _expectDiscarded(fixture.settings);
    await gesture.up();
    fixture.ticker.value = true;
    await tester.pumpAndSettle();
    _expectDiscarded(fixture.settings);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('removing an open anchor discards its unpublished font preview',
      (tester) async {
    final fixture = _Fixture();
    await fixture.open(tester);
    final gesture = await fixture.drag(tester);
    fixture.shown.value = false;
    await tester.pump();
    _expectDiscarded(fixture.settings);
    await gesture.up();
    fixture.shown.value = true;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lyric-font-size-open')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Slider>(
                find.byKey(const ValueKey('lyric-font-size-slider')))
            .value,
        39);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a replaced hidden dependency cannot cancel the next font drag',
      (tester) async {
    final fixture = _Fixture();
    await fixture.open(tester);
    final replacement = ValueNotifier(false);
    addTearDown(replacement.dispose);
    fixture.replacementHidden = replacement;
    await tester.pumpWidget(fixture.app());
    final gesture = await fixture.drag(tester);
    final value = fixture.settings.fontDragPreviewSize;
    fixture.hidden.value = true;
    expect(fixture.settings.fontDragPreviewSize, value);
    replacement.value = true;
    _expectDiscarded(fixture.settings);
    await gesture.up();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a released old slider cannot modify a replacement controller',
      (tester) async {
    final fixture = _Fixture();
    await fixture.open(tester);
    final gesture = await fixture.drag(tester);
    final replacement =
        LyricViewController(preferences: NowPlayingPagePreference.fromMap({}))
          ..setFontSize(22);
    addTearDown(replacement.dispose);
    fixture.source.value = replacement;
    await tester.pump();
    _expectDiscarded(fixture.settings);
    replacement.setFontSizeAdjusting(true);
    replacement.setFontDragPreview(52);
    await gesture.up();
    expect(replacement.lyricFontSize, 22);
    expect(replacement.fontDragPreviewSize, 52,
        reason: 'The released old pointer owns neither this value nor draft');
    expect(replacement.fontSizeAdjusting, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a pointer held before hiding cannot start a later font draft',
      (tester) async {
    final fixture = _Fixture();
    await fixture.open(tester);
    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('lyric-font-size-slider'))),
        pointer: 90);
    fixture.hidden.value = true;
    fixture.hidden.value = false;
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    _expectDiscarded(fixture.settings);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pending font cancellation cannot notify a disposed owner',
      (tester) async {
    final fixture = _Fixture();
    await fixture.open(tester);
    final gesture = await fixture.drag(tester);
    fixture.hidden.value = true;
    _expectDiscarded(fixture.settings);
    fixture.disposeSettings();
    await tester.pumpWidget(const SizedBox());
    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
