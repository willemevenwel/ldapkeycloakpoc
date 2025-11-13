#!/bin/bash

# Application-Specific JWT Role Verification Script
# 
# This script tests JWT tokens and role assignments for organization-specific application clients
# Can run on host or inside container - automatically detects environment
# 
# Usage: ./test_application_jwt.sh <realm-name> <app-name> <org-prefix> [user1] [user2] ...
#        ./test_application_jwt.sh --defaults
# 
# Examples:
#   ./test_application_jwt.sh capgemini app-a acme test-acme-admin test-multi-org
#   ./test_application_jwt.sh --defaults  (uses capgemini, app-a, acme, test-acme-admin)

echo "========================================="
echo "APPLICATION JWT VERIFICATION"
echo "========================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Source network detection functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/network_detect.sh"

# Source HTTP debug logging functions
source "${SCRIPT_DIR}/http_debug.sh"

# Get appropriate URLs based on execution context
KEYCLOAK_URL=$(get_keycloak_url)

# Function to get user password - tries CSV first, then username fallback
get_user_password() {
    local username=$1
    
    if [ -f "data/users.csv" ]; then
        # Look up password in CSV file
        local csv_password=$(grep "^${username}," data/users.csv | cut -d',' -f5 | tr -d '"' | tr -d ' ')
        if [ -n "$csv_password" ]; then
            echo "$csv_password"
            return
        fi
    fi
    
    # Fallback to username as password
    echo "$username"
}

# Function to try authentication with both CSV and fallback passwords
try_authenticate() {
    local username=$1
    local realm=$2
    local client_id=$3
    local client_secret=$4
    
    # First try CSV password
    if [ -f "data/users.csv" ]; then
        local csv_password=$(grep "^${username}," data/users.csv | cut -d',' -f5 | tr -d '"' | tr -d ' ')
        if [ -n "$csv_password" ] && [ "$csv_password" != "$username" ]; then
            log_http_request "POST" "${KEYCLOAK_URL}/realms/${realm}/protocol/openid-connect/token" \
                "Content-Type: application/x-www-form-urlencoded" \
                "grant_type=password&client_id=${client_id}&client_secret=${client_secret}&username=${username}&password=***"
            
            local token_response=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${realm}/protocol/openid-connect/token" \
                -H "Content-Type: application/x-www-form-urlencoded" \
                -d "grant_type=password" \
                -d "client_id=${client_id}" \
                -d "client_secret=${client_secret}" \
                -d "username=${username}" \
                -d "password=${csv_password}")
            
            log_http_response "200" "$token_response"
            
            if echo "$token_response" | jq -e '.access_token' > /dev/null 2>&1; then
                echo "$token_response"
                return 0
            fi
        fi
    fi
    
    # Fallback to username as password
    log_http_request "POST" "${KEYCLOAK_URL}/realms/${realm}/protocol/openid-connect/token" \
        "Content-Type: application/x-www-form-urlencoded" \
        "grant_type=password&client_id=${client_id}&client_secret=${client_secret}&username=${username}&password=***"
    
    local token_response=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${realm}/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=password" \
        -d "client_id=${client_id}" \
        -d "client_secret=${client_secret}" \
        -d "username=${username}" \
        -d "password=${username}")
    
    log_http_response "200" "$token_response"
    
    echo "$token_response"
}

# Parse arguments
DEFAULTS_MODE=false
DEBUG_MODE=false

# Check for --defaults flag and --debug flag
while [[ $# -gt 0 ]]; do
    case $1 in
        --defaults)
            DEFAULTS_MODE=true
            shift
            ;;
        --debug)
            DEBUG_MODE=true
            enable_http_debug
            shift
            ;;
        *)
            break
            ;;
    esac
done

if [ "$DEFAULTS_MODE" = true ]; then
    REALM_NAME="capgemini"
    APP_NAME="app-a"
    ORG_PREFIX="acme"
    USERS=("test-acme-admin")
    echo -e "${BLUE}🎯 Using defaults: realm=${REALM_NAME}, app=${APP_NAME}, org=${ORG_PREFIX}, users=[${USERS[*]}]${NC}"
else
    if [ "$#" -lt 3 ]; then
        echo -e "${RED}Usage: $0 <realm-name> <app-name> <org-prefix> [user1] [user2] ... [--debug]${NC}"
        echo -e "${RED}   or: $0 --defaults [--debug]${NC}"
        echo ""
        echo "Examples:"
        echo "  $0 capgemini app-a acme test-acme-admin test-multi-org"
        echo "  $0 capgemini app-a acme test-acme-admin --debug"
        echo "  $0 --defaults"
        echo "  $0 --defaults --debug"
        exit 1
    fi

    REALM_NAME=$1
    APP_NAME=$2
    ORG_PREFIX=$3
    shift 3
    
    # Parse remaining args for users and flags
    USERS=()
    while [[ $# -gt 0 ]]; do
        case $1 in
            --debug)
                DEBUG_MODE=true
                enable_http_debug
                shift
                ;;
            *)
                USERS+=("$1")
                shift
                ;;
        esac
    done
    
    if [ ${#USERS[@]} -eq 0 ]; then
        # Default to organization test user if no users specified
        USERS=("test-${ORG_PREFIX}-admin")
        echo -e "${YELLOW}No users specified, defaulting to: ${USERS[*]}${NC}"
    fi
fi

if [ "$DEBUG_MODE" = true ]; then
    echo -e "${BOLD_PURPLE}🔧 Debug mode enabled - showing detailed HTTP transaction logs${NC}"
fi

CLIENT_ID="${ORG_PREFIX}-${APP_NAME}-client"

echo -e "${CYAN}🔍 Testing Configuration:${NC}"
echo -e "   Realm: ${GREEN}${REALM_NAME}${NC}"
echo -e "   Application: ${GREEN}${APP_NAME}${NC}"
echo -e "   Organization: ${GREEN}${ORG_PREFIX}${NC}"
echo -e "   Client ID: ${MAGENTA}${CLIENT_ID}${NC}"
echo -e "   Users: ${GREEN}${USERS[*]}${NC}"
echo ""
echo -e "${CYAN}🌐 Keycloak URLs:${NC}"
echo -e "   Token Endpoint: ${BLUE}${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/token${NC}"
echo -e "   Account Console: ${BLUE}${KEYCLOAK_URL}/realms/${REALM_NAME}/account${NC}"
echo -e "   Authorization URL: ${BLUE}${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/auth?client_id=${CLIENT_ID}&response_type=code${NC}"
echo -e "${YELLOW}   💡 Note: Redirect URIs are pre-configured in client (localhost:3000, 8000, 8080, etc.)${NC}"
echo ""

# Get Keycloak admin token to retrieve client secret
echo -e "${YELLOW}🔑 Getting admin token to retrieve client secret...${NC}"

ADMIN_USERNAME="admin-${REALM_NAME}"
ADMIN_PASSWORD="${ADMIN_USERNAME}"

ADMIN_TOKEN_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${ADMIN_USERNAME}" \
    -d "password=${ADMIN_PASSWORD}" \
    -d "grant_type=password" \
    -d "client_id=admin-cli")

ADMIN_TOKEN=$(echo "$ADMIN_TOKEN_RESPONSE" | jq -r '.access_token')

if [ "$ADMIN_TOKEN" = "null" ] || [ -z "$ADMIN_TOKEN" ]; then
    echo -e "${YELLOW}⚠️  Failed to get realm admin token, trying master admin...${NC}"
    
    ADMIN_TOKEN_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=admin" \
        -d "password=admin" \
        -d "grant_type=password" \
        -d "client_id=admin-cli")
    
    ADMIN_TOKEN=$(echo "$ADMIN_TOKEN_RESPONSE" | jq -r '.access_token')
    
    if [ "$ADMIN_TOKEN" = "null" ] || [ -z "$ADMIN_TOKEN" ]; then
        echo -e "${RED}❌ Failed to get admin token. Is Keycloak running with ${REALM_NAME} realm?${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✅ Got admin token${NC}"

# Get client UUID
echo -e "${YELLOW}🔍 Looking up client UUID for ${CLIENT_ID}...${NC}"

CLIENT_UUID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients?clientId=${CLIENT_ID}" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" | jq -r '.[0].id // empty')

if [ -z "$CLIENT_UUID" ]; then
    echo -e "${RED}❌ Client '${CLIENT_ID}' not found in realm '${REALM_NAME}'${NC}"
    echo -e "${YELLOW}💡 Did you run: ./keycloak/configure_application_clients.sh ${REALM_NAME} ${APP_NAME} ${ORG_PREFIX}${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Found client: ${CLIENT_ID} (UUID: ${CLIENT_UUID})${NC}"

# Get client secret
echo -e "${YELLOW}🔑 Getting client secret...${NC}"

CLIENT_SECRET=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients/${CLIENT_UUID}/client-secret" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" | jq -r '.value')

if [ "$CLIENT_SECRET" = "null" ] || [ -z "$CLIENT_SECRET" ]; then
    echo -e "${RED}❌ Failed to retrieve client secret${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Retrieved client secret for ${CLIENT_ID}${NC}"
echo ""

# Test each user
for USER in "${USERS[@]}"; do
    echo "========================================="
    echo -e "${CYAN}👤 Testing user: ${GREEN}${USER}${NC}"
    echo "========================================="
    
    # Get user password
    PASSWORD=$(get_user_password "$USER")
    
    echo -e "${YELLOW}🔐 Authenticating ${USER}...${NC}"
    
    # Try authentication
    TOKEN_RESPONSE=$(try_authenticate "$USER" "$REALM_NAME" "$CLIENT_ID" "$CLIENT_SECRET")
    
    # Check if we got a token
    ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')
    
    if [ -z "$ACCESS_TOKEN" ]; then
        echo -e "${RED}❌ Authentication failed for ${USER}${NC}"
        ERROR_DESC=$(echo "$TOKEN_RESPONSE" | jq -r '.error_description // .error // "Unknown error"')
        echo -e "${RED}   Error: ${ERROR_DESC}${NC}"
        echo ""
        continue
    fi
    
    echo -e "${GREEN}✅ Authentication successful${NC}"
    echo -e "${GREEN}🎫 JWT Token obtained and validated${NC}"
    echo ""
    
    # Decode JWT payload (the middle part between dots)
    JWT_PAYLOAD=$(echo "$ACCESS_TOKEN" | cut -d'.' -f2)
    
    # Add padding if needed (JWT base64 might not have padding)
    case $((${#JWT_PAYLOAD} % 4)) in
        2) JWT_PAYLOAD="${JWT_PAYLOAD}==" ;;
        3) JWT_PAYLOAD="${JWT_PAYLOAD}=" ;;
    esac
    
    # Decode base64
    DECODED_PAYLOAD=$(echo "$JWT_PAYLOAD" | base64 -d 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$DECODED_PAYLOAD" ]; then
        echo -e "${CYAN}📋 Decoded JWT payload:${NC}"
        echo "$DECODED_PAYLOAD" | jq '.'
        echo ""
        
        # Extract specific claims
        ROLES=$(echo "$DECODED_PAYLOAD" | jq -r '.realm_access.roles[]? // empty' 2>/dev/null)
        ORG_CLAIM=$(echo "$DECODED_PAYLOAD" | jq -r '.organization // "N/A"' 2>/dev/null)
        APP_CLAIM=$(echo "$DECODED_PAYLOAD" | jq -r '.application // "N/A"' 2>/dev/null)
        EMAIL=$(echo "$DECODED_PAYLOAD" | jq -r '.email // "N/A"' 2>/dev/null)
        USERNAME=$(echo "$DECODED_PAYLOAD" | jq -r '.preferred_username // "N/A"' 2>/dev/null)
        
        echo -e "${CYAN}🔑 Key Claims:${NC}"
        echo -e "   Username: ${GREEN}${USERNAME}${NC}"
        echo -e "   Email: ${GREEN}${EMAIL}${NC}"
        echo -e "   Organization: ${MAGENTA}${ORG_CLAIM}${NC}"
        echo -e "   Application: ${MAGENTA}${APP_CLAIM}${NC}"
        echo ""
        
        if [ -n "$ROLES" ]; then
            echo -e "${CYAN}👥 Assigned Roles:${NC}"
            echo "$ROLES" | while read -r role; do
                if [[ $role == ${ORG_PREFIX}-* ]]; then
                    echo -e "   ${GREEN}✓${NC} ${role} ${YELLOW}(organization-specific)${NC}"
                else
                    echo -e "   ${GREEN}✓${NC} ${role}"
                fi
            done
        else
            echo -e "${YELLOW}⚠️  No roles found in token${NC}"
        fi
        
        echo ""
        
        # Verify organization and application claims match expected values
        if [ "$ORG_CLAIM" = "$ORG_PREFIX" ]; then
            echo -e "${GREEN}✅ Organization claim matches: ${ORG_PREFIX}${NC}"
        else
            echo -e "${RED}❌ Organization claim mismatch! Expected: ${ORG_PREFIX}, Got: ${ORG_CLAIM}${NC}"
        fi
        
        if [ "$APP_CLAIM" = "$APP_NAME" ]; then
            echo -e "${GREEN}✅ Application claim matches: ${APP_NAME}${NC}"
        else
            echo -e "${RED}❌ Application claim mismatch! Expected: ${APP_NAME}, Got: ${APP_CLAIM}${NC}"
        fi
        
    else
        echo -e "${RED}❌ Failed to decode JWT payload${NC}"
    fi
    
    echo ""
done

echo "========================================="
echo -e "${GREEN}✨ Application JWT testing complete!${NC}"
echo "========================================="
echo ""

echo -e "${CYAN}📝 Summary:${NC}"
echo -e "   Client: ${MAGENTA}${CLIENT_ID}${NC}"
echo -e "   Organization: ${GREEN}${ORG_PREFIX}${NC}"
echo -e "   Application: ${GREEN}${APP_NAME}${NC}"
echo -e "   Users Tested: ${GREEN}${#USERS[@]}${NC}"
echo ""

echo -e "${YELLOW}💡 Next Steps:${NC}"
echo -e "   • Configure your ${APP_NAME} application to use client: ${CLIENT_ID}"
echo -e "   • Use the client secret retrieved above"
echo -e "   • JWT tokens will include organization and application claims"
echo -e "   • Filter roles by organization prefix: ${ORG_PREFIX}-*"
