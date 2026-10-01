import 'dart:convert';

import 'package:dan_player/lyric/local_lyric_parser.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lyric_edit_codec.dart';
import 'package:dan_player/lyric/ttml.dart';
import 'package:flutter_test/flutter_test.dart';

String _ttml(String body,
        {bool apple = true, String attributes = '', String head = ''}) =>
    '<tt xmlns="http://www.w3.org/ns/ttml" '
    'xmlns:m="http://www.w3.org/ns/ttml#metadata" '
    'xmlns:p="http://www.w3.org/ns/ttml#parameter" '
    'xmlns:s="http://www.w3.org/ns/ttml#styling" '
    '${apple ? 'xmlns:a="http://music.apple.com/lyric-ttml-internal"' : ''} '
    '$attributes>$head<body><div>$body</div></body></tt>';

List<SyncLyricLine> _lines(String text) => parseTtmlLyric(text)
    .lines
    .whereType<SyncLyricLine>()
    .where((line) => line.content.trim().isNotEmpty)
    .toList();

void main() {
  test('Apple word timing is absolute and inline roles never enter original',
      () {
    final line = _lines(_ttml('''
<p begin="00:01.000" end="00:03.000">
<span begin="1s" end="1.5s">漢<span>字</span> &amp; </span><span begin="1500ms" dur="1500ms">👩🏽‍💻é</span>
<span m:role="x-translation">译<span>文</span></span><span m:role="x-roman">kanji</span>
</p>''')).single;
    expect(line.start.inMilliseconds, 1000);
    expect(line.length.inMilliseconds, 2000);
    expect(line.content, '漢字 & 👩🏽‍💻é');
    expect(line.words.map((word) => word.start.inMilliseconds), [1000, 1500]);
    expect(line.words.map((word) => word.length.inMilliseconds), [500, 1500]);
    expect(line.translation, '译文');
    expect(line.romanization, 'kanji');
    final restored = LyricSnapshot.capture(parseTtmlLyric(_ttml('''
<p begin="1s" end="3s"><span begin="1s" end="3s">👩🏽‍💻é</span></p>''')))
        .toLyric();
    expect((restored.lines.single as SyncLyricLine).content, '👩🏽‍💻é');
  });

  test('standard TTML containers and spans use relative media intervals', () {
    const document = '''<t:tt xmlns:t="http://www.w3.org/ns/ttml">
<t:body begin="10s"><t:div dur="4s"><t:p begin="1s" end="3s">(
<t:span begin=".25s" dur=".75s">Hello </t:span><t:span begin="1s" dur="1s">world</t:span>)</t:p>
</t:div></t:body></t:tt>''';
    final line = _lines(document).single;
    expect(line.start.inMilliseconds, 11000);
    expect(line.length.inMilliseconds, 2000);
    expect(line.words.map((word) => word.start.inMilliseconds), [11250, 12000]);
    expect(line.words.map((word) => word.length.inMilliseconds), [750, 1000]);
    expect(line.content, '( Hello world)');
  });

  test('line durations accept clocks seconds and fractional milliseconds', () {
    for (final entry in [
      ('01:02.125', '1.25s', 62125, 1250),
      ('01:01:02.125', '1250ms', 3662125, 1250),
      ('62.125s', '1250.4ms', 62125, 1250),
      ('62.125', '1250.5ms', 62125, 1251),
    ]) {
      final line = _lines(
              _ttml('<p begin="${entry.$1}" dur="${entry.$2}">whole line</p>'))
          .single;
      expect(line.start.inMilliseconds, entry.$3);
      expect(line.length.inMilliseconds, entry.$4);
      expect(line.words.single.content, 'whole line');
    }
  });

  test('a line can derive its end from fully timed children without truncation',
      () {
    final line = _lines(_ttml('''<p begin="1s">
<span begin="1s" end="1.4s">first</span> <span begin="1.5s" dur=".5s">last</span>!</p>'''))
        .single;
    expect(line.length.inMilliseconds, 1000);
    expect(line.content, 'first last!');
    expect(line.words.last.length.inMilliseconds, 500);
  });

  test('CDATA entities nested text and explicit line breaks retain characters',
      () {
    final line = _lines(_ttml(
            '''<p begin="1s" end="2s">&#x1F388; &lt;<span><![CDATA[&not-an-entity; <!DOCTYPE literal>]]></span><br/>后&#233;</p>'''))
        .single;
    expect(line.content, '🎈 <&not-an-entity; <!DOCTYPE literal>\n后é');
    final draft = LyricEditDraft.importBytes(
        utf8.encode(_ttml('''<p begin="1s" end="2s">one<br/>two</p>''')),
        'local.TTML');
    expect(draft.format, LyricEditFormat.lossless);
    expect((draft.parse().lines.single as SyncLyricLine).content, 'one\ntwo');
  });

  test('xml space inheritance preserves intentional spaces and role text', () {
    final line = _lines(_ttml(
            '''<p begin="1s" end="2s">  A <span> B </span>  <span m:role="x-translation"> 译文 </span></p>''',
            attributes: 'xml:space="preserve"'))
        .single;
    expect(line.content, '  A  B   ');
    expect(line.translation, ' 译文 ');
    final collapsed = _lines(_ttml('''<p begin="1s" end="2s">
<span> A </span><!-- boundary --> <span> B </span>
<span m:role="x-translation"><span> C </span> <span> D </span></span>
</p>''')).single;
    expect(collapsed.content, 'A B');
    expect(collapsed.translation, 'C D');
  });

  test('explicit background vocals and ruby roles are kept on separate axes',
      () {
    final lines = _lines(_ttml('''<p begin="1s" end="2s">
<span s:ruby="container"><span s:ruby="base">歌</span><span s:ruby="textContainer"><span s:ruby="text">うた</span></span></span>
<span m:role="x-bg"><span begin="1s" end="2s">backup</span><span m:role="x-translation">和声</span></span></p>'''));
    final main = lines.singleWhere((line) => line.content.trim() == '歌');
    final background = lines.singleWhere((line) => line.content == 'backup');
    expect(main.romanization, 'うた');
    expect(background.translation, '和声');
  });

  test('head sidecars reference explicit keys and merge duplicate inline roles',
      () {
    const head = '''<head><metadata><a:iTunesMetadata>
<a:translations><a:translation xml:lang="zh"><a:text for="L1">译文</a:text></a:translation></a:translations>
<a:transliterations><a:transliteration><a:text for="L1">roma</a:text></a:transliteration></a:transliterations>
</a:iTunesMetadata></metadata></head>''';
    final line = _lines(_ttml(
            '''<p begin="1s" end="2s" a:key="L1">original<span m:role="x-translation">译文</span></p>''',
            head: head))
        .single;
    expect(line.content, 'original');
    expect(line.translation, '译文');
    expect(line.romanization, 'roma');
  });

  test('role paragraphs match originals while unmarked voices remain originals',
      () {
    final text = _ttml('''<p begin="1s" end="2s" xml:id="L1">original</p>
<p begin="1s" end="2s" m:role="x-translation">translation</p>
<p for="L1" m:role="x-roman">romanization</p>''');
    final line = _lines(text).single;
    expect(line.translation, 'translation');
    expect(line.romanization, 'romanization');
    final unmarked =
        _ttml('''<p begin="1s" end="2s">甲</p><p begin="1s" end="2s">乙</p>''');
    for (final order in LocalLyricLineOrder.values) {
      final lyric =
          parseLocalLyricText(unmarked, extension: '.ttml', lineOrder: order)!;
      expect(lyric.lines.map((line) => (line as SyncLyricLine).content),
          ['甲', '乙']);
      expect(lyric.lines.every((line) => line.romanization == null), isTrue);
    }
  });

  test('DTD external entities unknown entities and illegal XML characters fail',
      () {
    for (final text in [
      '<!DOCTYPE tt SYSTEM "file:///private.txt">${_ttml('<p begin="1s" end="2s">x</p>')}',
      '<!DOCTYPE tt [<!ENTITY x "secret">]>${_ttml('<p begin="1s" end="2s">&x;</p>')}',
      _ttml('<p begin="1s" end="2s">&unknown;</p>'),
      _ttml('<p begin="1s" end="2s">&amp</p>'),
      _ttml('<p begin="1s" end="2s">&#xD800;</p>'),
      _ttml('<p begin="1s" end="2s">\u0000</p>'),
      _ttml('<p begin="1s" end="2s">${String.fromCharCode(0xd800)}</p>'),
    ]) {
      expect(() => parseTtmlLyric(text), throwsFormatException);
    }
  });

  test(
      'unsupported time bases metrics and sequential containers fail explicitly',
      () {
    for (final value in [
      '20f',
      '2t',
      'wallclock(12:00:00)',
      '01:02:03:04',
      'NaNs',
      '-1s',
      '00:60:00'
    ]) {
      expect(() => parseTtmlLyric(_ttml('<p begin="$value" dur="1s">x</p>')),
          throwsFormatException);
    }
    for (final attributes in [
      'p:timeBase="smpte"',
      'p:timeBase="clock"',
      'timeContainer="seq"'
    ]) {
      expect(
          () => parseTtmlLyric(
              _ttml('<p begin="1s" dur="1s">x</p>', attributes: attributes)),
          throwsFormatException);
    }
    expect(() => parseTtmlLyric(_ttml('<p begin="1s">unbounded</p>')),
        throwsFormatException);
  });

  test('overflowing times and out of order or out of range words cannot wrap',
      () {
    for (final body in [
      '<p begin="9223372036854775807:00:00" dur="1s">x</p>',
      '<p begin="999999999999999999999999s" dur="1s">x</p>',
      '<p begin="1s" end="2s"><span begin="1.8s" end="2s">later</span><span begin="1.2s" end="1.5s">earlier</span></p>',
      '<p begin="1s" end="2s"><span begin="1s" end="3s">outside</span></p>',
      '<p begin="2s" end="1s">backward</p>',
    ]) {
      expect(() => parseTtmlLyric(_ttml(body)), throwsFormatException);
    }
  });

  test('malformed namespaces unsupported visible nodes and orphan roles fail',
      () {
    for (final text in [
      '<unknown><body><p begin="1s" end="2s">x</p></body></unknown>',
      '<bad:tt><body><p begin="1s" end="2s">x</p></body></bad:tt>',
      _ttml('<p begin="1s" end="2s">before<b>hidden</b>after</p>'),
      _ttml('<p begin="1s" end="2s">before<br>hidden</br>after</p>'),
      _ttml('<p begin="1s" end="2s"><span xml:space="unknown">x</span></p>'),
      _ttml('<p begin="1s" end="2s">x</p>', attributes: 'xmlns:xml="wrong"'),
      _ttml('<![CDATA[hidden]]><p begin="1s" end="2s">x</p>'),
      _ttml('<p for="missing" m:role="x-translation">orphan</p>'),
      _ttml('<p begin="1s" end="2s">x</p>'
          '<p begin="2s" end="3s"><span m:role="x-translation">orphan</span></p>'),
      _ttml('<p begin="1s" end="2s">open'),
    ]) {
      expect(() => parseTtmlLyric(text), throwsFormatException);
    }
  });

  test('byte node and depth bounds reject oversized XML before DOM allocation',
      () {
    expect(
        () =>
            parseTtmlLyric(_ttml('<p begin="1s" end="2s">${'汉' * 700000}</p>')),
        throwsFormatException);
    expect(
        () => parseTtmlLyric(_ttml(
            '<p begin="1s" end="2s">${'<span>' * 129}x${'</span>' * 129}</p>')),
        throwsFormatException);
    expect(
        () => parseTtmlLyric(
            _ttml('<p begin="1s" end="2s">${'<span/>' * 100000}</p>')),
        throwsFormatException);
    expect(
        () => parseTtmlLyric(_ttml(
            '<p begin="1s" end="2s" ${List.generate(129, (i) => 'x$i="a"').join(' ')}>x</p>')),
        throwsFormatException);
  });
}
