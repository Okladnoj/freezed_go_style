import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as path;

import 'parameter_info.dart';

/// Formatter for Freezed models in Go-style
class FreezedGoStyleFormatter {
  /// Format a single file
  bool formatFile(File file, {bool verbose = false}) {
    if (!file.path.endsWith('.dart')) {
      return false;
    }

    try {
      final collection = AnalysisContextCollection(
        includedPaths: [path.dirname(file.path)],
      );

      final context = collection.contextFor(file.path);
      final result = context.currentSession.getParsedUnit(file.path);

      if (result is! ParsedUnitResult) {
        if (verbose) {
          print('Warning: Could not parse ${file.path}');
        }
        return false;
      }

      final unit = result.unit;
      final originalContent = file.readAsStringSync();
      final formatted = _formatUnit(unit, originalContent, verbose: verbose);

      if (formatted != originalContent) {
        file.writeAsStringSync(formatted);
        if (verbose) {
          print('Formatted: ${file.path}');
        }
        return true;
      } else if (verbose) {
        print('No changes needed for: ${file.path}');
      }

      return false;
    } catch (e) {
      if (verbose) {
        print('Error formatting ${file.path}: $e');
      }
      return false;
    }
  }

  /// Format all Dart files in a directory recursively
  int formatDirectory(Directory directory, {bool verbose = false}) {
    int formattedCount = 0;
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        if (formatFile(entity, verbose: verbose)) {
          formattedCount++;
        }
      }
    }
    return formattedCount;
  }

  String _formatUnit(
    CompilationUnit unit,
    String source, {
    bool verbose = false,
  }) {
    String result = source;

    for (final declaration in unit.declarations) {
      if (declaration is ClassDeclaration) {
        result = _formatClass(declaration, result, verbose: verbose);
      }
    }

    return result;
  }

  bool _hasFreezedGoStyleAnnotation(ClassDeclaration classDecl) {
    for (final metadata in classDecl.metadata) {
      final name = metadata.name.name;
      if (name == 'FreezedGoStyle') {
        return true;
      }
    }
    return false;
  }

  String _formatClass(
    ClassDeclaration classDecl,
    String source, {
    bool verbose = false,
  }) {
    // Check if class has @FreezedGoStyle annotation
    if (!_hasFreezedGoStyleAnnotation(classDecl)) {
      return source;
    }

    if (verbose) {
      print('Processing class: ${classDecl.name.lexeme}');
    }

    String result = source;

    // Find factory constructors
    for (final member in classDecl.members) {
      if (member is ConstructorDeclaration && member.factoryKeyword != null) {
        result = _formatFactoryConstructor(member, result, verbose: verbose);
      } else if (member is MethodDeclaration &&
          member.name.lexeme == 'fromJson') {
        // Skip fromJson methods
        continue;
      }
    }

    return result;
  }

  String _formatFactoryConstructor(
    ConstructorDeclaration factory,
    String source, {
    bool verbose = false,
  }) {
    if (verbose) {
      print('  Processing factory constructor');
    }

    final parameters = _extractParametersFromConstructor(
      factory,
      source,
      verbose: verbose,
    );

    if (parameters.isEmpty) {
      if (verbose) {
        print('    No parameters found, skipping');
      }
      return source;
    }

    return _formatFactoryWithAlignment(
      factory,
      parameters,
      source,
      verbose: verbose,
    );
  }

  List<ParameterInfo> _extractParametersFromConstructor(
    ConstructorDeclaration constructor,
    String source, {
    bool verbose = false,
  }) {
    final parameters = <ParameterInfo>[];
    final parameterList = constructor.parameters;

    if (parameterList.parameters.isEmpty) {
      return parameters;
    }

    for (final param in parameterList.parameters) {
      final annotations = <String>[];

      // Extract annotations
      if (param.metadata.isNotEmpty) {
        for (final annotation in param.metadata) {
          final annotationText = source.substring(
            annotation.offset,
            annotation.end,
          );
          annotations.add(annotationText);
        }
      }

      // Extract type
      String type = '';
      if (param is DefaultFormalParameter) {
        final normalParam = param.parameter;
        if (normalParam is SimpleFormalParameter) {
          type = normalParam.type?.toSource() ?? '';
        } else if (normalParam is FieldFormalParameter) {
          type = normalParam.type?.toSource() ?? '';
        }
      } else if (param is SimpleFormalParameter) {
        type = param.type?.toSource() ?? '';
      } else if (param is FieldFormalParameter) {
        type = param.type?.toSource() ?? '';
      }

      // Extract name
      String name = '';
      if (param is DefaultFormalParameter) {
        name = param.parameter.name?.lexeme ?? '';
      } else {
        name = param.name?.lexeme ?? '';
      }

      // Check if required
      bool isRequired = false;
      if (param is DefaultFormalParameter) {
        isRequired = param.isRequired;
      }

      // Add "required" to type if needed
      if (isRequired && !type.startsWith('required ')) {
        type = 'required $type';
      }

      if (name.isNotEmpty) {
        parameters.add(
          ParameterInfo(
            annotations: annotations,
            type: type,
            name: name,
            isRequired: isRequired,
          ),
        );
      }
    }

    return parameters;
  }

  String _formatFactoryWithAlignment(
    ConstructorDeclaration factory,
    List<ParameterInfo> parameters,
    String source, {
    bool verbose = false,
  }) {
    if (parameters.isEmpty) {
      return source;
    }

    // Calculate max lengths for alignment
    int maxAnnotationCount = 0;
    final maxAnnotationLengthsByPosition = <int, int>{};

    for (final param in parameters) {
      if (param.annotations.length > maxAnnotationCount) {
        maxAnnotationCount = param.annotations.length;
      }

      for (int i = 0; i < param.annotations.length; i++) {
        final currentMax = maxAnnotationLengthsByPosition[i] ?? 0;
        if (param.annotations[i].length > currentMax) {
          maxAnnotationLengthsByPosition[i] = param.annotations[i].length;
        }
      }
    }

    final maxTypeLength = parameters
        .map((p) => p.type.length)
        .reduce((a, b) => a > b ? a : b);

    if (verbose) {
      print('    Max annotation count: $maxAnnotationCount');
      print(
        '    Max annotation lengths by position: $maxAnnotationLengthsByPosition',
      );
      print('    Max type length: $maxTypeLength');
    }

    // Get the factory start and end positions
    final factoryStartOffset = factory.offset;
    final parameterList = factory.parameters;

    // Get the opening parenthesis offset
    final paramsStart = parameterList.leftParenthesis.offset;

    // Get everything from factory start to opening parenthesis (includes "const factory ClassName")
    final factoryDeclaration = source
        .substring(factoryStartOffset, paramsStart)
        .trim();

    if (verbose) {
      print('        Factory declaration: "$factoryDeclaration"');
      print(
        '        Factory start: $factoryStartOffset, params start: $paramsStart',
      );
    }

    // Check source code between ( and first parameter for {
    bool isNamedParameters = false;
    if (parameters.isNotEmpty) {
      final leftParenOffset = parameterList.leftParenthesis.offset;

      // Check if there's a { after ( and before first parameter
      if (leftParenOffset < source.length) {
        final afterLeftParen = source.substring(
          leftParenOffset + 1,
          leftParenOffset + 100, // Check first 100 chars
        );
        isNamedParameters = afterLeftParen.trim().startsWith('{');
      }
    }

    // Get the closing part after last parameter (should be "}) = _ClassName;")
    final lastParamEnd = parameterList.rightParenthesis.offset;

    // Find the end of factory (semicolon)
    final factoryEnd = source.indexOf(';', lastParamEnd);
    if (factoryEnd == -1) {
      return source; // Cannot format without semicolon
    }

    final closingPart = source.substring(lastParamEnd, factoryEnd + 1).trim();

    if (verbose) {
      print('        Closing part: "$closingPart"');
    }

    // Find the line before factory for indentation
    final beforeFactory = source.substring(0, factoryStartOffset);
    final lastNewline = beforeFactory.lastIndexOf('\n');
    final factoryIndent = lastNewline != -1
        ? source.substring(lastNewline + 1, factoryStartOffset)
        : '';

    // Calculate base indentation (usually 2 spaces more than factory line)
    final baseIndent = '${factoryIndent.replaceAll(RegExp(r'[^\s]'), '')}  ';

    if (verbose) {
      print('        Factory indent: "${factoryIndent.replaceAll(' ', '·')}"');
      print('        Base indent: "${baseIndent.replaceAll(' ', '·')}"');
    }

    // Build formatted factory
    final buffer = StringBuffer();
    buffer.writeln('$factoryDeclaration(${isNamedParameters ? '{' : ''}');

    // Build formatted parameters
    for (final param in parameters) {
      buffer.write(baseIndent);

      // Write annotations with padding
      for (int j = 0; j < maxAnnotationCount; j++) {
        if (j < param.annotations.length) {
          final annotation = param.annotations[j];
          final padding =
              ' ' * (maxAnnotationLengthsByPosition[j]! - annotation.length);
          buffer.write('$annotation$padding ');
        } else {
          // Empty annotation position
          final padding = ' ' * maxAnnotationLengthsByPosition[j]!;
          buffer.write('$padding ');
        }
      }

      // Write type with padding
      final typePadding = ' ' * (maxTypeLength - param.type.length);
      buffer.write('${param.type}$typePadding ');

      // Write parameter name
      buffer.write(param.name);

      // Add comma
      buffer.writeln(',');
    }

    // Close parameters
    buffer.write('$baseIndent${isNamedParameters ? '}' : ''}) $closingPart');

    // Replace in source
    final formatted = buffer.toString();
    final before = source.substring(0, factoryStartOffset);
    final after = source.substring(factoryEnd + 1);

    return before + formatted + after;
  }
}
