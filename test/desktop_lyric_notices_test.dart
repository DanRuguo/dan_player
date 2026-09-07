import 'package:desktop_lyric/app_presentation.dart';
import 'package:desktop_lyric/component/foreground.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:desktop_lyric/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/desktop_lyric_test_support.dart';

class _FailingWindow extends FakeDesktopLyricWindow {
  bool failReads = false;

  @override
  Future<Rect> getBounds() async {
    if (failReads) throw StateError('synthetic geometry failure');
    return super.getBounds();
  }
}

Widget _app(DesktopLyricController source, DesktopLyricWindowLayout layout) =>
    MaterialApp(
      builder: (context, child) => AppPresentationHost(child: child!),
      home: Scaffold(
        body: Provider<ThemeChangedMessage>.value(
          value: source.theme.value,
          child: DesktopLyricForeground(
            controller: source,
            windowLayout: layout,
            isHovering: true,
            sendMessage: (_) {},
          ),
        ),
      ),
    );

void _expectErrorBubble(WidgetTester tester, String message) {
  expect(find.textContaining(message), findsOneWidget);
  final bubble = find.byKey(const ValueKey('app-notice-bubble'));
  expect(bubble, findsOneWidget);
  expect(tester.widget<Material>(bubble).color,
      Theme.of(tester.element(bubble)).colorScheme.errorContainer);
  expect(
      tester.getSize(bubble).width, lessThan(tester.view.physicalSize.width));
  expect(find.byType(SnackBar), findsNothing);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('lock failure uses the shared error bubble', (tester) async {
    final source = DesktopLyricController.detached(
      clock: PlaybackClock(automaticTicks: false),
      setIgnoreMouseEvents: (_) async {
        throw StateError('synthetic lock failure');
      },
    );
    final layout = DesktopLyricWindowLayout(adapter: FakeDesktopLyricWindow());
    await layout.initialize(vertical: false);
    await tester.pumpWidget(_app(source, layout));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('desktop-lyric-lock')));
    await tester.pumpAndSettle();
    _expectErrorBubble(tester, '无法锁定歌词：');
    expect(source.locked.value, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    layout.dispose();
    source.dispose();
  });

  testWidgets('geometry failure uses the shared error bubble', (tester) async {
    final source = DesktopLyricController.detached(
        clock: PlaybackClock(automaticTicks: false));
    final native = _FailingWindow();
    final layout = DesktopLyricWindowLayout(adapter: native);
    await layout.initialize(vertical: false);
    native.failReads = true;
    await tester.pumpWidget(_app(source, layout));
    await tester.pumpAndSettle();
    _expectErrorBubble(tester, '调整歌词窗口失败：');
    await tester.pumpWidget(const SizedBox.shrink());
    layout.dispose();
    source.dispose();
  });
}
