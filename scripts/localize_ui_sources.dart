import 'dart:io';
import 'dart:convert';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'inventory_ui_strings.dart' show templateOf;

// One-time, syntax-aware mechanical migration. It changes explicit UI strings,
// never user files, metadata models, matching rules, IDs or persisted keys.
void main(List<String> args) {
  final apply = args.contains('--apply');
  final roots = args.where((a) => !a.startsWith('--')).toList();
  final manifest = <Map<String, Object>>[];
  for (final root in roots) {
    final entity = FileSystemEntity.typeSync(root);
    final files = entity == FileSystemEntityType.file ? [File(root)] :
      Directory(root).listSync(recursive: true).whereType<File>().toList();
    for (final file in files) {
      if (!file.path.endsWith('.dart') || file.path.endsWith('.g.dart')) continue;
      final source = file.readAsStringSync();
      final unit = parseString(content: source).unit;
      final visitor = _Localize(source);
      unit.accept(visitor);
      if (visitor.edits.isEmpty) continue;
      for (final message in visitor.messages) {
        manifest.add({'file': file.path.replaceAll('\\', '/'), 'text': message});
      }
      final watchers = _Watch(visitor.edits);
      unit.accept(watchers);
      if (!unit.directives.any((d) => d is PartOfDirective) &&
          !source.contains("import 'package:desktop_lyric/ui_language.dart'")) {
        final directives = unit.directives.where((d) => d is! PartDirective).toList();
        final offset = directives.isEmpty ? 0 : directives.last.end;
        visitor.edits[offset] = (0, "\nimport 'package:desktop_lyric/ui_language.dart';\n");
      }
      var result = source;
      for (final offset in visitor.edits.keys.toList()..sort((a,b) => b.compareTo(a))) {
        final (length, text) = visitor.edits[offset]!;
        result = result.replaceRange(offset, offset + length, text);
      }
      if (apply) file.writeAsStringSync(result);
      stdout.writeln('${apply ? 'Updated' : 'Would update'} ${file.path}: ${visitor.messages.length} messages');
    }
  }
  File('build/localized-ui-manifest.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(manifest));
}

class _Localize extends RecursiveAstVisitor<void> {
  _Localize(this.source);
  final String source;
  final edits = <int, (int, String)>{};
  final messages = <String>[];
  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) => translate(node);
  @override
  void visitStringInterpolation(StringInterpolation node) => translate(node);
  @override
  void visitAdjacentStrings(AdjacentStrings node) => translate(node);

  bool allowed(AstNode node) {
    for (AstNode? p = node.parent; p != null; p = p.parent) {
      if (p is FieldDeclaration || p is EnumDeclaration || p is DefaultFormalParameter ||
          p is TopLevelVariableDeclaration || p is Annotation) return false;
      if (p is NamedExpression && ['key', 'value', 'initialValue'].contains(p.name.label.name)) return false;
      if (p is BinaryExpression && ['==', '!='].contains(p.operator.lexeme)) return false;
      if (p is InstanceCreationExpression && ['RegExp', 'ValueKey'].contains(p.constructorName.type.name.lexeme)) return false;
      if (p is MethodInvocation && ['ui', 'RegExp', 'contains', 'startsWith', 'endsWith', 'replaceAll', 'replaceFirst', 'split', 'assert', 'debugPrint'].contains(p.methodName.name)) return false;
    }
    return true;
  }

  void translate(StringLiteral node) {
    if (node.parent is AdjacentStrings) return;
    final template = templateOf(node);
    if (!RegExp(r'[\u3400-\u9fff]').hasMatch(template) || !allowed(node)) return;
    final arguments = <String>[];
    void collect(StringLiteral item) {
      if (item is AdjacentStrings) { for (final s in item.strings) { collect(s); } }
      if (item is StringInterpolation) {
        for (final e in item.elements.whereType<InterpolationExpression>()) {
          arguments.add(e.expression.toSource());
        }
      }
    }
    collect(node);
    // JSON's double-quoted string syntax is valid Dart after escaping '$'.
    final quoted = jsonEncode(template).replaceAll(r'$', r'\$');
    edits[node.offset] = (node.length, 'ui($quoted${arguments.isEmpty ? '' : ', [${arguments.join(', ')}]'})');
    messages.add(template);
    for (AstNode? p = node.parent; p != null; p = p.parent) {
      final token = switch (p) {
        InstanceCreationExpression p => p.keyword,
        ListLiteral p => p.constKeyword,
        SetOrMapLiteral p => p.constKeyword,
        RecordLiteral p => p.constKeyword,
        VariableDeclarationList p => p.keyword,
        _ => null,
      };
      if (token?.lexeme == 'const') {
        edits[token!.offset] = (token.length, p is VariableDeclarationList ? 'final' : '');
      }
    }
  }
}

class _Watch extends RecursiveAstVisitor<void> {
  _Watch(this.edits);
  final Map<int, (int, String)> edits;
  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme == 'build' && node.parameters != null &&
        !node.body.toSource().contains('UiLanguageScope.watch')) {
      final parameter = node.parameters!.parameters.firstOrNull;
      final name = parameter?.name?.lexeme;
      if (name != null && name != '_') {
        final body = node.body;
        if (body is BlockFunctionBody) {
          edits[body.block.leftBracket.end] = (0, '\n    UiLanguageScope.watch($name);');
        } else if (body is ExpressionFunctionBody) {
          edits[body.functionDefinition.offset] = (body.functionDefinition.length,
              '{ UiLanguageScope.watch($name); return');
          edits[body.end] = (0, ' }');
        }
      }
    }
    super.visitMethodDeclaration(node);
  }
}
