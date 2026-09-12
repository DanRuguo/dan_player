import 'package:dan_player/component/app_menu_anchor.dart';
import 'package:dan_player/component/app_item_ink_well.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('repeated close/reopen keeps animated menu visible and operable',
      (tester) async {
    late MenuController controller;
    var chosen = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: AppMenuAnchor(
                    menuChildren: [
          MenuItemButton(onPressed: () => chosen++, child: const Text('Choose'))
        ],
                    builder: (_, c, __) {
                      controller = c;
                      return const SizedBox(width: 80, height: 80);
                    })))));
    controller.open();
    await tester.pumpAndSettle();
    for (var i = 0; i < 15; i++) {
      controller.close();
      await tester.pump(const Duration(milliseconds: 15));
      controller.open(position: Offset(i.toDouble(), 0));
      await tester.pump(const Duration(milliseconds: 15));
    }
    await tester.pumpAndSettle();
    expect(controller.isOpen, isTrue);
    expect(find.text('Choose').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(chosen, 1);
    expect(controller.isOpen, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'secondary popup opens only after release; long press clears transient ink',
      (tester) async {
    var opened = 0, held = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 100,
                    height: 100,
                    child: AppItemInkWell(
                        onTap: () {},
                        onLongPress: () => held++,
                        onSecondaryTapDown: (_) => opened++,
                        child: const Text('Item')))))));
    final right = await tester.startGesture(tester.getCenter(find.text('Item')),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await tester.pump(const Duration(milliseconds: 150));
    expect(opened, 0);
    await right.up();
    await tester.pumpAndSettle();
    expect(opened, 1);
    final primary = await tester.startGesture(
        tester.getCenter(find.text('Item')),
        kind: PointerDeviceKind.mouse);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 30));
    expect(held, 1);
    await primary.up();
    await tester.pumpAndSettle();
    final ink = tester.widget<InkWell>(find.byType(InkWell));
    expect(ink.statesController!.value.contains(WidgetState.pressed), isFalse);
    expect(ink.overlayColor!.resolve({}), Colors.transparent);
    expect(tester.takeException(), isNull);
  });
}
