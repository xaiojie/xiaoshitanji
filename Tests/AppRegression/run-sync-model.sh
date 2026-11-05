#!/bin/bash
# Runs the app's actual synchronization orchestration on macOS with isolated
# credential/device/storage boundaries and a URLProtocol-backed fixture server.
set -euo pipefail
regression_root="$(cd "$(dirname "$0")/../.." && pwd)"
regression_temp="$(mktemp -d "${TMPDIR:-/tmp}/diary-sync-regression.XXXXXX")"
trap 'rm -rf "$regression_temp"' EXIT
cd "$regression_root"
xcrun swiftc -parse-as-library -swift-version 6 -module-name NutritionCore \
  -emit-library -static -emit-module \
  -emit-module-path "$regression_temp/NutritionCore.swiftmodule" \
  -o "$regression_temp/libNutritionCore.a" Sources/NutritionCore/*.swift
# UIKit's only dependency here is the device name, supplied by the test fixture.
sed '/^import UIKit$/d' FoodDiary/App/SyncModel.swift > "$regression_temp/SyncModel.swift"
xcrun swiftc -parse-as-library -swift-version 6 -I "$regression_temp" \
  "$regression_temp/SyncModel.swift" Tests/AppRegression/SyncModelRegression.swift \
  "$regression_temp/libNutritionCore.a" -o "$regression_temp/sync-model-regression"
"$regression_temp/sync-model-regression"
"$regression_temp/sync-model-regression" -legacy-owner
