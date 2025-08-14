#!/bin/bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
. "$SCRIPT_DIR/utilities.sh"

CONFIG_LOADED=false
CONFIG_ENVIRONMENT=default

# Globals
SCDF_CONFIG_DIR=${SCDF_CONFIG_DIR:-"$(cd "$SCRIPT_DIR/.." && pwd)"}
GLOBAL_CONFIG="$SCDF_CONFIG_DIR/config.yml"
STREAMS_INDEX="$SCDF_CONFIG_DIR/streams-index.yml"

load_configuration() {
  local config_file="$1"
  local env="${2:-default}"
  need yq
  if [ ! -f "$config_file" ]; then
    log_error "Config file not found: $config_file"
    return 1
  fi
  # Handle both legacy format and new default: format
  export SCDF_URL=$(yq -r '.default.scdf.url // .scdf.url // "https://dataflow.example.com"' "$config_file")
  export SCDF_TOKEN_URL=$(yq -r '.default.scdf.token_url // .scdf.token_url // "https://login.example.com/oauth/token"' "$config_file")
  export STREAM_NAME=$(yq -r '.stream.name // ""' "$config_file")
  export STREAM_DEF=$(yq -r '.stream.definition // ""' "$config_file")
  CONFIG_LOADED=true
  CONFIG_ENVIRONMENT="$env"
  return 0
}

get_app_metadata() { # name env key
  local name="$1"; local env="${2:-default}"; local key="$3"
  need yq
  yq -r ".apps.$name.$key // \"\"" "$SCDF_CONFIG"
}

get_app_definitions() {
  need yq
  yq -r '.apps | keys | .[]' "$SCDF_CONFIG"
}

list_streams() {
  [ -f "$STREAMS_INDEX" ] && yq -r '.streams[]?.name' "$STREAMS_INDEX" || true
}

add_stream_to_index() {
  local name="$1"; local file="$2"
  touch "$STREAMS_INDEX"
  if ! yq -e '.streams' "$STREAMS_INDEX" >/dev/null 2>&1; then
    echo 'streams: []' > "$STREAMS_INDEX"
  fi
  yq -Yi ".streams += [{name: \"$name\", file: \"$file\"}]" "$STREAMS_INDEX"
}

make_stream_config() { # name def
  local name="$1"; local def="$2"
  local file="$SCDF_CONFIG_DIR/config-$name.yml"
  cat > "$file" <<YAML
scdf:
  url: "${SCDF_URL:-https://dataflow.example.com}"
  token_url: "${SCDF_TOKEN_URL:-https://login.example.com/oauth/token}"

apps:
  telemetryProcessor:
    type: processor
    github_url: "https://github.com/your-org/imc-telemetry-processor"
  hdfsSink:
    type: sink
    github_url: "https://github.com/your-org/imc-hdfs-sink"

stream:
  name: "$name"
  definition: "$def"
YAML
  add_stream_to_index "$name" "$file"
  echo "$file"
}

