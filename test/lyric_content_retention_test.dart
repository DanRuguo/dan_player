import 'package:desktop_lyric/lyric_ruby.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:desktop_lyric/lyric_content_reveal.dart';

class _Span implements LyricRubySpan {
  const _Span(this.text);
  @override
  int get start => 0;
  @override
  int get end => 2;
  @override
  final String text;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const spans = [_Span('よぞら')];
  const owner = ('document-1', 0);
  LyricContentVisibility? last;
  var ends = 0;
  Widget host({
    bool visible = true,
    List<LyricRubySpan> data = spans,
    Object? source = owner,
    bool reduced = false,
    Object? transition,
  }) => MaterialApp(
    home: LyricContentReveal(
      timestamp: false,
      romanization: false,
      translation: false,
      japaneseReading: visible,
      japaneseReadingSpans: data,
      japaneseReadingSource: source,
      japaneseReadingTransitionIdentity: transition,
      reducedMotion: reduced,
      onEnd: () => ends++,
      builder: (_, value) {
        last = value;
        return const SizedBox(width: 50, height: 50);
      },
    ),
  );
  setUp(() {
    last = null;
    ends = 0;
  });

  testWidgets(
    'shared reveal retains only same-owner spans through closing zero',
    (tester) async {
      await tester.pumpWidget(host());
      final accepted = last!.japaneseReadingSpans;
      expect(accepted.single, same(spans.single));
      await tester.pumpWidget(host(visible: false, data: const []));
      await tester.pump(const Duration(milliseconds: 240));
      expect(last!.japaneseReading, greaterThan(0));
      expect(last!.japaneseReading, lessThan(1));
      expect(last!.japaneseReadingSpans, same(accepted));
      expect(ends, 0);
      await tester.pumpAndSettle();
      expect(last!.japaneseReading, 0);
      expect(last!.japaneseReadingSpans, isEmpty);
      expect(ends, 1);
      await tester.pumpWidget(host(visible: true, data: const []));
      await tester.pumpAndSettle();
      expect(
        last!.japaneseReadingSpans,
        isEmpty,
        reason: 'No closed data resurrects',
      );
    },
  );

  testWidgets(
    'shared reveal new or absent source never retains outgoing spans',
    (tester) async {
      for (final source in [null, ('replacement-document', 0)]) {
        await tester.pumpWidget(host());
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          host(visible: false, data: const [], source: source),
        );
        await tester.pump(const Duration(milliseconds: 120));
        expect(last!.japaneseReadingSpans, isEmpty);
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(host(source: null));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        host(visible: false, source: null, data: const []),
      );
      expect(last!.japaneseReadingSpans, isEmpty);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'shared reveal reduced or hidden endpoint releases spans immediately',
    (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpWidget(host(visible: false, data: const []));
      await tester.pump(const Duration(milliseconds: 120));
      expect(last!.japaneseReadingSpans, isNotEmpty);
      await tester.pumpWidget(
        host(visible: false, data: const [], reduced: true),
      );
      expect(last!.japaneseReading, 0);
      expect(last!.japaneseReadingSpans, isEmpty);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'shared reveal rapid reopen keeps current scalar and valid new spans',
    (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpWidget(host(visible: false, data: const []));
      await tester.pump(const Duration(milliseconds: 120));
      final before = last!.japaneseReading;
      const replacement = [_Span('そら')];
      await tester.pumpWidget(host(data: replacement));
      expect(last!.japaneseReading, before);
      expect(last!.japaneseReadingSpans.single, same(replacement.single));
      await tester.pumpAndSettle();
      expect(last!.japaneseReading, 1);
      expect(ends, 1);
    },
  );

  testWidgets(
    'shared reveal partial availability triggers owner end without fake local reading',
    (tester) async {
      await tester.pumpWidget(
        host(visible: false, data: const [], transition: (true, 0)),
      );
      await tester.pumpWidget(
        host(visible: false, data: const [], transition: (true, 1)),
      );
      await tester.pump(const Duration(milliseconds: 240));
      expect(last!.japaneseReading, 0);
      expect(last!.japaneseReadingSpans, isEmpty);
      expect(ends, 0);
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpAndSettle();
      expect(ends, 1);
      expect(last!.japaneseReading, 0);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'shared reveal omitted ownership keeps ordinary four-scalar behavior',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LyricContentReveal(
            timestamp: false,
            romanization: false,
            translation: false,
            reducedMotion: false,
            builder: (_, value) {
              last = value;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(last!.timestamp, 0);
      expect(last!.romanization, 0);
      expect(last!.japaneseReading, 0);
      expect(last!.translation, 0);
      expect(last!.japaneseReadingSpans, isEmpty);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    },
  );
}
