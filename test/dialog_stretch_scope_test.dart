import 'package:desktop_lyric/app_edge_stretch.dart';
import 'package:desktop_lyric/app_presentation.dart';
import 'package:desktop_lyric/app_scrollbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('custom stretch is limited to dialog scroll viewports',
      (tester) async {
    late BuildContext pageContext;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      scrollBehavior: const AppScrollBehavior(),
      home: Scaffold(
        body: Builder(builder: (context) {
          pageContext = context;
          return ListView.builder(
            key: const ValueKey('page-scroll'),
            itemExtent: 40,
            itemCount: 30,
            itemBuilder: (_, index) => Text('Page row $index'),
          );
        }),
      ),
    ));

    expect(find.byType(StretchingOverscrollIndicator), findsOneWidget);
    expect(find.byType(AppStretchingOverscrollIndicator), findsNothing);

    final dialog = showAppDialog<void>(
      context: pageContext,
      builder: (_) => Dialog(
        child: SizedBox(
          width: 320,
          height: 240,
          child: ListView.builder(
            key: const ValueKey('dialog-scroll'),
            itemExtent: 40,
            itemCount: 30,
            itemBuilder: (_, index) => Text('Dialog row $index'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(AppStretchingOverscrollIndicator),
      ),
      findsOneWidget,
    );
    expect(find.byType(StretchingOverscrollIndicator), findsOneWidget);

    Navigator.of(pageContext).pop();
    await dialog;
    await tester.pumpAndSettle();
    expect(find.byType(AppStretchingOverscrollIndicator), findsNothing);
    expect(find.byType(StretchingOverscrollIndicator), findsOneWidget);
  });
}
