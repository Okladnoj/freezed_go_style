import 'dart:io';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/analysis/results.dart';
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
    int count = 0;

    for (final entity in directory.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        if (formatFile(entity, verbose: verbose)) {
          count++;
        }
      }
    }

    return count;
  }

  String _formatUnit(
    CompilationUnit unit,
    String source, {
    bool verbose = false,
  }) {
    final buffer = StringBuffer();
    final lines = source.split('\n');
    int currentLine = 0;

    for (final declaration in unit.declarations) {
      if (declaration is ClassDeclaration) {
        // Check if class has @FreezedGoStyle annotation
        final hasAnnotation = declaration.metadata.any((meta) {
          final name = meta.name.name;
          return name == 'FreezedGoStyle';
        });

        if (verbose) {
          print(
            'Class ${declaration.name.lexeme}: hasAnnotation=$hasAnnotation',
          );
          print(
            '  Metadata: ${declaration.metadata.map((m) => m.name.name).toList()}',
          );
        }

        if (!hasAnnotation) {
          // Copy class as is
          final classStart = _getLineNumber(source, declaration.offset);
          final classEnd = _getLineNumber(source, declaration.end);
          for (int i = classStart; i <= classEnd && i < lines.length; i++) {
            buffer.writeln(lines[i]);
          }
          currentLine = classEnd + 1;
          continue;
        }

        // Copy everything before the class
        final classStart = _getLineNumber(source, declaration.offset);
        while (currentLine < classStart && currentLine < lines.length) {
          buffer.writeln(lines[currentLine]);
          currentLine++;
        }

        // Format the class
        if (verbose) {
          print('  Formatting class ${declaration.name.lexeme}...');
        }
        final formattedClass = _formatClass(
          declaration,
          lines,
          source,
          verbose: verbose,
        );
        buffer.write(formattedClass);

        // Skip class lines
        final classEnd = _getLineNumber(source, declaration.end);
        currentLine = classEnd + 1;
      } else {
        // Copy non-class declarations as is
        final declStart = _getLineNumber(source, declaration.offset);
        final declEnd = _getLineNumber(source, declaration.end);
        while (currentLine <= declEnd && currentLine < lines.length) {
          if (currentLine >= declStart) {
            buffer.writeln(lines[currentLine]);
          }
          currentLine++;
        }
      }
    }

    // Copy remaining lines
    while (currentLine < lines.length) {
      buffer.writeln(lines[currentLine]);
      currentLine++;
    }

    return buffer.toString();
  }

  String _formatClass(
    ClassDeclaration classDecl,
    List<String> lines,
    String source, {
    bool verbose = false,
  }) {
    final buffer = StringBuffer();

    // Copy class declaration line and opening brace
    final classStartLine = _getLineNumber(source, classDecl.offset);
    final classBodyStart = _getLineNumber(source, classDecl.leftBracket.offset);

    for (int i = classStartLine; i <= classBodyStart && i < lines.length; i++) {
      buffer.writeln(lines[i]);
    }

    // Process class members
    if (verbose) {
      print('    Class members: ${classDecl.members.length}');
    }
    for (final member in classDecl.members) {
      if (member is ConstructorDeclaration) {
        // Check if it's a factory constructor
        final isFactory = member.factoryKeyword != null;

        if (verbose) {
          final constructorName = member.name?.lexeme ?? 'unnamed';
          final className = classDecl.name.lexeme;
          print(
            '    Constructor: $constructorName, isFactory=$isFactory, className=$className',
          );
        }

        if (isFactory) {
          // Only format main factory constructors
          // In Freezed, main factory is:
          // 1. Unnamed: const factory ClassName({...}) = _ClassName;
          // 2. Named with class name: const factory ClassName.className({...}) = _ClassName;
          // Skip fromJson and other special named factories
          final factoryName = member.name?.lexeme ?? '';
          final className = classDecl.name.lexeme;

          // Main factory is either unnamed or has the same name as the class
          final isMainFactory = factoryName.isEmpty || factoryName == className;

          if (isMainFactory) {
            if (verbose) {
              print('    Found factory: ${member.name?.lexeme ?? 'unnamed'}');
            }
            final formattedFactory = _formatFactoryConstructor(
              member,
              lines,
              source,
              verbose: verbose,
            );
            buffer.write(formattedFactory);
          } else {
            // Copy named factory methods (like fromJson) as is
            final memberStart = _getLineNumber(source, member.offset);
            final memberEnd = _getLineNumber(source, member.end);
            for (int i = memberStart; i <= memberEnd && i < lines.length; i++) {
              buffer.writeln(lines[i]);
            }
          }
        } else {
          // Copy non-factory constructors as is
          final memberStart = _getLineNumber(source, member.offset);
          final memberEnd = _getLineNumber(source, member.end);
          for (int i = memberStart; i <= memberEnd && i < lines.length; i++) {
            buffer.writeln(lines[i]);
          }
        }
      } else if (member is MethodDeclaration) {
        // Handle regular methods
        final memberStart = _getLineNumber(source, member.offset);
        final memberEnd = _getLineNumber(source, member.end);
        for (int i = memberStart; i <= memberEnd && i < lines.length; i++) {
          buffer.writeln(lines[i]);
        }
      } else {
        // Copy other members as is
        final memberStart = _getLineNumber(source, member.offset);
        final memberEnd = _getLineNumber(source, member.end);
        for (int i = memberStart; i <= memberEnd && i < lines.length; i++) {
          buffer.writeln(lines[i]);
        }
      }
    }

    // Copy closing brace
    final classEndLine = _getLineNumber(source, classDecl.end);
    if (classEndLine < lines.length) {
      buffer.writeln(lines[classEndLine]);
    }

    return buffer.toString();
  }

  String _formatFactoryConstructor(
    ConstructorDeclaration factory,
    List<String> lines,
    String source, {
    bool verbose = false,
  }) {
    // Extract parameters
    final parameters = _extractParametersFromConstructor(
      factory,
      source,
      verbose: verbose,
    );

    if (verbose) {
      print('      Parameters extracted: ${parameters.length}');
      for (int i = 0; i < parameters.length; i++) {
        final p = parameters[i];
        print(
          '        [$i] ${p.name}: ${p.type} (annotations: ${p.annotations.length})',
        );
      }
    }

    if (parameters.isEmpty) {
      // No parameters, return as is
      final factoryStart = _getLineNumber(source, factory.offset);
      final factoryEnd = _getLineNumber(source, factory.end);
      final buffer = StringBuffer();
      for (int i = factoryStart; i <= factoryEnd && i < lines.length; i++) {
        buffer.writeln(lines[i]);
      }
      return buffer.toString();
    }

    // Calculate alignment widths
    // For each annotation position (1st, 2nd, etc.) find the maximum length
    // This is needed to align annotations by position
    final maxAnnotationLengthsByPosition = <int, int>{};
    for (final param in parameters) {
      for (int i = 0; i < param.annotations.length; i++) {
        final currentMax = maxAnnotationLengthsByPosition[i] ?? 0;
        final annotationLength = param.annotations[i].length;
        if (annotationLength > currentMax) {
          maxAnnotationLengthsByPosition[i] = annotationLength;
        }
      }
    }

    // maxAnnotationLength - maximum length of a single annotation (for backward compatibility)
    final maxAnnotationLength = maxAnnotationLengthsByPosition.values.isEmpty
        ? 0
        : maxAnnotationLengthsByPosition.values.reduce((a, b) => a > b ? a : b);

    // maxAnnotationsCount - maximum number of annotations for a single parameter
    final maxAnnotationsCount = parameters.isEmpty
        ? 0
        : parameters
              .map((p) => p.annotations.length)
              .reduce((a, b) => a > b ? a : b);

    final maxTypeLength = parameters.isEmpty
        ? 0
        : parameters.map((p) => p.type.length).reduce((a, b) => a > b ? a : b);

    // Format factory constructor
    return _formatFactoryWithAlignment(
      factory,
      parameters,
      maxAnnotationLength,
      maxAnnotationLengthsByPosition,
      maxAnnotationsCount,
      maxTypeLength,
      lines,
      source,
      verbose: verbose,
    );
  }

  List<ParameterInfo> _extractParametersFromConstructor(
    ConstructorDeclaration factory,
    String source, {
    bool verbose = false,
  }) {
    final parameters = <ParameterInfo>[];

    // Get parameter list
    final parameterList = factory.parameters;
    if (parameterList.parameters.isEmpty) {
      if (verbose) {
        print('        ERROR: factory.parameters is null!');
      }
      return parameters;
    }

    if (verbose) {
      print(
        '        Parameter list found: ${parameterList.parameters.length} parameters',
      );
    }

    for (final param in parameterList.parameters) {
      // Extract annotations - normalize whitespace (remove newlines, extra spaces)
      final annotations = <String>[];
      for (final meta in param.metadata) {
        final annotationSource = source.substring(meta.offset, meta.end);
        // Normalize: remove newlines and extra whitespace, but keep single spaces
        final normalized = annotationSource
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        annotations.add(normalized);
        if (verbose && param.name?.lexeme == 'name') {
          print('          Annotation: "$annotationSource" -> "$normalized"');
        }
      }

      // Extract type
      String type = 'dynamic';
      if (param is DefaultFormalParameter) {
        final innerParam = param.parameter;
        if (innerParam is SimpleFormalParameter) {
          type = innerParam.type?.toString() ?? 'dynamic';
        }
      } else if (param is SimpleFormalParameter) {
        type = param.type?.toString() ?? 'dynamic';
      }

      // Extract name
      String name = '';
      if (param is DefaultFormalParameter) {
        final innerParam = param.parameter;
        if (innerParam is SimpleFormalParameter) {
          name = innerParam.name?.lexeme ?? '';
        }
      } else if (param is SimpleFormalParameter) {
        name = param.name?.lexeme ?? '';
      } else if (param is FieldFormalParameter) {
        name = param.name.lexeme;
      }

      // Check if required
      final isRequired = param.isRequired;

      parameters.add(
        ParameterInfo(
          annotations: annotations,
          type: type.trim(),
          name: name,
          isRequired: isRequired,
        ),
      );
    }

    return parameters;
  }

  String _formatFactoryWithAlignment(
    ConstructorDeclaration factory,
    List<ParameterInfo> parameters,
    int maxAnnotationLength,
    Map<int, int> maxAnnotationLengthsByPosition,
    int maxAnnotationsCount,
    int maxTypeLength,
    List<String> lines,
    String source, {
    bool verbose = false,
  }) {
    final buffer = StringBuffer();

    final parameterList = factory.parameters;

    // Get indentation from factory declaration
    final factoryDeclLine = _getLineNumber(source, factory.offset);
    String indent = '    '; // Default
    if (factoryDeclLine < lines.length) {
      final factoryLine = lines[factoryDeclLine];
      final match = RegExp(r'^(\s+)').firstMatch(factoryLine);
      if (match != null) {
        indent = match.group(1)!;
      }
    }

    // Get factory name and modifiers from source
    final factoryStartOffset = factory.offset;

    // Get the opening parenthesis offset
    final paramsStart =
        parameterList?.leftParenthesis.offset ?? factoryStartOffset;

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

    // Check if parameters are named (have curly braces)
    final hasCurlyBraces =
        parameterList != null &&
        parameterList.leftParenthesis != null &&
        parameterList.rightParenthesis != null;

    // Check source code between ( and first parameter for {
    bool isNamedParameters = false;
    if (hasCurlyBraces && parameters.isNotEmpty) {
      final leftParenOffset = parameterList!.leftParenthesis!.offset;
      final firstParamOffset = parameters.first.annotations.isNotEmpty
          ? parameters.first.annotations.first.length > 0
                ? source.indexOf(
                    parameters.first.annotations.first,
                    leftParenOffset,
                  )
                : -1
          : -1;

      // Check if there's a { after ( and before first parameter
      if (leftParenOffset < source.length) {
        final afterLeftParen = source.substring(
          leftParenOffset + 1,
          leftParenOffset + 100, // Check first 100 chars
        );
        isNamedParameters = afterLeftParen.trim().startsWith('{');
      }
    }

    // Format factory declaration with parameters
    buffer.write('$indent$factoryDeclaration(${isNamedParameters ? '{' : ''}');
    if (parameters.isNotEmpty) {
      buffer.writeln();
    }

    for (int i = 0; i < parameters.length; i++) {
      final param = parameters[i];
      final isLast = i == parameters.length - 1;

      // Write annotations with alignment - all on one line
      buffer.write('$indent  ');

      if (param.annotations.isNotEmpty) {
        // Write all annotations on one line
        // Each annotation is padded to max length for its position
        // Between annotations always exactly one space
        for (int j = 0; j < param.annotations.length; j++) {
          final annotation = param.annotations[j];
          final maxLengthForPosition =
              maxAnnotationLengthsByPosition[j] ?? annotation.length;
          final padding = ' ' * (maxLengthForPosition - annotation.length);
          // Write annotation + padding
          buffer.write('$annotation$padding');
          // Add exactly one space between annotations AND after last annotation (before type)
          buffer.write(' ');
        }
      }

      // Add padding to align types (fill remaining annotation slots with spaces)
      // For each missing annotation, add maxAnnotationLength + 1 spaces
      final remainingAnnotationSlots =
          maxAnnotationsCount - param.annotations.length;
      if (remainingAnnotationSlots > 0) {
        final paddingForMissingAnnotations =
            ' ' * (remainingAnnotationSlots * (maxAnnotationLength + 1));
        buffer.write(paddingForMissingAnnotations);
      }

      // After all annotations (or padding), add type
      final typePadding = ' ' * (maxTypeLength - param.type.length);
      buffer.write('${param.type}$typePadding ');

      // Write parameter name
      buffer.write(param.name);

      // Write comma after all parameters (including last one)
      buffer.writeln(',');
    }

    // Get everything after closing parenthesis/bracket
    // For named parameters: find } before )
    // For positional parameters: use )
    final paramsEnd = parameterList?.rightParenthesis.offset;
    if (paramsEnd != null && paramsEnd < factory.end) {
      // Check if there's a } before ) in the source
      String afterParams;
      if (isNamedParameters) {
        // For named parameters, find } before )
        final beforeRightParen = source.substring(
          parameterList!.leftParenthesis!.offset + 1,
          paramsEnd,
        );
        final closingBraceIndex = beforeRightParen.lastIndexOf('}');
        if (closingBraceIndex >= 0) {
          // Use } position instead of ) position
          // closingBraceIndex is relative to beforeRightParen start
          // beforeRightParen starts at leftParenthesis.offset + 1
          final braceOffset =
              parameterList.leftParenthesis!.offset + 1 + closingBraceIndex + 1;
          afterParams = source.substring(braceOffset, factory.end);
          // afterParams should start with } =, but if it starts with }, we need to keep it
          if (!afterParams.startsWith('}')) {
            // This shouldn't happen, but if it does, add }
            afterParams = '}$afterParams';
          }
        } else {
          // No } found, use ) position and add }
          afterParams = source.substring(paramsEnd, factory.end);
          if (afterParams.startsWith(')')) {
            afterParams = '}${afterParams.substring(1)}';
          }
        }
      } else {
        // For positional parameters, use ) position
        afterParams = source.substring(paramsEnd, factory.end);
        // If source has }, remove it
        if (afterParams.startsWith('}')) {
          afterParams = ')${afterParams.substring(1)}';
        }
      }
      buffer.write('$indent$afterParams');
    } else {
      // Fallback: just close with ) or })
      buffer.write('$indent${isNamedParameters ? '}' : ''})');
    }
    buffer.writeln();

    return buffer.toString();
  }

  int _getLineNumber(String source, int offset) {
    return source.substring(0, offset).split('\n').length - 1;
  }
}
