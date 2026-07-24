#!/usr/bin/env bash
# test-gate.sh — per-feature compile-gate wrapper used by /sortie feature_test_cmd.
# The Sotto repo's `xcodebuild test` launcher crashes with "signal trap before
# establishing connection" (documented in HANDOFF_sotto-followups_2026-05-22.md).
# We use `build-for-testing` as the per-feature gate — verifies the worker's
# new test target compiles + links cleanly. Behavior assertion is the validator's
# job + the standalone-swift pattern in worker reports.
#
# Usage: bash scripts/test-gate.sh <test-target>
#   e.g. bash scripts/test-gate.sh SottoTests/TranscriptionRegistryLoaderFetchTests
set -euo pipefail
TARGET="${1:-}"
[ -z "$TARGET" ] && { echo "test-gate.sh: missing test-target argument" >&2; exit 2; }
xcodebuild build-for-testing \
  -project Sotto.xcodeproj -scheme Sotto -configuration Debug \
  -only-testing:"$TARGET" \
  -skipMacroValidation \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -quiet
