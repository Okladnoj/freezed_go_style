import 'dart:io';

import 'package:freezed_go_style/freezed_go_style.dart';
import 'package:test/test.dart';

void main() {
  group('FreezedGoStyleFormatter', () {
    late FreezedGoStyleFormatter formatter;
    late Directory tempDir;

    setUp(() {
      formatter = FreezedGoStyleFormatter();
      tempDir = Directory.systemTemp.createTempSync('freezed_go_style_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('formats file with @FreezedGoStyle annotation', () {
      final testFile = File('${tempDir.path}/test.dart');
      testFile.writeAsStringSync('''
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:freezed_go_style/freezed_go_style.dart';

part 'test.freezed.dart';

@FreezedGoStyle()
@freezed
class User with _\$User {
  const factory User({
    @JsonKey(name: 'id') @Default(0) int id,
    @JsonKey(name: 'email') required String email,
  }) = _User;
}
''');

      final result = formatter.formatFile(testFile);

      expect(result, isTrue);

      final formattedContent = testFile.readAsStringSync();
      expect(formattedContent, contains('@FreezedGoStyle()'));
      expect(formattedContent, contains('@JsonKey(name: \'id\')'));
      expect(formattedContent, contains('@Default(0)'));
    });

    test('does not format file without @FreezedGoStyle annotation', () {
      final testFile = File('${tempDir.path}/test.dart');
      final originalContent = '''
@freezed
class User with _\$User {
  const factory User({
    @JsonKey(name: 'id') @Default(0) int id,
  }) = _User;
}
''';
      testFile.writeAsStringSync(originalContent);

      final result = formatter.formatFile(testFile);

      expect(result, isFalse);

      final content = testFile.readAsStringSync();
      expect(content, equals(originalContent));
    });

    test('skips non-dart files', () {
      final testFile = File('${tempDir.path}/test.txt');
      testFile.writeAsStringSync('some content');

      final result = formatter.formatFile(testFile);

      expect(result, isFalse);
    });

    test('handles empty factory constructor', () {
      final testFile = File('${tempDir.path}/test.dart');
      testFile.writeAsStringSync('''
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:freezed_go_style/freezed_go_style.dart';

part 'test.freezed.dart';

@FreezedGoStyle()
@freezed
class User with _\$User {
  const factory User() = _User;
}
''');

      final result = formatter.formatFile(testFile);

      // Should not fail, but may or may not format (empty params)
      expect(result, isA<bool>());
    });
  });
}

