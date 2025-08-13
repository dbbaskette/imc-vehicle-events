#!/bin/bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
. "$SCRIPT_DIR/utilities.sh"

resolve_github_jar() {
  local github_url="$1"
  if [ -z "$github_url" ] || [ "$github_url" = "null" ]; then
    echo ""
    return 0
  fi
  if ! echo "$github_url" | grep -E 'github.com/([^/]+)/([^/]+)' >/dev/null; then
    log_warn "Invalid GitHub URL: $github_url"
    echo ""
    return 0
  fi
  local owner repo api_url
  owner=$(echo "$github_url" | sed -nE 's|.*github.com/([^/]+)/([^/]+).*|\1|p')
  repo=$(echo "$github_url" | sed -nE 's|.*github.com/([^/]+)/([^/]+).*|\2|p')
  api_url="https://api.github.com/repos/$owner/$repo/releases/latest"
  local release_json
  release_json=$(curl -sS -H "Accept: application/vnd.github.v3+json" "$api_url")
  local jar_url
  jar_url=$(echo "$release_json" | jq -r '.assets[]? | select(.name | endswith(".jar")) | .browser_download_url' | head -n1)
  echo "$jar_url"
}

register_app_uri() { # type name uri token scdf_url
  local app_type="$1"; local app_name="$2"; local uri="$3"; local token="$4"; local scdf_url="$5"
  local auth=()
  [ -n "$token" ] && auth=(-H "Authorization: Bearer $token")
  curl -sS -X POST "${scdf_url%/}/apps/$app_type/$app_name" -H "Content-Type: application/x-www-form-urlencoded" "${auth[@]}" --data-urlencode "uri=$uri"
}

register_custom_apps() { # token scdf_url config_file
  local token="$1"; local scdf_url="$2"; local config_file="$3"
  need yq; need jq
  local app_names
  app_names=$(yq -r '.apps | keys | .[]' "$config_file")
  for app in $app_names; do
    local type github_url maven_uri uri
    type=$(yq -r ".apps.$app.type" "$config_file")
    github_url=$(yq -r ".apps.$app.github_url // \"\"" "$config_file")
    maven_uri=$(yq -r ".apps.$app.uri // \"\"" "$config_file")
    uri=$(resolve_github_jar "$github_url")
    if [ -z "$uri" ]; then uri="$maven_uri"; fi
    if [ -z "$uri" ]; then log_warn "No URI for $app; skipping"; continue; fi
    log_info "Registering $app ($type) -> $uri"
    register_app_uri "$type" "$app" "$uri" "$token" "$scdf_url" >/dev/null || log_warn "Registration API call returned non-zero for $app"
  done
}

