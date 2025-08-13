#!/bin/bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
. "$SCRIPT_DIR/utilities.sh"

delete_stream() { # name token scdf_url
  local name="$1"; local token="${2:-}"; local scdf_url="$3"
  local auth=()
  [ -n "$token" ] && auth=(-H "Authorization: Bearer $token")
  curl -sS -X DELETE "${scdf_url%/}/streams/definitions/$name?force=true" "${auth[@]}" || true
}

create_and_deploy_stream() { # name def token scdf_url
  local name="$1"; local def="$2"; local token="${3:-}"; local scdf_url="$4"
  local auth=()
  [ -n "$token" ] && auth=(-H "Authorization: Bearer $token")
  curl -sS -X POST "${scdf_url%/}/streams/definitions" -H "Content-Type: application/x-www-form-urlencoded" "${auth[@]}" \
    --data-urlencode "name=$name" \
    --data-urlencode "definition=$def" \
    --data-urlencode "deploy=true"
}


