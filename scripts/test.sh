#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/scripts/test-startup.sh"
"$ROOT/scripts/test-pace.sh"
"$ROOT/scripts/test-billing.sh"
