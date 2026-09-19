#!/usr/bin/env bash
set -euo pipefail
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --release
