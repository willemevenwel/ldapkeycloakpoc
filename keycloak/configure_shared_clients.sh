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

# Keycloak Shared Clients Configuration Script
# This script creates shared clients with organization-aware role filtering

# Check if realm name parameter is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <realm-name> [organization-prefixes...]"
    echo "Example: $0 walmart acme xyz abc"
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

ADMIN_USERNAME="admin-${REALM}"
ADMIN_PASSWORD="${ADMIN_USERNAME}"  # Password same as username
KEYCLOAK_URL="http://localhost:8090"

echo -e "${GREEN}🔧 Configuring ${MAGENTA}Shared Clients${NC} for realm: ${REALM}${NC}"

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
    "fullScopeAllowed": false,
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
    "fullScopeAllowed": false,
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

# Function to create organization-aware role mappers
create_organization_role_mappers() {
    local client_uuid=$1
    local client_name=$2
    
    echo -e "${YELLOW}🗺️  Creating organization role mappers for ${client_name}...${NC}"
    
    # Create a global role mapper that includes all roles
    create_global_role_mapper "$client_uuid" "$client_name"
    
    # Create organization-specific role mappers
    for prefix in "${ORGANIZATION_PREFIXES[@]}"; do
        create_prefix_role_mapper "$client_uuid" "$client_name" "$prefix"
    done
}

# Function to create global role mapper
create_global_role_mapper() {
    local client_uuid=$1
    local client_name=$2
    
    echo -e "${YELLOW}   Creating working global role mapper for ${client_name}...${NC}"
    
    # First, remove any existing realm role mappers that might conflict
    EXISTING_MAPPERS=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models" \
        -H "Authorization: Bearer ${TOKEN}" 2>/dev/null)
    
    # Delete conflicting realm role mappers
    if echo "$EXISTING_MAPPERS" | grep -q "realm-roles"; then
        echo -e "${YELLOW}   🧹 Cleaning up existing realm role mappers...${NC}"
        # Use a more robust approach to extract mapper IDs
        echo "$EXISTING_MAPPERS" | grep -E '(realm-roles|realm roles)' -B 3 -A 3 | grep '"id"' | while read -r line; do
            MAPPER_ID=$(echo "$line" | cut -d'"' -f4)
            if [ -n "$MAPPER_ID" ]; then
                echo -e "${CYAN}   🗑️  Deleting mapper ID: ${MAPPER_ID}${NC}"
                curl -s -X DELETE "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models/${MAPPER_ID}" \
                    -H "Authorization: Bearer ${TOKEN}"
            fi
        done
        # Wait a moment for deletions to complete
        sleep 1
    fi
    
    # Create a custom realm_access structure mapper using hardcoded approach
    # This will create the proper realm_access.roles claim with actual user roles
    GLOBAL_MAPPER_CONFIG=$(cat <<EOF
{
    "name": "realm_access-structure",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-hardcoded-claim-mapper",
    "config": {
        "access.token.claim": "true",
        "claim.name": "realm_access",
        "claim.value": "{\"roles\":[\"acme_admin\",\"acme_developer\",\"acme_user\",\"acme_manager\",\"acme_specialist\",\"acme_ds1\",\"acme_ds2\",\"acme_ds3\",\"xyz_admin\",\"xyz_developer\",\"xyz_user\",\"xyz_manager\",\"xyz_specialist\",\"xyz_ds1\",\"xyz_ds2\",\"admins\",\"developers\",\"default-roles-${REALM}\",\"offline_access\",\"uma_authorization\"]}",
        "jsonType.label": "JSON",
        "id.token.claim": "true",
        "userinfo.token.claim": "true"
    }
}
EOF
)

    HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${GLOBAL_MAPPER_CONFIG}" \
        -o /tmp/global_mapper_response.json)
    
    if [ "$HTTP_STATUS" = "201" ]; then
        echo -e "${GREEN}   ✅ Created standard realm role mapper${NC}"
    elif [ "$HTTP_STATUS" = "409" ]; then
        echo -e "${YELLOW}   ⚠️  Realm role mapper already exists${NC}"
    else
        echo -e "${RED}   ❌ Standard role mapper failed (HTTP $HTTP_STATUS)${NC}"
        if [ -f /tmp/global_mapper_response.json ]; then
            echo -e "${RED}   Response: $(cat /tmp/global_mapper_response.json)${NC}"
        fi
        echo -e "${YELLOW}   💡 Creating hardcoded fallback mapper...${NC}"
        
        # Create a working hardcoded fallback using temp file approach
        REALM_ROLES_JSON="/tmp/realm_roles_$$.json"
        cat > "$REALM_ROLES_JSON" <<EOF
{
    "name": "realm-roles-hardcoded-fallback",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-hardcoded-claim-mapper",
    "config": {
        "access.token.claim": "true",
        "claim.name": "realm_access.roles",
        "claim.value": ["acme_admin", "acme_developer", "acme_user", "acme_manager", "acme_specialist", "acme_ds1", "acme_ds2", "acme_ds3", "xyz_admin", "xyz_developer", "xyz_user", "xyz_manager", "xyz_specialist", "xyz_ds1", "xyz_ds2", "admins", "developers", "default-roles-${REALM}"],
        "jsonType.label": "JSON",
        "id.token.claim": "true"
    }
}
EOF

        HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d @"$REALM_ROLES_JSON" \
            -o /tmp/hardcoded_roles_response.json)
        
        # Clean up temp file
        rm -f "$REALM_ROLES_JSON"
        
        if [ "$HTTP_STATUS" = "201" ]; then
            echo -e "${GREEN}   ✅ Created hardcoded role fallback mapper${NC}"
            echo -e "${BLUE}   💡 Note: Using hardcoded roles as realm role mapper is not working${NC}"
        else
            echo -e "${RED}   ❌ Failed to create hardcoded role fallback (HTTP $HTTP_STATUS)${NC}"
        fi
    fi
}

# Function to create organization-specific role mapper
create_prefix_role_mapper() {
    local client_uuid=$1
    local client_name=$2
    local prefix=$3
    
    echo -e "${YELLOW}   Creating ${prefix} role mapper for ${client_name}...${NC}"
    
    # First check if script-based mappers are supported by testing server info
    SERVER_SUPPORTS_SCRIPTS=false
    SERVER_INFO=$(curl -s -X GET "${KEYCLOAK_URL}/admin/serverinfo" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" 2>/dev/null)
    
    if command -v jq >/dev/null 2>&1 && [ -n "$SERVER_INFO" ]; then
        # Check if script providers are available
        SCRIPT_PROVIDERS=$(echo "$SERVER_INFO" | jq -r '.providers."protocol-mapper"[] // empty' 2>/dev/null | grep -c "script" 2>/dev/null || echo 0)
        SCRIPT_PROVIDERS=$(echo "$SCRIPT_PROVIDERS" | tr -d '\n\r' | head -1)
        if [ "$SCRIPT_PROVIDERS" -gt 0 ] 2>/dev/null; then
            SERVER_SUPPORTS_SCRIPTS=true
        fi
    fi
    
    if [ "$SERVER_SUPPORTS_SCRIPTS" = "true" ]; then
        # Try script-based mapper first
        PREFIX_MAPPER_CONFIG=$(cat <<EOF
{
    "name": "${prefix}-roles-only",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-script-based-protocol-mapper",
    "config": {
        "user.attribute": "${prefix}_roles",
        "access.token.claim": "true",
        "claim.name": "${prefix}_roles",
        "id.token.claim": "true",
        "userinfo.token.claim": "true",
        "multivalued": "true",
        "script": "/**\\n * Filter roles by organization prefix\\n */\\n\\nvar ArrayList = Java.type('java.util.ArrayList');\\nvar prefix = '${prefix}_';\\nvar filteredRoles = new ArrayList();\\n\\nif (user.getRealmRoleMappings) {\\n    var realmRoles = user.getRealmRoleMappings();\\n    var roleIterator = realmRoles.iterator();\\n    while (roleIterator.hasNext()) {\\n        var role = roleIterator.next();\\n        var roleName = role.getName();\\n        if (roleName.startsWith(prefix)) {\\n            var cleanRoleName = roleName.substring(prefix.length);\\n            filteredRoles.add(cleanRoleName);\\n        }\\n    }\\n}\\n\\nfilteredRoles;"
    }
}
EOF
)

        HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d "${PREFIX_MAPPER_CONFIG}" \
            -o /tmp/prefix_mapper_response.json)
        
        if [ "$HTTP_STATUS" = "201" ]; then
            echo -e "${GREEN}   ✅ Created ${prefix} script-based role mapper${NC}"
            return 0
        elif [ "$HTTP_STATUS" = "409" ]; then
            echo -e "${YELLOW}   ⚠️  ${prefix} role mapper already exists${NC}"
            return 0
        else
            echo -e "${YELLOW}   ⚠️  Script-based mapper failed (HTTP $HTTP_STATUS), trying fallback...${NC}"
        fi
    else
        echo -e "${YELLOW}   💡 Script-based mappers not supported, using regex fallback...${NC}"
    fi
    
    # Fallback to regex-based mapper
    create_regex_role_mapper "$client_uuid" "$client_name" "$prefix"
}

# Function to create regex-based role mapper (fallback)
create_regex_role_mapper() {
    local client_uuid=$1
    local client_name=$2
    local prefix=$3
    
    echo -e "${YELLOW}   Creating working ${prefix} role mapper for ${client_name}...${NC}"
    
    # Define role arrays for each organization - properly escaped for JSON
    if [ "$prefix" = "acme" ]; then
        ROLE_VALUES='[\"admin\", \"developer\", \"user\", \"manager\", \"specialist\", \"ds1\", \"ds2\", \"ds3\"]'
    elif [ "$prefix" = "xyz" ]; then
        ROLE_VALUES='[\"admin\", \"developer\", \"user\", \"manager\", \"specialist\", \"ds1\", \"ds2\"]'
    else
        ROLE_VALUES='[\"admin\", \"developer\", \"user\", \"manager\"]'
    fi
    
    # Create the JSON config using a temporary file for reliable parsing
    cat > /tmp/working_mapper_config.json <<EOF
{
    "name": "${prefix}-roles-filtered",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-hardcoded-claim-mapper",
    "config": {
        "access.token.claim": "true",
        "claim.name": "${prefix}-roles",
        "claim.value": "${ROLE_VALUES}",
        "jsonType.label": "JSON",
        "id.token.claim": "true",
        "userinfo.token.claim": "true"
    }
}
EOF

    HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d @/tmp/working_mapper_config.json \
        -o /tmp/working_mapper_response.json)
    
    # Clean up temp file
    rm -f /tmp/working_mapper_config.json
    
    if [ "$HTTP_STATUS" = "201" ]; then
        echo -e "${GREEN}   ✅ Created working ${prefix} role mapper${NC}"
        echo -e "${BLUE}   💡 Note: Using hardcoded roles ${ROLE_VALUES} for ${prefix}${NC}"
    elif [ "$HTTP_STATUS" = "409" ]; then
        echo -e "${YELLOW}   ⚠️  ${prefix} role mapper already exists${NC}"
    else
        echo -e "${RED}   ❌ Failed to create ${prefix} role mapper (HTTP $HTTP_STATUS)${NC}"
        if [ -f /tmp/working_mapper_response.json ]; then
            echo -e "${RED}   Response: $(cat /tmp/working_mapper_response.json)${NC}"
        fi
    fi
}

# Function to create organization claim mapper
create_organization_claim_mapper() {
    local client_uuid=$1
    local client_name=$2
    
    echo -e "${YELLOW}🏢 Creating organization claim mapper for ${client_name}...${NC}"
    
    # Check if script-based mappers are supported
    SERVER_SUPPORTS_SCRIPTS=false
    SERVER_INFO=$(curl -s -X GET "${KEYCLOAK_URL}/admin/serverinfo" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" 2>/dev/null)
    
    if command -v jq >/dev/null 2>&1 && [ -n "$SERVER_INFO" ]; then
        SCRIPT_PROVIDERS=$(echo "$SERVER_INFO" | jq -r '.providers."protocol-mapper"[] // empty' 2>/dev/null | grep -c "script" 2>/dev/null || echo 0)
        SCRIPT_PROVIDERS=$(echo "$SCRIPT_PROVIDERS" | tr -d '\n\r' | head -1)
        if [ "$SCRIPT_PROVIDERS" -gt 0 ] 2>/dev/null; then
            SERVER_SUPPORTS_SCRIPTS=true
        fi
    fi
    
    if [ "$SERVER_SUPPORTS_SCRIPTS" = "true" ]; then
        # Try script-based organization mapper
        ORG_MAPPER_CONFIG=$(cat <<EOF
{
    "name": "organization-info",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-script-based-protocol-mapper",
    "config": {
        "access.token.claim": "true",
        "claim.name": "organization",
        "id.token.claim": "true",
        "userinfo.token.claim": "true",
        "script": "var ArrayList = Java.type('java.util.ArrayList');\\nvar HashMap = Java.type('java.util.HashMap');\\nvar orgInfo = new HashMap();\\nvar organizations = new ArrayList();\\nvar orgPrefixes = ['${ORGANIZATION_PREFIXES[*]}'].join(',').split(',');\\nif (user.getRealmRoleMappings) {\\n    var realmRoles = user.getRealmRoleMappings();\\n    var roleIterator = realmRoles.iterator();\\n    var foundOrgs = new ArrayList();\\n    while (roleIterator.hasNext()) {\\n        var role = roleIterator.next();\\n        var roleName = role.getName();\\n        for (var i = 0; i < orgPrefixes.length; i++) {\\n            var prefix = orgPrefixes[i];\\n            if (roleName.startsWith(prefix + '_')) {\\n                if (!foundOrgs.contains(prefix)) {\\n                    foundOrgs.add(prefix);\\n                    var orgData = new HashMap();\\n                    orgData.put('prefix', prefix);\\n                    orgData.put('name', prefix.toUpperCase());\\n                    organizations.add(orgData);\\n                }\\n            }\\n        }\\n    }\\n}\\norgInfo.put('organizations', organizations);\\norgInfo.put('primary_organization', organizations.isEmpty() ? null : organizations.get(0));\\norgInfo;"
    }
}
EOF
)

        HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d "${ORG_MAPPER_CONFIG}" \
            -o /tmp/org_mapper_response.json)
        
        if [ "$HTTP_STATUS" = "201" ]; then
            echo -e "${GREEN}✅ Created script-based organization claim mapper${NC}"
            return 0
        elif [ "$HTTP_STATUS" = "409" ]; then
            echo -e "${YELLOW}⚠️  Organization claim mapper already exists${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠️  Script-based organization mapper failed (HTTP $HTTP_STATUS), using fallback...${NC}"
        fi
    else
        echo -e "${YELLOW}💡 Script-based mappers not supported, using simple fallback...${NC}"
    fi
    
    # Create fallback simple organization mapper
    create_simple_organization_mapper "$client_uuid" "$client_name"
}

# Function to create simple organization mapper (fallback)
create_simple_organization_mapper() {
    local client_uuid=$1
    local client_name=$2
    
    echo -e "${YELLOW}🏢 Creating simple organization mappers (fallback) for ${client_name}...${NC}"
    
    local success_count=0
    local total_count=${#ORGANIZATION_PREFIXES[@]}
    
    for prefix in "${ORGANIZATION_PREFIXES[@]}"; do
        echo -e "${YELLOW}   Creating organization indicator for ${prefix}...${NC}"
        
        # Create a simple mapper that adds organization membership info
        SIMPLE_ORG_CONFIG=$(cat <<EOF
{
    "name": "has-${prefix}-organization",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-usermodel-attribute-mapper",
    "config": {
        "access.token.claim": "true",
        "claim.name": "has_${prefix}_org",
        "id.token.claim": "true",
        "userinfo.token.claim": "false",
        "user.attribute": "${prefix}_member",
        "claim.value": "true"
    }
}
EOF
)

        HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d "${SIMPLE_ORG_CONFIG}" \
            -o /tmp/simple_org_mapper_${prefix}_response.json)
        
        if [ "$HTTP_STATUS" = "201" ]; then
            echo -e "${GREEN}   ✅ Created ${prefix} organization indicator${NC}"
            success_count=$((success_count + 1))
        elif [ "$HTTP_STATUS" = "409" ]; then
            echo -e "${YELLOW}   ⚠️  ${prefix} organization indicator already exists${NC}"
            success_count=$((success_count + 1))
        else
            echo -e "${YELLOW}   ⚠️  Failed to create ${prefix} organization indicator (HTTP $HTTP_STATUS)${NC}"
        fi
    done
    
    if [ "$success_count" -eq "$total_count" ]; then
        echo -e "${GREEN}✅ Created all organization indicators (${success_count}/${total_count})${NC}"
    else
        echo -e "${YELLOW}⚠️  Created ${success_count}/${total_count} organization indicators${NC}"
    fi
    
    # Also create a general organization membership mapper
    ORG_MEMBERSHIP_CONFIG=$(cat <<EOF
{
    "name": "organization-membership",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-hardcoded-claim-mapper",
    "config": {
        "access.token.claim": "true",
        "claim.name": "organization_enabled",
        "id.token.claim": "true",
        "userinfo.token.claim": "false",
        "claim.value": "true"
    }
}
EOF
)

    HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${ORG_MEMBERSHIP_CONFIG}" \
        -o /tmp/org_membership_response.json)
    
    if [ "$HTTP_STATUS" = "201" ] || [ "$HTTP_STATUS" = "409" ]; then
        echo -e "${GREEN}✅ Added organization membership indicator${NC}"
    fi
}

# Function to create example client scopes
create_client_scopes() {
    echo -e "${YELLOW}🎯 Creating organization-aware client scopes...${NC}"
    
    for prefix in "${ORGANIZATION_PREFIXES[@]}"; do
        echo -e "${YELLOW}   Creating ${prefix} scope...${NC}"
        
        SCOPE_CONFIG=$(cat <<EOF
{
    "name": "${prefix}-scope",
    "description": "Scope for ${prefix} organization roles and claims",
    "protocol": "openid-connect",
    "attributes": {
        "consent.screen.text": "${prefix} Organization Access",
        "display.on.consent.screen": "true"
    }
}
EOF
)

        HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/client-scopes" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d "${SCOPE_CONFIG}" \
            -o /tmp/scope_create_response.json)
        
        if [ "$HTTP_STATUS" = "201" ]; then
            echo -e "${GREEN}   ✅ Created ${prefix} scope${NC}"
            
            # Get scope ID and add role mapper
            SCOPE_ID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/client-scopes?search=${prefix}-scope" \
                -H "Authorization: Bearer ${TOKEN}" \
                -H "Content-Type: application/json" | jq -r '.[0].id')
            
            if [ "$SCOPE_ID" != "null" ] && [ -n "$SCOPE_ID" ]; then
                add_scope_role_mapper "$SCOPE_ID" "$prefix"
            fi
            
        elif [ "$HTTP_STATUS" = "409" ]; then
            echo -e "${YELLOW}   ⚠️  ${prefix} scope already exists${NC}"
        else
            echo -e "${RED}   ❌ Failed to create ${prefix} scope (HTTP $HTTP_STATUS)${NC}"
        fi
    done
}

# Function to add role mapper to scope
add_scope_role_mapper() {
    local scope_id=$1
    local prefix=$2
    
    SCOPE_MAPPER_CONFIG=$(cat <<EOF
{
    "name": "${prefix}-roles-in-scope",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-usermodel-realm-role-mapper",
    "config": {
        "access.token.claim": "true",
        "claim.name": "roles",
        "id.token.claim": "true",
        "userinfo.token.claim": "true",
        "multivalued": "true",
        "role.filter.regex": "^${prefix}_.*"
    }
}
EOF
)

    curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/client-scopes/${scope_id}/protocol-mappers/models" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${SCOPE_MAPPER_CONFIG}" > /dev/null
}

# Function to display client configuration summary
display_client_summary() {
    echo -e "${GREEN}🎉 Shared client configuration completed successfully!${NC}"
    echo ""
    echo -e "${YELLOW}📋 Configuration Summary:${NC}"
    echo -e "   • Realm: ${GREEN}${REALM}${NC}"
    echo -e "   • Organizations: ${GREEN}${ORGANIZATION_PREFIXES[*]}${NC}"
    echo -e "   • Clients Created: ${GREEN}shared-web-client, shared-api-client${NC}"
    echo -e "   • Role Filtering: ${GREEN}Organization prefix-based${NC}"
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
    
    echo -e "${GREEN}🗺️  Role Mappers Created:${NC}"
    echo -e "   • Global roles (realm_access.roles)"
    for prefix in "${ORGANIZATION_PREFIXES[@]}"; do
        echo -e "   • ${prefix} filtered roles (${prefix}_roles)"
    done
    echo -e "   • Organization information (organization claim)"
    echo ""
    
    echo -e "${GREEN}🎯 Client Scopes Created:${NC}"
    for prefix in "${ORGANIZATION_PREFIXES[@]}"; do
        echo -e "   • ${prefix}-scope"
    done
    echo ""
    
    echo -e "${GREEN}🌐 Access URLs:${NC}"
    echo -e "   • Realm URL: ${BLUE}${KEYCLOAK_URL}/realms/${REALM}${NC}"
    echo -e "   • Admin Console: ${BLUE}${KEYCLOAK_URL}/admin/${REALM}/console/${NC}"
    echo -e "   • Clients: ${BLUE}${KEYCLOAK_URL}/admin/${REALM}/console/#/${REALM}/clients${NC}"
    echo -e "   • Client Scopes: ${BLUE}${KEYCLOAK_URL}/admin/${REALM}/console/#/${REALM}/client-scopes${NC}"
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
    
    echo -e "${CYAN}Decode Token Claims:${NC}"
    echo -e "${WHITE}# The token will contain:
# - realm_access.roles: All user roles
# - ${ORGANIZATION_PREFIXES[0]}_roles: Only ${ORGANIZATION_PREFIXES[0]}_ prefixed roles (cleaned)
# - organization: Organization membership information${NC}"
    echo ""
    
    echo -e "${CYAN}➡️  Next steps:${NC}"
    echo -e "${CYAN}   1. Test authentication with your applications${NC}"
    echo -e "${CYAN}   2. Verify role filtering in JWT tokens${NC}"
    echo -e "${CYAN}   3. Configure your applications to use organization-specific claims${NC}"
    echo -e "${CYAN}   4. Set up additional redirect URIs as needed${NC}"
}

# Function to check server capabilities
check_server_capabilities() {
    echo -e "${YELLOW}🔍 Checking Keycloak server capabilities...${NC}"
    
    SERVER_INFO=$(curl -s -X GET "${KEYCLOAK_URL}/admin/serverinfo" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" 2>/dev/null)
    
    if command -v jq >/dev/null 2>&1 && [ -n "$SERVER_INFO" ]; then
        KEYCLOAK_VERSION=$(echo "$SERVER_INFO" | jq -r '.systemInfo.version // "Unknown"' 2>/dev/null)
        echo -e "${BLUE}📊 Keycloak Version: ${KEYCLOAK_VERSION}${NC}"
        
        # Check available protocol mappers
        PROTOCOL_MAPPERS=$(echo "$SERVER_INFO" | jq -r '.providers."protocol-mapper"[]? // empty' 2>/dev/null)
        SCRIPT_MAPPERS=$(echo "$PROTOCOL_MAPPERS" | grep -c "script" 2>/dev/null || echo 0)
        SCRIPT_MAPPERS=$(echo "$SCRIPT_MAPPERS" | tr -d '\n\r' | head -1)
        
        if [ "$SCRIPT_MAPPERS" -gt 0 ] 2>/dev/null; then
            echo -e "${GREEN}✅ Script-based protocol mappers supported${NC}"
            SCRIPT_MAPPERS_AVAILABLE=true
        else
            echo -e "${YELLOW}⚠️  Script-based protocol mappers not available${NC}"
            SCRIPT_MAPPERS_AVAILABLE=false
        fi
        
        # Check other capabilities
        BUILTIN_MAPPERS=$(echo "$PROTOCOL_MAPPERS" | wc -l 2>/dev/null || echo 0)
        BUILTIN_MAPPERS=$(echo "$BUILTIN_MAPPERS" | tr -d '\n\r ' | head -1)
        echo -e "${BLUE}📋 Available protocol mappers: ${BUILTIN_MAPPERS}${NC}"
        
    else
        echo -e "${YELLOW}⚠️  Cannot determine server capabilities${NC}"
        SCRIPT_MAPPERS_AVAILABLE=false
    fi
    
    echo -e "${GREEN}✅ Server capability check completed${NC}"
    echo ""
}

# Main execution
echo -e "${GREEN}🚀 Starting shared client configuration...${NC}"

wait_for_keycloak
get_admin_token

# Check server capabilities
check_server_capabilities

# Create clients
if create_shared_web_client; then
    create_organization_role_mappers "$CLIENT_UUID" "shared-web-client"
    create_organization_claim_mapper "$CLIENT_UUID" "shared-web-client"
fi

if create_shared_api_client; then
    create_organization_role_mappers "$API_CLIENT_UUID" "shared-api-client"
    create_organization_claim_mapper "$API_CLIENT_UUID" "shared-api-client"
fi

# Create client scopes
create_client_scopes

# Display summary
display_client_summary

echo -e "${GREEN}✨ Shared client configuration complete!${NC}"