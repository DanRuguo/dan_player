import 'dart:convert';

import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/page/settings_page/custom_music_source_settings.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {double scale = 1}) => MaterialApp(
      theme: ThemeData(
        platform: TargetPlatform.windows,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [child],
        ),
      ),
    );

CustomMusicSourceProfile _profile(String id, String name, String url) =>
    CustomMusicSourceProfile.tryCreate(
      id: id,
      name: name,
      baseUrl: url,
      capabilities: const {
        CustomMusicSourceCapability.search,
        CustomMusicSourceCapability.lyrics,
      },
      endpoints: {
        CustomMusicSourceCapability.search: url,
        CustomMusicSourceCapability.lyrics: url,
      },
    )!;

Future<void> _openAdd(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('custom-source-add')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('custom-source-add')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('adding a second source never overwrites the first',
      (tester) async {
    final first = _profile('first', 'First source', 'https://one.example/api');
    final profiles = ValueNotifier<List<CustomMusicSourceProfile>>([first]);
    addTearDown(profiles.dispose);
    var saves = 0;
    await tester.pumpWidget(_host(CustomMusicSourceSettings(
      profiles: profiles,
      persist: () async => saves++,
    )));

    await _openAdd(tester);
    await tester.enterText(
        find.byKey(const ValueKey('custom-source-name')), 'Second source');
    await tester.enterText(find.byKey(const ValueKey('custom-source-url')),
        'https://two.example/api');
    await tester.tap(find.byKey(const ValueKey('custom-source-save')));
    await tester.pumpAndSettle();

    expect(profiles.value, hasLength(2));
    expect(profiles.value.first, first);
    expect(profiles.value.last.name, 'Second source');
    for (final capability in profiles.value.last.capabilities) {
      expect(profiles.value.last.endpointFor(capability)?.toString(),
          'https://two.example/api');
    }
    expect(saves, 1);
    expect(find.text('First source'), findsOneWidget);
    expect(find.text('Second source'), findsOneWidget);
  });

  testWidgets('profiles can be disabled and deleted independently',
      (tester) async {
    final profiles = ValueNotifier<List<CustomMusicSourceProfile>>([
      _profile('first', 'First source', 'https://one.example/api'),
      _profile('second', 'Second source', 'https://two.example/api'),
    ]);
    addTearDown(profiles.dispose);
    await tester.pumpWidget(_host(CustomMusicSourceSettings(
      profiles: profiles,
      persist: () async {},
    )));

    final firstSwitch =
        find.byKey(const ValueKey('custom-source-enabled-first'));
    await tester.ensureVisible(firstSwitch);
    await tester.tap(firstSwitch);
    await tester.pumpAndSettle();
    expect(profiles.value.first.enabled, isFalse);
    expect(profiles.value.last.enabled, isTrue);

    final deleteFirst =
        find.byKey(const ValueKey('custom-source-delete-first'));
    await tester.ensureVisible(deleteFirst);
    await tester.tap(deleteFirst);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(profiles.value.map((item) => item.id), ['second']);
    expect(find.text('Second source'), findsOneWidget);
  });

  testWidgets('legacy lyric profile remains visible and clearly constrained',
      (tester) async {
    final legacy = CustomMusicSourceProfile.legacyLyric(
        'https://lyrics.example/api/lyrics')!;
    final profiles = ValueNotifier<List<CustomMusicSourceProfile>>([legacy]);
    addTearDown(profiles.dispose);
    await tester.pumpWidget(_host(CustomMusicSourceSettings(
      profiles: profiles,
      persist: () async {},
    )));

    expect(find.text('Legacy lyric API'), findsNothing);
    expect(find.text('旧版歌词 API'), findsOneWidget);
    expect(find.textContaining('旧版歌词 API'), findsNWidgets(2));
    expect(find.text('歌词'), findsOneWidget);
    expect(find.text('搜索'), findsNothing);
  });

  testWidgets('old lyric backup imports every usable endpoint and merges',
      (tester) async {
    final existing =
        _profile('existing', 'Existing source', 'https://existing.example/api');
    final profiles = ValueNotifier<List<CustomMusicSourceProfile>>([existing]);
    addTearDown(profiles.dispose);
    final backup = jsonEncode({
      'currentLyricApiUrl': 'https://current.example/lyrics',
      'apis': [
        {
          'type': 'lyric',
          'name': 'Mirror one',
          'url': 'https://mirror-one.example/lyrics',
        },
        {
          'type': 'lyric',
          'name': 'Mirror two',
          'url': 'https://mirror-two.example/lyrics',
        },
      ],
    });
    await tester.pumpWidget(_host(CustomMusicSourceSettings(
      profiles: profiles,
      persist: () async {},
      importReader: () async => backup,
    )));

    final import = find.byKey(const ValueKey('custom-source-import'));
    await tester.ensureVisible(import);
    await tester.tap(import);
    await tester.pumpAndSettle();
    expect(profiles.value, hasLength(4));
    expect(profiles.value.first, existing);
    expect(profiles.value.map((item) => item.name),
        containsAll(['Legacy lyric API', 'Mirror one', 'Mirror two']));
  });

  testWidgets('matching IDs can merge and update without dropping new items',
      (tester) async {
    final original =
        _profile('same', 'Original name', 'https://old.example/api');
    final replacement =
        _profile('same', 'Updated name', 'https://new.example/api');
    final added = _profile('new', 'New source', 'https://added.example/api');
    final profiles = ValueNotifier<List<CustomMusicSourceProfile>>([original]);
    addTearDown(profiles.dispose);
    final backup = jsonEncode(
        CustomMusicSourceProfileCodec.encodeBackup([replacement, added]));
    await tester.pumpWidget(_host(CustomMusicSourceSettings(
      profiles: profiles,
      persist: () async {},
      importReader: () async => backup,
    )));

    await tester.tap(find.byKey(const ValueKey('custom-source-import')));
    await tester.pumpAndSettle();
    expect(find.text('仅添加新项'), findsOneWidget);
    expect(find.text('合并并更新'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '合并并更新'));
    await tester.pumpAndSettle();
    expect(profiles.value.map((item) => item.name),
        ['Updated name', 'New source']);
  });

  testWidgets('search owns track details and cover capabilities',
      (tester) async {
    final profiles = ValueNotifier<List<CustomMusicSourceProfile>>([]);
    addTearDown(profiles.dispose);
    await tester.pumpWidget(_host(CustomMusicSourceSettings(
      profiles: profiles,
      persist: () async {},
    )));
    await _openAdd(tester);

    Finder chip(String id) => find.byKey(ValueKey('custom-capability-$id'));
    await tester.tap(chip('search'));
    await tester.pump();
    expect(tester.widget<FilterChip>(chip('search')).selected, isFalse);
    expect(tester.widget<FilterChip>(chip('metadata')).selected, isFalse);
    expect(tester.widget<FilterChip>(chip('cover')).selected, isFalse);

    await tester.tap(chip('cover'));
    await tester.pump();
    expect(tester.widget<FilterChip>(chip('cover')).selected, isTrue);
    expect(tester.widget<FilterChip>(chip('search')).selected, isTrue);
  });

  for (final language in UiLanguage.values) {
    testWidgets('${language.code} narrow window at 200% keeps editor usable',
        (tester) async {
      final previous = uiLanguage.value;
      uiLanguage.value = language;
      addTearDown(() => uiLanguage.value = previous);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 560);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final profiles = ValueNotifier<List<CustomMusicSourceProfile>>([
        _profile('first', 'A source with a deliberately long display name',
            'https://a-very-long-domain-name.example/api'),
      ]);
      addTearDown(profiles.dispose);
      await tester.pumpWidget(_host(
        CustomMusicSourceSettings(
          profiles: profiles,
          persist: () async {},
        ),
        scale: 2,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await _openAdd(tester);
      expect(find.byKey(const ValueKey('custom-source-name')), findsOneWidget);
      await tester.ensureVisible(
          find.byKey(const ValueKey('custom-capability-download')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
