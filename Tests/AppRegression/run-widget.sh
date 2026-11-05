#!/bin/bash
set -euo pipefail
regression_root="$(cd "$(dirname "$0")/../.." && pwd)"
regression_temp="$(mktemp -d "${TMPDIR:-/tmp}/diary-widget.XXXXXX")"
trap 'rm -rf "$regression_temp"' EXIT
cd "$regression_root"
xcrun swiftc -parse-as-library -swift-version 6 -module-name NutritionCore \
  -emit-library -static -emit-module \
  -emit-module-path "$regression_temp/NutritionCore.swiftmodule" \
  -o "$regression_temp/libNutritionCore.a" Sources/NutritionCore/*.swift
regression_sources=(Shared/DiaryWidgetSnapshot.swift Tests/AppRegression/WidgetRegression.swift)
for file in FoodDiary/Services/WidgetSnapshotBuilder.swift FoodDiary/App/WidgetNavigation.swift; do
  if [[ -f "$file" ]]; then regression_sources+=("$file"); fi
done
xcrun swiftc -parse-as-library -swift-version 6 -I "$regression_temp" \
  "${regression_sources[@]}" "$regression_temp/libNutritionCore.a" \
  -o "$regression_temp/widget-regression"
"$regression_temp/widget-regression"
