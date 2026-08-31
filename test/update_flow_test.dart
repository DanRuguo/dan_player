import 'dart:async';
import 'dart:io';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/page/settings_page/check_update.dart';
import 'package:dan_player/update/installer_launcher.dart';
import 'package:dan_player/update/update_channel_preference.dart';
import 'package:dan_player/update/update_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github/github.dart';

AvailableUpdate _update({bool preview = false}) {
  final version = preview ? '26.0.4-snapshot.2' : '26.0.4';
  return AvailableUpdate(
    release: Release(
        tagName: version,
        name: 'Dan Player $version',
        body: 'Update notes.',
        isPrerelease: preview),
    version: AppVersion.tryParse(version)!,
    asset: ReleaseAsset(
        name: 'DanPlayer-$version-Setup-x64.exe',
        browserDownloadUrl:
            'https://github.com/DanRuguo/dan_player/releases/download/v$version/setup.exe'),
  );
}

UpdateDownloadResult _result(AvailableUpdate update, {bool verified = true}) =>
    UpdateDownloadResult(
        file: File(update.asset!.name!),
        sha256Digest: 'a' * 64,
        checksumVerified: verified);

void main() {
  late UpdateChannelPreference originalChannel;
  late String? originalIgnored;
  late DateTime? originalCheck;
  setUp(() {
    originalChannel = AppSettings.instance.updateChannel;
    originalIgnored = AppSettings.instance.ignoredUpdateVersion;
    originalCheck = AppSettings.instance.lastUpdateCheckAt;
  });
  tearDown(() {
    AppSettings.instance.updateChannel = originalChannel;
    AppSettings.instance.ignoredUpdateVersion = originalIgnored;
    AppSettings.instance.lastUpdateCheckAt = originalCheck;
    uiLanguage.value = UiLanguage.zh;
  });

  Future<BuildContext> mount(WidgetTester tester,
      {Widget? content,
      double scale = 1,
      Size size = const Size(900, 650)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late BuildContext pageContext;
    await tester.pumpWidget(UiLanguageScope(
        child: MaterialApp(
      locale: uiLanguage.value.locale,
      supportedLocales: UiLanguage.values.map((value) => value.locale),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: AppPresentationHost(child: child!),
      ),
      home: Scaffold(body: Builder(builder: (context) {
        pageContext = context;
        return content ?? const SizedBox.expand();
      })),
    )));
    await tester.pumpAndSettle();
    return pageContext;
  }

  Future<void> open(WidgetTester tester, NewestUpdateView view,
      {double scale = 1, Size size = const Size(900, 650)}) async {
    final context = await mount(tester, scale: scale, size: size);
    unawaited(showAppDialog<void>(context: context, builder: (_) => view));
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, Finder finder) async {
    final progress = find.byKey(const ValueKey('update-install-progress'));
    Future<void> settleFiniteAnimations() async {
      await tester.pump();
      if (progress.evaluate().isEmpty) {
        await tester.pumpAndSettle();
      } else {
        // Native verification/exit can legitimately remain pending. Advance
        // the dialog transition without waiting on its indeterminate spinner.
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    await tester.ensureVisible(finder);
    await settleFiniteAnimations();
    await tester.tap(finder);
    await settleFiniteAnimations();
  }

  final downloadButton = find.byKey(const ValueKey('update-download'));
  final confirmButton = find.byKey(const ValueKey('update-confirm-action'));
  final restartButton = find.byKey(const ValueKey('update-restart'));

  testWidgets('download and restart each require separate confirmation',
      (tester) async {
    final update = _update(preview: true);
    final events = <String>[];
    await open(
        tester,
        NewestUpdateView(
          update: update,
          download: (_, {onProgress, cancellation}) async {
            events.add('download');
            return _result(update);
          },
          launchInstaller: (_, __) async => events.add('launch'),
          exitApplication: () async => events.add('exit'),
        ));
    expect(events, isEmpty);
    expect(find.textContaining('这是预览版'), findsOneWidget);
    await press(tester, downloadButton);
    expect(events, isEmpty);
    expect(find.text('下载预览更新？'), findsOneWidget);
    await press(tester, find.text('取消'));
    expect(events, isEmpty);
    await press(tester, downloadButton);
    await press(tester, confirmButton);
    expect(events, ['download']);
    await press(tester, restartButton);
    expect(events, ['download']);
    await press(tester, find.text('取消'));
    expect(events, ['download']);
    await press(tester, restartButton);
    await press(tester, confirmButton);
    expect(events, ['download', 'launch', 'exit']);
  });

  testWidgets('unverified download has only manual reveal, never restart',
      (tester) async {
    final update = _update();
    var revealed = 0;
    await open(
        tester,
        NewestUpdateView(
          update: update,
          download: (_, {onProgress, cancellation}) async =>
              _result(update, verified: false),
          revealFile: (_) async {
            revealed++;
            return true;
          },
          launchInstaller: (_, __) => throw StateError('Must never launch'),
          exitApplication: () => throw StateError('Must never exit'),
        ));
    await press(tester, downloadButton);
    await press(tester, confirmButton);
    expect(restartButton, findsNothing);
    await press(tester, find.text('显示安装包'));
    expect(revealed, 1);
  });

  testWidgets('launch failure keeps app and file, and unlocks retry',
      (tester) async {
    final update = _update();
    var launches = 0;
    var exits = 0;
    await open(
        tester,
        NewestUpdateView(
          update: update,
          download: (_, {onProgress, cancellation}) async => _result(update),
          launchInstaller: (_, __) async {
            if (++launches == 1) {
              throw const InstallerLaunchException('start_failed', 'synthetic');
            }
          },
          exitApplication: () async => exits++,
        ));
    await press(tester, downloadButton);
    await press(tester, confirmButton);
    await press(tester, restartButton);
    await press(tester, confirmButton);
    expect(exits, 0);
    expect(find.textContaining('播放器仍保持打开'), findsOneWidget);
    expect(find.text('显示安装包'), findsOneWidget);
    await press(tester, restartButton);
    await press(tester, confirmButton);
    expect(launches, 2);
    expect(exits, 1);
  });

  testWidgets('untrusted signature explains manual boundary without quitting',
      (tester) async {
    final update = _update();
    var exits = 0;
    await open(
        tester,
        NewestUpdateView(
          update: update,
          download: (_, {onProgress, cancellation}) async => _result(update),
          launchInstaller: (_, __) async =>
              throw const InstallerLaunchException(
                  'signature_untrusted', 'private path must not be shown'),
          exitApplication: () async => exits++,
        ));
    await press(tester, downloadButton);
    await press(tester, confirmButton);
    await press(tester, restartButton);
    await press(tester, confirmButton);
    expect(exits, 0);
    expect(find.textContaining('不会自动修改系统信任设置'), findsOneWidget);
    expect(find.textContaining('private path'), findsNothing);
    expect(find.text('显示安装包'), findsOneWidget);
  });

  testWidgets(
      'download disposal cancels only its operation and handles late error',
      (tester) async {
    final update = _update();
    final pending = Completer<UpdateDownloadResult>();
    late UpdateDownloadCancellation cancel;
    await open(
        tester,
        NewestUpdateView(
          update: update,
          download: (_, {onProgress, cancellation}) {
            cancel = cancellation!;
            return pending.future;
          },
        ));
    await press(tester, downloadButton);
    await tester.tap(confirmButton);
    await tester.pump(const Duration(milliseconds: 250));
    expect(cancel.isCancelled, isFalse);
    await tester.pumpWidget(const SizedBox());
    expect(cancel.isCancelled, isTrue);
    pending.completeError(const UpdateException('已取消下载。'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await open(
        tester,
        NewestUpdateView(
            update: update,
            download: (_, {onProgress, cancellation}) async =>
                _result(update)));
    await press(tester, downloadButton);
    await press(tester, confirmButton);
    expect(restartButton, findsOneWidget);
  });

  testWidgets('disposing a pending confirmation never starts download',
      (tester) async {
    var downloads = 0;
    final update = _update();
    await open(
        tester,
        NewestUpdateView(
            update: update,
            download: (_, {onProgress, cancellation}) async {
              downloads++;
              return _result(update);
            }));
    await press(tester, downloadButton);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(downloads, 0);
    expect(tester.takeException(), isNull);
  });

  for (final succeeds in [true, false]) {
    testWidgets('launch owns completion after view disposal ($succeeds)',
        (tester) async {
      final update = _update();
      final started = Completer<void>();
      var launches = 0;
      var exits = 0;
      await open(
          tester,
          NewestUpdateView(
            update: update,
            download: (_, {onProgress, cancellation}) async => _result(update),
            launchInstaller: (_, __) {
              launches++;
              return started.future;
            },
            exitApplication: () async => exits++,
          ));
      await press(tester, downloadButton);
      await press(tester, confirmButton);
      await press(tester, restartButton);
      await press(tester, confirmButton);
      expect(launches, 1);
      expect(exits, 0);
      expect(tester.widget<FilledButton>(restartButton).onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
      if (succeeds) {
        started.complete();
      } else {
        started.completeError(StateError('synthetic'));
      }
      await tester.pump();
      expect(exits, succeeds ? 1 : 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed ignore save unlocks action and retry can close',
      (tester) async {
    var saves = 0;
    final service = UpdateService.forTesting(
      appDataDirectory: () => throw StateError('No disk'),
      httpClientFactory: () => throw StateError('No network'),
      savePreferences: () async {
        if (++saves == 1) throw StateError('synthetic');
      },
    );
    await open(tester, NewestUpdateView(update: _update(), service: service));
    await press(tester, find.text('忽略此版本'));
    expect(find.text('更新偏好保存失败，请重试'), findsOneWidget);
    await press(tester, find.text('忽略此版本'));
    expect(find.byType(NewestUpdateView), findsNothing);
  });

  testWidgets('disabling previews suppresses an old in-flight preview prompt',
      (tester) async {
    final pending = Completer<List<Release>>();
    AppSettings.instance.receivePreviewUpdates = true;
    final service = UpdateService.forTesting(
      appDataDirectory: () => throw StateError('No disk'),
      httpClientFactory: () => throw StateError('No network'),
      currentVersion: '26.0.4-snapshot.1',
      releaseLoader: () => pending.future,
    );
    final context = await mount(tester);
    final checking = checkForUpdateAndPresent(context, service: service);
    AppSettings.instance.receivePreviewUpdates = false;
    pending
        .complete([Release(tagName: '26.0.4-snapshot.2', isPrerelease: true)]);
    await checking;
    await tester.pumpAndSettle();
    expect(find.byType(NewestUpdateView), findsNothing);
  });

  testWidgets('preview preference failure restores toggle and permits retry',
      (tester) async {
    AppSettings.instance.receivePreviewUpdates = false;
    var saves = 0;
    await mount(tester, content: CheckForUpdate(savePreferences: () async {
      if (++saves == 1) throw StateError('synthetic');
    }));
    final toggle = find.byKey(const ValueKey('update-preview-channel'));
    tester.widget<SettingsSwitchTile>(toggle).onChanged!(true);
    await tester.pumpAndSettle();
    expect(AppSettings.instance.receivePreviewUpdates, isFalse);
    expect(tester.widget<SettingsSwitchTile>(toggle).onChanged, isNotNull);
    tester.widget<SettingsSwitchTile>(toggle).onChanged!(true);
    await tester.pumpAndSettle();
    expect(AppSettings.instance.receivePreviewUpdates, isTrue);
  });

  testWidgets('hash rejection removes restart and offers a fresh download',
      (tester) async {
    final update = _update();
    var downloads = 0;
    var exits = 0;
    await open(
        tester,
        NewestUpdateView(
          update: update,
          download: (_, {onProgress, cancellation}) async {
            downloads++;
            return _result(update);
          },
          launchInstaller: (_, __) async =>
              throw const InstallerLaunchException(
                  'hash_mismatch', 'synthetic'),
          exitApplication: () async => exits++,
        ));
    await press(tester, downloadButton);
    await press(tester, confirmButton);
    await press(tester, restartButton);
    await press(tester, confirmButton);
    expect(exits, 0);
    expect(restartButton, findsNothing);
    expect(find.text('显示安装包'), findsOneWidget);
    await press(tester, find.byKey(const ValueKey('update-redownload')));
    await press(tester, confirmButton);
    expect(downloads, 2);
    expect(restartButton, findsOneWidget);
  });

  testWidgets(
      'old disposed preference failure cannot revert a newer explicit choice',
      (tester) async {
    AppSettings.instance.receivePreviewUpdates = false;
    final oldSave = Completer<void>();
    await mount(tester,
        content: CheckForUpdate(savePreferences: () => oldSave.future));
    final toggle = find.byKey(const ValueKey('update-preview-channel'));
    tester.widget<SettingsSwitchTile>(toggle).onChanged!(true);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await mount(tester, content: CheckForUpdate(savePreferences: () async {}));
    tester.widget<SettingsSwitchTile>(toggle).onChanged!(true);
    await tester.pumpAndSettle();
    oldSave.completeError(StateError('old synthetic failure'));
    await tester.pump();
    expect(AppSettings.instance.receivePreviewUpdates, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failed exit is visible and retry never starts a second installer',
      (tester) async {
    final update = _update();
    var launches = 0;
    var exits = 0;
    await open(
        tester,
        NewestUpdateView(
          update: update,
          download: (_, {onProgress, cancellation}) async => _result(update),
          launchInstaller: (_, __) async => launches++,
          exitApplication: () async {
            if (++exits == 1) throw StateError('synthetic close failure');
          },
        ));
    await press(tester, downloadButton);
    await press(tester, confirmButton);
    await press(tester, restartButton);
    await press(tester, confirmButton);
    expect(find.textContaining('播放器未能完成退出'), findsOneWidget);
    expect(find.text('重试退出'), findsOneWidget);
    await press(tester, restartButton);
    expect(launches, 1);
    expect(exits, 2);
  });

  testWidgets('verification progress changes to exit progress and then clears',
      (tester) async {
    final update = _update();
    final launching = Completer<void>();
    final exiting = Completer<void>();
    await open(
        tester,
        NewestUpdateView(
          update: update,
          download: (_, {onProgress, cancellation}) async => _result(update),
          launchInstaller: (_, __) => launching.future,
          exitApplication: () => exiting.future,
        ));
    final progress = find.byKey(const ValueKey('update-install-progress'));
    expect(progress, findsNothing);
    await press(tester, downloadButton);
    await press(tester, confirmButton);
    await press(tester, restartButton);
    await press(tester, confirmButton);
    expect(progress.hitTestable(), findsOneWidget);
    expect(tester.getSize(progress), const Size(18, 18));
    expect(find.text('正在验证安装器…'), findsOneWidget);
    launching.complete();
    await tester.pump();
    expect(find.text('正在退出…'), findsOneWidget);
    expect(progress, findsOneWidget);
    exiting.complete();
    await tester.pumpAndSettle();
    expect(progress, findsNothing);
  });

  testWidgets(
      'failed deferred verification removes progress and restores action',
      (tester) async {
    final update = _update();
    final launching = Completer<void>();
    var exits = 0;
    await open(
        tester,
        NewestUpdateView(
          update: update,
          download: (_, {onProgress, cancellation}) async => _result(update),
          launchInstaller: (_, __) => launching.future,
          exitApplication: () async => exits++,
        ));
    final progress = find.byKey(const ValueKey('update-install-progress'));
    await press(tester, downloadButton);
    await press(tester, confirmButton);
    await press(tester, restartButton);
    await press(tester, confirmButton);
    expect(progress.hitTestable(), findsOneWidget);
    launching.completeError(
        const InstallerLaunchException('signature_untrusted', 'synthetic'));
    await tester.pumpAndSettle();
    expect(progress, findsNothing);
    expect(exits, 0);
    expect(tester.widget<FilledButton>(restartButton).onPressed, isNotNull);
  });

  for (final language in UiLanguage.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('confirmations fit ${language.code} at $scale short window',
          (tester) async {
        uiLanguage.value = language;
        final update = _update(preview: true);
        await open(
            tester,
            NewestUpdateView(
              update: update,
              download: (_, {onProgress, cancellation}) async =>
                  _result(update),
              launchInstaller: (_, __) async {},
              exitApplication: () async {},
            ),
            scale: scale,
            size: const Size(507, 360));
        await press(tester, downloadButton);
        expect(confirmButton.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await press(tester, confirmButton);
        await press(tester, restartButton);
        expect(confirmButton.hitTestable(), findsOneWidget);
        expect(tester.getRect(confirmButton).bottom, lessThanOrEqualTo(360));
        expect(tester.takeException(), isNull);
        await press(tester, confirmButton);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
