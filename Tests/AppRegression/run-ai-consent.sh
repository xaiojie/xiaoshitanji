#!/bin/bash
set -euo pipefail
regression_root="$(cd "$(dirname "$0")/../.." && pwd)"
regression_temp="$(mktemp -d "${TMPDIR:-/tmp}/diary-ai-consent.XXXXXX")"
trap 'rm -rf "$regression_temp"' EXIT
cd "$regression_root"
xcrun swiftc -parse-as-library -swift-version 6 \
  FoodDiary/Services/AIConsent.swift Tests/AppRegression/AIConsentRegression.swift \
  -o "$regression_temp/ai-consent-regression"
"$regression_temp/ai-consent-regression"
