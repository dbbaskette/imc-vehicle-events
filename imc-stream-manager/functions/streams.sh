#!/bin/bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
. "$SCRIPT_DIR/utilities.sh"

# Deploy stream from configuration file - general purpose deployment
deploy_stream_from_config() {
    local config_file="$1"
    local token="$2" 
    local scdf_url="$3"
    local context="DEPLOY_STREAM"
    
    log_info "Deploying stream from configuration: $config_file" "$context"
    
    # Validate config file exists
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file" "$context"
        return 1
    fi
    
    # Load stream configuration
    local stream_names
    stream_names=$(yq e '.streams[].name' "$config_file")
    if [[ -z "$stream_names" ]]; then
        log_error "No stream names found in configuration" "$context"
        return 1
    fi
    
    # Step 1: Delete existing streams
    log_info "Step 1: Cleaning up existing streams..." "$context"
    
    # Migration: Explicitly delete old stream if it exists
    delete_stream "vehicle-events-output" "$token" "$scdf_url"
    
    for stream_name in $stream_names; do
        log_info "Deleting stream: $stream_name" "$context"
        delete_stream "$stream_name" "$token" "$scdf_url"
    done
    
    # Step 2: Unregister and register custom apps
    log_info "Step 2: Refreshing custom applications..." "$context"
    if yq e '.apps' "$config_file" >/dev/null 2>&1; then
        # Get app names from config
        local app_names
        app_names=$(yq e '.apps | keys | .[]' "$config_file")
        
        # Unregister existing apps
        for app_name in $app_names; do
            local app_type
            app_type=$(yq e ".apps.$app_name.type" "$config_file")
            log_info "Unregistering app: $app_name ($app_type)" "$context"
            curl -sS -X DELETE "${scdf_url%/}/apps/$app_type/$app_name" \
                -H "Authorization: Bearer $token" 2>/dev/null || true
        done
        
        # Register apps from GitHub
        for app_name in $app_names; do
            local app_type github_url jar_url version
            app_type=$(yq e ".apps.$app_name.type" "$config_file")
            github_url=$(yq e ".apps.$app_name.github_url" "$config_file")
            
            log_info "Registering app: $app_name ($app_type)" "$context"
            
            # Extract owner/repo from GitHub URL
            if echo "$github_url" | grep -E 'github.com/([^/]+)/([^/]+)' >/dev/null; then
                local owner repo
                owner=$(echo "$github_url" | sed -nE 's|.*github.com/([^/]+)/([^/]+).*|\1|p')
                repo=$(echo "$github_url" | sed -nE 's|.*github.com/([^/]+)/([^/]+).*|\2|p')
                
                # Get latest release
                local api_url="https://api.github.com/repos/$owner/$repo/releases/latest"
                if release_json=$(curl -s "$api_url" -H "Accept: application/vnd.github.v3+json"); then
                    version=$(echo "$release_json" | jq -r '.tag_name // .name // "unknown"')
                    
                    # Debug: show available assets
                    if [[ "${DEBUG:-false}" = "true" ]]; then
                        log_debug "Available assets in release $version:" "$context"
                        echo "$release_json" | jq -r '.assets[].name' | while read asset; do
                            log_debug "  - $asset" "$context"
                        done
                    fi
                    
                    # For multi-module projects, look for exact app name matches
                    jar_url=$(echo "$release_json" | jq -r ".assets[] | select(.name == \"$app_name-${version#v}.jar\" or .name == \"$app_name-$version.jar\") | .browser_download_url" | head -n1)
                    
                    # Fallback: broader pattern matching
                    if [[ -z "$jar_url" ]]; then
                        log_debug "Exact match not found, trying pattern matching for $app_name" "$context"
                        jar_url=$(echo "$release_json" | jq -r ".assets[] | select(.name | test(\"$app_name.*[.]jar$\") and (test(\"SNAPSHOT\") | not)) | .browser_download_url" | head -n1)
                    fi
                    
                    # Last resort: try SNAPSHOT
                    if [[ -z "$jar_url" ]]; then
                        log_warn "No release JAR found for $app_name, trying SNAPSHOT" "$context"
                        jar_url=$(echo "$release_json" | jq -r ".assets[] | select(.name | test(\"$app_name.*[.]jar$\")) | .browser_download_url" | head -n1)
                    fi
                    
                    if [[ -n "$jar_url" ]]; then
                        log_info "Found JAR: $jar_url (version: $version)" "$context"
                        if curl -sS -X POST "${scdf_url%/}/apps/$app_type/$app_name" \
                            -H "Authorization: Bearer $token" \
                            -H "Content-Type: application/x-www-form-urlencoded" \
                            -d "uri=$jar_url"; then
                            log_success "App $app_name registered successfully" "$context"
                        else
                            log_error "Failed to register app $app_name" "$context"
                            return 1
                        fi
                    else
                        log_error "No JAR found for app $app_name" "$context"
                        return 1
                    fi
                else
                    log_error "Failed to fetch release info for $owner/$repo" "$context"
                    return 1
                fi
            else
                log_error "Invalid GitHub URL format: $github_url" "$context"
                return 1
            fi
        done
    fi
    
    # Step 3: Create and deploy streams
    log_info "Step 3: Creating and deploying streams..." "$context"
    
    local stream_defs
    stream_defs=$(yq e '.streams[].definition' "$config_file")
    
    # Create an array of names and definitions (Bash 3 compatible)
    IFS=$'\n' read -r -d '' -a names_array <<< "$stream_names"
    IFS=$'\n' read -r -d '' -a defs_array <<< "$stream_defs"
    
    # Get deployment properties as a single JSON string
    local props_json
    props_json=$(build_deployment_properties_json "$config_file")

    for i in "${!names_array[@]}"; do
        local stream_name="${names_array[$i]}"
        local stream_def="${defs_array[$i]}"
        
        log_info "Creating and deploying stream: $stream_name" "$context"
        log_debug "Stream definition: $stream_def" "$context"
        
        # Create the stream
        if ! curl -sS -X POST "${scdf_url%/}/streams/definitions" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            --data-urlencode "name=$stream_name" \
            --data-urlencode "definition=$stream_def"; then
            log_error "Failed to create stream: $stream_name" "$context"
            return 1
        fi

        # Deploy the stream with common properties
        if ! curl -sS -X POST "${scdf_url%/}/streams/deployments/$stream_name" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "$props_json"; then
            log_error "Failed to deploy stream: $stream_name" "$context"
            return 1
        fi
        log_success "Stream $stream_name deployed successfully." "$context"
    done
    
    log_success "All streams deployed successfully." "$context"
    return 0
}

# Build deployment properties from config file as JSON (following SCDF-RAG pattern)
build_deployment_properties_json() {
    local config_file="$1"
    local context="DEPLOY_PROPS"
    
    # Check if deployment properties exist
    if ! yq e '.deployment_properties' "$config_file" >/dev/null 2>&1; then
        log_debug "No deployment properties found, using empty config" "$context"
        echo "{}"
        return 0
    fi
    
    # Extract deployment properties in key=value format (preserving dots in keys)
    local props
    props=$(yq e '.deployment_properties | to_entries | .[] | .key + "=" + .value' "$config_file")
    
    if [[ -z "$props" ]]; then
        log_debug "No valid properties found, using empty deployment config" "$context"
        echo "{}"
        return 0
    fi
    
    # Convert properties to JSON using the same method as SCDF-RAG
    local temp_file
    temp_file=$(mktemp)
    echo "$props" > "$temp_file"
    
    # Build JSON object using jq, handling keys with dots properly
    local deploy_props_json
    deploy_props_json=$(awk '{split($0, arr, "="); key=arr[1]; value=substr($0, index($0,"=")+1); print key "=" value}' "$temp_file" | \
        jq -R -s 'split("\n") | map(select(length > 0)) | map(split("=")) | map({key: .[0], value: (.[1:] | join("="))}) | from_entries')
    
    rm -f "$temp_file"
    
    if [[ -z "$deploy_props_json" ]] || [[ "$deploy_props_json" = "null" ]]; then
        log_debug "Failed to build JSON, using empty deployment config" "$context"
        echo "{}"
    else
        echo "$deploy_props_json"
    fi
}

# Check stream deployment status
check_stream_status() {
    local stream_name="$1"
    local token="$2"
    local scdf_url="$3"
    
    curl -sS "${scdf_url%/}/streams/deployments/$stream_name" \
        -H "Authorization: Bearer $token" | jq -r '.status // .state // "unknown"'
}

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


