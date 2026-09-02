import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/online_source_display.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/page/search_page/search_page.dart';
import 'package:dan_player/page/search_page/search_result_page.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {double scale = 1}) => UiLanguageScope(
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: Scaffold(body: child),
      ),
    );

CustomMusicSourceProfile _profile(String name) =>
    CustomMusicSourceProfile.tryCreate(
      id: 'display-source',
      name: name,
      baseUrl: 'https://source.example/api',
      capabilities: const {CustomMusicSourceCapability.search},
      endpoints: const {
        CustomMusicSourceCapability.search: 'https://source.example/api',
      },
    )!;

void main() {
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  test('built-in source labels localize while custom names remain user data',
      () {
    final previous = AppSettings.instance.customMusicSources.value;
    addTearDown(() => AppSettings.instance.customMusicSources.value = previous);
    final profile = _profile('播放');
    AppSettings.instance.customMusicSources.value = [profile];
    uiLanguage.value = UiLanguage.en;

    expect(
      onlineSourceDisplayLabel(provider: 'qq', fallback: 'QQ音乐'),
      'QQ Music',
    );
    expect(
      onlineSourceDisplayLabel(
        provider: profile.providerId,
        fallback: profile.name,
      ),
      '播放',
    );
    expect(
      onlineSourceDisplayLabel(
        provider: 'custom:removed-source',
        fallback: '自定义歌源',
      ),
      'Custom source',
    );
  });

  testWidgets('mixed-source tile visibly preserves a custom source name',
      (tester) async {
    tester.view.physicalSize = const Size(507, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previous = AppSettings.instance.customMusicSources.value;
    addTearDown(() => AppSettings.instance.customMusicSources.value = previous);
    final profile = _profile('播放');
    AppSettings.instance.customMusicSources.value = [profile];
    uiLanguage.value = UiLanguage.en;
    final audio = Audio.online(
      provider: profile.providerId,
      id: 'track-1',
      title: 'Media title',
      artist: 'Artist',
      album: 'Album',
      duration: 120,
    );

    await tester.pumpWidget(_host(
      AudioTile(
        audioIndex: 0,
        playlist: [audio],
        showSourceLabel: true,
      ),
      scale: 2,
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Source: 播放'), findsOneWidget);
    expect(find.textContaining('Source: Play'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'search failures use provider IDs without translating custom names',
      (tester) async {
    tester.view.physicalSize = const Size(507, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previous = AppSettings.instance.customMusicSources.value;
    addTearDown(() => AppSettings.instance.customMusicSources.value = previous);
    final profile = _profile('播放');
    AppSettings.instance.customMusicSources.value = [profile];
    uiLanguage.value = UiLanguage.en;
    final result = UnionSearchResult('query')
      ..online = Future.value(OnlineSearchResponse(
        tracks: const [],
        failures: {
          'qq': '联网请求超时，请稍后重试',
          profile.providerId: '联网失败，请检查网络连接',
        },
      ));

    await tester.pumpWidget(_host(
      SearchResultPage(searchResult: result),
      scale: 2,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ui('联网')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(CustomScrollView).hitTestable(),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
          'QQ Music：The online request timed out. Try again later.'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
          '播放：The online request failed. Check your network connection.'),
      findsOneWidget,
    );
    expect(find.textContaining('Play：'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long online identity stays compact and copies the full value',
      (tester) async {
    tester.view.physicalSize = const Size(320, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const provider = 'custom:provider-with-a-deliberately-long-identifier';
    final id = List.filled(200, '歌').join();
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(_host(
      OnlineIdentitySummary(provider: provider, id: id),
      scale: 2,
    ));
    await tester.pumpAndSettle();

    final summary = tester.widget<Text>(
      find.byKey(const ValueKey('online-identity-summary')),
    );
    expect(summary.data, contains('…'));
    expect(summary.data!.length, lessThan('$provider · $id'.length));
    await tester.tap(find.byKey(const ValueKey('online-identity-copy')));
    await tester.pumpAndSettle();
    expect(copied, '$provider · $id');
    expect(tester.takeException(), isNull);
  });
}
