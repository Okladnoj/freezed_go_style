# Freezed GoStyle Formatter

VS Code/Cursor extension that automatically formats Freezed models in Go-style alignment after `dart format`.

## Before
```dart
@freezed
class User with _$User {
  const factory User({
    @JsonKey(name: 'id') @Default(0) int id,
    @JsonKey(name: 'email') required String email,
    @JsonKey(name: 'full_name') @Default('') String fullName,
    @JsonKey(name: 'age') int? age,
    @JsonKey(name: 'is_active') @Default(true) bool isActive,
    @JsonKey(name: 'tags') @Default([]) List<String> tags,
    @JsonKey(name: 'metadata') Map<String, dynamic>? metadata,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _User;
}
```

## After
```dart
@FreezedGoStyle()
@freezed
class User with _$User {
  const factory User({
    @JsonKey(name: 'id')           @Default(0)    int                    id,
    @JsonKey(name: 'email')                       required String        email,
    @JsonKey(name: 'full_name')    @Default('')   String                 fullName,
    @JsonKey(name: 'age')                         int?                   age,
    @JsonKey(name: 'is_active')    @Default(true) bool                   isActive,
    @JsonKey(name: 'tags')         @Default([])   List<String>           tags,
    @JsonKey(name: 'metadata')                    Map<String, dynamic>?  metadata,
    @JsonKey(name: 'created_at')                  DateTime?              createdAt,
  }) = _User;
}
```

## Setup

To use the `@FreezedGoStyle()` annotation, you need to import the library:

```dart
import 'package:freezed_go_style/freezed_go_style.dart';
```

Add `freezed_go_style` to your `pubspec.yaml`:

```yaml
dependencies:
  freezed_go_style: last
```

## Features

- ✅ Automatically runs after `dart format` (Cmd+S / Ctrl+S)
- ✅ Formats only classes with `@FreezedGoStyle` annotation
- ✅ Fast native executable for instant formatting
- ✅ Zero configuration needed

## How It Works

1. Save your Dart file (Cmd+S / Ctrl+S)
2. `dart format` runs automatically
3. Extension detects save and formats classes with `@FreezedGoStyle()` annotation
4. File reloads with Go-style aligned parameters

## Requirements

- VS Code/Cursor 1.80.0+
- Dart SDK installed
- `freezed_go_style` package in workspace (or parent directory)

## Links

- [GitHub Repository](https://github.com/Okladnoj/freezed_go_style)
- [Dart Package](https://pub.dev/packages/freezed_go_style)
- [Issue Tracker](https://github.com/Okladnoj/freezed_go_style/issues)

## License

MIT License
