import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as path;
import 'package:freezed_go_style/src/formatter.dart';

const String version = '0.0.1';

ArgParser buildParser() {
  return ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Show additional command output.',
    )
    ..addFlag('version', negatable: false, help: 'Print the tool version.')
    ..addOption('file', abbr: 'f', help: 'File path to format.')
    ..addOption('dir', abbr: 'd', help: 'Directory to format (recursively).');
}

void printUsage(ArgParser argParser) {
  print('Usage: freezed_go_style <flags> [file_path]');
  print('');
  print(
    'Formats Freezed models marked with @FreezedGoStyle annotation in Go-style.',
  );
  print('');
  print(argParser.usage);
  print('');
  print('Examples:');
  print('  freezed_go_style -f lib/models/user.dart');
  print('  freezed_go_style -d lib/models/');
  print('  freezed_go_style lib/models/user.dart');
}

void main(List<String> arguments) {
  final ArgParser argParser = buildParser();
  try {
    final ArgResults results = argParser.parse(arguments);
    final bool verbose = results.flag('verbose');

    if (results.flag('help')) {
      printUsage(argParser);
      return;
    }

    if (results.flag('version')) {
      print('freezed_go_style version: $version');
      return;
    }

    // Get file or directory path
    String? targetPath;
    if (results.wasParsed('file')) {
      targetPath = results['file'] as String;
    } else if (results.wasParsed('dir')) {
      targetPath = results['dir'] as String;
    } else if (results.rest.isNotEmpty) {
      targetPath = results.rest.first;
    } else {
      print('Error: No file or directory specified.');
      print('');
      printUsage(argParser);
      exit(1);
    }

    final absolutePath = path.absolute(targetPath);
    final target = File(absolutePath);
    final isDirectory = Directory(absolutePath).existsSync();

    // Always print basic info to stderr for debugging
    stderr.writeln('Target path: $targetPath');
    stderr.writeln('Absolute path: $absolutePath');
    stderr.writeln('File exists: ${target.existsSync()}');
    stderr.writeln('Is directory: $isDirectory');

    if (verbose) {
      print('Target path: $targetPath');
      print('Absolute path: $absolutePath');
      print('File exists: ${target.existsSync()}');
      print('Is directory: $isDirectory');
    }

    if (!target.existsSync() && !isDirectory) {
      print('Error: File or directory not found: $targetPath');
      exit(1);
    }

    // Format files
    final formatter = FreezedGoStyleFormatter();
    int formattedCount = 0;

    stderr.writeln('Starting formatting...');
    if (verbose) {
      print('Starting formatting...');
    }

    if (isDirectory) {
      formattedCount = formatter.formatDirectory(
        Directory(absolutePath),
        verbose: verbose,
      );
    } else {
      if (formatter.formatFile(File(absolutePath), verbose: verbose)) {
        formattedCount = 1;
      }
    }

    stderr.writeln('Formatted count: $formattedCount');
    if (verbose) {
      print('Formatted $formattedCount file(s).');
    } else if (formattedCount > 0) {
      print('✅ Formatted $formattedCount file(s).');
    } else if (verbose) {
      print('No files were formatted.');
    } else {
      stderr.writeln('No files were formatted.');
    }
  } on FormatException catch (e) {
    print('Error: ${e.message}');
    print('');
    printUsage(argParser);
    exit(1);
  } catch (e) {
    print('Error: $e');
    exit(1);
  }
}
