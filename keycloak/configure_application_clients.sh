#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Keycloak Application Clients Configuration Script
# Creates organization-specific application clients
# Pattern: {org}-{app}-client (e.g., acme-app-a-client, xyz-app-a-client)

# Check if required parameters are provided
if [ $# -lt 3 ]; then
    echo "Usage: $0 <realm-name> <app-name> <org-prefix1> [org-prefix2] ..."
    echo ""
    echo "Examples:"
    echo "  $0 capgemini app-a acme xyz"
    echo "  $0 walmart app-b acme xyz abc"
    echo ""
    echo "This creates one client per organization for the specified application:"
    echo "  - acme-app-a-client (for ACME organization's App A access)"
    echo "  - xyz-app-a-client (for XYZ organization's App A access)"
    exit 1
fi

REALM="$1"
APP_NAME="$2"
shift 2  # Remove realm and app name from arguments
ORGANIZATION_PREFIXES=("$@")

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

echo -e "${GREEN}🔧 Configuring ${MAGENTA}Application Clients${NC} for realm: ${REALM}${NC}"
echo -e "${BLUE}📱 Application: ${APP_NAME}${NC}"
echo -e "${BLUE}🏢 Organizations: ${ORGANIZATION_PREFIXES[*]}${NC}"
echo ""

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
    else
        echo -e "${GREEN}✅ Got admin token for realm '${REALM}'${NC}"
    fi
}

# Function to get organization ID by name
get_organization_id() {
    local org_name=$1
    
    ORG_RESPONSE=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/organizations?search=${org_name}" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json")
    
    ORG_ID=$(echo "$ORG_RESPONSE" | jq -r ".[0].id // empty")
    echo "$ORG_ID"
}

# NOTE: We explored client-scope-based role filtering but found that:
# - Keycloak's oidc-usermodel-realm-role-mapper always includes ALL user realm roles
# - Scope mappings control which roles CAN be granted, but don't filter token contents
# - Complex filtering would require JavaScript mappers (not recommended in newer Keycloak)
# 
# DESIGN DECISION: Use fullScopeAllowed=true with organization claim for client-side filtering
# - Simpler, more maintainable
# - Clear security boundary: organization claim identifies context
# - Client applications filter roles by organization prefix
# - Still secure: client knows its organization context

# Function to create application client for an organization
create_organization_app_client() {
    local org_prefix=$1
    local client_id="${org_prefix}-${APP_NAME}-client"
    
    echo -e "${YELLOW}🌐 Creating client: ${CYAN}${client_id}${NC}"
    
    # Get organization ID for linking
    ORG_ID=$(get_organization_id "${org_prefix}")
    
    if [ -z "$ORG_ID" ]; then
        echo -e "${YELLOW}⚠️  Organization '${org_prefix}' not found, creating client without org link${NC}"
    else
        echo -e "${GREEN}   Found organization: ${org_prefix} (ID: ${ORG_ID})${NC}"
    fi
    
    CLIENT_CONFIG=$(cat <<EOF
{
    "clientId": "${client_id}",
    "name": "${org_prefix} - ${APP_NAME} Application",
    "description": "Organization-specific client for ${org_prefix} accessing ${APP_NAME}",
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
        "http://localhost:3000/callback",
        "http://localhost:3000/auth/callback",
        "http://localhost:8080/*",
        "http://localhost:8080/callback",
        "http://localhost:8080/auth/callback",
        "http://localhost:8000/*",
        "http://localhost:8000/callback",
        "http://localhost:8000/auth/callback",
        "https://localhost:3000/*",
        "https://localhost:3000/callback",
        "https://localhost:3000/auth/callback",
        "https://localhost:8080/*",
        "https://localhost:8080/callback",
        "https://localhost:8080/auth/callback",
        "https://localhost:8000/*",
        "https://localhost:8000/callback",
        "https://localhost:8000/auth/callback",
        "http://${APP_NAME}.${org_prefix}.${REALM}.local/*",
        "http://${APP_NAME}.${org_prefix}.${REALM}.local/callback",
        "http://${APP_NAME}.${org_prefix}.${REALM}.local/auth/callback",
        "https://${APP_NAME}.${org_prefix}.${REALM}.local/*",
        "https://${APP_NAME}.${org_prefix}.${REALM}.local/callback",
        "https://${APP_NAME}.${org_prefix}.${REALM}.local/auth/callback",
        "http://${org_prefix}-${APP_NAME}.${REALM}.local/*",
        "http://${org_prefix}-${APP_NAME}.${REALM}.local/callback",
        "https://${org_prefix}-${APP_NAME}.${REALM}.local/*",
        "https://${org_prefix}-${APP_NAME}.${REALM}.local/callback"
    ],
    "webOrigins": [
        "http://localhost:3000",
        "http://localhost:8080",
        "http://localhost:8000",
        "https://localhost:3000",
        "https://localhost:8080",
        "https://localhost:8000",
        "http://${APP_NAME}.${org_prefix}.${REALM}.local",
        "https://${APP_NAME}.${org_prefix}.${REALM}.local",
        "http://${org_prefix}-${APP_NAME}.${REALM}.local",
        "https://${org_prefix}-${APP_NAME}.${REALM}.local"
    ],
    "attributes": {
        "access.token.lifespan": "1800",
        "oauth2.device.authorization.grant.enabled": "false",
        "oidc.ciba.grant.enabled": "false",
        "backchannel.logout.session.required": "true",
        "backchannel.logout.revoke.offline.tokens": "false",
        "organization": "${org_prefix}",
        "application": "${APP_NAME}"
    }
}
EOF
)

    HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${CLIENT_CONFIG}" \
        -o /tmp/${client_id}_create_response.json)
    
    if [ "$HTTP_STATUS" = "201" ]; then
        echo -e "${GREEN}✅ Created client: ${client_id}${NC}"
        
        # Get client UUID
        CLIENT_UUID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/clients?clientId=${client_id}" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" | jq -r '.[0].id')
        
        # Generate and set client secret
        generate_client_secret "$CLIENT_UUID" "$client_id" "$org_prefix"
        
        # Create protocol mappers (includes realm roles + organization/application metadata)
        create_client_protocol_mappers "$CLIENT_UUID" "$client_id" "$org_prefix"
        
        return 0
    elif [ "$HTTP_STATUS" = "409" ]; then
        echo -e "${YELLOW}⚠️  Client '${client_id}' already exists${NC}"
        
        # Get existing client UUID
        CLIENT_UUID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/clients?clientId=${client_id}" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" | jq -r '.[0].id')
        
        # Get existing client secret
        get_existing_client_secret "$CLIENT_UUID" "$client_id" "$org_prefix"
        
        return 0
    else
        echo -e "${RED}❌ Failed to create client '${client_id}' (HTTP $HTTP_STATUS)${NC}"
        cat /tmp/${client_id}_create_response.json
        return 1
    fi
}

# Function to generate client secret
generate_client_secret() {
    local client_uuid=$1
    local client_id=$2
    local org_prefix=$3
    
    echo -e "${YELLOW}🔐 Generating secret for ${client_id}...${NC}"
    
    SECRET_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/client-secret" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json")
    
    CLIENT_SECRET=$(echo "$SECRET_RESPONSE" | jq -r '.value')
    
    if [ "$CLIENT_SECRET" != "null" ] && [ -n "$CLIENT_SECRET" ]; then
        echo -e "${GREEN}✅ Generated secret for ${client_id}${NC}"
        
        # Store client information in arrays
        CLIENT_IDS+=("${client_id}")
        CLIENT_SECRETS_VALUES+=("$CLIENT_SECRET")
    else
        echo -e "${RED}❌ Failed to generate secret for ${client_id}${NC}"
    fi
}

# Function to get existing client secret
get_existing_client_secret() {
    local client_uuid=$1
    local client_id=$2
    local org_prefix=$3
    
    echo -e "${YELLOW}🔍 Getting existing secret for ${client_id}...${NC}"
    
    SECRET_RESPONSE=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/client-secret" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json")
    
    CLIENT_SECRET=$(echo "$SECRET_RESPONSE" | jq -r '.value')
    
    if [ "$CLIENT_SECRET" != "null" ] && [ -n "$CLIENT_SECRET" ]; then
        echo -e "${GREEN}✅ Retrieved secret for ${client_id}${NC}"
        CLIENT_IDS+=("${client_id}")
        CLIENT_SECRETS_VALUES+=("$CLIENT_SECRET")
    else
        echo -e "${YELLOW}⚠️  Could not retrieve existing secret for ${client_id}${NC}"
    fi
}

# Function to create protocol mappers for the client
create_client_protocol_mappers() {
    local client_uuid=$1
    local client_id=$2
    local org_prefix=$3
    
    echo -e "${YELLOW}🗺️  Creating protocol mappers for ${client_id}...${NC}"
    
    # 1. Realm Roles Mapper - includes ALL user's realm roles
    # Note: Client applications should filter by organization prefix using the organization claim
    REALM_ROLES_MAPPER=$(cat <<EOF
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
    
    curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${REALM_ROLES_MAPPER}" > /dev/null
    
    # 2. Organization Claim Mapper (hardcoded) - identifies which organization this client belongs to
    ORG_CLAIM_MAPPER=$(cat <<EOF
{
    "name": "organization",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-hardcoded-claim-mapper",
    "config": {
        "access.token.claim": "true",
        "claim.name": "organization",
        "claim.value": "${org_prefix}",
        "id.token.claim": "true",
        "userinfo.token.claim": "true",
        "jsonType.label": "String"
    }
}
EOF
)
    
    curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${ORG_CLAIM_MAPPER}" > /dev/null
    
    # 2. Application Claim Mapper
    APP_CLAIM_MAPPER=$(cat <<EOF
{
    "name": "application",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-hardcoded-claim-mapper",
    "config": {
        "access.token.claim": "true",
        "claim.name": "application",
        "claim.value": "${APP_NAME}",
        "id.token.claim": "true",
        "userinfo.token.claim": "true",
        "jsonType.label": "String"
    }
}
EOF
)
    
    curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${APP_CLAIM_MAPPER}" > /dev/null
    
    # 3. Email Mapper
    EMAIL_MAPPER=$(cat <<EOF
{
    "name": "email",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-usermodel-property-mapper",
    "config": {
        "access.token.claim": "true",
        "claim.name": "email",
        "id.token.claim": "true",
        "userinfo.token.claim": "true",
        "user.attribute": "email",
        "jsonType.label": "String"
    }
}
EOF
)
    
    curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${EMAIL_MAPPER}" > /dev/null
    
    # 4. Username Mapper
    USERNAME_MAPPER=$(cat <<EOF
{
    "name": "username",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-usermodel-property-mapper",
    "config": {
        "access.token.claim": "true",
        "claim.name": "preferred_username",
        "id.token.claim": "true",
        "userinfo.token.claim": "true",
        "user.attribute": "username",
        "jsonType.label": "String"
    }
}
EOF
)
    
    curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${USERNAME_MAPPER}" > /dev/null
    
    echo -e "${GREEN}✅ Created protocol mappers for ${client_id}${NC}"
}

# Function to display configuration summary
display_summary() {
    echo ""
    echo -e "${GREEN}🎉 Application client configuration completed successfully!${NC}"
    echo ""
    echo -e "${YELLOW}📋 Configuration Summary:${NC}"
    echo -e "   • Realm: ${GREEN}${REALM}${NC}"
    echo -e "   • Application: ${GREEN}${APP_NAME}${NC}"
    echo -e "   • Organizations: ${GREEN}${ORGANIZATION_PREFIXES[*]}${NC}"
    echo -e "   • Clients Created: ${GREEN}${#CLIENT_IDS[@]}${NC}"
    echo ""
    
    echo -e "${GREEN}🔑 Client Credentials:${NC}"
    for i in "${!CLIENT_IDS[@]}"; do
        echo -e "   ${CYAN}${CLIENT_IDS[$i]}${NC}"
        echo -e "      Client ID: ${BLUE}${CLIENT_IDS[$i]}${NC}"
        echo -e "      Client Secret: ${BLUE}${CLIENT_SECRETS_VALUES[$i]}${NC}"
        echo ""
    done
    
    echo -e "${GREEN}🔐 Security Model & Design Decision:${NC}"
    echo -e "   • fullScopeAllowed: ${MAGENTA}true${NC} (All user roles included)"
    echo -e "   • Role Filtering Approach: ${YELLOW}Client-side via organization claim${NC}"
    echo -e "   • Rationale: Keycloak's realm role mappers include ALL user roles by design"
    echo -e "   • Trust Model: Organization claim identifies client's organizational context"
    echo ""
    
    echo -e "${GREEN}🗺️  Protocol Mappers Created:${NC}"
    echo -e "   • realm_access.roles - ${YELLOW}ALL user realm roles (client must filter)${NC}"
    echo -e "   • organization - ${GREEN}Org identifier (${ORGANIZATION_PREFIXES[*]})${NC} ${CYAN}← Use this to filter!${NC}"
    echo -e "   • application - Application name (${APP_NAME})"
    echo -e "   • email - User email address"
    echo -e "   • preferred_username - Username"
    echo ""
    
    echo -e "${CYAN}📘 How to Use the Organization Claim:${NC}"
    echo -e "   ${CYAN}1. Extract 'organization' claim from JWT (e.g., \"acme\")${NC}"
    echo -e "   ${CYAN}2. Filter realm_access.roles to only include roles starting with that prefix${NC}"
    echo -e "   ${CYAN}3. Example: If organization=\"acme\", only use roles matching \"acme_*\"${NC}"
    echo -e "   ${CYAN}4. This prevents cross-organization authorization bypass${NC}"
    echo ""
    
    echo -e "${GREEN}🌐 Keycloak URLs:${NC}"
    echo -e "   Token Endpoint: ${BLUE}${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token${NC}"
    echo -e "   Authorization Endpoint: ${BLUE}${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/auth${NC}"
    echo -e "   Account Console: ${BLUE}${KEYCLOAK_URL}/realms/${REALM}/account${NC}"
    echo ""
    
    echo -e "${GREEN}🔐 Application Login URLs (per organization):${NC}"
    echo -e "${YELLOW}   💡 Redirect URIs are pre-configured - no need to specify redirect_uri parameter${NC}"
    for i in "${!CLIENT_IDS[@]}"; do
        local org="${ORGANIZATION_PREFIXES[$i]}"
        echo -e "   ${CYAN}${CLIENT_IDS[$i]}:${NC}"
        echo -e "      Simplified Login: ${BLUE}${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/auth?client_id=${CLIENT_IDS[$i]}&response_type=code${NC}"
        echo -e "      With Scope: ${BLUE}${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/auth?client_id=${CLIENT_IDS[$i]}&response_type=code&scope=openid profile email${NC}"
    done
    echo ""
    
    echo -e "${GREEN}📋 Pre-configured Redirect URIs:${NC}"
    echo -e "   • http://localhost:3000/* (and /callback, /auth/callback)"
    echo -e "   • http://localhost:8080/* (and /callback, /auth/callback)"
    echo -e "   • http://localhost:8000/* (and /callback, /auth/callback)"
    echo -e "   • http://${APP_NAME}.{org}.${REALM}.local/* (and /callback, /auth/callback)"
    echo -e "   • All HTTPS variants of above"
    echo ""
    
    echo -e "${CYAN}🧪 Testing Example (for first organization):${NC}"
    local first_org="${ORGANIZATION_PREFIXES[0]}"
    local first_client="${CLIENT_IDS[0]}"
    local first_secret="${CLIENT_SECRETS_VALUES[0]}"
    
    echo -e "${WHITE}curl -X POST '${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token' \\
  -H 'Content-Type: application/x-www-form-urlencoded' \\
  -d 'username=test-${first_org}-admin' \\
  -d 'password=test-${first_org}-admin' \\
  -d 'grant_type=password' \\
  -d 'client_id=${first_client}' \\
  -d 'client_secret=${first_secret}'${NC}"
    echo ""
    
    echo -e "${YELLOW}⚠️  Security Consideration:${NC}"
    echo -e "   ${YELLOW}• JWT tokens contain ALL user roles across all organizations${NC}"
    echo -e "   ${YELLOW}• Your application MUST filter roles by the organization claim${NC}"
    echo -e "   ${YELLOW}• Do NOT trust a role unless it matches the organization prefix${NC}"
    echo -e "   ${YELLOW}• Example: acme-app-a-client should only honor acme_* roles${NC}"
    echo ""
    
    echo -e "${CYAN}➡️  Next steps:${NC}"
    echo -e "${CYAN}   1. Test authentication: ./test_application_jwt.sh ${REALM} ${APP_NAME} ${ORGANIZATION_PREFIXES[0]}${NC}"
    echo -e "${CYAN}   2. Implement role filtering in your application:${NC}"
    echo -e "${CYAN}      const org = jwt.organization; // e.g., 'acme'${NC}"
    echo -e "${CYAN}      const orgRoles = jwt.realm_access.roles.filter(r => r.startsWith(org + '_'));${NC}"
    echo -e "${CYAN}   3. Configure your ${APP_NAME} application to use these clients${NC}"
    echo -e "${CYAN}   4. Never authorize actions based on roles from other organizations${NC}"
}

# Main execution
echo -e "${GREEN}🚀 Starting application client configuration...${NC}"
echo ""

# Initialize arrays for storing client information
CLIENT_IDS=()
CLIENT_SECRETS_VALUES=()

wait_for_keycloak
get_admin_token

# Create a client for each organization
for org_prefix in "${ORGANIZATION_PREFIXES[@]}"; do
    echo ""
    create_organization_app_client "$org_prefix"
done

# Display summary
display_summary

echo -e "${GREEN}✨ Application client configuration complete!${NC}"

# Clean up temp files
rm -f /tmp/*_response.json
