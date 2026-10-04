import 'dart:async';
import 'package:dan_player/app_paths.dart' as paths;
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_data_storage_card.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/process_resource_monitor.dart';
import 'package:dan_player/component/side_nav.dart';
import 'package:dan_player/process_resource_coordinator.dart';
import 'package:dan_player/process_resource_preferences.dart';
import 'package:dan_player/statistics/app_data_storage.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'support/playlist_feature_fixture.dart';
import 'support/process_resource_fixture.dart';

// Public documentation renders use real components with explicitly fictional
// samples. No filesystem scanner, actual process worker or music is started.
void main() {
  setUpAll(loadPlaylistFeatureFonts);
  testWidgets('recent monitoring and storage documentation renders',
      (tester) async {
    sizePlaylistFeature(tester, width: 1080, height: 860);
    final saved = AppSettings.instance.processResources.value;
    final previousLanguage = uiLanguage.value;
    addTearDown(() {
      AppSettings.instance.processResources.value = saved;
      uiLanguage.value = previousLanguage;
    });
    uiLanguage.value = UiLanguage.zh;
    final rig = ResourceTestRig();
    final coordinator =
        ProcessResourceCoordinator.forTesting(service: rig.service);
    final hidden = ValueNotifier(false);
    AppSettings.instance.processResources.value =
        const ProcessResourcePreferences(
            enabled: true,
            showInSidebar: true,
            showInLyrics: true,
            display: ProcessResourceDisplay.line);
    final boundary = GlobalKey();
    final page = ValueNotifier(false);
    const storage = AppDataStorageSnapshot(
        path: r'D:\DanPlayer\Data',
        unreadable: 0,
        skippedLinks: 0,
        truncated: false,
        parts: [
          AppDataStoragePart('封面缓存', 428, 112 * 1024 * 1024,
              paths: [r'D:\DanPlayer\Data\covers']),
          AppDataStoragePart('联网歌词缓存', 126, 5 * 1024 * 1024,
              paths: [r'D:\DanPlayer\Data\cache\online_lyrics']),
          AppDataStoragePart('评论缓存', 32, 900 * 1024,
              paths: [r'D:\DanPlayer\Data\cache\song_comments']),
          AppDataStoragePart('自选图片与封面', 7, 12 * 1024 * 1024),
          AppDataStoragePart('曲库与用户资料', 8, 6 * 1024 * 1024),
          AppDataStoragePart('迁移与恢复快照', 3, 4 * 1024 * 1024),
        ]);
    Widget contents(BuildContext context, GoRouterState state) => Scaffold(
            body:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SideNav(desktopWidth: 220, resourceCoordinator: coordinator),
          Expanded(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ValueListenableBuilder(
                      valueListenable: page,
                      builder: (context, cache, _) => Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(ui(cache ? '统计' : '备份与恢复'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium),
                                const SizedBox(height: 20),
                                if (cache)
                                  AppDataStorageCard(
                                      reading: Future.value(storage))
                                else
                                  ProcessResourceMonitor(
                                      coordinator: coordinator,
                                      isHidden: hidden,
                                      onPreferencesChanged: (prefs) async =>
                                          AppSettings.instance.processResources
                                              .value = prefs),
                              ])))),
        ]));
    final router = GoRouter(initialLocation: paths.SETTINGS_PAGE, routes: [
      GoRoute(path: paths.SETTINGS_PAGE, builder: contents),
      GoRoute(path: paths.STATISTICS_PAGE, builder: contents),
    ]);
    await tester.pumpWidget(playlistFeatureHost(
        MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: router,
            theme: ThemeData(
                useMaterial3: true,
                fontFamily: danEmbeddedFontFamily,
                fontFamilyFallback: danFontFamilyFallback,
                colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!)),
        boundary: boundary));
    await tester.pumpAndSettle();
    for (var i = 0; i < 18; i++) {
      final done = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
              rig.channel.name,
              const StandardMethodCodec()
                  .encodeMethodCall(MethodCall('sample', {
                'session': rig.session,
                'cpuPercent': 3.5 + (i % 6) * .8,
                'gpuPercent': 7.0 + (i % 7) * 1.1,
                'workingSetBytes': (140 + i) * 1024 * 1024,
                'totalPhysicalMemoryBytes': 16 * 1024 * 1024 * 1024,
                'cpuStatus': 'ready',
                'gpuStatus': 'ready',
              })),
              (_) => done.complete());
      await done.future;
    }
    await tester.pump();
    expect(tester.takeException(), isNull);
    await capturePlaylistFeature(
        tester, boundary, 'process-resource-locations');
    page.value = true;
    router.go(paths.STATISTICS_PAGE);
    await tester.pumpAndSettle();
    expect(find.text(ui('评论缓存')), findsOneWidget);
    expect(find.text(storage.path), findsNothing);
    expect(tester.takeException(), isNull);
    await capturePlaylistFeature(tester, boundary, 'cache-storage-statistics');
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    page.dispose();
    hidden.dispose();
    await rig.close();
  });
}
