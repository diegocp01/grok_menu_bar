#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/.build/billing-tests"
clang -fobjc-arc -mmacosx-version-min=13.0 -framework Foundation \
  -I "$ROOT/Sources/GrokCLIUsageMenuBar" "$ROOT/Tests/BillingParseTests.m" \
  -o "$ROOT/.build/billing-tests/BillingParseTests"
"$ROOT/.build/billing-tests/BillingParseTests"

clang -fobjc-arc -mmacosx-version-min=13.0 -framework Foundation \
  -I "$ROOT/Sources/GrokCLIUsageMenuBar" "$ROOT/Tests/AuthParseTests.m" \
  -o "$ROOT/.build/billing-tests/AuthParseTests"
"$ROOT/.build/billing-tests/AuthParseTests"
