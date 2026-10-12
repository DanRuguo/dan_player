import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/lyric/japanese_phonetic_channel.dart';
import 'package:dan_player/lyric/japanese_reading_preferences.dart';
import 'package:dan_player/online/app_network_proxy.dart';

typedef JapaneseOnlineRequest = Future<Map<String, dynamic>> Function(
    Map<String, dynamic> body, String clientId, bool Function() active);

/// Yahoo! JAPAN's documented furigana API. Credentials are supplied by the
/// user, never embedded. One owner, a finite deadline and exact source alignment
/// prevent late replies from changing another song or inventing ruby offsets.
class JapaneseOnlineReadingAnalyzer {
  JapaneseOnlineReadingAnalyzer({
    this.request,
    this.timeout = const Duration(seconds: 6),
    this.httpClientFactory,
    this.endpoint,
  });
  final JapaneseOnlineRequest? request;
  final Duration timeout;
  // Transport injection for isolated loopback tests; no setting accepts a URL.
  final HttpClient Function()? httpClientFactory;
  final Uri? endpoint;
  HttpClient? _client;
  HttpClientRequest? _request;
  int _generation = 0;
  static final _white = RegExp(r'^\s+$', unicode: true);
  static final _kana =
      RegExp(r'^[\u3041-\u3096\u309D-\u309F\u30A1-\u30FA\u30FC-\u30FF]+$');
  static const _unavailable = JapanesePhoneticBatch([], available: false);

  void cancel() {
    _generation++;
    _request?.abort();
    _client?.close(force: true);
    _request = null;
    _client = null;
  }

  Future<JapanesePhoneticBatch> analyze(
    List<String> chunks, {
    required String clientId,
    required bool Function() stillCurrent,
  }) async {
    cancel();
    final generation = _generation;
    bool active() => generation == _generation && stillCurrent();
    if (!active() ||
        clientId.isEmpty ||
        normalizeJapaneseReadingClientId(clientId) != clientId ||
        chunks.isEmpty ||
        chunks.length > 16 ||
        chunks.any((text) => text.isEmpty || text.length > 100)) {
      return _unavailable;
    }
    final watch = Stopwatch()..start();
    final result = <List<JapanesePhoneticWord>?>[];
    try {
      var start = 0;
      while (start < chunks.length) {
        if (!active()) return _unavailable;
        var end = start + 1;
        Map<String, dynamic> bodyFor(int stop) => {
              'id': '$generation-$start',
              'jsonrpc': '2.0',
              'method': 'jlp.furiganaservice.furigana',
              'params': {
                'q': chunks.sublist(start, stop).join('\n'),
                'grade': 1
              },
            };
        while (end < chunks.length &&
            utf8.encode(jsonEncode(bodyFor(end + 1))).length <= 4096) {
          end++;
        }
        final body = bodyFor(end);
        if (utf8.encode(jsonEncode(body)).length > 4096) return _unavailable;
        final remaining = timeout - watch.elapsed;
        if (remaining <= Duration.zero) return _unavailable;
        final response =
            await (request ?? _send)(body, clientId, active).timeout(remaining);
        if (!active() ||
            response['jsonrpc'] != '2.0' ||
            response['id'] != body['id'] ||
            response.containsKey('error')) {
          return _unavailable;
        }
        final value = response['result'];
        if (value is! Map || value['word'] is! List) return _unavailable;
        final text = chunks.sublist(start, end).join('\n');
        final words = _align(text, value['word'] as List);
        if (words == null) return _unavailable;
        final split = _split(chunks.sublist(start, end), words);
        if (split == null) return _unavailable;
        result.addAll(split);
        start = end;
      }
      return active()
          ? JapanesePhoneticBatch(List.unmodifiable(result),
              cacheNamespace: 'online/${sha256.convert(utf8.encode(clientId))}')
          : _unavailable;
    } catch (_) {
      // Protocol/auth/network failure is an ordinary offline fallback. Do not
      // expose request headers, credentials or the user's lyric text in errors.
      return _unavailable;
    } finally {
      if (generation == _generation) {
        _client?.close(force: true);
        _client = null;
        _request = null;
      }
    }
  }

  Future<Map<String, dynamic>> _send(Map<String, dynamic> body, String clientId,
      bool Function() active) async {
    if (!active()) throw const FormatException('Obsolete reading request');
    final client = _client ??= httpClientFactory?.call() ??
        AppNetworkProxy.createHttpClient(
            preferences: AppSettings.instance.networkProxy.value);
    client.connectionTimeout = timeout;
    final next = await client
        .postUrl(endpoint ?? Uri.https('jlp.yahooapis.jp', '/jsonrpc'));
    if (!active()) {
      next.abort();
      throw const FormatException('Obsolete reading request');
    }
    _request = next;
    next.followRedirects = false;
    next.headers.set(HttpHeaders.userAgentHeader, 'Yahoo AppID: $clientId');
    next.headers.contentType = ContentType.json;
    next.add(utf8.encode(jsonEncode(body)));
    final response = await next.close();
    if (!active() ||
        response.statusCode != HttpStatus.ok ||
        response.contentLength > 64 * 1024) {
      throw const FormatException('Reading service unavailable');
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      if (!active() || bytes.length + chunk.length > 64 * 1024) {
        throw const FormatException('Reading response exceeds limit');
      }
      bytes.addAll(chunk);
    }
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid reading response');
    }
    return json;
  }

  static List<JapanesePhoneticWord>? _align(String source, List raw,
      [int depth = 0]) {
    if (raw.length > 4096 || depth > 2) return null;
    final flat = <JapanesePhoneticWord>[];
    for (final entry in raw) {
      if (entry is! Map ||
          entry['surface'] is! String ||
          (entry['surface'] as String).isEmpty) {
        return null;
      }
      final surface = entry['surface'] as String;
      final sub = entry['subword'];
      if (sub is List && sub.isNotEmpty) {
        final parts = _align(surface, sub, depth + 1);
        if (parts == null) return null;
        flat.addAll(parts);
      } else {
        final reading = entry['furigana'];
        if (reading != null &&
            (reading is! String ||
                reading.length > 4 * surface.length + 16 ||
                !_kana.hasMatch(reading))) {
          return null;
        }
        flat.add(JapanesePhoneticWord(surface, reading as String? ?? surface));
      }
    }
    final aligned = <JapanesePhoneticWord>[];
    var offset = 0;
    for (final word in flat) {
      final found = source.indexOf(word.text, offset);
      if (found < offset) return null;
      if (found > offset) {
        final gap = source.substring(offset, found);
        if (!_white.hasMatch(gap)) return null;
        aligned.add(JapanesePhoneticWord(gap, gap));
      }
      aligned.add(word);
      offset = found + word.text.length;
    }
    if (offset < source.length) {
      final tail = source.substring(offset);
      if (!_white.hasMatch(tail)) return null;
      aligned.add(JapanesePhoneticWord(tail, tail));
    }
    return aligned;
  }

  static List<List<JapanesePhoneticWord>>? _split(
      List<String> chunks, List<JapanesePhoneticWord> words) {
    final output = <List<JapanesePhoneticWord>>[];
    var wordIndex = 0, inWord = 0;
    for (var i = 0; i < chunks.length; i++) {
      final group = <JapanesePhoneticWord>[];
      var left = chunks[i].length;
      while (left > 0) {
        if (wordIndex >= words.length) return null;
        final word = words[wordIndex];
        final available = word.text.length - inWord;
        final take = available < left ? available : left;
        if ((inWord != 0 || take != word.text.length) &&
            !_white.hasMatch(word.text)) {
          return null;
        }
        final text = word.text.substring(inWord, inWord + take);
        group.add(JapanesePhoneticWord(
            text, take == word.text.length ? word.reading : text));
        inWord += take;
        left -= take;
        if (inWord == word.text.length) {
          wordIndex++;
          inWord = 0;
        }
      }
      output.add(List.unmodifiable(group));
      if (i < chunks.length - 1) {
        if (wordIndex >= words.length ||
            words[wordIndex].text.codeUnitAt(inWord) != 10 ||
            !_white.hasMatch(words[wordIndex].text)) {
          return null;
        }
        inWord++;
        if (inWord == words[wordIndex].text.length) {
          wordIndex++;
          inWord = 0;
        }
      }
    }
    return wordIndex == words.length && inWord == 0 ? output : null;
  }
}
