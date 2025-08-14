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
    local stream_name
    stream_name=$(yq e '.stream.name // ""' "$config_file")
    if [[ -z "$stream_name" ]]; then
        log_error "No stream name found in configuration" "$context"
        return 1
    fi
    
    log_info "Processing stream: $stream_name" "$context"
    
    # Step 1: Delete existing streams
    log_info "Step 1: Cleaning up existing streams..." "$context"
    if yq e '.stream.main_stream.name' "$config_file" >/dev/null 2>&1; then
        # Handle multi-stream configuration (main + tap)
        local main_stream_name tap_stream_name
        main_stream_name=$(yq e '.stream.main_stream.name' "$config_file")
        tap_stream_name=$(yq e '.stream.tap_stream.name' "$config_file")
        
        log_info "Deleting tap stream: $tap_stream_name" "$context"
        curl -sS -X DELETE "${scdf_url%/}/streams/definitions/$tap_stream_name" \
            -H "Authorization: Bearer $token" 2>/dev/null || true
            
        log_info "Deleting main stream: $main_stream_name" "$context"
        curl -sS -X DELETE "${scdf_url%/}/streams/definitions/$main_stream_name" \
            -H "Authorization: Bearer $token" 2>/dev/null || true
    else
        # Handle single stream configuration
        log_info "Deleting stream: $stream_name" "$context"
        curl -sS -X DELETE "${scdf_url%/}/streams/definitions/$stream_name" \
            -H "Authorization: Bearer $token" 2>/dev/null || true
    fi
    
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
    if yq e '.stream.main_stream.name' "$config_file" >/dev/null 2>&1; then
        # Handle multi-stream configuration (main + tap)
        local main_stream_name main_stream_def tap_stream_name tap_stream_def
        main_stream_name=$(yq e '.stream.main_stream.name' "$config_file")
        main_stream_def=$(yq e '.stream.main_stream.definition' "$config_file")
        tap_stream_name=$(yq e '.stream.tap_stream.name' "$config_file")
        tap_stream_def=$(yq e '.stream.tap_stream.definition' "$config_file")
        
        # Create main stream
        log_info "Creating main stream: $main_stream_name" "$context"
        log_debug "Main stream definition: $main_stream_def" "$context"
        if ! curl -sS -X POST "${scdf_url%/}/streams/definitions" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            --data-urlencode "name=$main_stream_name" \
            --data-urlencode "definition=$main_stream_def"; then
            log_error "Failed to create main stream" "$context"
            return 1
        fi
        
        # Deploy main stream with properties
        log_info "Deploying main stream: $main_stream_name" "$context"
        local main_props_json
        main_props_json=$(build_deployment_properties_json "$config_file")
        if ! curl -sS -X POST "${scdf_url%/}/streams/deployments/$main_stream_name" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "$main_props_json"; then
            log_error "Failed to deploy main stream" "$context"
            return 1
        fi
        
        # Wait for main stream to start
        sleep 10
        
        # Create tap stream
        log_info "Creating tap stream: $tap_stream_name" "$context"
        log_debug "Tap stream definition: $tap_stream_def" "$context"
        if ! curl -sS -X POST "${scdf_url%/}/streams/definitions" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            --data-urlencode "name=$tap_stream_name" \
            --data-urlencode "definition=$tap_stream_def"; then
            log_error "Failed to create tap stream" "$context"
            return 1
        fi
        
        # Deploy tap stream
        log_info "Deploying tap stream: $tap_stream_name" "$context"
        local tap_props_json
        tap_props_json=$(build_deployment_properties_json "$config_file")
        if ! curl -sS -X POST "${scdf_url%/}/streams/deployments/$tap_stream_name" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "$tap_props_json"; then
            log_error "Failed to deploy tap stream" "$context"
            return 1
        fi
        
        log_success "Multi-stream deployment completed: $main_stream_name + $tap_stream_name" "$context"
    else
        # Handle single stream configuration
        local stream_def
        stream_def=$(yq e '.stream.definition' "$config_file")
        
        log_info "Creating stream: $stream_name" "$context"
        log_debug "Stream definition: $stream_def" "$context"
        if ! curl -sS -X POST "${scdf_url%/}/streams/definitions" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            --data-urlencode "name=$stream_name" \
            --data-urlencode "definition=$stream_def"; then
            log_error "Failed to create stream" "$context"
            return 1
        fi
        
        # Deploy stream
        log_info "Deploying stream: $stream_name" "$context"
        local props_json
        props_json=$(build_deployment_properties_json "$config_file")
        if ! curl -sS -X POST "${scdf_url%/}/streams/deployments/$stream_name" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "$props_json"; then
            log_error "Failed to deploy stream" "$context"
            return 1
        fi
        
        log_success "Single stream deployment completed: $stream_name" "$context"
    fi
    
    return 0
}

# Build deployment properties from config file as JSON (following SCDF-RAG pattern)
build_deployment_properties_json() {
    local config_file="$1"
    local context="DEPLOY_PROPS"
    
    # Check if deployment properties exist
    if ! yq e '.stream.deployment_properties' "$config_file" >/dev/null 2>&1; then
        log_debug "No deployment properties found, using empty config" "$context"
        echo "{}"
        return 0
    fi
    
    # Extract deployment properties in key=value format (preserving dots in keys)
    local props
    props=$(yq e '.stream.deployment_properties | to_entries | .[] | .key + "=" + .value' "$config_file")
    
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


