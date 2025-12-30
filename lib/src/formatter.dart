import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:path/path.dart' as path;

import 'parameter_info.dart';

/// Represents a text replacement in source code
class _Replacement {
  final int start;
  final int end;
  final String newText;

  _Replacement({required this.start, required this.end, required this.newText});
}

/// Formatter for Freezed models in Go-style
class FreezedGoStyleFormatter {
  /// Format a single file
  bool formatFile(File file, {bool verbose = false}) {
    if (verbose) {
      print('formatFile called for: ${file.path}');
    }

    if (!file.path.endsWith('.dart')) {
      if (verbose) {
        print('Skipping non-Dart file: ${file.path}');
      }
      return false;
    }

    try {
      if (verbose) {
        print('Creating analysis context for: ${file.path}');
      }

      // Normalize path to remove .. components
      final normalizedPath = path.normalize(path.absolute(file.path));
      final normalizedDir = path.normalize(
        path.absolute(path.dirname(file.path)),
      );

      if (verbose) {
        print('Normalized file path: $normalizedPath');
        print('Normalized dir path: $normalizedDir');
      }

      final collection = AnalysisContextCollection(
        includedPaths: [normalizedDir],
      );

      final context = collection.contextFor(normalizedPath);
      final result = context.currentSession.getParsedUnit(normalizedPath);

      if (result is! ParsedUnitResult) {
        if (verbose) {
          print('Warning: Could not parse ${file.path}');
          print('Result type: ${result.runtimeType}');
        }
        return false;
      }

      if (verbose) {
        print('Successfully parsed: ${file.path}');
      }

      final unit = result.unit;
      final originalContent = file.readAsStringSync();
      final formatted = _formatUnit(unit, originalContent, verbose: verbose);

      if (verbose) {
        print(
          'Original length: ${originalContent.length}, Formatted length: ${formatted.length}',
        );
        print('Are equal: ${formatted == originalContent}');
      }

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
    // Collect all replacements first (from end to start to preserve offsets)
    final replacements = <_Replacement>[];

    for (final declaration in unit.declarations) {
      if (declaration is ClassDeclaration) {
        final replacement = _formatClassReplacement(
          declaration,
          source,
          verbose: verbose,
        );
        if (replacement != null) {
          replacements.add(replacement);
        }
      }
    }

    // Apply replacements from end to start
    replacements.sort((a, b) => b.start.compareTo(a.start));

    String result = source;
    for (final replacement in replacements) {
      result =
          result.substring(0, replacement.start) +
          replacement.newText +
          result.substring(replacement.end);
    }

    return result;
  }

  _Replacement? _formatClassReplacement(
    ClassDeclaration classDecl,
    String source, {
    bool verbose = false,
  }) {
    // Check if class has @FreezedGoStyle annotation
    if (!_hasFreezedGoStyleAnnotation(classDecl)) {
      return null;
    }

    if (verbose) {
      print('Processing class: ${classDecl.name.lexeme}');
    }

    // Find factory constructors and collect replacements
    final factoryReplacements = <_Replacement>[];

    for (final member in classDecl.members) {
      if (member is ConstructorDeclaration && member.factoryKeyword != null) {
        final replacement = _formatFactoryConstructorReplacement(
          member,
          source,
          verbose: verbose,
        );
        if (replacement != null) {
          factoryReplacements.add(replacement);
        }
      }
    }

    // If no replacements, return null
    if (factoryReplacements.isEmpty) {
      return null;
    }

    // Combine all factory replacements into one class replacement
    // Sort from end to start
    factoryReplacements.sort((a, b) => b.start.compareTo(a.start));

    // Apply factory replacements to get new class content
    String classContent = source.substring(classDecl.offset, classDecl.end);
    for (final replacement in factoryReplacements) {
      // Adjust replacement offsets relative to class start
      final relativeStart = replacement.start - classDecl.offset;
      final relativeEnd = replacement.end - classDecl.offset;
      classContent =
          classContent.substring(0, relativeStart) +
          replacement.newText +
          classContent.substring(relativeEnd);
    }

    return _Replacement(
      start: classDecl.offset,
      end: classDecl.end,
      newText: classContent,
    );
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

  _Replacement? _formatFactoryConstructorReplacement(
    ConstructorDeclaration factory,
    String source, {
    bool verbose = false,
  }) {
    // Skip fromJson factory constructors
    if (factory.name?.lexeme == 'fromJson') {
      if (verbose) {
        print('  Skipping fromJson factory constructor');
      }
      return null;
    }

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
      return null;
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
      final comments = <String>[];

      // Extract preceding comments from tokens
      // We start from the first token of the parameter (which could be an annotation or the type/name)
      Token? currentToken = param.beginToken;

      // We look at preceding comments of the first token
      Token? commentToken = currentToken.precedingComments;
      while (commentToken != null) {
        comments.add(commentToken.lexeme.trim());
        commentToken = commentToken.next;
      }

      // Also look for comments inside the parameter declaration (e.g. between annotation and type)
      // This is a heuristic: we scan from beginToken to endToken
      // IMPORTANT: We only want comments that are "inside" this parameter's range,
      // but essentially we want to hoist ALL comments found in this parameter's declaration to the top.

      // To avoid duplication, we need to be careful. The precedingComments of the first token
      // covers everything before the parameter.
      // Now let's just collect comments attached to subsequent tokens within this parameter.
      // But we shouldn't scan past the end of this parameter.
      Token? scanToken = currentToken.next;
      while (scanToken != null && scanToken.offset <= param.end) {
        Token? innerComment = scanToken.precedingComments;
        while (innerComment != null) {
          comments.add(innerComment.lexeme.trim());
          innerComment = innerComment.next;
        }
        if (scanToken == param.endToken) break;
        scanToken = scanToken.next;
      }

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
            comments: comments,
          ),
        );
      }
    }

    return parameters;
  }

  _Replacement? _formatFactoryWithAlignment(
    ConstructorDeclaration factory,
    List<ParameterInfo> parameters,
    String source, {
    bool verbose = false,
  }) {
    if (parameters.isEmpty) {
      return null;
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

    // Find the semicolon after the factory constructor
    final factoryEnd = source.indexOf(';', lastParamEnd);
    if (factoryEnd == -1) {
      if (verbose) {
        print('        Warning: Could not find semicolon after factory');
      }
      return null; // Cannot format without semicolon
    }

    // Extract closing part (everything after right parenthesis until semicolon)
    // This should be ") = _ClassName;" or "}) = _ClassName;"
    String closingPart = source.substring(lastParamEnd, factoryEnd + 1).trim();

    // Extract just the class name part (e.g., "_ClassName;")
    // Pattern: ") = _ClassName;" or "}) = _ClassName;"
    final match = RegExp(r'=\s*([^;]+);').firstMatch(closingPart);
    if (match != null) {
      closingPart = '${match.group(1)};';
    } else {
      // Fallback: remove all ) and = from start
      closingPart = closingPart.replaceAll(RegExp(r'^\)+\s*'), '');
      closingPart = closingPart.replaceFirst(RegExp(r'^=\s*'), '');
    }

    // closingPart should now be just "_ClassName;"

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

    for (final param in parameters) {
      // Write comments
      for (final comment in param.comments) {
        buffer.writeln('$baseIndent$comment');
      }

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
    final closingIndent = factoryIndent.replaceAll(RegExp(r'[^\s]'), '');
    buffer.write(
      '$closingIndent${isNamedParameters ? '}' : ''}) = $closingPart',
    );

    // Return replacement
    final formatted = buffer.toString();

    return _Replacement(
      start: factoryStartOffset,
      end: factoryEnd + 1, // Include semicolon
      newText: formatted,
    );
  }
}
