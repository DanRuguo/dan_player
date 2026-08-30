import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

// Mechanical follow-up: classify legacy notices BEFORE translating the text.
void main() {
  for (final file in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
    final source = file.readAsStringSync();
    final visitor = _Notices();
    parseString(content: source).unit.accept(visitor);
    var result = source;
    for (final offset in visitor.edits.keys.toList()..sort((a,b) => b.compareTo(a))) {
      final (length, replacement) = visitor.edits[offset]!;
      result = result.replaceRange(offset, offset + length, replacement);
    }
    if (result != source) { file.writeAsStringSync(result); stdout.writeln(file.path); }
  }
}
class _Notices extends RecursiveAstVisitor<void> {
  final edits = <int, (int, String)>{};
  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'showTextOnSnackBar') {
      final translated = node.argumentList.arguments.firstOrNull;
      if (translated is MethodInvocation && translated.methodName.name == 'ui') {
        final args = translated.argumentList.arguments;
        edits[translated.offset] = (translated.length, args.first.toSource() +
          (args.length > 1 ? ', arguments: ${args[1].toSource()}' : ''));
      }
    }
    super.visitMethodInvocation(node);
  }
}
