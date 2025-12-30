#!/bin/bash
cd "$(dirname "$0")"
echo "Testing formatter..."
echo "File to format: ../freezed_go_style_tester/lib/src/test_models.dart"
echo ""
dart run bin/freezed_go_style.dart -f ../freezed_go_style_tester/lib/src/test_models.dart -v
echo ""
echo "Exit code: $?"
echo "Done."

