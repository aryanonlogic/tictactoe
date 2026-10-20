#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
echo "== 1/3 UI audit =="
flutter test test/ui_audit_test.dart
echo "== 2/3 analyze =="
flutter analyze
echo "== 3/3 tests =="
flutter test test/game_logic_test.dart test/models_test.dart test/vault_controller_test.dart
echo "== ALL GREEN =="
