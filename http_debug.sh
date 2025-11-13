#!/bin/bash

# HTTP Debug Logging Library
# Provides elegant HTTP request/response logging for --debug mode
# Source this file in scripts that need HTTP debugging capabilities

# Color definitions for HTTP debugging (using colors not commonly used elsewhere)
GRAY='\033[0;90m'           # Dark gray for general HTTP transaction info
LIGHT_GRAY='\033[0;37m'     # Light gray for request details
BOLD_PURPLE='\033[1;35m'    # Bold purple for section headers
LIGHT_GREEN='\033[1;32m'    # Light green for successful responses
LIGHT_RED='\033[1;31m'      # Light red for error responses
ORANGE='\033[0;33m'         # Orange for HTTP status codes
BOLD_CYAN='\033[1;36m'      # Bold cyan for emphasis
NC='\033[0m'                # No Color

# Global flag to track if debug mode is enabled
HTTP_DEBUG_ENABLED=false

# Function to enable HTTP debug logging
# Call this when --debug flag is detected
enable_http_debug() {
    HTTP_DEBUG_ENABLED=true
}

# Function to disable HTTP debug logging
disable_http_debug() {
    HTTP_DEBUG_ENABLED=false
}

# Function to check if HTTP debug is enabled
is_http_debug_enabled() {
    [ "$HTTP_DEBUG_ENABLED" = true ]
}

# Function to log HTTP request details
# Usage: log_http_request "METHOD" "URL" "headers" "payload"
log_http_request() {
    if ! is_http_debug_enabled; then
        return
    fi
    
    local method="$1"
    local url="$2"
    local headers="$3"
    local payload="$4"
    
    {
        echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD_PURPLE}HTTP Transaction${NC}"
        echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD_PURPLE}Request Details:${NC}"
        echo -e "${LIGHT_GRAY}  Method:${NC}       ${BOLD_CYAN}${method}${NC}"
        echo -e "${LIGHT_GRAY}  URL:${NC}          ${BOLD_CYAN}${url}${NC}"
        
        if [ -n "$headers" ]; then
            echo -e "${LIGHT_GRAY}  Headers:${NC}"
            echo "$headers" | while IFS= read -r header; do
                if [ -n "$header" ]; then
                    echo -e "${LIGHT_GRAY}    ${header}${NC}"
                fi
            done
        fi
        
        if [ -n "$payload" ]; then
            echo -e "${LIGHT_GRAY}  Payload:${NC}"
            # Try to pretty-print JSON payload
            if echo "$payload" | jq . >/dev/null 2>&1; then
                echo "$payload" | jq . 2>/dev/null | while IFS= read -r line; do
                    echo -e "${LIGHT_GRAY}    ${line}${NC}"
                done
            else
                # If not JSON, try to format as URL-encoded data with password masking
                echo "$payload" | tr '&' '\n' | while IFS= read -r line; do
                    # Mask password fields
                    if echo "$line" | grep -q "password="; then
                        line=$(echo "$line" | sed 's/password=.*/password=***/')
                    fi
                    if echo "$line" | grep -q "client_secret="; then
                        # Don't mask client_secret in payload display, only in logs if needed
                        :
                    fi
                    echo -e "${LIGHT_GRAY}    ${line}${NC}"
                done
            fi
        fi
    } >&2
}

# Function to log HTTP response
# Usage: log_http_response "status_code" "response_body"
log_http_response() {
    if ! is_http_debug_enabled; then
        return
    fi
    
    local status_code="$1"
    local response_body="$2"
    
    {
        echo ""
        echo -e "${BOLD_PURPLE}Response:${NC}"
        
        # Color the status code based on HTTP status ranges
        local status_color=""
        if [ "$status_code" -ge 200 ] && [ "$status_code" -lt 300 ]; then
            status_color="$LIGHT_GREEN"
        elif [ "$status_code" -ge 300 ] && [ "$status_code" -lt 400 ]; then
            status_color="$ORANGE"
        elif [ "$status_code" -ge 400 ] && [ "$status_code" -lt 600 ]; then
            status_color="$LIGHT_RED"
        else
            status_color="$GRAY"
        fi
        
        echo -e "${LIGHT_GRAY}  Status:${NC}       ${status_color}${status_code}${NC}"
        
        if [ -n "$response_body" ] && [ "$response_body" != "null" ] && [ "$response_body" != "" ]; then
            echo -e "${LIGHT_GRAY}  Body:${NC}"
            
            # Determine color based on status code success/failure
            local body_color=""
            if [ "$status_code" -ge 200 ] && [ "$status_code" -lt 300 ]; then
                body_color="$LIGHT_GREEN"
            else
                body_color="$LIGHT_RED"
            fi
            
            # Try to pretty-print JSON response
            if echo "$response_body" | jq . >/dev/null 2>&1; then
                echo "$response_body" | jq . 2>/dev/null | while IFS= read -r line; do
                    echo -e "${body_color}    ${line}${NC}"
                done
            else
                # If not JSON, just display as-is with color
                echo -e "${body_color}    ${response_body}${NC}"
            fi
        fi
        
        echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
    } >&2
}

# Wrapper function for curl that automatically logs when debug is enabled
# Usage: debug_curl [curl arguments...]
# Returns the response body to stdout, status code in $HTTP_STATUS_CODE
debug_curl() {
    local curl_args=("$@")
    local method="GET"
    local url=""
    local headers=""
    local payload=""
    local temp_response="/tmp/curl_response_$$_${RANDOM}.txt"
    local temp_headers="/tmp/curl_headers_$$_${RANDOM}.txt"
    
    # Parse curl arguments to extract method, URL, headers, and payload
    local i=0
    while [ $i -lt ${#curl_args[@]} ]; do
        case "${curl_args[$i]}" in
            -X)
                i=$((i + 1))
                method="${curl_args[$i]}"
                ;;
            -H)
                i=$((i + 1))
                if [ -n "$headers" ]; then
                    headers="${headers}\n${curl_args[$i]}"
                else
                    headers="${curl_args[$i]}"
                fi
                ;;
            -d|--data|--data-raw)
                i=$((i + 1))
                if [ -n "$payload" ]; then
                    payload="${payload}&${curl_args[$i]}"
                else
                    payload="${curl_args[$i]}"
                fi
                ;;
            http*)
                url="${curl_args[$i]}"
                ;;
        esac
        i=$((i + 1))
    done
    
    # Log the request if debug is enabled
    if is_http_debug_enabled; then
        log_http_request "$method" "$url" "$(echo -e "$headers")" "$payload"
    fi
    
    # Execute curl with response capture
    # Add -D flag to capture headers and -o to capture body
    local response=$(curl -w "%{http_code}" -D "$temp_headers" -o "$temp_response" "${curl_args[@]}" 2>/dev/null)
    local status_code="${response: -3}"  # Last 3 characters are the status code
    local response_body=$(cat "$temp_response" 2>/dev/null)
    
    # Export status code for caller
    export HTTP_STATUS_CODE="$status_code"
    
    # Log the response if debug is enabled
    if is_http_debug_enabled; then
        log_http_response "$status_code" "$response_body"
    fi
    
    # Clean up temp files
    rm -f "$temp_response" "$temp_headers" 2>/dev/null
    
    # Return the response body
    echo "$response_body"
}

# Alternative simpler logging for existing curl calls
# Usage: log_http_call "description" before curl
#        Then call log_http_response_simple "$?" "$output" after
log_http_call() {
    if ! is_http_debug_enabled; then
        return
    fi
    
    local description="$1"
    {
        echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD_PURPLE}HTTP Transaction:${NC} ${LIGHT_GRAY}${description}${NC}"
    } >&2
}

log_http_response_simple() {
    if ! is_http_debug_enabled; then
        return
    fi
    
    local exit_code="$1"
    local response="$2"
    
    {
        if [ "$exit_code" -eq 0 ]; then
            echo -e "${LIGHT_GREEN}✓ Success${NC}"
        else
            echo -e "${LIGHT_RED}✗ Failed (exit code: ${exit_code})${NC}"
        fi
        
        if [ -n "$response" ]; then
            echo -e "${LIGHT_GRAY}Response:${NC}"
            if echo "$response" | jq . >/dev/null 2>&1; then
                echo "$response" | jq -C . 2>/dev/null | sed 's/^/  /'
            else
                echo "$response" | sed 's/^/  /'
            fi
        fi
        
        echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
    } >&2
}
