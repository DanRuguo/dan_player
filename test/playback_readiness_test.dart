import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/component/compact_player.dart';
import 'package:dan_player/component/scene_background.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/window_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(
        body: SizedBox(width: 520, height: 300, child: child),
      ),
    );

class _Observable<T> extends ValueNotifier<T> {
  _Observable(super.value);

  bool get isObserved => hasListeners;
}

class _LiveProbe extends StatefulWidget {
  const _LiveProbe({required this.track});
  final ValueNotifier<String> track;

  @override
  State<_LiveProbe> createState() => _LiveProbeState();
}

class _LiveProbeState extends State<_LiveProbe> {
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
        valueListenable: widget.track,
        builder: (_, value, __) => Text(value),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('readiness is passive and has no public value setter', () {
    final ready = PlaybackReadiness();
    addTearDown(ready.dispose);
    expect(ready.value, isFalse);
    expect(PlayService.isInitialized, isFalse);
    expect(PlayService.playbackReady.value, isFalse);
  });

  test('a throwing constructor never publishes ready and can retry', () async {
    final ready = PlaybackReadiness();
    addTearDown(ready.dispose);
    var notifications = 0;
    ready.addListener(() => notifications++);
    expect(
        () => ready.initialize<Object>(() => throw StateError('fake failure')),
        throwsStateError);
    await Future<void>.value();
    expect(ready.value, isFalse);
    expect(notifications, 0);
    final resource = Object();
    expect(ready.initialize(() => resource), same(resource));
    expect(ready.value, isFalse);
    await Future<void>.value();
    expect(ready.value, isTrue);
    expect(notifications, 1);
  });

  test('the caller assigns its lazy resource before readiness listeners run',
      () async {
    final ready = PlaybackReadiness();
    addTearDown(ready.dispose);
    final expected = Object();
    late final Object assigned;
    var notifications = 0;
    ready.addListener(() {
      expect(assigned, same(expected));
      expect(ready.value, isTrue);
      notifications++;
    });
    assigned = ready.initialize(() {
      expect(ready.value, isFalse);
      return expected;
    });
    expect(notifications, 0);
    await Future<void>.value();
    expect(notifications, 1);
    ready.initialize(() => expected);
    await Future<void>.value();
    expect(notifications, 1);
  });

  test('disposing a pending signal does not notify disposed listeners',
      () async {
    final ready = PlaybackReadiness();
    var notifications = 0;
    ready.addListener(() => notifications++);
    ready.initialize(Object.new);
    ready.dispose();
    await Future<void>.value();
    expect(notifications, 0);
  });

  testWidgets(
      'cold mount wakes once and then follows tracks without a theme change',
      (tester) async {
    final ready = _Observable(false);
    final track = _Observable('Track A');
    addTearDown(ready.dispose);
    addTearDown(track.dispose);
    var liveBuilds = 0;
    Widget gate() => PlaybackReadyBuilder(
          readiness: ready,
          waitingBuilder: (_) => const Text('Waiting for startup'),
          readyBuilder: (_) {
            liveBuilds++;
            return _LiveProbe(track: track);
          },
        );
    await tester.pumpWidget(_host(gate()));
    expect(find.text('Waiting for startup'), findsOneWidget);
    expect(liveBuilds, 0);
    expect(track.isObserved, isFalse);
    expect(ready.isObserved, isTrue);
    ready.value = true;
    await tester.pump();
    expect(find.text('Track A'), findsOneWidget);
    expect(track.isObserved, isTrue);
    final state = tester.state(find.byType(_LiveProbe));
    track.value = 'Track B';
    await tester.pump();
    expect(find.text('Track B'), findsOneWidget);
    await tester.pumpWidget(_host(gate()));
    expect(tester.state(find.byType(_LiveProbe)), same(state));
    expect(PlayService.isInitialized, isFalse);
    expect(PlayService.playbackReady.value, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(ready.isObserved, isFalse);
    expect(track.isObserved, isFalse);
    track.value = 'After unmount';
    ready.value = false;
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a completed construction during build notifies after the frame',
      (tester) async {
    final ready = PlaybackReadiness();
    addTearDown(ready.dispose);
    late Object assigned;
    var created = false;
    await tester.pumpWidget(_host(Builder(builder: (_) {
      if (!created) {
        assigned = ready.initialize(Object.new);
        created = true;
      }
      return PlaybackReadyBuilder(
        readiness: ready,
        waitingBuilder: (_) => const Text('Waiting'),
        readyBuilder: (_) => Text('Ready: ${assigned.runtimeType}'),
      );
    })));
    await tester.pump();
    expect(find.text('Ready: Object'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(PlayService.isInitialized, isFalse);
  });

  for (final mini in [false, true]) {
    testWidgets(
        'actual ${mini ? 'mini adapter' : 'artwork background'} cold mount does not create a player',
        (tester) async {
      expect(PlayService.isInitialized, isFalse);
      expect(PlayService.playbackReady.value, isFalse);
      await tester.pumpWidget(_host(mini
          ? const CompactPlayer()
          : const BackgroundLayer(
              appearance:
                  BackgroundAppearance(source: BackgroundSource.artwork),
              status: WindowBackdropStatus(),
            )));
      await tester.pumpAndSettle();
      expect(find.byType(PlaybackReadyBuilder), findsOneWidget);
      expect(PlayService.isInitialized, isFalse);
      expect(PlayService.playbackReady.value, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  // The existing facade getter remains lazy. Creating only this facade is not
  // audio construction and must not unlock any live/background player getter.
  testWidgets(
      'an allocated facade without playback construction is still gated',
      (tester) async {
    final facade = PlayService.instance;
    expect(PlayService.isInitialized, isTrue);
    expect(PlayService.instance, same(facade));
    expect(PlayService.playbackReady.value, isFalse);
    await tester.pumpWidget(_host(const Stack(
      fit: StackFit.expand,
      children: [
        BackgroundLayer(
          appearance: BackgroundAppearance(source: BackgroundSource.artwork),
          status: WindowBackdropStatus(),
        ),
        CompactPlayer(),
      ],
    )));
    await tester.pumpAndSettle();
    expect(find.byType(PlaybackReadyBuilder), findsNWidgets(2));
    expect(PlayService.playbackReady.value, isFalse);
    expect(tester.takeException(), isNull);
  });
}
