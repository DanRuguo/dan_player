import 'dart:convert';

import 'package:desktop_lyric/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("desktop lyric messages are newline framed", () {
    const message = PlayerStateChangedMessage(true);
    final encoded = message.buildMessageJson();

    expect(encoded.endsWith("\n"), isTrue);
    final lines = const LineSplitter().convert(encoded);
    expect(lines, hasLength(1));
    expect(json.decode(lines.single)["type"], "PlayerStateChangedMessage");
  });

  test('desktop lyric timeline message round-trips word timing', () {
    const message = LyricLineTimelineMessage(
      sequence: 7,
      lineIndex: 3,
      startMilliseconds: 1200,
      lengthMilliseconds: 2400,
      content: '你好世界',
      translation: 'Hello world',
      romanization: 'ni hao shi jie',
      words: [
        DesktopLyricWord(1200, 900, '你好'),
        DesktopLyricWord(2100, 1500, '世界'),
      ],
    );

    final envelope = json.decode(message.buildMessageJson());
    final decoded = LyricLineTimelineMessage.fromJson(
      Map<String, dynamic>.from(envelope['message']),
    );

    expect(envelope['type'], 'LyricLineTimelineMessage');
    expect(decoded.sequence, 7);
    expect(decoded.lineIndex, 3);
    expect(decoded.translation, 'Hello world');
    expect(decoded.romanization, 'ni hao shi jie');
    expect(decoded.words, hasLength(2));
    expect(decoded.words.last.startMilliseconds, 2100);
    expect(decoded.words.last.content, '世界');
  });

  test('older detailed JSON without pronunciation and legacy JSON stay valid',
      () {
    final detailed = LyricLineTimelineMessage.fromJson({
      'sequence': 1,
      'lineIndex': 0,
      'content': '你好',
      'translation': 'Hello',
      'words': const [],
    });
    expect(detailed.romanization, isNull);
    const legacy =
        LyricLineChangedMessage('你好', Duration(seconds: 2), 'Hello');
    final envelope = json.decode(legacy.buildMessageJson());
    expect(envelope['message'].containsKey('romanization'), isFalse);
    expect(
        LyricLineChangedMessage.fromJson(
                Map<String, dynamic>.from(envelope['message']))
            .translation,
        'Hello');
  });

  test('playback timeline keeps the song sequence and clock', () {
    const message = PlaybackTimelineMessage(11, 54321, true);
    final envelope = json.decode(message.buildMessageJson());
    final decoded = PlaybackTimelineMessage.fromJson(
      Map<String, dynamic>.from(envelope['message']),
    );

    expect(decoded.sequence, 11);
    expect(decoded.positionMilliseconds, 54321);
    expect(decoded.playing, isTrue);
  });
}
