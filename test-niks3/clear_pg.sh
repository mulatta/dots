#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-root@taps.i}"

echo "Clearing PostgreSQL on $HOST..."
ssh "$HOST" bash <<'EOF'
set -euo pipefail
systemctl stop niks3
sudo -u postgres psql -d niks3 -c "TRUNCATE closures, objects, pending_closures, pending_objects, multipart_uploads CASCADE;"
systemctl start niks3
echo "Waiting for niks3 to be ready..."
sleep 3
EOF
echo "PostgreSQL cleared"
