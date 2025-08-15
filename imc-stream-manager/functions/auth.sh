#!/bin/bash
# Enhanced OAuth token management for stream-manager.sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
TOKEN_FILE="$SCRIPT_DIR/../.cf_token"
CLIENT_ID_FILE="$SCRIPT_DIR/../.cf_client_id"
CLIENT_SECRET_FILE="$SCRIPT_DIR/../.cf_client_secret"

. "$SCRIPT_DIR/utilities.sh"

# Enhanced curl wrapper for auth with retry logic
auth_curl_with_retry() {
    local url="$1"
    shift
    local max_retries=3
    local delay=2
    
    for attempt in $(seq 1 $max_retries); do
        if curl -s --max-time 30 --connect-timeout 10 --fail-with-body "$@" "$url"; then
            return 0
        fi
        
        local exit_code=$?
        if [[ $attempt -lt $max_retries ]]; then
            sleep $delay
            delay=$((delay * 2))
        fi
    done
    
    return 1
}

# Helper function to request and save a new token
_request_and_save_token() {
    local client_id="$1"
    local client_secret="$2"

    if [[ -z "$client_id" || -z "$client_secret" ]]; then
        log_error "Client ID and Secret are required."
        return 1
    fi

    if [[ -z "$SCDF_TOKEN_URL" ]]; then
        log_error "Token URL is not configured."
        return 1
    fi

    if token_response=$(auth_curl_with_retry "$SCDF_TOKEN_URL" \
        -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=client_credentials" \
        -d "client_id=$client_id" \
        -d "client_secret=$client_secret"); then
        
        new_token=$(echo "$token_response" | jq -r '.access_token // empty')
        
        if [[ -n "$new_token" && "$new_token" != "null" ]]; then
            echo "$new_token" > "$TOKEN_FILE"
            chmod 600 "$TOKEN_FILE"
            export token="$new_token"
            return 0
        else
            log_error "Failed to extract access token from response."
            if [[ "${DEBUG:-false}" = "true" ]]; then
                log_error "Token response: $token_response"
            fi
            return 1
        fi
    else
        log_error "Token request API call failed."
        if [[ "${DEBUG:-false}" = "true" ]]; then
            log_error "Token URL: $SCDF_TOKEN_URL"
            log_error "Client ID: $client_id"
        fi
        return 1
    fi
}

# Enhanced OAuth token acquisition with persistence and refresh
get_oauth_token() {
    # 1. Check environment variable first
    if [ -n "${TOKEN:-}" ]; then
        log_info "Using TOKEN from environment"
        export token="$TOKEN"
        return 0
    fi
    
    # 2. Check for an existing and valid token
    if [[ -f "$TOKEN_FILE" && -s "$TOKEN_FILE" ]]; then
        local existing_token
        existing_token=$(cat "$TOKEN_FILE")
        if [[ -n "$existing_token" && -n "$SCDF_CF_URL" ]]; then
            # Validate token by making a test API call
            if auth_curl_with_retry "$SCDF_CF_URL/about" \
                -H "Authorization: Bearer $existing_token" \
                -H "Accept: application/json" \
                -w "%{http_code}" \
                -o /dev/null | grep -q "200"; then
                
                log_success "Using existing valid token"
                export token="$existing_token"
                return 0
            else
                log_warn "Existing token is invalid or expired. Attempting to refresh."
            fi
        fi
    fi

    # 3. Attempt non-interactive re-authentication using stored credentials
    if [[ -f "$CLIENT_ID_FILE" && -s "$CLIENT_ID_FILE" && -f "$CLIENT_SECRET_FILE" && -s "$CLIENT_SECRET_FILE" ]]; then
        log_info "Attempting to re-authenticate with stored credentials..."
        local client_id client_secret
        client_id=$(cat "$CLIENT_ID_FILE")
        client_secret=$(cat "$CLIENT_SECRET_FILE")

        if _request_and_save_token "$client_id" "$client_secret"; then
            log_success "Successfully re-authenticated with stored credentials."
            return 0
        else
            log_warn "Failed to re-authenticate with stored credentials."
        fi
    fi

    # 4. Check for environment variables
    if [ -n "${SCDF_CLIENT_ID:-}" ] && [ -n "${SCDF_CLIENT_SECRET:-}" ]; then
        if _request_and_save_token "$SCDF_CLIENT_ID" "$SCDF_CLIENT_SECRET"; then
            # Save credentials for future use
            echo "$SCDF_CLIENT_ID" > "$CLIENT_ID_FILE"
            echo "$SCDF_CLIENT_SECRET" > "$CLIENT_SECRET_FILE"
            chmod 600 "$CLIENT_SECRET_FILE"
            log_success "Authentication successful using environment variables."
            return 0
        fi
    fi

    # 5. Fallback to interactive authentication
    if [ "${NO_PROMPT:-false}" != "true" ]; then
        log_info "Requesting new authentication"
        
        local SCDF_CLIENT_ID SCDF_CLIENT_SECRET
        
        # Prompt for Client ID
        if [[ -f "$CLIENT_ID_FILE" && -s "$CLIENT_ID_FILE" ]]; then
            SCDF_CLIENT_ID=$(cat "$CLIENT_ID_FILE")
            read -p "SCDF Client ID [default: $SCDF_CLIENT_ID]: " input_id
            SCDF_CLIENT_ID=${input_id:-$SCDF_CLIENT_ID}
        else
            read -p "SCDF Client ID: " SCDF_CLIENT_ID
        fi
        while [[ -z "$SCDF_CLIENT_ID" ]]; do
            log_error "Client ID cannot be empty."
            read -p "SCDF Client ID: " SCDF_CLIENT_ID
        done

        # Prompt for Client Secret
        read -rsp "SCDF Client Secret: " SCDF_CLIENT_SECRET
        echo
        while [[ -z "$SCDF_CLIENT_SECRET" ]]; do
            log_error "Client Secret cannot be empty."
            read -rsp "SCDF Client Secret: " SCDF_CLIENT_SECRET
            echo
        done
        
        # Attempt to get token with provided credentials and save them on success
        if _request_and_save_token "$SCDF_CLIENT_ID" "$SCDF_CLIENT_SECRET"; then
            log_success "Authentication successful. Credentials saved for future use."
            echo "$SCDF_CLIENT_ID" > "$CLIENT_ID_FILE"
            echo "$SCDF_CLIENT_SECRET" > "$CLIENT_SECRET_FILE"
            chmod 600 "$CLIENT_SECRET_FILE"
            return 0
        else
            log_error "Authentication failed."
            return 1
        fi
    else
        log_error "No authentication method available in non-interactive mode."
        return 1
    fi
}


