#!/usr/bin/env nix-shell
#!nix-shell -i bash -p awscli2 jq
set -euo pipefail

export AWS_ACCESS_KEY_ID="e5d78ed7517b1b9df13eedd960f65dfe"
export AWS_SECRET_ACCESS_KEY="51010687e0053c337a88f17428a79c4380d7abf6ea10638f3834d5413d8a18e0"

ENDPOINT="https://a36871be6860124304dfb5c3b3eb8c1a.r2.cloudflarestorage.com"

echo "Listing R2 objects..."
KEYS=$(aws s3api list-objects-v2 --bucket cache --endpoint-url $ENDPOINT \
  --query 'Contents[].Key' --output text 2>/dev/null || true)

if [ -z "$KEYS" ] || [ "$KEYS" = "None" ]; then
  echo "R2 bucket already empty"
else
  echo "$KEYS" | tr '\t' '\n' >/tmp/all_keys.txt
  TOTAL=$(wc -l </tmp/all_keys.txt | tr -d ' ')
  echo "Found $TOTAL objects to delete"

  split -l 1000 /tmp/all_keys.txt /tmp/batch_

  delete_batch() {
    local file=$1
    local json=$(jq -R -s '{Objects: [split("\n")[] | select(length > 0) | {Key: .}]}' <"$file")
    aws s3api delete-objects --bucket cache --endpoint-url $ENDPOINT --delete "$json" >/dev/null
    echo "Deleted batch: $file"
  }

  export -f delete_batch
  export ENDPOINT

  ls /tmp/batch_* 2>/dev/null | xargs -P 4 -I {} bash -c 'delete_batch "$@"' _ {}

  rm -f /tmp/all_keys.txt /tmp/batch_*
  echo "R2 objects cleared"
fi

# Abort incomplete multipart uploads (always run)
SCRIPT_DIR="$(dirname "$0")"
"$SCRIPT_DIR/abort_multipart.py"

echo "R2 fully cleared"
