import 'dart:async';
import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/page/settings_page/check_update.dart';
import 'package:dan_player/update/update_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:github/github.dart';
import 'package:material_symbols_icons/symbols.dart';

AvailableUpdate _update({
  String? body,
  String? releaseUrl,
  bool omitReleaseUrl = false,
  bool omitAsset = false,
}) =>
    AvailableUpdate(
      release: Release(
        tagName: 'v26.0.6-snapshot.1',
        name: 'Dan Player 26.0.6 snapshot1',
        body: body ?? 'Playback refinements and bug fixes.',
        isPrerelease: true,
        htmlUrl: omitReleaseUrl
            ? null
            : releaseUrl ??
                'https://github.com/DanRuguo/dan_player/releases/tag/v26.0.6-snapshot.1',
      ),
      version: AppVersion.tryParse('26.0.6-snapshot.1')!,
      asset: omitAsset
          ? null
          : ReleaseAsset(
              name: 'DanPlayer-26.0.6-snapshot.1-Setup-x64.exe',
              browserDownloadUrl:
                  'https://github.com/DanRuguo/dan_player/releases/download/v26.0.6-snapshot.1/DanPlayer-26.0.6-snapshot.1-Setup-x64.exe',
            ),
    );

Future<GlobalKey> _open(WidgetTester tester, NewestUpdateView dialog,
    {Size size = const Size(507, 360), double scale = 1.5}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final boundary = GlobalKey();
  late BuildContext pageContext;
  await tester.pumpWidget(UiLanguageScope(
    child: MaterialApp(
      locale: uiLanguage.value.locale,
      supportedLocales: UiLanguage.values.map((language) => language.locale),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: applyAppControlTheme(ThemeData(
        fontFamily: danEmbeddedFontFamily,
        fontFamilyFallback: danFontFamilyFallback,
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple, brightness: Brightness.dark),
      )),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: RepaintBoundary(
          key: boundary,
          child: AppPresentationHost(child: child!),
        ),
      ),
      home: Scaffold(body: Builder(builder: (context) {
        pageContext = context;
        return const SizedBox.expand();
      })),
    ),
  ));
  unawaited(showAppDialog<void>(context: pageContext, builder: (_) => dialog));
  await tester.pumpAndSettle();
  return boundary;
}

Future<void> _capture(GlobalKey boundary, String name) async {
  const output = String.fromEnvironment('DAN_UPDATE_DIALOG_RENDER');
  if (output.isEmpty) return;
  final image = await (boundary.currentContext!.findRenderObject()
          as RenderRepaintBoundary)
      .toImage();
  final bytes = await image.toByteData(format: drawing.ImageByteFormat.png);
  final file = File('$output/$name.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  image.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    await (FontLoader('packages/material_symbols_icons/MaterialSymbolsOutlined')
          ..addFont(rootBundle.load(
              'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf')))
        .load();
    for (final entry in {
      'Malgun Gothic': 'malgun.ttf',
      'Segoe UI Emoji': 'seguiemj.ttf',
      'Yu Gothic UI': 'YuGothR.ttc',
    }.entries) {
      final file = File('C:/Windows/Fonts/${entry.value}');
      if (await file.exists()) {
        await (FontLoader(entry.key)
              ..addFont(
                  Future.value(ByteData.sublistView(await file.readAsBytes()))))
            .load();
      }
    }
  });
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  testWidgets('standard Chinese update keeps notes and actions visible',
      (tester) async {
    uiLanguage.value = UiLanguage.zh;
    final boundary = await _open(tester, NewestUpdateView(update: _update()),
        size: const Size(900, 650), scale: 1);
    final details = find.byKey(const ValueKey('update-details-scroll'));
    expect(tester.getSize(details).height, greaterThan(100));
    for (final key in ['update-download', 'update-github']) {
      expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await tester.runAsync(() => _capture(boundary, 'zh-regular'));
  });

  testWidgets('same-version build marker stays out of visible release notes',
      (tester) async {
    uiLanguage.value = UiLanguage.zh;
    final original = _update(
      body:
          '累计更新说明。\n${ReleaseBuildMarker.prefix}{"version":"26.0.6-snapshot.1"}${ReleaseBuildMarker.suffix}',
    );
    original.release.publishedAt = DateTime.utc(2026, 1, 1);
    final update = AvailableUpdate(
      release: original.release,
      version: original.version,
      asset: original.asset,
      releaseBuild: ReleaseBuildMarker(
        version: '26.0.6-snapshot.1',
        sourceRevision: 'b' * 40,
        assembledUtc: DateTime.utc(2026, 9, 25),
        installerAssetId: 1,
        installerSize: 1,
        installerSha256: 'a' * 64,
        checksumAssetId: 2,
        checksumSize: 1,
      ),
    );
    await _open(tester, NewestUpdateView(update: update),
        size: const Size(900, 650), scale: 1);
    final notes = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(notes.data, '累计更新说明。');
    expect(find.text('此版本已重新发布新构建，可选择下载更新。'), findsOneWidget);
    expect(find.text('忽略此构建'), findsOneWidget);
    expect(find.textContaining('2026-09-25'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    testWidgets('GitHub action is a full secondary button in ${language.name}',
        (tester) async {
      uiLanguage.value = language;
      final boundary = await _open(tester, NewestUpdateView(update: _update()));
      final github = find.byKey(const ValueKey('update-github'));
      expect(github, findsOneWidget);
      expect(tester.widget<OutlinedButton>(github).onPressed, isNotNull);
      expect(
          find.descendant(of: github, matching: find.text(ui('在 GitHub 查看'))),
          findsOneWidget);
      expect(
          find.descendant(
              of: github, matching: find.byIcon(Symbols.open_in_new)),
          findsOneWidget);
      await tester.ensureVisible(github);
      await tester.pumpAndSettle();
      final exit = find.ancestor(
          of: find.text(ui('稍后')), matching: find.byType(TextButton));
      final githubRect = tester.getRect(github);
      final exitRect = tester.getRect(exit);
      expect(githubRect.overlaps(exitRect), isFalse);
      expect(githubRect.left, greaterThanOrEqualTo(0));
      expect(
          githubRect.right, lessThanOrEqualTo(tester.view.physicalSize.width));
      expect(tester.takeException(), isNull);

      await tester
          .runAsync(() => _capture(boundary, '${language.name}-narrow'));
    });

    testWidgets('actions remain reachable at 200% text in ${language.name}',
        (tester) async {
      uiLanguage.value = language;
      await _open(tester, NewestUpdateView(update: _update()), scale: 2);
      for (final key in ['update-download', 'update-github']) {
        final action = find.byKey(ValueKey(key));
        expect(action.hitTestable(), findsOneWidget);
        final rect = tester.getRect(action);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(tester.view.physicalSize.width));
        expect(rect.bottom, lessThanOrEqualTo(tester.view.physicalSize.height));
      }
      expect(find.text(ui('稍后')).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed download replaces stale progress with an error and retry',
      (tester) async {
    final boundary = await _open(
      tester,
      NewestUpdateView(
        update: _update(),
        download: (_, {onProgress, cancellation}) async {
          onProgress?.call(const UpdateDownloadProgress(
              receivedBytes: 500, totalBytes: 1000));
          throw const UpdateException('更新包下载失败，请稍后重试');
        },
      ),
    );
    final download = find.byKey(const ValueKey('update-download'));
    await tester.ensureVisible(download);
    await tester.tap(download);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('update-confirm-action')));
    await tester.pumpAndSettle();
    final error = find.text(ui('更新包下载失败，请稍后重试'));
    expect(error, findsOneWidget);
    final viewport =
        tester.getRect(find.byKey(const ValueKey('update-details-scroll')));
    expect(viewport.overlaps(tester.getRect(error)), isTrue);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining(ui('已下载')), findsNothing);
    expect(tester.widget<FilledButton>(download).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() => _capture(boundary, 'download-error'));
  });

  testWidgets('completed download shows latest progress after UI throttling',
      (tester) async {
    final update = _update();
    await _open(
      tester,
      NewestUpdateView(
        update: update,
        download: (_, {onProgress, cancellation}) async {
          onProgress?.call(const UpdateDownloadProgress(
              receivedBytes: 256, totalBytes: 1024));
          onProgress?.call(const UpdateDownloadProgress(
              receivedBytes: 1024, totalBytes: 1024));
          return UpdateDownloadResult(
            file: File(update.asset!.name!),
            sha256Digest: 'a' * 64,
            checksumVerified: false,
          );
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('update-download')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('update-confirm-action')));
    await tester.pumpAndSettle();
    expect(
        find.text(ui('已下载 {0}{1}', ['1.0 KB', ' / 1.0 KB'])), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long release notes scroll while all action buttons stay visible',
      (tester) async {
    final body =
        '${List.generate(14, (index) => 'Paragraph $index: playback and lyric changes have detailed notes.').join('\n\n')}\n\n'
        'End of release notes: ${'longword' * 30}.';
    final boundary =
        await _open(tester, NewestUpdateView(update: _update(body: body)));
    final details = find.byKey(const ValueKey('update-details-scroll'));
    final scroll = tester.widget<SingleChildScrollView>(details).controller!;
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    await tester.drag(details, const Offset(0, -4000));
    await tester.pumpAndSettle();
    final end = find.textContaining('End of release notes', findRichText: true);
    expect(end, findsWidgets);
    expect(tester.getRect(details).overlaps(tester.getRect(end.first)), isTrue);
    for (final key in ['update-download', 'update-github']) {
      final button = find.byKey(ValueKey(key));
      expect(button.hitTestable(), findsOneWidget);
      expect(tester.getRect(button).bottom,
          lessThanOrEqualTo(tester.view.physicalSize.height));
    }
    expect(tester.takeException(), isNull);
    await tester.runAsync(() => _capture(boundary, 'long-notes'));
  });

  testWidgets('GitHub button opens only its trusted release URL',
      (tester) async {
    final opened = <Uri>[];
    await _open(
      tester,
      NewestUpdateView(
        update: _update(),
        openExternalLink: (uri) async {
          opened.add(uri);
          return true;
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('update-github')));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse(_update().release.htmlUrl!)]);

    await tester.pumpWidget(const SizedBox());
    opened.clear();
    await _open(
      tester,
      NewestUpdateView(
        update: _update(releaseUrl: 'https://github.com.evil.example/release'),
        openExternalLink: (uri) async {
          opened.add(uri);
          return true;
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('update-github')));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(find.text(ui('已阻止不安全的外部链接')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('external launcher exception becomes a visible failure',
      (tester) async {
    await _open(
      tester,
      NewestUpdateView(
        update: _update(),
        openExternalLink: (_) => throw StateError('launcher failed'),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('update-github')));
    await tester.pumpAndSettle();
    expect(find.text(ui('无法打开链接')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('release without asset or page URL still opens project releases',
      (tester) async {
    final opened = <Uri>[];
    await _open(
      tester,
      NewestUpdateView(
        update: _update(omitAsset: true, omitReleaseUrl: true),
        openExternalLink: (uri) async {
          opened.add(uri);
          return true;
        },
      ),
    );
    expect(find.text(ui('打开发布页')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('update-download')));
    await tester.pumpAndSettle();
    expect(
        opened, [Uri.parse('https://github.com/DanRuguo/dan_player/releases')]);
    expect(find.byKey(const ValueKey('update-github')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed check timestamp save does not suppress fetched update',
      (tester) async {
    final originalCheck = AppSettings.instance.lastUpdateCheckAt;
    addTearDown(() => AppSettings.instance.lastUpdateCheckAt = originalCheck);
    final service = UpdateService.forTesting(
      appDataDirectory: () => throw StateError('disk unused'),
      httpClientFactory: () => throw StateError('network unused'),
      currentVersion: '26.0.6-snapshot.1',
      releaseLoader: () async => [
        Release(
          tagName: 'v26.0.7',
          name: 'Dan Player 26.0.7',
          htmlUrl:
              'https://github.com/DanRuguo/dan_player/releases/tag/v26.0.7',
        ),
      ],
      savePreferences: () => throw StateError('preferences unavailable'),
    );
    late BuildContext pageContext;
    await tester.pumpWidget(UiLanguageScope(
      child: MaterialApp(
        builder: (context, child) => AppPresentationHost(child: child!),
        home: Scaffold(body: Builder(builder: (context) {
          pageContext = context;
          return const SizedBox.expand();
        })),
      ),
    ));
    unawaited(checkForUpdateAndPresent(pageContext, service: service));
    await tester.pumpAndSettle();
    expect(find.byType(NewestUpdateView), findsOneWidget);
    expect(find.text(ui('更新偏好保存失败，请重试')), findsOneWidget);
    expect(find.text(ui('检查更新失败，请稍后重试')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    testWidgets(
        'completed actions remain reachable at 200% text in ${language.name}',
        (tester) async {
      uiLanguage.value = language;
      final update = _update();
      final boundary = await _open(
        tester,
        NewestUpdateView(
          update: update,
          download: (_, {onProgress, cancellation}) async =>
              UpdateDownloadResult(
            file: File(update.asset!.name!),
            sha256Digest: 'a' * 64,
            checksumVerified: true,
          ),
        ),
        scale: 2,
      );
      await tester.tap(find.byKey(const ValueKey('update-download')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('update-confirm-action')));
      await tester.pumpAndSettle();
      await tester
          .runAsync(() => _capture(boundary, '${language.name}-completed-200'));
      for (final label in [
        ui('重启并更新'),
        ui('显示安装包'),
        ui('在 GitHub 查看'),
        ui('完成'),
      ]) {
        final action = find.text(label);
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        expect(action.hitTestable(), findsOneWidget);
        final rect = tester.getRect(action);
        expect(rect.right, lessThanOrEqualTo(tester.view.physicalSize.width));
        expect(rect.bottom, lessThanOrEqualTo(tester.view.physicalSize.height));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
