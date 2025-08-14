#!/bin/bash
set -euo pipefail

# Show help function
show_help() {
    cat << EOF
Usage: $0 [--help] [--no-prompt]

IMC Telemetry Stream Manager - Interactive SCDF stream management

Options:
  --help      Show this help message and exit
  --no-prompt Run in non-interactive mode (for automation)

Features:
  - Register applications in SCDF
  - Create and manage stream configurations  
  - Deploy telemetry streams with tap-based architecture
  - Interactive menu for stream operations
  - Enhanced OAuth2 authentication with token persistence

Configuration:
  - Global settings: config.yml
  - Stream configs: stream-configs/<streamname>.yml
  - Authentication tokens cached in .cf_token

Examples:
  $0                    # Interactive mode
  $0 --no-prompt       # Automated mode
  $0 --help            # Show this help

EOF
}

# Early argument parsing for help
for arg in "$@"; do
    case $arg in
        --help|-h)
            show_help
            exit 0
            ;;
    esac
done

SCDF_CONFIG_DIR=${SCDF_CONFIG_DIR:-.}
SCDF_CONFIG=${SCDF_CONFIG:-$SCDF_CONFIG_DIR/config.yml}
STREAM_CONFIGS_DIR=${STREAM_CONFIGS_DIR:-$SCDF_CONFIG_DIR/stream-configs}
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

# Set global variables for auth system
export SCDF_CF_URL="$SCDF_URL"
export SCDF_TOKEN_URL="$SCDF_TOKEN_URL"

# Use existing TOKEN from environment, or get OAuth token
if [ -n "${TOKEN:-}" ]; then
    log_info "Using TOKEN from environment"
else
    # Get OAuth token using enhanced auth system
    if ! get_oauth_token; then
      log_error "Failed to obtain authentication token"
      exit 1
    fi
    # TOKEN is now set by get_oauth_token as 'token' variable  
    TOKEN="$token"
fi

# Ensure telemetry streams config is available
ensure_telemetry_config >/dev/null 2>&1 || true

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

# Initialize telemetry streams config if it doesn't exist
ensure_telemetry_config() {
  local config_file="$STREAM_CONFIGS_DIR/telemetry-streams.yml"
  
  # Create stream-configs directory if it doesn't exist
  mkdir -p "$STREAM_CONFIGS_DIR"
  
  # Ensure the config file exists (it should from our setup)
  if [[ ! -f "$config_file" ]]; then
    log_warn "telemetry-streams.yml not found in stream-configs directory"
    return 1
  fi
  
  # Check if it's in the streams index
  local idx_file="$SCDF_CONFIG_DIR/streams-index.yml"
  if [[ ! -f "$idx_file" ]] || ! yq e '.streams[] | select(.name == "telemetry-streams")' "$idx_file" >/dev/null 2>&1; then
    log_info "Adding telemetry-streams to index..."
    add_stream_to_index "telemetry-streams" "stream-configs/telemetry-streams.yml"
    log_success "Added telemetry-streams to index"
  fi
  
  return 0
}

interactive_create_stream() {
  echo
  echo -e "${C_BLUE}🆕 Create New Stream Config${C_RESET}"
  echo "1) 📡 Telemetry Streams (tap-based architecture)"
  echo "2) 🔧 Custom Stream"
  echo "b) ↩️  Back"
  read -p "Choose: " stream_type
  
  case "$stream_type" in
    1)
      ensure_telemetry_config
      echo -e "${C_GREEN}✅ Telemetry streams configuration is ready${C_RESET}"
      echo "Use option 5) 🚀 Deploy Streams to deploy the complete architecture"
      ;;
    2)
      read -p "🆕 Stream name: " name
      read -p "📥 Input queue (default telematics_work_queue.crash-detection-group): " inq
      inq=${inq:-telematics_work_queue.crash-detection-group}
      local def="rabbit --queues=$inq | imc-telemetry-processor | ( :rabbit --routingKey=vehicle-events.vehicle-events-group & imc-hdfs-sink )"
      local file
      file=$(make_stream_config "$name" "$def")
      log_success "Created stream config: $file"
      ;;
    b|B)
      return 0
      ;;
    *)
      echo "Invalid choice"
      ;;
  esac
}

# Deploy streams from stream-configs directory
deploy_streams_menu() {
  echo
  echo -e "${C_BLUE}🚗 Deploy Telemetry Streams${C_RESET}"
  
  # List available stream configs
  if [[ ! -d "$STREAM_CONFIGS_DIR" ]] || [[ -z "$(ls -A "$STREAM_CONFIGS_DIR" 2>/dev/null)" ]]; then
    echo -e "${C_YELLOW}No stream configurations found in $STREAM_CONFIGS_DIR${C_RESET}"
    return 1
  fi
  
  echo "Available stream configurations:"
  local configs=()
  local i=1
  for config_file in "$STREAM_CONFIGS_DIR"/*.yml; do
    if [[ -f "$config_file" ]]; then
      local basename_file=$(basename "$config_file" .yml)
      local stream_name
      stream_name=$(yq e '.stream.name // .stream.main_stream.name // ""' "$config_file")
      echo "  $i) $basename_file ${stream_name:+($stream_name)}"
      configs+=("$config_file")
      ((i++))
    fi
  done
  echo "  b) Back"
  
  read -p "Select stream to deploy: " choice
  
  if [[ "$choice" == "b" || "$choice" == "B" ]]; then
    return 0
  fi
  
  if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#configs[@]} ]]; then
    local selected_config="${configs[$((choice-1))]}"
    local config_name=$(basename "$selected_config" .yml)
    
    echo
    echo -e "${C_BLUE}Deploying: $config_name${C_RESET}"
    echo -e "${C_YELLOW}This will:${C_RESET}"
    echo "• Delete existing streams"
    echo "• Unregister and register applications"
    echo "• Create and deploy new streams"
    echo
    read -p "Continue with deployment? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      log_info "Starting deployment of $config_name..."
      if deploy_stream_from_config "$selected_config" "$TOKEN" "$SCDF_URL"; then
        log_success "Deployment completed successfully!"
      else
        log_error "Deployment failed!"
      fi
    else
      echo "Deployment cancelled."
    fi
  else
    echo "Invalid selection."
  fi
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
    *)
      ;;
  esac
}

manage_streams_menu() {
  echo
  echo -e "${C_BLUE}📚 Manage Configured Streams${C_RESET}"
  
  # List available stream configs
  if [[ ! -d "$STREAM_CONFIGS_DIR" ]] || [[ -z "$(ls -A "$STREAM_CONFIGS_DIR" 2>/dev/null)" ]]; then
    echo -e "${C_YELLOW}No stream configurations found in $STREAM_CONFIGS_DIR${C_RESET}"
    return 1
  fi
  
  echo "Available stream configurations:"
  local configs=()
  local i=1
  for config_file in "$STREAM_CONFIGS_DIR"/*.yml; do
    if [[ -f "$config_file" ]]; then
      local basename_file=$(basename "$config_file" .yml)
      local stream_name
      stream_name=$(yq e '.stream.name // .stream.main_stream.name // ""' "$config_file")
      echo "  $i) $basename_file ${stream_name:+($stream_name)}"
      configs+=("$config_file")
      ((i++))
    fi
  done
  echo "  b) Back"
  
  read -p "Select stream to manage: " choice
  
  if [[ "$choice" == "b" || "$choice" == "B" ]]; then
    return 0
  fi
  
  if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#configs[@]} ]]; then
    local selected_config="${configs[$((choice-1))]}"
    local config_name=$(basename "$selected_config" .yml)
    
    # Don't reload configuration - use current global SCDF settings
    # load_configuration "$selected_config" default || { log_error "Failed to load $selected_config"; return 1; }
    
    # Show stream management submenu with current global config context
    stream_management_submenu "$selected_config" "$config_name" "$TOKEN" "$SCDF_URL"
  else
    echo "Invalid selection."
  fi
}

stream_management_submenu() {
  local config_file="$1"
  local config_name="$2"
  local token="$3"
  local scdf_url="$4"
  
  # Debug: show what we received
  echo "DEBUG: token=${token:0:20}... scdf_url=$scdf_url"
  
  while true; do
    echo
    echo -e "${C_BLUE}🔧 Managing: $config_name${C_RESET}"
    
    # Get stream names from config
    local stream_names
    stream_names=$(yq e '.streams[].name' "$config_file")
    
    if [[ -n "$stream_names" ]]; then
        echo "Streams in this configuration:"
        for name in $stream_names; do
            echo "  - $name"
        done
    fi
    
    echo
    echo "1) 🗑️  Delete stream(s)"
    echo "2) 🔍 View stream status"
    echo "3) 📱 View apps in stream"
    echo "4) 🚢 Create & deploy stream"
    echo "5) 📦 Register apps"
    echo "6) 📋 Show stream definition"
    echo "b) ↩️  Back to stream list"
    
    read -p "Choose: " sub_choice
    
    case "$sub_choice" in
      1)
        echo -e "${C_YELLOW}Delete Stream(s)${C_RESET}"
        if [[ -n "$stream_names" ]]; then
          echo "This will delete the following streams:"
          for name in $stream_names; do
              echo "  - $name"
          done
          read -p "Continue? (y/N): " confirm
          if [[ "$confirm" =~ ^[Yy]$ ]]; then
            for name in $stream_names; do
              delete_stream "$name" "$token" "$scdf_url"
            done
            echo -e "${C_GREEN}Stream(s) deleted successfully${C_RESET}"
          fi
        else
          echo "No streams found in this configuration."
        fi
        ;;
      2)
        echo -e "${C_YELLOW}Stream Status${C_RESET}"
        if [[ -n "$stream_names" ]]; then
          for name in $stream_names; do
            echo "Stream ($name):"
            check_stream_status "$name" "$token" "$scdf_url"
          done
        else
          echo "No streams found in this configuration."
        fi
        ;;
      3)
        echo -e "${C_YELLOW}Apps in Stream${C_RESET}"
        if yq e '.apps' "$config_file" >/dev/null 2>&1; then
          echo "Applications:"
          yq e '.apps | to_entries | .[] | "- \(.key) (\(.value.type))"' "$config_file"
        else
          echo "No apps defined in this configuration"
        fi
        ;;
      4)
        echo -e "${C_YELLOW}Create & Deploy Stream${C_RESET}"
        read -p "Deploy now? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          if deploy_stream_from_config "$config_file" "$token" "$scdf_url"; then
            echo -e "${C_GREEN}Deployment completed successfully!${C_RESET}"
          else
            echo -e "${C_RED}Deployment failed!${C_RESET}"
          fi
        fi
        ;;
      5)
        echo -e "${C_YELLOW}Register Apps${C_RESET}"
        register_custom_apps "$token" "$scdf_url" "$config_file"
        ;;
      6)
        echo -e "${C_YELLOW}Stream Definition${C_RESET}"
        local stream_defs
        stream_defs=$(yq e '.streams[].definition' "$config_file")
        
        # Create arrays of names and definitions (Bash 3 compatible)
        IFS=$'\n' read -r -d '' -a names_array <<< "$stream_names"
        IFS=$'\n' read -r -d '' -a defs_array <<< "$stream_defs"

        for i in "${!names_array[@]}"; do
            local stream_name="${names_array[$i]}"
            local stream_def="${defs_array[$i]}"
            echo "Stream ($stream_name):"
            echo "  $stream_def"
        done
        ;;
      b|B)
        break
        ;;
      *)
        echo "Invalid choice"
        ;;
    esac
  done
}

main_menu() {
  while true; do
    print_header
    echo "1) 📦 Register default apps (global)"
    echo "2) 🆕 Create a new stream config"
    echo "3) 📚 List configured streams"
    echo "4) 🧭 Manage an existing stream"
    echo "5) 🚀 Deploy Streams"
    echo "6) 🧩 Register custom app by GitHub URL"
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
        manage_streams_menu
        ;;
      5)
        deploy_streams_menu
        ;;
      6)
        read -p "App type (source/processor/sink): " at
        read -p "App name: " an
        read -p "GitHub URL: " gh
        uri=$( "$FUNCS_DIR/app_registration.sh"; )
        # quick register using resolved GitHub release
        jar_url=$(bash -lc ". '$FUNCS_DIR/app_registration.sh'; resolve_github_jar '$gh'" | tail -n 1)
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

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [ "${NO_PROMPT:-false}" = "true" ]; then
    register_custom_apps "$TOKEN" "$SCDF_URL" "$SCDF_CONFIG"
    delete_stream "$STREAM_NAME" "$TOKEN" "$SCDF_URL" || true
    create_and_deploy_stream "$STREAM_NAME" "$STREAM_DEF" "$TOKEN" "$SCDF_URL"
    log_success "Done"
  else
    main_menu
  fi
fi