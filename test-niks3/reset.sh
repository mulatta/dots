#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

echo "=== Resetting niks3 environment ==="

./clear_r2.sh
./clear_pg.sh

echo "=== Reset complete ==="
