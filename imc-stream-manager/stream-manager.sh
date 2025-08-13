#!/bin/bash
set -euo pipefail

SCDF_CONFIG_DIR=${SCDF_CONFIG_DIR:-imc-stream-manager}
SCDF_CONFIG=${SCDF_CONFIG:-$SCDF_CONFIG_DIR/config.yml}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
FUNCS_DIR="$SCRIPT_DIR/functions"

. "$FUNCS_DIR/utilities.sh"
. "$FUNCS_DIR/env_setup.sh"
. "$FUNCS_DIR/config.sh"
. "$FUNCS_DIR/app_registration.sh"
. "$FUNCS_DIR/streams.sh"
. "$FUNCS_DIR/auth.sh"

need curl; need jq; need yq

[ -f "$SCDF_CONFIG" ] || { echo -e "scdf:\n  url: \"https://dataflow.example.com\"\n  token_url: \"https://login.example.com/oauth/token\"\n" > "$SCDF_CONFIG"; }

load_configuration "$SCDF_CONFIG" default || { log_error "Failed to load global configuration"; exit 1; }

TOKEN="${TOKEN:-}"
if [ -z "$TOKEN" ]; then
  TOKEN=$(get_oauth_token || echo "")
fi

print_header() {
  echo -e "${C_MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
  echo -e "${C_GREEN}🚀 IMC Telemetry Stream Manager${C_RESET}"
  echo -e "${C_MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
}

select_stream_config() {
  local idx_file="$SCDF_CONFIG_DIR/streams-index.yml"
  if [ ! -f "$idx_file" ] || [ -z "$(yq -r '.streams[]? | .name' "$idx_file" 2>/dev/null)" ]; then
    log_warn "No streams configured yet"
    echo ""
    return 1
  fi
  echo -e "${C_BLUE}📚 Available streams:${C_RESET}"
  yq -r '.streams[] | "- \(.name) -> \(.file)"' "$idx_file"
  read -p "🔎 Enter stream name: " name
  local file
  file=$(yq -r ".streams[] | select(.name==\"$name\") | .file" "$idx_file")
  if [ -z "$file" ] || [ "$file" = "null" ]; then
    log_error "Stream not found: $name"
    return 1
  fi
  echo "$file"
}

interactive_create_stream() {
  read -p "🆕 Stream name: " name
  read -p "📥 Input queue (default telematics_work_queue.crash-detection-group): " inq
  inq=${inq:-telematics_work_queue.crash-detection-group}
  local def="rabbit --queues=$inq | imc-telemetry-processor | ( :rabbit --routingKey=vehicle-events.vehicle-events-group & imc-hdfs-sink )"
  local file
  file=$(make_stream_config "$name" "$def")
  log_success "Created stream config: $file"
}

operate_on_stream() {
  local file="$1"
  load_configuration "$file" default || { log_error "Failed to load $file"; return 1; }
  echo
  echo -e "${C_BLUE}🧭 Operate on stream: ${STREAM_NAME}${C_RESET}"
  echo "1) 📦 Register apps"
  echo "2) 🗑️  Delete stream"
  echo "3) 🚢 Create & deploy stream"
  echo "4) 🔍 Show stream status"
  echo "b) ↩️  Back"
  read -p "Choose: " c
  case "$c" in
    1) register_custom_apps "$TOKEN" "$SCDF_URL" "$file" ;;
    2) delete_stream "$STREAM_NAME" "$TOKEN" "$SCDF_URL" ;;
    3) create_and_deploy_stream "$STREAM_NAME" "$STREAM_DEF" "$TOKEN" "$SCDF_URL" ;;
    4) curl -sS "${SCDF_URL%/}/streams/deployments/$STREAM_NAME" ${TOKEN:+-H "Authorization: Bearer $TOKEN"} | jq -r '.status // .state // .name // "unknown"' ;;
    *) ;;
  esac
}

main_menu() {
  while true; do
    print_header
    echo "1) 📦 Register default apps (global)"
    echo "2) 🆕 Create a new stream config"
    echo "3) 📚 List configured streams"
    echo "4) 🧭 Manage an existing stream"
    echo "5) 🧩 Register custom app by GitHub URL"
    echo "q) ❎ Quit"
    read -p "Choose: " choice
    case "$choice" in
      1)
        register_custom_apps "$TOKEN" "$SCDF_URL" "$SCDF_CONFIG" || log_error "App registration failed"
        ;;
      2)
        interactive_create_stream
        ;;
      3)
        list_streams || true
        ;;
      4)
        local file
        file=$(select_stream_config) || continue
        operate_on_stream "$file"
        ;;
      5)
        read -p "App type (source/processor/sink): " at
        read -p "App name: " an
        read -p "GitHub URL: " gh
        uri=$( "$FUNCS_DIR/app_registration.sh"; )
        # quick register using resolved GitHub release
        jar_url=$(bash -lc ". '$FUNCS_DIR/app_registration.sh'; resolve_github_jar '$gh'")
        if [ -z "$jar_url" ]; then log_error "Failed to resolve jar from $gh"; else
          local auth=(); [ -n "$TOKEN" ] && auth=(-H "Authorization: Bearer $TOKEN")
          curl -sS -X POST "${SCDF_URL%/}/apps/$at/$an" -H "Content-Type: application/x-www-form-urlencoded" "${auth[@]}" --data-urlencode "uri=$jar_url" && log_success "Registered $an"
        fi
        ;;
      q|Q)
        exit 0
        ;;
      *)
        echo "Invalid choice"
        ;;
    esac
  done
}

if [ "${NO_PROMPT:-false}" = "true" ]; then
  register_custom_apps "$TOKEN" "$SCDF_URL" "$SCDF_CONFIG"
  delete_stream "$STREAM_NAME" "$TOKEN" "$SCDF_URL" || true
  create_and_deploy_stream "$STREAM_NAME" "$STREAM_DEF" "$TOKEN" "$SCDF_URL"
  log_success "Done"
else
  main_menu
fi


