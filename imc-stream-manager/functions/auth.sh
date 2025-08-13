#!/bin/bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
. "$SCRIPT_DIR/utilities.sh"

# Acquire OAuth token if TOKEN is not already provided
get_oauth_token() {
  if [ -n "${TOKEN:-}" ]; then
    log_info "Using TOKEN from environment"
    echo "$TOKEN"
    return 0
  fi
  if [ -z "${SCDF_TOKEN_URL:-}" ] || [ -z "${SCDF_CLIENT_ID:-}" ] || [ -z "${SCDF_CLIENT_SECRET:-}" ]; then
    log_warn "No TOKEN and missing SCDF_TOKEN_URL/SCDF_CLIENT_ID/SCDF_CLIENT_SECRET; proceeding without auth"
    echo ""
    return 0
  fi
  need curl
  local resp
  resp=$(curl -sS -X POST "$SCDF_TOKEN_URL" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials&client_id=$SCDF_CLIENT_ID&client_secret=$SCDF_CLIENT_SECRET") || {
      log_error "Failed to obtain token from UAA"
      echo ""
      return 1
    }
  local token
  token=$(echo "$resp" | jq -r '.access_token // ""')
  if [ -z "$token" ]; then
    log_error "No access_token in token response"
    echo ""
    return 1
  fi
  echo "$token"
}


