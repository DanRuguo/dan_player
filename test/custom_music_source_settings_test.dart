import 'dart:async';
import 'dart:convert';

import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/online/custom_music_source_transport.dart';
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
      expect(
          profiles.value.last.endpointFor(capability)?.toString(),
          capability == CustomMusicSourceCapability.metadata ||
                  capability == CustomMusicSourceCapability.cover
              ? isNull
              : 'https://two.example/api');
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

  testWidgets('LRC API is a normal editable source without legacy labels',
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
    expect(find.text('旧版歌词 API'), findsNothing);
    expect(find.text('LRC API'), findsOneWidget);
    expect(find.text('歌词'), findsOneWidget);
    expect(find.text('搜索'), findsNothing);
    expect(find.byType(Chip), findsNothing);

    final edit = find.byKey(ValueKey('custom-source-edit-${legacy.id}'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    final protocol = find.byKey(const ValueKey('custom-source-protocol'));
    expect(
        tester
            .widget<DropdownButtonFormField<CustomMusicSourceProtocol>>(
                protocol)
            .onChanged,
        isNotNull);
    expect(find.byType(FilterChip), findsNothing,
        reason:
            'A single fixed lyric capability is descriptive, not a disabled button.');
    await tester.tap(protocol);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dan Player 通用 v1').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('custom-source-name')), 'My LRC service');
    await tester.tap(find.byKey(const ValueKey('custom-source-save')));
    await tester.pumpAndSettle();
    expect(profiles.value.single.id, legacy.id);
    expect(profiles.value.single.name, 'My LRC service');
    expect(
        profiles.value.single.protocol, CustomMusicSourceProtocol.danSourceV1);
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
        containsAll(['LRC API', 'Mirror one', 'Mirror two']));
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

  testWidgets('editing keeps imported per-capability endpoint routes',
      (tester) async {
    final profile = CustomMusicSourceProfile.tryCreate(
      id: 'advanced',
      name: 'Advanced source',
      baseUrl: 'https://service.example',
      capabilities: const {
        CustomMusicSourceCapability.search,
        CustomMusicSourceCapability.lyrics,
      },
      endpoints: const {
        CustomMusicSourceCapability.search: '/v1/search',
        CustomMusicSourceCapability.lyrics: '/v1/lyrics',
      },
    )!;
    final profiles = ValueNotifier<List<CustomMusicSourceProfile>>([profile]);
    addTearDown(profiles.dispose);
    await tester.pumpWidget(_host(CustomMusicSourceSettings(
      profiles: profiles,
      persist: () async {},
    )));

    final edit = find.byKey(const ValueKey('custom-source-edit-advanced'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('custom-source-name')), 'Renamed source');
    await tester.tap(find.byKey(const ValueKey('custom-source-save')));
    await tester.pumpAndSettle();

    expect(profiles.value.single.name, 'Renamed source');
    expect(profiles.value.single.endpoints, profile.endpoints);
  });

  testWidgets(
      'deleted presets can be added back without overwriting another source',
      (tester) async {
    final existing = _profile('user', 'LRC API', 'https://user.example/api');
    final profiles = ValueNotifier<List<CustomMusicSourceProfile>>([existing]);
    addTearDown(profiles.dispose);
    await tester.pumpWidget(_host(CustomMusicSourceSettings(
      profiles: profiles,
      persist: () async {},
    )));
    final addPreset = find.byKey(const ValueKey('custom-source-add-preset'));
    await tester.ensureVisible(addPreset);
    await tester.tap(addPreset);
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const ValueKey('custom-source-preset-legacy-lyric-api')));
    await tester.pumpAndSettle();
    expect(profiles.value, hasLength(2));
    expect(profiles.value.first, existing);
    expect(profiles.value.last, CustomMusicSourceProfile.lrcApiPreset());
  });

  testWidgets(
      'Kugou endpoints and capabilities are editable without dropping public configuration',
      (tester) async {
    final profile = CustomMusicSourceProfile.kugouPreset().copyWith(
      publicHeaders: const {'X-Client': 'test-client'},
    );
    final profiles = ValueNotifier<List<CustomMusicSourceProfile>>([profile]);
    addTearDown(profiles.dispose);
    await tester.pumpWidget(_host(CustomMusicSourceSettings(
      profiles: profiles,
      persist: () async {},
    )));
    final edit = find.byKey(const ValueKey('custom-source-edit-kugou'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    final download = find.byKey(const ValueKey('custom-capability-download'));
    await tester.ensureVisible(download);
    expect(tester.widget<FilterChip>(download).onSelected, isNotNull);
    await tester.tap(download);
    final endpoints = find.byKey(const ValueKey('custom-source-endpoints'));
    await tester.ensureVisible(endpoints);
    await tester.tap(find.text('独立接口地址（可选）'));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('custom-endpoint-search'));
    await tester.ensureVisible(search);
    await tester.enterText(search, '/search-custom');
    await tester.tap(find.byKey(const ValueKey('custom-source-save')));
    await tester.pumpAndSettle();
    expect(profiles.value.single.endpoints[CustomMusicSourceCapability.search],
        '/search-custom');
    expect(profiles.value.single.capabilities,
        isNot(contains(CustomMusicSourceCapability.download)));
    expect(profiles.value.single.publicHeaders, profile.publicHeaders);
  });

  testWidgets(
      'NetEase preset can be added disabled and configured in the editor',
      (tester) async {
    final profiles = ValueNotifier<List<CustomMusicSourceProfile>>([]);
    addTearDown(profiles.dispose);
    await tester.pumpWidget(_host(CustomMusicSourceSettings(
      profiles: profiles,
      persist: () async {},
    )));
    await tester.tap(find.byKey(const ValueKey('custom-source-add-preset')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('custom-source-preset-netease-api')));
    await tester.pumpAndSettle();
    expect(profiles.value.single.enabled, isFalse);
    final edit = find.byKey(const ValueKey('custom-source-edit-netease-api'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('custom-source-url')),
        'http://127.0.0.1:3333/');
    await tester.tap(find.byKey(const ValueKey('custom-source-save')));
    await tester.pumpAndSettle();
    expect(profiles.value.single.baseUrl, 'http://127.0.0.1:3333/');
    expect(
        profiles.value.single.protocol, CustomMusicSourceProtocol.neteaseApi);
    expect(
        profiles.value.single
            .endpointFor(CustomMusicSourceCapability.comments)!
            .path,
        '/comment/music');
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual probe is scoped to search and disables peer buttons',
      (tester) async {
    final profiles = ValueNotifier<List<CustomMusicSourceProfile>>([
      _profile('first', 'First source', 'https://one.example/api')
          .copyWith(enabled: false),
      _profile('second', 'Second source', 'https://two.example/api'),
    ]);
    addTearDown(profiles.dispose);
    final gate = Completer<void>();
    CustomMusicSourceProfile? probed;
    await tester.pumpWidget(_host(CustomMusicSourceSettings(
      profiles: profiles,
      persist: () async {},
      probe: (profile) async {
        probed = profile;
        await gate.future;
      },
    )));

    final first = find.byKey(const ValueKey('custom-source-test-first'));
    await tester.ensureVisible(first);
    await tester.tap(first);
    await tester.pump();
    expect(probed?.enabled, isTrue,
        reason: 'an explicit probe may test a disabled profile once');
    expect(
      tester
          .widget<TextButton>(
              find.byKey(const ValueKey('custom-source-test-second')))
          .onPressed,
      isNull,
    );

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('搜索接口连接正常；其他能力需使用实际歌曲验证'), findsOneWidget);
  });

  testWidgets('probe failures are translated instead of leaking Chinese',
      (tester) async {
    final previous = uiLanguage.value;
    uiLanguage.value = UiLanguage.en;
    addTearDown(() => uiLanguage.value = previous);
    final profiles = ValueNotifier<List<CustomMusicSourceProfile>>([
      _profile('first', 'First source', 'https://one.example/api'),
    ]);
    addTearDown(profiles.dispose);
    await tester.pumpWidget(_host(CustomMusicSourceSettings(
      profiles: profiles,
      persist: () async {},
      probe: (_) async => throw const CustomMusicSourceException(
        CustomMusicSourceFailureKind.timeout,
        '自定义歌源请求超时',
      ),
    )));

    final testButton = find.byKey(const ValueKey('custom-source-test-first'));
    await tester.ensureVisible(testButton);
    await tester.tap(testButton);
    await tester.pumpAndSettle();

    expect(
        find.text('Source test failed: Connection timed out'), findsOneWidget);
    expect(find.textContaining('自定义歌源请求超时'), findsNothing);
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
      expect(
        find.text(ui('停用或删除后立即停止该来源的新请求；已保存的收藏、歌单和歌曲信息不会删除。')),
        findsOneWidget,
      );
      expect(
        find.text(ui('搜索会发送关键词；歌词、评论和播放/下载解析会向所选来源发送来源歌曲 ID 或必要的歌曲信息。')),
        findsOneWidget,
      );
      expect(
        find.text(ui('请勿在地址或公开请求头中填写密钥。')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await _openAdd(tester);
      expect(find.byKey(const ValueKey('custom-source-name')), findsOneWidget);
      await tester.ensureVisible(
          find.byKey(const ValueKey('custom-capability-download')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final protocol = find.byKey(const ValueKey('custom-source-protocol'));
      await tester.ensureVisible(protocol);
      await tester.tap(protocol);
      await tester.pumpAndSettle();
      await tester.tap(find.text(ui('歌词 API')).last);
      await tester.pumpAndSettle();
      expect(find.byType(FilterChip), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
