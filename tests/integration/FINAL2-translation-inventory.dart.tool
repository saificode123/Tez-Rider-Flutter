// Standalone Dart tool, run with Flutter tooling's existing --packages file.
// The .tool suffix keeps its SDK-only dependency outside app analysis scope.
import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

class UiStrings extends RecursiveAstVisitor<void> {
  UiStrings(this.path, this.helpers, this.widgetNames);
  final String path;
  final Map<String, Set<int>> helpers;
  final Set<String> widgetNames;
  final entries = <Map<String, dynamic>>[];
  final nodes = <int, Expression>{};
  void collect(Expression expression) {
    if (expression is ParenthesizedExpression) {
      collect(expression.expression);
      return;
    }
    if (expression is ConditionalExpression) {
      collect(expression.thenExpression);
      collect(expression.elseExpression);
      return;
    }
    if (expression is BinaryExpression &&
        ['??', '+'].contains(expression.operator.lexeme)) {
      collect(expression.leftOperand);
      collect(expression.rightOperand);
      return;
    }
    if (expression is! StringLiteral) return;
    var parent = expression.parent;
    while (parent != null) {
      if (parent is MethodDeclaration &&
          parent.name.lexeme.toLowerCase().contains('biometric'))
        return;
      parent = parent.parent;
    }
    final params = <String, String>{};
    final text = StringBuffer();
    void append(StringLiteral literal) {
      if (literal is AdjacentStrings) {
        for (final part in literal.strings) {
          append(part);
        }
        return;
      }
      if (literal is! StringInterpolation) {
        text.write(literal.stringValue);
        return;
      }
      for (final element in literal.elements) {
        if (element is InterpolationString) text.write(element.value);
        if (element is InterpolationExpression) {
          final name = 'slot${params.length}end';
          text.write('@$name');
          params[name] = element.expression.toSource();
        }
      }
    }

    append(expression);
    final key = text.toString();
    if (!RegExp(
      '[A-Za-z]{2}',
    ).hasMatch(key.replaceAll(RegExp(r'@slot\d+end'), '')))
      return;
    nodes[expression.offset] = expression;
    entries.add({
      'path': path,
      'offset': expression.offset,
      'length': expression.length,
      'key': key,
      'params': params,
    });
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type.toSource();
    if (type == 'Text' && node.argumentList.arguments.isNotEmpty)
      collect(node.argumentList.arguments.first);
    for (final arg
        in node.argumentList.arguments.whereType<NamedExpression>()) {
      final name = arg.name.label.name;
      if ([
            'labelText',
            'hintText',
            'helperText',
            'errorText',
            'tooltip',
            'semanticLabel',
            'prefixText',
            'suffixText',
          ].contains(name) ||
          type == 'TextSpan' && name == 'text' ||
          widgetNames.contains(type) &&
              [
                'title',
                'label',
                'subtitle',
                'description',
                'message',
              ].contains(name))
        collect(arg.expression);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final helper = node.target == null ? helpers[node.methodName.name] : null;
    if (helper != null) {
      for (final index in helper) {
        if (index < node.argumentList.arguments.length)
          collect(node.argumentList.arguments[index]);
      }
    }
    // Without type resolution, implicit constructor calls parse as invocations.
    if (node.target == null &&
        node.methodName.name == 'Text' &&
        node.argumentList.arguments.isNotEmpty)
      collect(node.argumentList.arguments.first);
    if (node.target == null) {
      for (final arg
          in node.argumentList.arguments.whereType<NamedExpression>()) {
        final name = arg.name.label.name;
        if ([
              'labelText',
              'hintText',
              'helperText',
              'errorText',
              'tooltip',
              'semanticLabel',
              'prefixText',
              'suffixText',
            ].contains(name) ||
            node.methodName.name == 'TextSpan' && name == 'text' ||
            widgetNames.contains(node.methodName.name) &&
                [
                  'title',
                  'label',
                  'subtitle',
                  'description',
                  'message',
                ].contains(name))
          collect(arg.expression);
      }
    }
    if (node.target?.toSource() == 'Get' &&
        node.methodName.name == 'snackbar') {
      for (final arg in node.argumentList.arguments.take(2)) collect(arg);
    }
    super.visitMethodInvocation(node);
  }
}

class UiHelpers extends RecursiveAstVisitor<void> {
  final helpers = <String, Set<int>>{};
  final widgetNames = <String>{'Tooltip', 'DropdownMenuEntry'};
  void inspect(
    String name,
    TypeAnnotation? type,
    FormalParameterList? parameters,
    FunctionBody body,
  ) {
    if (!['Widget', 'InputDecoration'].contains(type?.toSource()) ||
        parameters == null)
      return;
    final source = body.toSource();
    if (['.rpc(', '.from(', 'Get.to('].any(source.contains)) return;
    for (var i = 0; i < parameters.parameters.length; i++) {
      final decl = parameters.parameters[i].toSource().split('=').first;
      final param = RegExp(r'[A-Za-z_]\w*').allMatches(decl).last.group(0)!;
      if (![
        'title',
        'label',
        'text',
        'subtitle',
        'description',
        'message',
        'hint',
      ].contains(param))
        continue;
      if (RegExp(r'\b' + param + r'\s*(?:==|!=)').hasMatch(source)) continue;
      if (RegExp(r'Text\s*\(\s*' + param + r'\b').hasMatch(source) ||
          RegExp(
            r'(?:labelText|hintText|helperText|tooltip):\s*' + param + r'\b',
          ).hasMatch(source))
        helpers.putIfAbsent(name, () => {}).add(i);
    }
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    inspect(node.name.lexeme, node.returnType, node.parameters, node.body);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    inspect(
      node.name.lexeme,
      node.returnType,
      node.functionExpression.parameters,
      node.functionExpression.body,
    );
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (node.extendsClause?.superclass.toSource().contains('Widget') ?? false)
      widgetNames.add(node.name.lexeme);
    super.visitClassDeclaration(node);
  }
}

class LocaleDependencies extends RecursiveAstVisitor<void> {
  final edits = <int, ({int length, String value})>{};
  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme == 'build' &&
        (node.parameters?.toSource().contains('BuildContext context') ??
            false)) {
      final body = node.body;
      if (body is BlockFunctionBody) {
        edits[body.block.leftBracket.end] = (
          length: 0,
          value: '\n    Localizations.localeOf(context);',
        );
      } else if (body is ExpressionFunctionBody) {
        edits[body.functionDefinition.offset] = (
          length: body.functionDefinition.length,
          value: '{ Localizations.localeOf(context); return ',
        );
        edits[body.semicolon!.offset] = (
          length: body.semicolon!.length,
          value: '; }',
        );
      }
    }
    super.visitMethodDeclaration(node);
  }
}

class BoundaryCalls extends RecursiveAstVisitor<void> {
  final calls = <String>[];
  @override
  void visitMethodInvocation(MethodInvocation node) {
    const methods = {
      'rpc',
      'from',
      'invoke',
      'select',
      'insert',
      'upsert',
      'delete',
      'update',
      'eq',
      'neq',
      'gt',
      'gte',
      'lt',
      'lte',
      'inFilter',
      'filter',
      'match',
      'order',
      'range',
      'limit',
      'offAllNamed',
      'offNamed',
      'toNamed',
    };
    if (methods.contains(node.methodName.name)) {
      // Serialize arguments only; a chained receiver contains display closures.
      calls.add('${node.methodName.name}${node.argumentList.toSource()}');
    }
    super.visitMethodInvocation(node);
  }
}

void verifyBoundaries(List<String> targets, String base, String output) {
  final results = <Map<String, dynamic>>[];
  for (final path in targets) {
    final previous = Process.runSync('git', ['show', '$base:$path']);
    if (previous.exitCode != 0) throw StateError('Base source missing: $path');
    final before = BoundaryCalls(), after = BoundaryCalls();
    parseString(
      content: previous.stdout as String,
      throwIfDiagnostics: true,
    ).unit.accept(before);
    parseString(
      content: File(path).readAsStringSync(),
      throwIfDiagnostics: true,
    ).unit.accept(after);
    final ok = jsonEncode(before.calls) == jsonEncode(after.calls);
    results.add({
      'path': path,
      'boundary_calls': after.calls.length,
      'unchanged': ok,
    });
  }
  File(output).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
          'base': base,
          'scope':
              'static API arguments and named navigation; not execution evidence',
          'results': results,
        }) +
        '\n',
  );
  if (results.any((row) => row['unchanged'] != true))
    throw StateError('Boundary arguments changed; inspect report');
  print(
    jsonEncode({
      'files': results.length,
      'boundary_calls': results.fold<int>(
        0,
        (n, r) => n + r['boundary_calls'] as int,
      ),
      'unchanged': true,
    }),
  );
}

void main(List<String> args) {
  if (args.length == 4 && args[2] == '--verify') {
    verifyBoundaries(
      List<String>.from(jsonDecode(File(args[0]).readAsStringSync())),
      args[3],
      args[1],
    );
    return;
  }
  if (args.length != 2 && args.length != 3)
    throw ArgumentError(
      'Target list, output, and optional translation map required',
    );
  final targets = List<String>.from(
    jsonDecode(File(args[0]).readAsStringSync()),
  );
  final entries = <Map<String, dynamic>>[];
  final units = <String, CompilationUnit>{};
  final discovery = UiHelpers();
  for (final path in targets) {
    final parsed = parseString(
      content: File(path).readAsStringSync(),
      path: path,
      throwIfDiagnostics: false,
    );
    if (parsed.errors.isNotEmpty) throw StateError('Parse errors: $path');
    units[path] = parsed.unit;
    parsed.unit.accept(discovery);
  }
  final translations = args.length == 3
      ? Map<String, String>.from(jsonDecode(File(args[2]).readAsStringSync()))
      : <String, String>{};
  final skipped = <Map<String, dynamic>>[];
  var changedFiles = 0;
  for (final path in targets) {
    final visitor = UiStrings(path, discovery.helpers, discovery.widgetNames);
    units[path]!.accept(visitor);
    entries.addAll(visitor.entries);
    if (args.length != 3 || visitor.entries.isEmpty) continue;
    final edits = <int, ({int length, String value})>{};
    var dynamicUsed = false;
    for (final entry in visitor.entries) {
      if (!translations.containsKey(entry['key'])) continue;
      final node = visitor.nodes[entry['offset']]!;
      AstNode? ancestor = node.parent;
      var constantOnly = false;
      final constants = <int, int>{};
      while (ancestor != null) {
        if (ancestor is VariableDeclarationList && ancestor.isConst ||
            ancestor is DefaultFormalParameter ||
            ancestor is Annotation ||
            ancestor is EnumConstantDeclaration ||
            ancestor is ConstantPattern)
          constantOnly = true;
        if (ancestor is InstanceCreationExpression &&
            ancestor.keyword?.lexeme == 'const')
          constants[ancestor.keyword!.offset] = ancestor.keyword!.length;
        if (ancestor is ListLiteral && ancestor.constKeyword != null)
          constants[ancestor.constKeyword!.offset] =
              ancestor.constKeyword!.length;
        if (ancestor is SetOrMapLiteral && ancestor.constKeyword != null)
          constants[ancestor.constKeyword!.offset] =
              ancestor.constKeyword!.length;
        ancestor = ancestor.parent;
      }
      if (constantOnly) {
        skipped.add({...entry, 'reason': 'compile_time_constant'});
        continue;
      }
      String literal(String value) => jsonEncode(value).replaceAll(r'$', r'\$');
      final params = Map<String, String>.from(entry['params']);
      final replacement = params.isEmpty
          ? '${literal(entry['key'])}.tr'
          : '${literal(entry['key'])}.uiTr({${params.entries.map((e) => '${literal(e.key)}: (${e.value}).toString()').join(', ')}})';
      dynamicUsed = dynamicUsed || params.isNotEmpty;
      edits[node.offset] = (length: node.length, value: replacement);
      for (final constant in constants.entries) {
        edits[constant.key] = (length: constant.value, value: '');
      }
    }
    if (edits.isEmpty) continue;
    final dependency = LocaleDependencies();
    units[path]!.accept(dependency);
    for (final edit in dependency.edits.entries) {
      edits[edit.key] = edit.value;
    }
    var source = File(path).readAsStringSync();
    var previous = source.length;
    for (final offset in edits.keys.toList()..sort((a, b) => b.compareTo(a))) {
      final edit = edits[offset]!;
      if (offset + edit.length > previous)
        throw StateError('Overlapping edit: $path:$offset');
      source = source.replaceRange(offset, offset + edit.length, edit.value);
      previous = offset;
    }
    final imports = StringBuffer();
    if (!source.contains("package:get/get.dart"))
      imports.writeln("import 'package:get/get.dart';");
    if (dynamicUsed)
      imports.writeln(
        "import 'package:flutter_application_1/core/stage2_ui_strings.dart';",
      );
    File(path).writeAsStringSync('$imports$source');
    changedFiles++;
  }
  File(args[1]).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(entries) + '\n',
  );
  print(
    jsonEncode({
      'files': targets.length,
      'untranslated_literal_instances': entries.length,
      'distinct_keys': entries.map((e) => e['key']).toSet().length,
      'read_only': args.length == 2,
      'changed_files': changedFiles,
      'skipped': skipped,
    }),
  );
}
