#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BLACK='\033[0;30m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color

# Keycloak Shared Clients Configuration Script - SIMPLIFIED VERSION
# This script creates shared clients with working organization-aware role filtering

# Function to show help
show_help() {
    echo -e "${GREEN}Keycloak Shared Clients Configuration Script${NC}"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo -e "  $0 <realm-name> [organization-prefixes...]"
    echo ""
    echo -e "${YELLOW}Description:${NC}"
    echo -e "  Creates shared clients (web and API) with organization-aware role filtering"
    echo ""
    echo -e "${YELLOW}Arguments:${NC}"
    echo -e "  realm-name               Name of the realm to configure"
    echo -e "  organization-prefixes    Space-separated list of organization prefixes"
    echo -e "                          (default: acme xyz)"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  -h, --help              Show this help message"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo -e "  $0 walmart acme xyz abc"
    echo -e "  $0 capgemini acme xyz"
    echo ""
    echo -e "${YELLOW}Prerequisites:${NC}"
    echo -e "  - Realm must exist"
    echo -e "  - Organizations should be configured (run setup_organizations.sh first)"
    echo ""
    echo -e "${YELLOW}What this creates:${NC}"
    echo -e "  - shared-web-client (for web applications)"
    echo -e "  - shared-api-client (for API access)"
    echo -e "  - Protocol mappers with organization flags"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "  ./configure_application_clients.sh <realm-name> <app-name> <org-prefixes...>"
    echo ""
    exit 0
}

# Check for help flag first
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
fi

# Check if realm name parameter is provided
if [ $# -eq 0 ]; then
    echo -e "${RED}❌ Error: Realm name is required${NC}"
    echo ""
    echo -e "${YELLOW}Usage: $0 <realm-name> [organization-prefixes...]${NC}"
    echo -e "${YELLOW}Try: $0 --help for more information${NC}"
    echo ""
    echo -e "${YELLOW}If no organization prefixes provided, default prefixes will be used: acme, xyz${NC}"
    exit 1
fi

REALM="$1"
shift  # Remove realm name from arguments

# Use provided organization prefixes or defaults
if [ $# -eq 0 ]; then
    ORGANIZATION_PREFIXES=("acme" "xyz")
    echo -e "${YELLOW}💡 No organization prefixes provided, using defaults: ${ORGANIZATION_PREFIXES[*]}${NC}"
else
    ORGANIZATION_PREFIXES=("$@")
    echo -e "${BLUE}📋 Using provided organization prefixes: ${ORGANIZATION_PREFIXES[*]}${NC}"
fi

# Get script directory for relative imports
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source network detection utility
if [ -f "${SCRIPT_DIR}/../network_detect.sh" ]; then
    source "${SCRIPT_DIR}/../network_detect.sh"
else
    echo -e "${RED}❌ Network detection utility not found${NC}"
    exit 1
fi

ADMIN_USERNAME="admin-${REALM}"
ADMIN_PASSWORD="${ADMIN_USERNAME}"  # Password same as username
KEYCLOAK_URL="$(get_keycloak_url)"

echo -e "${GREEN}🔧 Configuring ${MAGENTA}Shared Clients${NC} for realm: ${REALM} (SIMPLIFIED VERSION)${NC}"

# Function to wait for Keycloak to be ready
wait_for_keycloak() {
    echo -e "${YELLOW}⏳ Waiting for ${MAGENTA}Keycloak${NC} and realm '${REALM}' to be ready...${NC}"
    until curl -s -f "${KEYCLOAK_URL}/realms/${REALM}" > /dev/null 2>&1; do
        echo -n "."
        sleep 2
    done
    echo -e "${GREEN}✅ ${MAGENTA}Keycloak${NC} and realm '${REALM}' are ready!${NC}"
}

# Function to get admin token
get_admin_token() {
    echo -e "${YELLOW}🔑 Getting admin token for '${ADMIN_USERNAME}'...${NC}"
    TOKEN_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${ADMIN_USERNAME}" \
        -d "password=${ADMIN_PASSWORD}" \
        -d "grant_type=password" \
        -d "client_id=admin-cli")
    
    TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
    
    if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
        echo -e "${YELLOW}⚠️  Failed to get realm admin token, trying master admin...${NC}"
        echo -e "${YELLOW}🔑 Getting master admin token...${NC}"
        
        # Try with master realm admin
        TOKEN_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "username=admin" \
            -d "password=admin" \
            -d "grant_type=password" \
            -d "client_id=admin-cli")
        
        TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
        
        if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
            echo -e "${RED}❌ Failed to get master admin token${NC}"
            echo -e "${RED}Response: $TOKEN_RESPONSE${NC}"
            exit 1
        fi
        echo -e "${GREEN}✅ Got master admin token${NC}"
        USE_MASTER_ADMIN=true
    else
        echo -e "${GREEN}✅ Got admin token for realm '${REALM}'${NC}"
        USE_MASTER_ADMIN=false
    fi
}

# Function to create shared web client
create_shared_web_client() {
    echo -e "${YELLOW}🌐 Creating shared web client...${NC}"
    
    CLIENT_CONFIG=$(cat <<EOF
{
    "clientId": "shared-web-client",
    "name": "Shared Web Application Client",
    "description": "Shared client for web applications with organization-aware role filtering",
    "enabled": true,
    "publicClient": false,
    "bearerOnly": false,
    "standardFlowEnabled": true,
    "implicitFlowEnabled": false,
    "directAccessGrantsEnabled": true,
    "serviceAccountsEnabled": false,
    "protocol": "openid-connect",
    "fullScopeAllowed": true,
    "redirectUris": [
        "http://localhost:3000/*",
        "http://localhost:8080/*",
        "http://localhost:8000/*",
        "https://localhost:3000/*",
        "https://localhost:8080/*",
        "https://localhost:8000/*"
    ],
    "webOrigins": [
        "http://localhost:3000",
        "http://localhost:8080",
        "http://localhost:8000",
        "https://localhost:3000",
        "https://localhost:8080",
        "https://localhost:8000"
    ],
    "attributes": {
        "access.token.lifespan": "1800",
        "client.secret.creation.time": "0",
        "oauth2.device.authorization.grant.enabled": "false",
        "oidc.ciba.grant.enabled": "false",
        "backchannel.logout.session.required": "true",
        "backchannel.logout.revoke.offline.tokens": "false"
    }
}
EOF
)

    HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${CLIENT_CONFIG}" \
        -o /tmp/client_create_response.json)
    
    if [ "$HTTP_STATUS" = "201" ]; then
        echo -e "${GREEN}✅ Created shared web client${NC}"
        
        # Get client ID from Location header
        CLIENT_UUID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/clients?clientId=shared-web-client" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" | jq -r '.[0].id')
        
        echo -e "${GREEN}   Client UUID: ${CLIENT_UUID}${NC}"
        
        # Generate and set client secret
        generate_client_secret "$CLIENT_UUID" "shared-web-client"
        
        return 0
    elif [ "$HTTP_STATUS" = "409" ]; then
        echo -e "${YELLOW}⚠️  Client 'shared-web-client' already exists${NC}"
        
        # Get existing client UUID
        CLIENT_UUID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/clients?clientId=shared-web-client" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" | jq -r '.[0].id')
        
        # Get existing client secret
        get_existing_client_secret "$CLIENT_UUID" "shared-web-client"
        
        return 0
    else
        echo -e "${RED}❌ Failed to create shared web client (HTTP $HTTP_STATUS)${NC}"
        cat /tmp/client_create_response.json
        return 1
    fi
}

# Function to create shared API client
create_shared_api_client() {
    echo -e "${YELLOW}🔌 Creating shared API client...${NC}"
    
    CLIENT_CONFIG=$(cat <<EOF
{
    "clientId": "shared-api-client",
    "name": "Shared API Client",
    "description": "Shared client for API access with organization-aware role filtering",
    "enabled": true,
    "publicClient": false,
    "bearerOnly": true,
    "standardFlowEnabled": false,
    "implicitFlowEnabled": false,
    "directAccessGrantsEnabled": false,
    "serviceAccountsEnabled": true,
    "protocol": "openid-connect",
    "fullScopeAllowed": true,
    "attributes": {
        "access.token.lifespan": "3600",
        "client.secret.creation.time": "0"
    }
}
EOF
)

    HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${CLIENT_CONFIG}" \
        -o /tmp/api_client_create_response.json)
    
    if [ "$HTTP_STATUS" = "201" ]; then
        echo -e "${GREEN}✅ Created shared API client${NC}"
        
        # Get client ID
        API_CLIENT_UUID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/clients?clientId=shared-api-client" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" | jq -r '.[0].id')
        
        echo -e "${GREEN}   Client UUID: ${API_CLIENT_UUID}${NC}"
        
        # Generate and set client secret
        generate_client_secret "$API_CLIENT_UUID" "shared-api-client"
        
        return 0
    elif [ "$HTTP_STATUS" = "409" ]; then
        echo -e "${YELLOW}⚠️  Client 'shared-api-client' already exists${NC}"
        
        # Get existing client UUID
        API_CLIENT_UUID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/clients?clientId=shared-api-client" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" | jq -r '.[0].id')
        
        # Get existing client secret
        get_existing_client_secret "$API_CLIENT_UUID" "shared-api-client"
        
        return 0
    else
        echo -e "${RED}❌ Failed to create shared API client (HTTP $HTTP_STATUS)${NC}"
        cat /tmp/api_client_create_response.json
        return 1
    fi
}

# Function to get existing client secret
get_existing_client_secret() {
    local client_uuid=$1
    local client_name=$2
    
    echo -e "${YELLOW}🔍 Getting existing secret for ${client_name}...${NC}"
    
    SECRET_RESPONSE=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/client-secret" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json")
    
    CLIENT_SECRET=$(echo "$SECRET_RESPONSE" | jq -r '.value')
    
    if [ "$CLIENT_SECRET" != "null" ] && [ -n "$CLIENT_SECRET" ]; then
        echo -e "${GREEN}✅ Retrieved secret for ${client_name}${NC}"
        
        # Store secrets for later display
        if [ "$client_name" = "shared-web-client" ]; then
            WEB_CLIENT_SECRET="$CLIENT_SECRET"
        elif [ "$client_name" = "shared-api-client" ]; then
            API_CLIENT_SECRET="$CLIENT_SECRET"
        fi
    else
        echo -e "${YELLOW}⚠️  Could not retrieve existing secret for ${client_name}${NC}"
    fi
}

# Function to generate client secret
generate_client_secret() {
    local client_uuid=$1
    local client_name=$2
    
    echo -e "${YELLOW}🔐 Generating secret for ${client_name}...${NC}"
    
    SECRET_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/client-secret" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json")
    
    CLIENT_SECRET=$(echo "$SECRET_RESPONSE" | jq -r '.value')
    
    if [ "$CLIENT_SECRET" != "null" ] && [ -n "$CLIENT_SECRET" ]; then
        echo -e "${GREEN}✅ Generated secret for ${client_name}${NC}"
        
        # Store secrets for later display
        if [ "$client_name" = "shared-web-client" ]; then
            WEB_CLIENT_SECRET="$CLIENT_SECRET"
        elif [ "$client_name" = "shared-api-client" ]; then
            API_CLIENT_SECRET="$CLIENT_SECRET"
        fi
    else
        echo -e "${RED}❌ Failed to generate secret for ${client_name}${NC}"
    fi
}

# SIMPLIFIED Protocol Mapper Functions - Based on working temporary scripts
# Function to clean existing mappers
clean_existing_mappers() {
    local client_uuid=$1
    local client_name=$2
    
    echo -e "${YELLOW}🗑️  Deleting existing protocol mappers for ${client_name}...${NC}"
    
    MAPPERS=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models" \
        -H "Authorization: Bearer ${TOKEN}")
    
    # Extract mapper IDs and delete them
    echo "$MAPPERS" | python3 -c "
import sys, json
try:
    mappers = json.load(sys.stdin)
    for mapper in mappers:
        if 'id' in mapper:
            print(mapper['id'])
except:
    pass
" | while read -r mapper_id; do
        if [ -n "$mapper_id" ]; then
            curl -s -X DELETE "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models/${mapper_id}" \
                -H "Authorization: Bearer ${TOKEN}"
        fi
    done
    
    echo -e "${GREEN}✅ Deleted all existing mappers for ${client_name}${NC}"
}

# Function to create essential realm roles mapper (based on final_fix_mappers.sh)
create_essential_realm_roles_mapper() {
    local client_uuid=$1
    local client_name=$2
    
    echo -e "${YELLOW}📝 Creating essential realm roles mapper for ${client_name}...${NC}"
    
    ESSENTIAL_MAPPER=$(cat <<EOF
{
    "name": "realm-roles",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-usermodel-realm-role-mapper",
    "config": {
        "access.token.claim": "true",
        "claim.name": "realm_access.roles",
        "id.token.claim": "true",
        "userinfo.token.claim": "true",
        "multivalued": "true"
    }
}
EOF
)

    HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${ESSENTIAL_MAPPER}" \
        -o /tmp/essential_mapper_response.json)
    
    if [ "$HTTP_STATUS" = "201" ] || [ "$HTTP_STATUS" = "409" ]; then
        echo -e "${GREEN}✅ Created essential realm roles mapper${NC}"
    else
        echo -e "${RED}❌ Failed to create essential mapper (HTTP $HTTP_STATUS)${NC}"
        cat /tmp/essential_mapper_response.json 2>/dev/null
        exit 1
    fi
}

# Function to create organization flags (based on final_fix_mappers.sh)
create_organization_flags() {
    local client_uuid=$1
    local client_name=$2
    
    echo -e "${YELLOW}📝 Adding simple organization flags for ${client_name}...${NC}"
    
    # Create organization flags for each prefix
    for prefix in "${ORGANIZATION_PREFIXES[@]}"; do
        ORG_FLAG=$(cat <<EOF
{
    "name": "${prefix}-enabled",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-hardcoded-claim-mapper",
    "config": {
        "access.token.claim": "true",
        "claim.name": "${prefix}_enabled",
        "claim.value": "true",
        "id.token.claim": "true",
        "userinfo.token.claim": "false"
    }
}
EOF
)

        curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d "${ORG_FLAG}" > /dev/null
    done
    
    echo -e "${GREEN}✅ Added organization flags${NC}"
}

# Function to create organization-aware role mappers (SIMPLIFIED VERSION)
create_organization_role_mappers() {
    local client_uuid=$1
    local client_name=$2
    
    echo -e "${YELLOW}🗺️  Creating organization role mappers for ${client_name}...${NC}"
    
    # Clean up any existing problematic mappers first
    clean_existing_mappers "$client_uuid" "$client_name"
    
    # Create ONLY the essential realm roles mapper
    create_essential_realm_roles_mapper "$client_uuid" "$client_name"
    
    # Create simple organization flags
    create_organization_flags "$client_uuid" "$client_name"
}

# Function to create organization claim mapper (SIMPLIFIED VERSION)
create_organization_claim_mapper() {
    local client_uuid=$1
    local client_name=$2
    
    echo -e "${YELLOW}🏢 Creating simple organization claim for ${client_name}...${NC}"
    
    # Just create a simple organization enabled flag - no complex scripting
    ORG_ENABLED_CONFIG=$(cat <<EOF
{
    "name": "organization-enabled",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-hardcoded-claim-mapper",
    "config": {
        "access.token.claim": "true",
        "claim.name": "organization_enabled",
        "claim.value": "true",
        "id.token.claim": "true",
        "userinfo.token.claim": "false"
    }
}
EOF
)

    HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${ORG_ENABLED_CONFIG}" \
        -o /tmp/org_enabled_response.json)
    
    if [ "$HTTP_STATUS" = "201" ] || [ "$HTTP_STATUS" = "409" ]; then
        echo -e "${GREEN}✅ Created organization enabled flag${NC}"
    else
        echo -e "${YELLOW}⚠️  Failed to create organization flag (HTTP $HTTP_STATUS)${NC}"
    fi
}

# Function to display client configuration summary
display_client_summary() {
    echo -e "${GREEN}🎉 Shared client configuration completed successfully! (SIMPLIFIED VERSION)${NC}"
    echo ""
    echo -e "${YELLOW}📋 Configuration Summary:${NC}"
    echo -e "   • Realm: ${GREEN}${REALM}${NC}"
    echo -e "   • Organizations: ${GREEN}${ORGANIZATION_PREFIXES[*]}${NC}"
    echo -e "   • Clients Created: ${GREEN}shared-web-client, shared-api-client${NC}"
    echo -e "   • Role Filtering: ${GREEN}Client-side filtering from realm_access.roles${NC}"
    echo ""
    
    echo -e "${GREEN}🌐 Web Client Details:${NC}"
    echo -e "   • Client ID: ${BLUE}shared-web-client${NC}"
    if [ -n "$WEB_CLIENT_SECRET" ]; then
        echo -e "   • Client Secret: ${BLUE}${WEB_CLIENT_SECRET}${NC}"
    fi
    echo -e "   • Redirect URIs: ${BLUE}http://localhost:3000/*, http://localhost:8080/*, http://localhost:8000/*${NC}"
    echo -e "   • Token Endpoint: ${BLUE}${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token${NC}"
    echo ""
    
    echo -e "${GREEN}🔌 API Client Details:${NC}"
    echo -e "   • Client ID: ${BLUE}shared-api-client${NC}"
    if [ -n "$API_CLIENT_SECRET" ]; then
        echo -e "   • Client Secret: ${BLUE}${API_CLIENT_SECRET}${NC}"
    fi
    echo -e "   • Bearer Only: ${BLUE}true${NC}"
    echo -e "   • Service Account: ${BLUE}enabled${NC}"
    echo ""
    
    echo -e "${GREEN}🗺️  Role Mappers Created (SIMPLIFIED):${NC}"
    echo -e "   • realm_access.roles - contains ALL user's realm roles"
    for prefix in "${ORGANIZATION_PREFIXES[@]}"; do
        echo -e "   • ${prefix}_enabled - boolean flag for ${prefix} organization"
    done
    echo -e "   • organization_enabled - general organization flag"
    echo ""
    
    echo -e "${YELLOW}💡 Important Notes:${NC}"
    echo -e "   • JWT tokens contain realm_access.roles with ALL user roles"
    echo -e "   • Organization flags indicate which orgs are supported"
    echo -e "   • Client applications must filter based on organization prefix"
    echo -e "   • Use realm_access.roles to determine which org roles the user has"
    echo ""
    
    echo -e "${GREEN}🌐 Access URLs:${NC}"
    echo -e "   • Realm URL: ${BLUE}${KEYCLOAK_URL}/realms/${REALM}${NC}"
    echo -e "   • Admin Console: ${BLUE}${KEYCLOAK_URL}/admin/${REALM}/console/${NC}"
    echo -e "   • Clients: ${BLUE}${KEYCLOAK_URL}/admin/${REALM}/console/#/${REALM}/clients${NC}"
    echo ""
    
    echo -e "${CYAN}🧪 Testing Examples:${NC}"
    echo ""
    echo -e "${CYAN}Get Token (Password Grant):${NC}"
    echo -e "${WHITE}curl -X POST '${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token' \\
  -H 'Content-Type: application/x-www-form-urlencoded' \\
  -d 'username=YOUR_USERNAME' \\
  -d 'password=YOUR_PASSWORD' \\
  -d 'grant_type=password' \\
  -d 'client_id=shared-web-client' \\
  -d 'client_secret=${WEB_CLIENT_SECRET:-YOUR_CLIENT_SECRET}'${NC}"
    echo ""
    
    echo -e "${CYAN}JWT Token Claims:${NC}"
    echo -e "${WHITE}# The token will contain:
# - realm_access.roles: All user roles (filter by prefix for organization roles)
# - ${ORGANIZATION_PREFIXES[0]}_enabled: Boolean flag for ${ORGANIZATION_PREFIXES[0]} organization
# - organization_enabled: General organization support flag${NC}"
    echo ""
    
    echo -e "${CYAN}➡️  Next steps:${NC}"
    echo -e "${CYAN}   1. Test authentication with your applications${NC}"
    echo -e "${CYAN}   2. Filter realm_access.roles by organization prefix in your app${NC}"
    echo -e "${CYAN}   3. Use organization flags for UI/feature toggles${NC}"
    echo -e "${CYAN}   4. Set up additional redirect URIs as needed${NC}"
}

# Main execution
echo -e "${GREEN}🚀 Starting simplified shared client configuration...${NC}"

wait_for_keycloak
get_admin_token

# Create clients with simplified mappers
if create_shared_web_client; then
    create_organization_role_mappers "$CLIENT_UUID" "shared-web-client"
    create_organization_claim_mapper "$CLIENT_UUID" "shared-web-client"
fi

if create_shared_api_client; then
    create_organization_role_mappers "$API_CLIENT_UUID" "shared-api-client"
    create_organization_claim_mapper "$API_CLIENT_UUID" "shared-api-client"
fi

# Display summary
display_client_summary

echo -e "${GREEN}✨ Simplified shared client configuration complete!${NC}"

# Clean up temp files
rm -f /tmp/*_response.json