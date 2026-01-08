#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <store-path> [test-name]"
  echo "Example: $0 /nix/store/fw32lki9n5li6cf8irlbyvgkr3517b8h-fastfetch-2.55.1 fastfetch"
  exit 1
fi

STORE_PATH="$1"
TEST_NAME="${2:-$(basename "$STORE_PATH")}"

echo "=== Test: $TEST_NAME ==="
echo "Store path: $STORE_PATH"
echo ""

# Reset environment
./reset.sh

echo ""
echo "=== Running niks3 push ==="
START=$(date +%s.%N)

niks3 push "$STORE_PATH" 2>&1

END=$(date +%s.%N)
DURATION=$(echo "$END - $START" | bc)

echo ""
echo "=== Result ==="
echo "Test: $TEST_NAME"
echo "Duration: ${DURATION}s"
echo ""
