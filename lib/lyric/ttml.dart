import 'dart:convert';

import 'package:dan_player/lyric/lyric_text_codec.dart';
import 'package:dan_player/lyric/lyric_timeline.dart';
import 'package:dan_player/lyric/qrc.dart';
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

const _ttmlNamespaces = {
  null,
  'http://www.w3.org/ns/ttml',
  'http://www.w3.org/2006/10/ttaf1',
};
const _appleNamespaces = {
  'http://music.apple.com/lyric-ttml-internal',
  'http://itunes.apple.com/lyric-ttml-extensions',
};
const _metadataNamespaces = {
  null,
  'http://www.w3.org/ns/ttml#metadata',
  'http://www.w3.org/2006/10/ttaf1#metadata',
};
const _parameterNamespaces = {
  null,
  'http://www.w3.org/ns/ttml#parameter',
  'http://www.w3.org/2006/10/ttaf1#parameter',
};
const _xmlNamespace = 'http://www.w3.org/XML/1998/namespace';

/// Reads the bounded local TTML lyric subset into the existing word timeline.
/// Apple lyric files use global word timestamps; standard TTML media timing
/// is relative to its containing element. No styling, URI or entity is fetched.
Qrc parseTtmlLyric(String text) {
  if (utf8.encode(text).length > maxLyricTextBytes) {
    throw const FormatException('歌词文件过大');
  }
  final units = text.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final code = units[i];
    if (code >= 0xd800 && code <= 0xdbff) {
      if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
        throw const FormatException('TTML 结构无效');
      }
    } else if ((code >= 0xdc00 && code <= 0xdfff) ||
        code == 0xfffe ||
        code == 0xffff ||
        (code < 0x20 && code != 9 && code != 10 && code != 13)) {
      throw const FormatException('TTML 结构无效');
    }
  }
  XmlDocument document;
  try {
    var nodes = 0, depth = 0;
    for (final event in parseEvents(text,
        entityMapping: const _TtmlEntities(),
        validateNesting: true,
        validateDocument: true)) {
      if (event is XmlDoctypeEvent) {
        throw const FormatException('TTML 不支持 DTD 或外部实体');
      }
      nodes++;
      if (event is XmlStartElementEvent) {
        nodes += event.attributes.length;
        if (!event.isSelfClosing) depth++;
      } else if (event is XmlEndElementEvent) {
        depth--;
      }
      if (nodes > 100000 ||
          depth > 128 ||
          (event is XmlStartElementEvent && event.attributes.length > 128)) {
        throw const FormatException('TTML 节点过多或嵌套过深');
      }
    }
    document = XmlDocument.parse(text, entityMapping: const _TtmlEntities());
  } on XmlException catch (error) {
    throw FormatException('TTML 结构无效', error.toString());
  }
  final root = document.rootElement;
  if (!_isTtml(root, 'tt')) throw const FormatException('TTML 结构无效');
  return _TtmlReader(root).read();
}

/// Unknown or unterminated entities must not become literal, silently damaged
/// lyric text. The XML package never fetches external entities; DTD is rejected
/// before its DOM is built as well.
class _TtmlEntities extends XmlEntityMapping {
  const _TtmlEntities();

  @override
  String decode(String input) {
    final out = StringBuffer();
    var cursor = 0;
    while (true) {
      final start = input.indexOf('&', cursor);
      if (start < 0) {
        out.write(input.substring(cursor));
        return out.toString();
      }
      out.write(input.substring(cursor, start));
      final end = input.indexOf(';', start + 1);
      final next = input.indexOf('&', start + 1);
      if (end < 0 || (next >= 0 && next < end)) {
        throw const FormatException('TTML 包含无效字符实体');
      }
      out.write(decodeEntity(input.substring(start + 1, end)));
      cursor = end + 1;
    }
  }

  @override
  String decodeEntity(String input) {
    if (input.startsWith('#')) {
      final hex = input.startsWith('#x');
      final code =
          int.tryParse(input.substring(hex ? 2 : 1), radix: hex ? 16 : 10);
      if (code == null ||
          !(code == 9 ||
              code == 10 ||
              code == 13 ||
              (code >= 0x20 && code <= 0xd7ff) ||
              (code >= 0xe000 && code <= 0xfffd) ||
              (code >= 0x10000 && code <= 0x10ffff))) {
        throw const FormatException('TTML 包含无效字符实体');
      }
    }
    final value = defaultEntityMapping.decodeEntity(input);
    if (value == null) {
      throw const FormatException('TTML 包含无效字符实体');
    }
    return value;
  }

  @override
  String encodeText(String input) => defaultEntityMapping.encodeText(input);
  @override
  String encodeAttributeValue(String input, XmlAttributeType type) =>
      defaultEntityMapping.encodeAttributeValue(input, type);
}

bool _isTtml(XmlElement element, String name) =>
    element.localName == name && _ttmlNamespaces.contains(element.namespaceUri);

String? _attribute(XmlElement element, String name, Set<String?> namespaces) {
  for (final attribute in element.attributes) {
    if (attribute.localName == name &&
        namespaces.contains(_attributeNamespace(attribute))) {
      return attribute.value;
    }
  }
  return null;
}

String? _attributeNamespace(XmlAttribute attribute) {
  // XML's default namespace applies to elements only. The package also needs
  // the reserved xml prefix resolved explicitly when it is not declared.
  if (attribute.namespacePrefix == null) return null;
  if (attribute.namespacePrefix == 'xml') return _xmlNamespace;
  return attribute.namespaceUri;
}

String? _role(XmlElement element) {
  final roles =
      _attribute(element, 'role', _metadataNamespaces)?.split(RegExp(r'\s+'));
  if (roles?.contains('x-translation') == true) return 'translation';
  if (roles?.any((role) =>
          role == 'x-roman' ||
          role == 'x-romanization' ||
          role == 'x-transliteration') ==
      true) {
    return 'romanization';
  }
  final ruby =
      _attribute(element, 'ruby', {'http://www.w3.org/ns/ttml#styling', null});
  if (ruby == 'text' || ruby == 'textContainer') return 'romanization';
  if (roles?.contains('x-bg') == true) return 'background';
  return null;
}

bool _preserveSpace(XmlElement element) {
  XmlNode? current = element;
  while (current is XmlElement) {
    final value = _attribute(current, 'space', {_xmlNamespace});
    if (value != null) {
      if (value != 'preserve' && value != 'default') {
        throw const FormatException('TTML 结构无效');
      }
      return value == 'preserve';
    }
    current = current.parent;
  }
  return false;
}

class _Window {
  const _Window(this.start, this.end);
  final int start;
  final int? end;
}

class _Piece {
  _Piece(this.text, this.window, this.preserve);
  String text;
  final _Window? window;
  final bool preserve;
}

void _normalizeSpace(List<_Piece> pieces) {
  for (final piece in pieces) {
    if (piece.preserve) break;
    piece.text = piece.text.trimLeft();
    if (piece.text.isNotEmpty) break;
  }
  for (final piece in pieces.reversed) {
    if (piece.preserve) break;
    piece.text = piece.text.trimRight();
    if (piece.text.isNotEmpty) break;
  }
  _Piece? previous;
  for (final piece in pieces) {
    if (piece.text.isEmpty) continue;
    if (previous != null &&
        !previous.preserve &&
        !piece.preserve &&
        previous.text.endsWith(' ') &&
        piece.text.startsWith(' ')) {
      piece.text = piece.text.substring(1);
    }
    if (piece.text.isNotEmpty) previous = piece;
  }
}

class _Row {
  _Row(this.line, this.key, this.translation, this.romanization,
      {this.background = false});
  final QrcLine line;
  final String? key;
  final List<String> translation, romanization;
  final bool background;
}

class _Auxiliary {
  const _Auxiliary(this.role, this.text, {this.key, this.start});
  final String role, text;
  final String? key;
  final int? start;
}

class _TtmlReader {
  _TtmlReader(this.root)
      : absolute = root.descendants
            .whereType<XmlElement>()
            .followedBy([root]).any((element) => element.attributes.any(
                (attribute) =>
                    (attribute.name.prefix == 'xmlns' ||
                        attribute.name.qualified == 'xmlns') &&
                    _appleNamespaces.contains(attribute.value)));

  final XmlElement root;
  final bool absolute;
  final rows = <_Row>[];
  final auxiliary = <_Auxiliary>[];

  Qrc read() {
    for (final element
        in root.descendants.whereType<XmlElement>().followedBy([root])) {
      if ((element.namespacePrefix != null && element.namespaceUri == null) ||
          element.attributes.any((attribute) =>
              attribute.namespacePrefix != null &&
              attribute.namespacePrefix != 'xmlns' &&
              attribute.namespacePrefix != 'xml' &&
              attribute.namespaceUri == null)) {
        throw const FormatException('TTML 结构无效');
      }
      if (element.attributes.any((attribute) =>
          (attribute.name.qualified == 'xmlns:xml' &&
              attribute.value != _xmlNamespace) ||
          (attribute.namespacePrefix == 'xml' &&
              attribute.namespaceUri != null &&
              attribute.namespaceUri != _xmlNamespace))) {
        throw const FormatException('TTML 结构无效');
      }
      final base = _attribute(element, 'timeBase', _parameterNamespaces);
      final space = _attribute(element, 'space', {_xmlNamespace});
      if (space != null && space != 'default' && space != 'preserve') {
        throw const FormatException('TTML 结构无效');
      }
      if ((base != null && base != 'media') ||
          (element.getAttribute('timeContainer') != null &&
              element.getAttribute('timeContainer') != 'par')) {
        throw const FormatException('TTML 时间格式或时制不受支持');
      }
      for (final name in ['begin', 'end', 'dur']) {
        final value = element.getAttribute(name);
        if (value != null) _time(value);
      }
    }
    final bodies = root.childElements.where((child) => _isTtml(child, 'body'));
    if (bodies.length != 1) throw const FormatException('TTML 结构无效');
    _body(bodies.single, const _Window(0, null));
    _headAuxiliary();
    for (final item in auxiliary) {
      final candidates = rows.where((row) => item.key != null
          ? row.key == item.key
          : !row.background && row.line.start.inMilliseconds == item.start);
      if (candidates.length != 1) {
        throw const FormatException('TTML 辅助轨未匹配原文');
      }
      (item.role == 'translation'
              ? candidates.single.translation
              : candidates.single.romanization)
          .add(item.text);
    }
    if (rows.isEmpty || rows.length > 20000) {
      throw FormatException(rows.isEmpty ? '歌词不能为空' : '歌词文件过大');
    }
    for (final row in rows) {
      if (row.translation.isNotEmpty) {
        row.line.translation = row.translation.toSet().join('┃');
      }
      if (row.romanization.isNotEmpty) {
        row.line.romanization = row.romanization.toSet().join('┃');
      }
    }
    return Qrc(normalizeSyncLyricLines(rows.map((row) => row.line).toList(),
        (start, length) => QrcLine(start, length, [])));
  }

  int _time(String raw) {
    final value = raw.trim();
    if (value.length > 64) throw const FormatException('歌词时间超出范围');
    if (value.startsWith('-')) throw const FormatException('时间不能为负数');
    final clock =
        RegExp(r'^(?:(\d+):)?(\d{2}):(\d{2})(?:\.(\d+))?$').firstMatch(value);
    if (clock != null) {
      final hours = BigInt.parse(clock[1] ?? '0');
      final minutes = int.parse(clock[2]!);
      final seconds = int.parse(clock[3]!);
      if (minutes > 59 || seconds > 59) {
        throw const FormatException('TTML 时间格式或时制不受支持');
      }
      return _decimal(
          (hours * BigInt.from(3600) + BigInt.from(minutes * 60 + seconds))
              .toString(),
          clock[4] ?? '',
          1000);
    }
    final offset = RegExp(r'^(\d+)(?:\.(\d+))?(s|ms)?$')
        .firstMatch(value.startsWith('.') ? '0$value' : value);
    if (offset == null || (!absolute && offset[3] == null)) {
      throw const FormatException('TTML 时间格式或时制不受支持');
    }
    return _decimal(offset[1]!, offset[2] ?? '', offset[3] == 'ms' ? 1 : 1000);
  }

  int _decimal(String whole, String fraction, int unit) {
    final number = BigInt.parse('$whole$fraction') * BigInt.from(unit);
    final divisor = BigInt.from(10).pow(fraction.length);
    final milliseconds = (number + divisor ~/ BigInt.two) ~/ divisor;
    if (milliseconds > BigInt.from(9007199254740)) {
      throw const FormatException('歌词时间超出范围');
    }
    return milliseconds.toInt();
  }

  int _bounded(int value) {
    if (value < 0 || value > 9007199254740) {
      throw const FormatException('歌词时间超出范围');
    }
    return value;
  }

  _Window _window(XmlElement element, _Window parent) {
    final begin = element.getAttribute('begin');
    final end = element.getAttribute('end');
    final dur = element.getAttribute('dur');
    final base = absolute ? 0 : parent.start;
    final start = begin == null ? parent.start : _bounded(base + _time(begin));
    var stop = end == null ? parent.end : _bounded(base + _time(end));
    if (dur != null) {
      final candidate = _bounded(start + _time(dur));
      if (stop == null || candidate < stop) stop = candidate;
    }
    if ((stop != null && stop < start) || start < parent.start) {
      throw const FormatException('结束时间不能早于开始时间');
    }
    if (parent.end != null && stop != null && stop > parent.end!) {
      throw const FormatException('逐字时间超出所在行范围');
    }
    return _Window(start, stop);
  }

  String? _key(XmlElement element) =>
      _attribute(element, 'id', {_xmlNamespace}) ??
      _attribute(element, 'key', _appleNamespaces);

  void _body(XmlElement element, _Window parent) {
    final window = _window(element, parent);
    if (_isTtml(element, 'p')) {
      final role = _role(element);
      if (role == 'translation' || role == 'romanization') {
        auxiliary.add(_Auxiliary(role!, _text(element),
            key: element.getAttribute('for'), start: window.start));
      } else {
        _original(element, window, _key(element));
      }
      return;
    }
    for (final child in element.children) {
      if (child is XmlElement) {
        if (!_isTtml(child, 'div') && !_isTtml(child, 'p')) {
          throw const FormatException('TTML 正文包含不支持的元素');
        }
        _body(child, window);
      } else if ((child is XmlText && child.value.trim().isNotEmpty) ||
          (child is XmlCDATA && child.value.trim().isNotEmpty)) {
        throw const FormatException('TTML 正文包含不支持的元素');
      }
    }
  }

  void _original(XmlElement element, _Window window, String? key,
      {bool background = false}) {
    final pieces = <_Piece>[];
    final translations = <String>[], romanizations = <String>[];
    void collect(
        XmlElement parent, _Window interval, _Window? word, bool preserve) {
      final space = _attribute(parent, 'space', {_xmlNamespace});
      preserve = space == 'preserve' || (space == null && preserve);
      for (final child in parent.children) {
        if (child is XmlText || child is XmlCDATA) {
          final text =
              child is XmlText ? child.value : (child as XmlCDATA).value;
          pieces.add(_Piece(
              preserve ? text : text.replaceAll(RegExp(r'[\t\r\n ]+'), ' '),
              word,
              preserve));
        } else if (child is XmlElement) {
          if (_isTtml(child, 'br')) {
            _checkBreak(child);
            pieces.add(_Piece('\n', word, true));
            continue;
          }
          if (!_isTtml(child, 'span')) {
            throw const FormatException('TTML 正文包含不支持的元素');
          }
          final childWindow = _window(child, interval);
          final role = _role(child);
          if (role == 'translation' || role == 'romanization') {
            (role == 'translation' ? translations : romanizations)
                .add(_text(child));
          } else if (role == 'background') {
            _original(child, childWindow, _key(child), background: true);
          } else {
            final timed = ['begin', 'end', 'dur']
                .any((name) => child.getAttribute(name) != null);
            collect(child, childWindow, timed ? childWindow : word, preserve);
          }
        }
      }
    }

    collect(element, window, null, _preserveSpace(element));
    void checkOrphanRoles() {
      if (translations.any((text) => text.isNotEmpty) ||
          romanizations.any((text) => text.isNotEmpty)) {
        throw const FormatException('TTML 辅助轨未匹配原文');
      }
    }

    if (pieces.isEmpty) {
      checkOrphanRoles();
      return;
    }
    _normalizeSpace(pieces);
    final words = <QrcWord>[];
    var prefix = '';
    var end = window.end;
    for (final piece in pieces) {
      if (piece.text.isEmpty) continue;
      final timing = piece.window;
      if (timing == null) {
        if (words.isEmpty) {
          prefix += piece.text;
        } else {
          words.last.content += piece.text;
        }
        continue;
      }
      final stop = timing.end;
      if (stop == null) throw const FormatException('TTML 歌词行需要结束时间');
      if (end == null || (window.end == null && stop > end)) end = stop;
      if (words.isNotEmpty &&
          words.last.start.inMilliseconds == timing.start &&
          words.last.length.inMilliseconds == stop - timing.start) {
        words.last.content += piece.text;
      } else {
        words.add(QrcWord(Duration(milliseconds: timing.start),
            Duration(milliseconds: stop - timing.start), prefix + piece.text));
        prefix = '';
      }
    }
    if (end == null) throw const FormatException('TTML 歌词行需要结束时间');
    if (words.isEmpty) {
      if (prefix.trim().isEmpty) {
        checkOrphanRoles();
        return;
      }
      words.add(QrcWord(Duration(milliseconds: window.start),
          Duration(milliseconds: end - window.start), prefix));
    }
    var previous = window.start;
    for (final word in words) {
      final start = word.start.inMilliseconds;
      if (start < previous ||
          word.length.isNegative ||
          start + word.length.inMilliseconds > end) {
        throw const FormatException('逐字时间超出所在行范围');
      }
      previous = start;
    }
    rows.add(_Row(
        QrcLine(Duration(milliseconds: window.start),
            Duration(milliseconds: end - window.start), words),
        key,
        translations.where((text) => text.isNotEmpty).toList(),
        romanizations.where((text) => text.isNotEmpty).toList(),
        background: background));
  }

  String _text(XmlElement element) {
    final pieces = <_Piece>[];
    void collect(XmlElement parent, bool preserve) {
      final space = _attribute(parent, 'space', {_xmlNamespace});
      preserve = space == 'preserve' || (space == null && preserve);
      for (final child in parent.children) {
        if (child is XmlText || child is XmlCDATA) {
          final text =
              child is XmlText ? child.value : (child as XmlCDATA).value;
          pieces.add(_Piece(
              preserve ? text : text.replaceAll(RegExp(r'[\t\r\n ]+'), ' '),
              null,
              preserve));
        } else if (child is XmlElement) {
          if (_isTtml(child, 'br')) {
            _checkBreak(child);
            pieces.add(_Piece('\n', null, true));
          } else if (_isTtml(child, 'span')) {
            collect(child, preserve);
          } else {
            throw const FormatException('TTML 正文包含不支持的元素');
          }
        }
      }
    }

    collect(element, _preserveSpace(element));
    _normalizeSpace(pieces);
    return pieces.map((piece) => piece.text).join();
  }

  void _headAuxiliary() {
    for (final head
        in root.childElements.where((child) => _isTtml(child, 'head'))) {
      for (final container in head.descendants.whereType<XmlElement>()) {
        if (!_appleNamespaces.contains(container.namespaceUri) ||
            (container.localName != 'translation' &&
                container.localName != 'transliteration')) {
          continue;
        }
        for (final text in container.childElements) {
          if (text.localName != 'text' ||
              !_appleNamespaces.contains(text.namespaceUri)) {
            continue;
          }
          final key = text.getAttribute('for');
          if (key == null || key.isEmpty) {
            throw const FormatException('TTML 辅助轨未匹配原文');
          }
          auxiliary.add(_Auxiliary(
              container.localName == 'translation'
                  ? 'translation'
                  : 'romanization',
              _text(text),
              key: key));
        }
      }
    }
  }

  void _checkBreak(XmlElement element) {
    if (element.childElements.isNotEmpty ||
        element.children.any((child) =>
            (child is XmlText && child.value.trim().isNotEmpty) ||
            (child is XmlCDATA && child.value.trim().isNotEmpty))) {
      throw const FormatException('TTML 正文包含不支持的元素');
    }
  }
}
