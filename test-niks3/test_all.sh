#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Test targets
FASTFETCH="/nix/store/fw32lki9n5li6cf8irlbyvgkr3517b8h-fastfetch-2.55.1"
DARWIN_SYSTEM="/nix/store/r9vfhn5dp77pc7zrk9aygf7xhdwyk2h5-darwin-system-25.11.08585aa"

# Workspaces
ORIG_WORKSPACE="$HOME/test-niks3-orig"
PATCHED_WORKSPACE="$HOME/test-niks3-patched"

RESULTS_FILE="/tmp/niks3-test-results-$(date +%Y%m%d-%H%M%S).txt"

log_result() {
  echo "$1" | tee -a "$RESULTS_FILE"
}

run_version_tests() {
  local version="$1"
  local workspace="$2"

  log_result ""
  log_result "======================================"
  log_result "Testing: $version"
  log_result "Workspace: $workspace"
  log_result "======================================"

  # Deploy this version
  log_result "Deploying $version..."
  pushd "$workspace" >/dev/null
  clan machines update taps
  popd >/dev/null
  log_result "Deploy complete"

  # Test fastfetch
  log_result ""
  log_result "--- Test: $version / fastfetch ---"
  START=$(date +%s.%N)
  ./reset.sh
  niks3 push "$FASTFETCH" 2>&1
  END=$(date +%s.%N)
  DURATION=$(echo "$END - $START" | bc)
  log_result "Result: $version / fastfetch = ${DURATION}s"

  # Test darwin-system
  log_result ""
  log_result "--- Test: $version / darwin-system ---"
  START=$(date +%s.%N)
  ./reset.sh
  niks3 push "$DARWIN_SYSTEM" 2>&1
  END=$(date +%s.%N)
  DURATION=$(echo "$END - $START" | bc)
  log_result "Result: $version / darwin-system = ${DURATION}s"
}

log_result "niks3 Performance Test"
log_result "Started: $(date)"
log_result ""

# Test original version
run_version_tests "orig" "$ORIG_WORKSPACE"

# Test patched version
run_version_tests "patched" "$PATCHED_WORKSPACE"

log_result ""
log_result "======================================"
log_result "Test Complete"
log_result "Results saved to: $RESULTS_FILE"
log_result "======================================"

cat "$RESULTS_FILE"
