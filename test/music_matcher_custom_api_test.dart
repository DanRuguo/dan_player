import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("custom lyric API uses metadata query and parses LRC JSON", () async {
    final requests = <Uri>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    late final StreamSubscription subscription;

    subscription = server.listen((request) {
      requests.add(request.uri);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          "type": "lrc",
          "lyric": "[00:01.00]Hello\n[00:02.00]World",
          "translation": "[00:01.00]你好",
        }),
      );
      request.response.close();
    });

    final previousApi = AppSettings.instance.lyricApiUrl;
    AppSettings.instance.lyricApiUrl =
        "http://127.0.0.1:${server.port}/lyric?token=abc";

    try {
      final audio = Audio(
        "Tagged Title",
        "Artist Name",
        "Album Name",
        0,
        123,
        null,
        null,
        r"C:\Music\File Name.mp3",
        0,
        0,
        null,
      );

      final lyric = await getMostMatchedLyric(audio);

      expect(lyric, isA<Lrc>());
      expect(requests, hasLength(1));
      expect(requests.single.queryParameters["token"], "abc");
      expect(requests.single.queryParameters["title"], "Tagged Title");
      expect(requests.single.queryParameters["artist"], "Artist Name");
      expect(requests.single.queryParameters["album"], "Album Name");
      expect(requests.single.queryParameters["duration"], "123");
      expect(requests.single.queryParameters["fileName"], "File Name");
      expect(requests.single.queryParameters["displayTitle"], "File Name");

      final lines = (lyric as Lrc).lines.cast<LrcLine>();
      expect(lines, hasLength(2));
      expect(lines.first.content, "Hello┃你好");
      expect(lines.last.content, "World");
    } finally {
      AppSettings.instance.lyricApiUrl = previousApi;
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test("custom lyric API connectivity reports recognized lyrics", () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    late final StreamSubscription subscription;

    subscription = server.listen((request) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          "type": "lrc",
          "lyric": "[00:01.00]Probe",
        }),
      );
      request.response.close();
    });

    try {
      final result = await testLyricApiConnectivity(
        "http://127.0.0.1:${server.port}/lyric",
      );

      expect(result.isReachable, isTrue);
      expect(result.lyricRecognized, isTrue);
      expect(result.statusCode, 200);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test("custom lyric API connectivity reports HTTP failure", () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    late final StreamSubscription subscription;

    subscription = server.listen((request) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write("error");
      request.response.close();
    });

    try {
      final result = await testLyricApiConnectivity(
        "http://127.0.0.1:${server.port}/lyric",
      );

      expect(result.isReachable, isFalse);
      expect(result.lyricRecognized, isFalse);
      expect(result.statusCode, HttpStatus.internalServerError);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
