# shellcheck shell=bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage:
  n8n-provision credentials DECLARATIONS.json

DECLARATIONS.json is an array of credential declarations. Supported kinds:
  {"kind":"httpHeaderAuth","name":"...","tokenFile":"...","headerName":"Authorization","valuePrefix":"Bearer ","allowedHttpRequestDomains":"all|none|domains","allowedDomains":"example.com"}
  {"kind":"httpBasicAuth","name":"...","user":"...","passwordFile":"..."}
  {"kind":"restateApi","name":"...","baseUrl":"http://[fd00::1]:8081","bearerTokenFile":"..."}

Secret file paths are references resolved relative to CREDENTIALS_DIRECTORY.
Declarations contain metadata and secret references, not secret values.
EOF
}

die() {
  echo "n8n-provision: $*" >&2
  exit 1
}

credential_id_by_name_type() {
  name=$1
  type=$2
  n8n-cli -j credential list | jq -er \
    --arg name "$name" \
    --arg type "$type" \
    '
      (.data // .) as $credentials
      | [$credentials[] | select(.name == $name and .type == $type) | .id]
      | if length == 1 then .[0]
        elif length == 0 then ""
        else error("multiple credentials named: " + $name + " type: " + $type)
        end
    '
}

apply_credential() {
  name=$1
  type=$2
  payload=$3
  id=$(credential_id_by_name_type "$name" "$type")
  if [ -n "$id" ]; then
    n8n-cli credential update "$id" "$payload"
  else
    n8n-cli credential create "$payload"
  fi
}

apply_json_credential() {
  name=$1
  type=$2
  data=$3
  tmp=$(mktemp)
  jq -n \
    --arg name "$name" \
    --arg type "$type" \
    --argjson data "$data" \
    '{name:$name,type:$type,data:$data}' >"$tmp"
  apply_credential "$name" "$type" "$tmp"
  rm -f "$tmp"
}

read_credential_file() {
  file=$1
  [ -n "${CREDENTIALS_DIRECTORY:-}" ] || die "CREDENTIALS_DIRECTORY is not set"
  cat "$CREDENTIALS_DIRECTORY/$file"
}

apply_spec_item() {
  item=$1
  kind=$(jq -r '.kind // empty' <<<"$item")
  name=$(jq -r '.name // empty' <<<"$item")
  [ -n "$kind" ] || die "credential kind missing"
  [ -n "$name" ] || die "credential name missing"

  case "$kind" in
  httpHeaderAuth)
    token_file=$(jq -r '.tokenFile // empty' <<<"$item")
    [ -n "$token_file" ] || die "tokenFile missing for $name"
    token=$(read_credential_file "$token_file")
    header_name=$(jq -r '.headerName // "Authorization"' <<<"$item")
    value_prefix=$(jq -r '.valuePrefix // "Bearer "' <<<"$item")
    allowed_mode=$(jq -r '.allowedHttpRequestDomains // "all"' <<<"$item")
    case "$allowed_mode" in
    all | none)
      data=$(jq -n \
        --arg header_name "$header_name" \
        --arg value "${value_prefix}${token}" \
        --arg allowed_mode "$allowed_mode" \
        '{name:$header_name,value:$value,allowedHttpRequestDomains:$allowed_mode}')
      ;;
    domains)
      allowed_domains=$(jq -r '.allowedDomains // empty' <<<"$item")
      [ -n "$allowed_domains" ] || die "allowedDomains missing for $name"
      data=$(jq -n \
        --arg header_name "$header_name" \
        --arg value "${value_prefix}${token}" \
        --arg allowed_domains "$allowed_domains" \
        '{name:$header_name,value:$value,allowedHttpRequestDomains:"domains",allowedDomains:$allowed_domains}')
      ;;
    *)
      die "unsupported allowedHttpRequestDomains for $name: $allowed_mode"
      ;;
    esac
    apply_json_credential "$name" httpHeaderAuth "$data"
    ;;
  httpBasicAuth)
    user=$(jq -r '.user // empty' <<<"$item")
    password_file=$(jq -r '.passwordFile // empty' <<<"$item")
    [ -n "$user" ] || die "user missing for $name"
    [ -n "$password_file" ] || die "passwordFile missing for $name"
    password=$(read_credential_file "$password_file")
    data=$(jq -n \
      --arg user "$user" \
      --arg password "$password" \
      '{user:$user,password:$password,allowedHttpRequestDomains:"none"}')
    apply_json_credential "$name" httpBasicAuth "$data"
    ;;
  restateApi)
    base_url=$(jq -r '.baseUrl // empty' <<<"$item")
    [ -n "$base_url" ] || die "baseUrl missing for $name"
    bearer_token_file=$(jq -r '.bearerTokenFile // empty' <<<"$item")
    bearer_token=""
    if [ -n "$bearer_token_file" ]; then
      bearer_token=$(read_credential_file "$bearer_token_file")
    fi
    data=$(jq -n \
      --arg base_url "$base_url" \
      --arg bearer_token "$bearer_token" \
      '{baseUrl:$base_url,bearerToken:$bearer_token}')
    apply_json_credential "$name" restateApi "$data"
    ;;
  *)
    die "unsupported credential kind: $kind"
    ;;
  esac
}

provision_credentials() {
  spec=$1
  [ -f "$spec" ] || die "credential spec not found: $spec"
  jq -e 'type == "array"' "$spec" >/dev/null

  count=$(jq 'length' "$spec")
  i=0
  while [ "$i" -lt "$count" ]; do
    apply_spec_item "$(jq -c ".[$i]" "$spec")"
    i=$((i + 1))
  done
}

case "${1:-}" in
-h | --help | help)
  usage
  ;;
credentials)
  shift
  [ "$#" -eq 1 ] || die "credentials requires SPEC.json"
  provision_credentials "$1"
  ;;
*)
  usage >&2
  exit 2
  ;;
esac
