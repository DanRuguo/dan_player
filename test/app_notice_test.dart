import 'package:dan_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ColorScheme> mount(WidgetTester tester) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: SCAFFOLD_MESSAGER,
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      home: const Scaffold(body: SizedBox.expand()),
    ));
    return scheme;
  }

  testWidgets('a newer notice immediately replaces the current notice',
      (tester) async {
    await mount(tester);
    showAppNotice(
      '旧结果',
      duration: const Duration(milliseconds: 100),
    );
    await tester.pump();
    expect(find.text('旧结果'), findsOneWidget);

    showAppNotice(
      '最新结果',
      kind: AppNoticeKind.success,
      duration: const Duration(seconds: 1),
    );
    await tester.pump();
    expect(find.text('旧结果'), findsNothing);
    expect(find.text('最新结果'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);

    // Expiration of the removed notice must not dismiss its replacement.
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('最新结果'), findsOneWidget);
  });

  testWidgets('semantic kind controls icon, colours and live announcement',
      (tester) async {
    final scheme = await mount(tester);
    final semantics = tester.ensureSemantics();
    showAppNotice('网络请求失败', kind: AppNoticeKind.error);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.behavior, SnackBarBehavior.floating);
    expect(snackBar.backgroundColor, scheme.errorContainer);
    expect(snackBar.elevation, 8);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    final message = tester.widget<Text>(find.text('网络请求失败'));
    expect(message.style?.color, scheme.onErrorContainer);
    final announcement = find.bySemanticsLabel(RegExp('错误：网络请求失败'));
    expect(announcement, findsAtLeastNWidgets(1));
    final data = tester.getSemantics(announcement.first).getSemanticsData();
    expect(data.label, contains('错误：网络请求失败'));
    expect(data.flagsCollection.isLiveRegion, isTrue);
    semantics.dispose();
  });

  for (final phase in ['停留', '退场']) {
    testWidgets('$phase阶段的新消息也直接取代旧消息', (tester) async {
      await mount(tester);
      showAppNotice('阶段旧消息', duration: const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 300));
      if (phase == '退场') {
        SCAFFOLD_MESSAGER.currentState!.hideCurrentSnackBar();
        await tester.pump(const Duration(milliseconds: 60));
      }
      showAppNotice('阶段最新消息', kind: AppNoticeKind.warning);
      await tester.pump();
      expect(find.text('阶段旧消息'), findsNothing);
      expect(find.text('阶段最新消息'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  }

  testWidgets('legacy entry classifies common success and failure wording',
      (tester) async {
    await mount(tester);
    showTextOnSnackBar('保存失败：fixture');
    await tester.pump();
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    showTextOnSnackBar('已保存歌曲信息');
    await tester.pump();
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets('notice action remains reachable after visual restyling',
      (tester) async {
    await mount(tester);
    var retries = 0;
    showAppNotice(
      '保存失败',
      kind: AppNoticeKind.error,
      actionLabel: '重试',
      onAction: () => retries++,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(retries, 1);
  });

  testWidgets('a visible nested messenger wins over the offstage app messenger',
      (tester) async {
    final localKey = GlobalKey<ScaffoldMessengerState>();
    late BuildContext localContext;
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: SCAFFOLD_MESSAGER,
      home: Scaffold(
        body: ScaffoldMessenger(
          key: localKey,
          child: Scaffold(
            body: Builder(builder: (context) {
              localContext = context;
              return const SizedBox.expand();
            }),
          ),
        ),
      ),
    ));
    showAppNotice('后台旧消息');
    await tester.pump();
    expect(find.text('后台旧消息'), findsOneWidget);
    showAppNotice('迷你窗口消息', context: localContext);
    await tester.pump();
    expect(find.text('后台旧消息'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(localKey),
        matching: find.text('迷你窗口消息'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('floating notice fits a narrow short window with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: SCAFFOLD_MESSAGER,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: const Scaffold(body: SizedBox.expand()),
    ));
    showAppNotice('网络连接失败，请检查设置后重试', kind: AppNoticeKind.error);
    await tester.pump();
    final rect = tester.getRect(find.byType(SnackBar));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(320));
    expect(rect.bottom, lessThanOrEqualTo(240));
    expect(tester.takeException(), isNull);
  });
}
