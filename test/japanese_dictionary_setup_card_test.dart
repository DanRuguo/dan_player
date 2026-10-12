import 'package:dan_player/component/japanese_dictionary_setup_card.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/japanese_reading_ui_fixture.dart';

const _dialog = ValueKey('japanese-dictionary-dialog');
const _download = ValueKey('japanese-dictionary-download');
const _close = ValueKey('japanese-dictionary-close');
const _manual = ValueKey('japanese-dictionary-manual');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late UiLanguage previousLanguage;
  late UiDictionaryRuntime runtime;
  late List<UiDictionaryInstaller> installers;
  bool? result;
  setUpAll(setUpJapaneseUiFixture);
  tearDownAll(tearDownJapaneseUiFixture);
  setUp(() {
    previousLanguage = uiLanguage.value;
    runtime = UiDictionaryRuntime();
    installers = [];
    result = null;
  });
  tearDown(() => uiLanguage.value = previousLanguage);

  UiDictionaryInstaller factory(_) {
    final installer = UiDictionaryInstaller(runtime);
    installers.add(installer);
    return installer;
  }

  Widget launcher() => Builder(
      builder: (context) => TextButton(
          key: const ValueKey('open-dictionary'),
          onPressed: () async {
            result = await showJapaneseDictionarySetupDialog(context,
                runtime: runtime, installerFactory: factory);
          },
          child: const Text('Open fixture')));

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('open-dictionary')));
    await tester.pumpAndSettle();
    expect(find.byKey(_dialog), findsOneWidget);
  }

  for (final language in UiLanguage.values) {
    testWidgets(
        'Japanese dictionary ${language.code} narrow large text is complete',
        (tester) async {
      final boundary = GlobalKey();
      await mountJapaneseUi(tester, launcher(),
          language: language, width: 360, scale: 2, boundary: boundary);
      await open(tester);
      await captureJapaneseUi(
          tester, boundary, 'dictionary-${language.code}-360-2');
      await expectJapaneseUiText(tester, find.byKey(_dialog));
      expect(installers, isEmpty);
      expect(runtime.inspections, 0);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.ensureVisible(find.byKey(_close));
      await tester.tap(find.byKey(_close));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'Japanese dictionary verifies manual installation without download',
      (tester) async {
    await mountJapaneseUi(tester, launcher());
    await open(tester);
    expect(installers, isEmpty);
    expect(runtime.inspections, 0);
    await tester.tap(find.byKey(_manual));
    await tester.pumpAndSettle();
    expect(runtime.inspections, 1);
    expect(find.byKey(const ValueKey('japanese-dictionary-error')),
        findsOneWidget);
    expect(result, isNull);
    runtime.ready = true;
    await tester.tap(find.byKey(_manual));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(installers, isEmpty);
  });

  testWidgets(
      'Japanese dictionary explicit download reports progress and verifies',
      (tester) async {
    await mountJapaneseUi(tester, launcher());
    await open(tester);
    await tester.tap(find.byKey(_download));
    await tester.pump();
    expect(installers.single.starts, 1);
    installers.single.reportProgress!(.4);
    await tester.pump();
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        .4);
    expect(runtime.inspections, 0);
    runtime.ready = true;
    installers.single.completion.complete();
    await tester.pumpAndSettle();
    expect(runtime.inspections, 1);
    expect(result, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Japanese dictionary cancellation rejects late download and retries',
      (tester) async {
    await mountJapaneseUi(tester, launcher());
    await open(tester);
    await tester.tap(find.byKey(_download));
    await tester.pump();
    final previous = installers.single;
    await tester.tap(find.byKey(const ValueKey('japanese-dictionary-cancel')));
    await tester.pumpAndSettle();
    expect(previous.cancels, 1);
    runtime.ready = true;
    previous.reportProgress!(1);
    previous.completion.complete();
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(runtime.inspections, 0);
    expect(find.byKey(_dialog), findsOneWidget);
    await tester.tap(find.byKey(_download));
    await tester.pump();
    expect(installers, hasLength(2));
    installers.last.completion.complete();
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets(
      'Japanese dictionary reverse cancels before dispose and leaves new route',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await mountJapaneseUi(tester, launcher(),
        navigator: navigator, reduced: false);
    await open(tester);
    await tester.tap(find.byKey(_download));
    await tester.pump();
    final installer = installers.single;
    navigator.currentState!.pop();
    expect(installer.cancels, 1);
    runtime.ready = true;
    installer.reportProgress!(1);
    installer.completion.complete();
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('New page fixture'))));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(runtime.inspections, 0);
    expect(find.text('New page fixture'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Japanese dictionary failed download stays retryable and closes idle',
      (tester) async {
    await mountJapaneseUi(tester, launcher());
    await open(tester);
    await tester.tap(find.byKey(_download));
    await tester.pump();
    installers.single.completion.completeError(StateError('fixture failure'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('japanese-dictionary-error')),
        findsOneWidget);
    expect(result, isNull);
    expect(tester.widget<FilledButton>(find.byKey(_download)).onPressed,
        isNotNull);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.tap(find.byKey(_close));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Japanese dictionary late ready closes its own route below another popup',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await mountJapaneseUi(tester, launcher(), navigator: navigator);
    await open(tester);
    await tester.tap(find.byKey(_download));
    await tester.pump();
    navigator.currentState!.push(DialogRoute<void>(
        context: navigator.currentContext!,
        builder: (_) => const Dialog(child: Text('Other popup fixture'))));
    await tester.pumpAndSettle();
    runtime.ready = true;
    installers.single.completion.complete();
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.text('Other popup fixture'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(_dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
