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
}
