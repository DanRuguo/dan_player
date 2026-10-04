import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/song_comments_dialog.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dan_player/online/song_comments.dart';
import 'support/song_comments_fixtures.dart';

Future<void> _pending(WidgetTester tester, FakeCommentsTransport transport,
    {bool feedback = true, required ValueNotifier<bool> hidden}) async {
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MotionPreferencesScope(
      preferences: MotionPreferences(
          disabled: feedback ? const {} : const {MotionKind.feedback}),
      child: DesktopVisibilityHost(isHidden: hidden, child: child!),
    ),
    home: Scaffold(
      body: SongCommentsDialog(
          audio: commentAudio(),
          service: SongCommentsService(transport: transport)),
    ),
  ));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('song-comments-refresh')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  // The refresh becomes disabled in the preceding frame. Let its finite ink
  // fade finish before checking the request's ongoing loading clock.
  await tester.pump(const Duration(milliseconds: 350));
  expect(transport.requests, hasLength(1));
  expect(find.text('正在加载评论…'), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final gate in ['feedback', 'reduce', 'visibility']) {
    testWidgets('pending manual comments stop loading motion for $gate',
        (tester) async {
      final automatic = AppSettings.instance.automaticOnlineLyrics;
      final originalAutomatic = automatic.value;
      final hidden = ValueNotifier(false);
      final originalLifecycle = tester.binding.lifecycleState;
      automatic.value = false;
      hidden.value = false;
      final pending = Completer<Map<String, dynamic>>();
      final transport = FakeCommentsTransport((_) => pending.future);
      addTearDown(() {
        automatic.value = originalAutomatic;
        hidden.dispose();
        tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue();
        if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        }
        tester.binding.handleAppLifecycleStateChanged(
            originalLifecycle ?? AppLifecycleState.resumed);
      });
      await _pending(tester, transport,
          feedback: gate != 'feedback', hidden: hidden);
      if (gate == 'reduce') {
        expect(tester.binding.transientCallbackCount, greaterThan(0));
        tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(reduceMotion: true);
      } else if (gate == 'visibility') {
        expect(tester.binding.transientCallbackCount, greaterThan(0));
        hidden.value = true;
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, 0,
          reason:
              'A pending request keeps busy feedback without an idle clock');
      final semantics = tester.ensureSemantics();
      try {
        expect(find.bySemanticsLabel(RegExp('正在加载评论…')), findsWidgets);
        final values = <String>[];
        void collect(SemanticsNode node) {
          values.add(node.getSemanticsData().value);
          node.visitChildren((child) {
            collect(child);
            return true;
          });
        }

        for (final view in tester.binding.renderViews) {
          final root = view.owner?.semanticsOwner?.rootSemanticsNode;
          if (root != null) collect(root);
        }
        expect(values.where((value) => value.contains('%')), isEmpty,
            reason:
                'Unknown busy feedback must not announce a fake percentage');
        final indicator = tester.widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator));
        expect(indicator.value, 0,
            reason:
                'Static unknown progress must not imply partial completion');
      } finally {
        semantics.dispose();
      }
      expect(transport.requests.single.cancellation.isCancelled, isFalse,
          reason: 'Visual policy cannot revoke a manual network request');
      if (gate != 'feedback') {
        tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue();
        hidden.value = false;
        await tester.pump();
        expect(tester.binding.transientCallbackCount, greaterThan(0));
        if (gate == 'visibility') {
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.binding.transientCallbackCount, 0);
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await tester.pump();
          expect(tester.binding.transientCallbackCount, greaterThan(0));
        }
      }
      pending.complete(neteaseComments([neteaseComment(43)]));
      await tester.pumpAndSettle();
      expect(find.text('测试评论 43'), findsOneWidget);
      expect(transport.requests, hasLength(1));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
