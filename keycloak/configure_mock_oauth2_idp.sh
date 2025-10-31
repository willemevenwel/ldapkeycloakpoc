#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color

# Configure Mock OAuth2 Server as Keycloak Identity Provider
# This script adds Mock OAuth2 as an external identity provider in Keycloak

# Check if realm name parameter is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <realm-name> [organization-prefixes...]"
    echo "Example: $0 capgemini acme xyz"
    echo ""
    echo "If no organization prefixes provided, default prefixes will be used: acme, xyz"
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
ADMIN_PASSWORD="${ADMIN_USERNAME}"
KEYCLOAK_URL="$(get_keycloak_url)"
MOCK_OAUTH2_URL="http://localhost:8081"  # OAuth2 mock doesn't need container resolution

echo -e "${GREEN}🔧 Configuring Mock OAuth2 Server as Identity Provider for realm: ${REALM}${NC}"

# Function to wait for both Keycloak and Mock OAuth2 to be ready
wait_for_services() {
    echo -e "${YELLOW}⏳ Waiting for Keycloak to be ready...${NC}"
    
    # Wait for Keycloak realm
    until curl -s -f "${KEYCLOAK_URL}/realms/${REALM}" > /dev/null 2>&1; do
        echo -n "."
        sleep 2
    done
    
    echo -e "${GREEN}✅ Keycloak is ready!${NC}"
    echo -e "${YELLOW}⏳ Waiting for Mock OAuth2 to be ready...${NC}"
    
    # Wait for Mock OAuth2 to respond to health checks
    MOCK_READY=false
    MAX_ATTEMPTS=30  # 60 seconds total (30 attempts * 2 seconds)
    ATTEMPT=0
    
    while [ "$MOCK_READY" = false ] && [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        # Test Mock OAuth2 health by checking if the server responds (even with errors)
        HTTP_STATUS=$(curl -s -w "%{http_code}" -o /dev/null "${MOCK_OAUTH2_URL}/" 2>/dev/null)
        if [ -n "$HTTP_STATUS" ] && [[ "$HTTP_STATUS" =~ ^[0-9]+$ ]]; then
            MOCK_READY=true
            echo -e "${GREEN}✅ Mock OAuth2 is ready! (HTTP ${HTTP_STATUS})${NC}"
        else
            echo -n "."
            sleep 2
            ATTEMPT=$((ATTEMPT + 1))
        fi
    done
    
    if [ "$MOCK_READY" = false ]; then
        echo -e "${RED}❌ Mock OAuth2 failed to start within 60 seconds${NC}"
        echo -e "${YELLOW}Checking Mock OAuth2 container status...${NC}"
        docker logs mock-oauth2-server --tail 10
        exit 1
    fi
    
    echo -e "${GREEN}✅ All services are ready!${NC}"
}

# Function to get admin token
get_admin_token() {
    echo -e "${BLUE}🔑 Getting admin token for '${ADMIN_USERNAME}'...${NC}"
    
    RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${ADMIN_USERNAME}" \
        -d "password=${ADMIN_PASSWORD}" \
        -d "grant_type=password" \
        -d "client_id=admin-cli")
        
    TOKEN=$(echo "$RESPONSE" | jq -r '.access_token // empty')
    
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        echo -e "${RED}❌ Failed to get admin token${NC}"
        echo "Response: $RESPONSE"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Got admin token for realm '${REALM}'${NC}"
}

# Function to configure organization-specific Mock OAuth2 Identity Providers
configure_mock_oauth2_idp() {
    echo -e "${BLUE}🆔 Configuring organization-specific Mock OAuth2 Identity Providers...${NC}"
    
    for org_prefix in "${ORGANIZATION_PREFIXES[@]}"; do
        ORG_NAME=$(echo "$org_prefix" | tr '[:lower:]' '[:upper:]')
        IDP_ALIAS="mock-oauth2-${org_prefix}"
        
        echo -e "${CYAN}🏢 Creating IdP for organization: ${ORG_NAME} (alias: ${IDP_ALIAS})${NC}"
        
        # Use organization-specific Mock OAuth2 endpoints
        AUTH_URL="${MOCK_OAUTH2_URL}/${org_prefix}/authorize"
        TOKEN_URL="${MOCK_OAUTH2_URL}/${org_prefix}/token"
        ISSUER="${MOCK_OAUTH2_URL}/${org_prefix}"
        JWKS_URL="${MOCK_OAUTH2_URL}/${org_prefix}/jwks"
        
        echo -e "${CYAN}   📋 Configuration:${NC}"
        echo -e "${CYAN}      • Authorization URL: ${AUTH_URL}${NC}"
        echo -e "${CYAN}      • Token URL: ${TOKEN_URL}${NC}"
        echo -e "${CYAN}      • Issuer: ${ISSUER}${NC}"
        echo -e "${CYAN}      • JWKS URL: ${JWKS_URL}${NC}"
        
        # Check if Identity Provider already exists
        EXISTING_IDP=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/identity-provider/instances/${IDP_ALIAS}" \
            -H "Authorization: Bearer ${TOKEN}" \
            -w "%{http_code}" -o /tmp/idp_check_${org_prefix}.json)
        
        if [ "${EXISTING_IDP: -3}" = "200" ]; then
            echo -e "${YELLOW}   ⚠️  IdP ${IDP_ALIAS} already exists, updating...${NC}"
            HTTP_METHOD="PUT"
            ENDPOINT="${KEYCLOAK_URL}/admin/realms/${REALM}/identity-provider/instances/${IDP_ALIAS}"
        else
            echo -e "${BLUE}   🏗️  Creating new IdP ${IDP_ALIAS}...${NC}"
            HTTP_METHOD="POST"
            ENDPOINT="${KEYCLOAK_URL}/admin/realms/${REALM}/identity-provider/instances"
        fi
        
        # Create/Update Identity Provider configuration
        IDP_CONFIG=$(cat << EOF
{
    "alias": "${IDP_ALIAS}",
    "displayName": "Mock OAuth2 Server (${ORG_NAME})",
    "providerId": "oidc",
    "enabled": true,
    "updateProfileFirstLoginMode": "on",
    "trustEmail": false,
    "storeToken": true,
    "addReadTokenRoleOnCreate": false,
    "authenticateByDefault": false,
    "linkOnly": false,
    "firstBrokerLoginFlowAlias": "first broker login",
    "config": {
        "useJwksUrl": "true",
        "syncMode": "IMPORT",
        "authorizationUrl": "${AUTH_URL}",
        "hideOnLoginPage": "false",
        "loginHint": "",
        "uiLocales": "false",
        "backchannelSupported": "false",
        "disableUserInfo": "false",
        "acceptsPromptNoneForwardFromClient": "false",
        "validateSignature": "false",
        "pkceEnabled": "false",
        "tokenUrl": "${TOKEN_URL}",
        "clientAuthMethod": "client_secret_post",
        "jwksUrl": "${JWKS_URL}",
        "clientId": "${org_prefix}-keycloak-${REALM}",
        "clientSecret": "mock-secret-${org_prefix}-${REALM}",
        "issuer": "${ISSUER}",
        "defaultScope": "openid profile email organizations ${org_prefix}_access"
    }
}
EOF
)

        HTTP_STATUS=$(curl -s -w "%{http_code}" -X ${HTTP_METHOD} "${ENDPOINT}" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d "${IDP_CONFIG}" \
            -o /tmp/idp_response_${org_prefix}.json)

        if [[ "${HTTP_STATUS}" =~ ^(200|201|204)$ ]]; then
            echo -e "${GREEN}   ✅ Mock OAuth2 IdP ${IDP_ALIAS} configured successfully${NC}"
        else
            echo -e "${RED}   ❌ Failed to configure IdP ${IDP_ALIAS} (HTTP ${HTTP_STATUS})${NC}"
            cat /tmp/idp_response_${org_prefix}.json
            exit 1
        fi
    done
    
    echo -e "${GREEN}✅ All organization-specific Identity Providers configured${NC}"
}

# Function to create organization-specific clients in Mock OAuth2
create_org_oauth2_clients() {
    echo -e "${BLUE}🏢 Creating organization-specific Mock OAuth2 clients...${NC}"
    
    for org_prefix in "${ORGANIZATION_PREFIXES[@]}"; do
        ORG_NAME=$(echo "$org_prefix" | tr '[:lower:]' '[:upper:]')
        
        echo -e "${CYAN}📝 Creating Mock OAuth2 client for organization: ${ORG_NAME} (${org_prefix})${NC}"
        
        # Mock OAuth2 accepts any client configuration, but we'll document the expected setup
        CLIENT_CONFIG=$(cat << EOF
{
    "clientId": "${org_prefix}-${REALM}-client",
    "clientSecret": "${org_prefix}-secret-${REALM}",
    "redirectUris": [
        "${KEYCLOAK_URL}/realms/${REALM}/broker/mock-oauth2/endpoint",
        "http://${org_prefix}.${REALM}.local/*",
        "http://localhost:3000/${org_prefix}/*"
    ],
    "scopes": ["openid", "profile", "email", "organizations", "${org_prefix}_access"],
    "claims": {
        "sub": "user-${org_prefix}-{random}",
        "name": "Test User ${ORG_NAME}",
        "email": "test@${org_prefix}.${REALM}.local",
        "organizations": ["${org_prefix}"],
        "organization_roles": ["${org_prefix}_admin", "${org_prefix}_user"],
        "preferred_username": "test-${org_prefix}-user"
    }
}
EOF
)
        
        echo -e "${CYAN}   • Client ID: ${org_prefix}-${REALM}-client${NC}"
        echo -e "${CYAN}   • Domain: ${org_prefix}.${REALM}.local${NC}"
        echo -e "${CYAN}   • Claims: organizations=[${org_prefix}]${NC}"
        
        # Save client configuration for reference
        echo "$CLIENT_CONFIG" > "/tmp/mock-oauth2-${org_prefix}-client.json"
        echo -e "${GREEN}   ✅ Configuration saved to /tmp/mock-oauth2-${org_prefix}-client.json${NC}"
    done
    
    echo -e "${YELLOW}💡 Mock OAuth2 accepts any client_id/client_secret combination${NC}"
    echo -e "${YELLOW}   You can use these configurations in your applications for testing${NC}"
}

# Function to link Mock OAuth2 Identity Provider to organizations
link_idp_to_organizations() {
    echo -e "${BLUE}🔗 Linking Mock OAuth2 Identity Provider to organizations...${NC}"
    
    # First, get all organizations to link the IdP to them
    ORGANIZATIONS=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/organizations" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json")
    
    if [ $? -ne 0 ] || [ -z "$ORGANIZATIONS" ]; then
        echo -e "${YELLOW}⚠️  Failed to get organizations or no organizations found${NC}"
        echo -e "${YELLOW}💡 Organizations may not be enabled or configured yet${NC}"
        return 0
    fi
    
    if command -v jq >/dev/null 2>&1; then
        ORG_COUNT=$(echo "$ORGANIZATIONS" | jq '. | length' 2>/dev/null || echo 0)
        echo -e "${BLUE}📋 Found ${ORG_COUNT} organizations to link${NC}"
        
        if [ "$ORG_COUNT" -eq 0 ]; then
            echo -e "${YELLOW}⚠️  No organizations found to link to Mock OAuth2 IdP${NC}"
            echo -e "${YELLOW}💡 Make sure organizations are created before running this script${NC}"
            return 0
        fi
        
        # Link organization-specific Mock OAuth2 IdP to each organization
        for org_prefix in "${ORGANIZATION_PREFIXES[@]}"; do
            org_name=$(echo "$org_prefix" | tr '[:lower:]' '[:upper:]')
            idp_alias="mock-oauth2-${org_prefix}"
            
            # Find organization by name
            ORG_ID=$(echo "$ORGANIZATIONS" | jq -r ".[] | select(.name == \"${org_name}\") | .id" 2>/dev/null)
            
            if [ -z "$ORG_ID" ] || [ "$ORG_ID" = "null" ]; then
                echo -e "${YELLOW}⚠️  Organization ${org_name} not found, skipping IdP link${NC}"
                continue
            fi
            
            echo -e "${CYAN}🔗 Linking IdP ${idp_alias} to organization: ${org_name} (${ORG_ID})${NC}"
            
            # Link the organization-specific identity provider to the organization
            HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/organizations/${ORG_ID}/identity-providers" \
                -H "Authorization: Bearer ${TOKEN}" \
                -H "Content-Type: application/json" \
                -d "\"${idp_alias}\"" \
                -o /tmp/org_idp_link_response_${org_prefix}.json)

            if [[ "${HTTP_STATUS}" =~ ^(200|201|204)$ ]]; then
                echo -e "${GREEN}✅ Successfully linked IdP ${idp_alias} to organization ${org_name}${NC}"
            elif [ "${HTTP_STATUS}" = "409" ]; then
                echo -e "${YELLOW}⚠️  IdP ${idp_alias} already linked to organization ${org_name}${NC}"
            elif [ "${HTTP_STATUS}" = "400" ]; then
                echo -e "${YELLOW}⚠️  IdP linking error (HTTP 400) - checking error details${NC}"
                if [ -f /tmp/org_idp_link_response_${org_prefix}.json ]; then
                    ERROR_MSG=$(cat /tmp/org_idp_link_response_${org_prefix}.json | jq -r '.errorMessage // "Unknown error"')
                    if echo "$ERROR_MSG" | grep -q "already associated"; then
                        echo -e "${YELLOW}   💡 IdP ${idp_alias} already associated with another organization${NC}"
                    else
                        echo -e "${YELLOW}   💡 Error: ${ERROR_MSG}${NC}"
                    fi
                fi
            else
                echo -e "${YELLOW}⚠️  Direct IdP linking not supported (HTTP ${HTTP_STATUS}) - using alternative approach${NC}"
                
                # Try alternative approach - update organization with identity provider info
                echo -e "${CYAN}🔄 Using organization domain-based IdP association...${NC}"
                
                # Get current organization config
                CURRENT_ORG=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/organizations/${ORG_ID}" \
                    -H "Authorization: Bearer ${TOKEN}" \
                    -H "Content-Type: application/json")
                
                if [ -n "$CURRENT_ORG" ]; then
                    # Update organization with identity provider configuration
                    UPDATED_ORG=$(echo "$CURRENT_ORG" | jq --arg idp "mock-oauth2" --arg domain "${org_prefix}.${REALM}.local" '
                        .attributes.identity_provider = [$idp] |
                        .domains[0].name = $domain' 2>/dev/null)
                    
                    if [ -n "$UPDATED_ORG" ]; then
                        HTTP_STATUS=$(curl -s -w "%{http_code}" -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/organizations/${ORG_ID}" \
                            -H "Authorization: Bearer ${TOKEN}" \
                            -H "Content-Type: application/json" \
                            -d "${UPDATED_ORG}" \
                            -o /tmp/org_update_response.json)
                        
                        if [[ "${HTTP_STATUS}" =~ ^(200|204)$ ]]; then
                            echo -e "${GREEN}✅ Successfully updated organization ${org_name} with IdP configuration${NC}"
                        else
                            echo -e "${YELLOW}⚠️  Organization update approach also had issues (HTTP ${HTTP_STATUS})${NC}"
                            echo -e "${CYAN}💡 Domain-based association should still work via the Mock OAuth2 IdP configuration${NC}"
                        fi
                    fi
                else
                    echo -e "${YELLOW}💡 Using existing organization configuration${NC}"
                fi
            fi
        done
    else
        echo -e "${YELLOW}⚠️  jq not available, skipping organization IdP linking${NC}"
    fi
}

# Function to create organization-specific mappers  
create_organization_mappers() {
    echo -e "${BLUE}🗺️  Creating organization-specific attribute mappers...${NC}"
    
    for org_prefix in "${ORGANIZATION_PREFIXES[@]}"; do
        idp_alias="mock-oauth2-${org_prefix}"
        echo -e "${CYAN}📝 Creating mappers for IdP: ${idp_alias} (org: ${org_prefix})${NC}"
        
        # Organization claim mapper
        ORG_MAPPER_CONFIG=$(cat << EOF
{
    "name": "${org_prefix}-organization-mapper",
    "identityProviderAlias": "${idp_alias}",
    "identityProviderMapper": "oidc-user-attribute-idp-mapper",
    "config": {
        "syncMode": "INHERIT",
        "user.attribute": "organization_${org_prefix}",
        "claim": "organizations"
    }
}
EOF
)
        
        # Role mapper
        ROLE_MAPPER_CONFIG=$(cat << EOF
{
    "name": "${org_prefix}-role-mapper",
    "identityProviderAlias": "${idp_alias}",
    "identityProviderMapper": "oidc-role-idp-mapper",
    "config": {
        "syncMode": "INHERIT",
        "claim": "organization_roles",
        "role": "${org_prefix}_user"
    }
}
EOF
)
        
        # Create organization mapper
        HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/identity-provider/instances/${idp_alias}/mappers" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d "${ORG_MAPPER_CONFIG}" \
            -o /tmp/org_mapper_response_${org_prefix}.json)

        if [[ "${HTTP_STATUS}" =~ ^(200|201|204)$ ]]; then
            echo -e "${GREEN}   ✅ Created organization mapper for ${org_prefix}${NC}"
        else
            echo -e "${YELLOW}   ⚠️  Organization mapper may already exist (HTTP ${HTTP_STATUS})${NC}"
        fi
        
        # Create role mapper
        HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/identity-provider/instances/${idp_alias}/mappers" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d "${ROLE_MAPPER_CONFIG}" \
            -o /tmp/role_mapper_response_${org_prefix}.json)

        if [[ "${HTTP_STATUS}" =~ ^(200|201|204)$ ]]; then
            echo -e "${GREEN}   ✅ Created role mapper for ${org_prefix}${NC}"
        else
            echo -e "${YELLOW}   ⚠️  Role mapper may already exist (HTTP ${HTTP_STATUS})${NC}"
        fi
    done
}

# Main execution
echo -e "${GREEN}🚀 Starting Mock OAuth2 Identity Provider configuration...${NC}"

wait_for_services
get_admin_token
configure_mock_oauth2_idp
create_org_oauth2_clients
link_idp_to_organizations
create_organization_mappers

echo -e "${GREEN}🎉 Mock OAuth2 Identity Provider configuration completed successfully!${NC}"

echo ""
echo -e "${GREEN}📋 Configuration Summary:${NC}"
echo -e "${GREEN}   • Realm: ${REALM}${NC}"
echo -e "${GREEN}   • Identity Provider: mock-oauth2${NC}"
echo -e "${GREEN}   • Organizations: ${ORGANIZATION_PREFIXES[*]}${NC}"
echo -e "${GREEN}   • Mock OAuth2 URL: ${MOCK_OAUTH2_URL}${NC}"

echo ""
echo -e "${GREEN}🌐 Access URLs:${NC}"
echo -e "${GREEN}   • Keycloak Identity Providers: ${BLUE}${KEYCLOAK_URL}/admin/${REALM}/console/#/${REALM}/identity-providers${NC}"
echo -e "${GREEN}   • Mock OAuth2 Server: ${BLUE}${MOCK_OAUTH2_URL}${NC}"
echo -e "${GREEN}   • OIDC Configuration: ${BLUE}${MOCK_OAUTH2_URL}/default/.well-known/openid_configuration${NC}"

echo ""
echo -e "${GREEN}🧪 Testing:${NC}"
echo -e "${GREEN}   • Test login via Mock OAuth2 on the Keycloak login page${NC}"
echo -e "${GREEN}   • Organization-specific clients configured for each org${NC}"
echo -e "${GREEN}   • Claims mapping configured for organization roles${NC}"

echo ""
echo -e "${YELLOW}💡 Organization Clients Created:${NC}"
for org_prefix in "${ORGANIZATION_PREFIXES[@]}"; do
    echo -e "${YELLOW}   • ${org_prefix}-${REALM}-client (domain: ${org_prefix}.${REALM}.local)${NC}"
done

echo ""
echo -e "${CYAN}🔧 Organization-IdP Association:${NC}"
echo -e "${CYAN}   • Organizations have domains: acme.${REALM}.local, xyz.${REALM}.local${NC}"
echo -e "${CYAN}   • Mock OAuth2 configured with organization-specific clients${NC}"
echo -e "${CYAN}   • Claims mapping configured for organization roles${NC}"
echo -e "${CYAN}   • Users can authenticate via Mock OAuth2 and be mapped to organizations${NC}"

echo ""
echo -e "${CYAN}🔧 Next steps:${NC}"
echo -e "${CYAN}   1. Test authentication flows with both Keycloak and Mock OAuth2${NC}"
echo -e "${CYAN}   2. Configure applications to use organization-specific OAuth2 clients${NC}"
echo -e "${CYAN}   3. Test organization claim mapping and role assignment${NC}"
echo -e "${CYAN}   4. Use Mock OAuth2 for integration testing scenarios${NC}"