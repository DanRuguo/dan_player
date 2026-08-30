import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Read-only inventory for explicit UI localization (never scans user music).
void main(List<String> args) {
  final rows = <Map<String, Object>>[];
  for (final root in ['lib/component', 'lib/page', 'third_party/desktop_lyric/lib/component']) {
    for (final file in Directory(root).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final unit = parseString(content: file.readAsStringSync()).unit;
      unit.accept(_Strings(file.path.replaceAll('\\', '/'), rows));
    }
  }
  final output = File(args.isEmpty ? 'build/ui-strings.json' : args.first);
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
  stdout.writeln('${rows.length} UI string occurrences / ${rows.map((e) => e['text']).toSet().length} unique strings -> ${output.path}');
}

class _Strings extends RecursiveAstVisitor<void> {
  _Strings(this.path, this.rows);
  final String path;
  final List<Map<String, Object>> rows;
  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) => record(node);
  @override
  void visitStringInterpolation(StringInterpolation node) => record(node);
  @override
  void visitAdjacentStrings(AdjacentStrings node) => record(node);
  void record(StringLiteral node) {
    if (node.parent is AdjacentStrings) return;
    final raw = templateOf(node);
    if (!RegExp(r'[\u3400-\u9fff]').hasMatch(raw)) return;
    rows.add({'file': path, 'offset': node.offset, 'text': raw, 'parent': node.parent.runtimeType.toString()});
  }
}

String templateOf(StringLiteral node) {
  var index = 0;
  String part(StringLiteral item) {
    if (item is SimpleStringLiteral) return item.value;
    if (item is AdjacentStrings) return item.strings.map(part).join();
    if (item is StringInterpolation) return item.elements.map((e) {
      if (e is InterpolationString) return e.value;
      return '{${index++}}';
    }).join();
    return item.toSource();
  }
  return part(node);
}
