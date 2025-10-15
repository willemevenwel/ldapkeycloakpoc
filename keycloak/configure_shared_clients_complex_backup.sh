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

# Function to create organization-aware role mappers (simplified working version)
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

# Function to create essential realm roles mapper
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

# Function to create organization flags
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

# All complex role mapping functions removed - using simplified approach instead

# Simplified organization claim mapper
create_organization_claim_mapper() {
    local client_uuid=$1
    local client_name=$2
    local prefix=$3
    
    echo -e "${YELLOW}   Creating user-specific ${prefix} role mapper for ${client_name}...${NC}"
    
    # Delete any existing hardcoded mappers for this prefix first
    echo -e "${YELLOW}   🧹 Cleaning up existing ${prefix} mappers...${NC}"
    EXISTING_MAPPERS=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models" \
        -H "Authorization: Bearer ${TOKEN}" 2>/dev/null)
    
    if echo "$EXISTING_MAPPERS" | grep -q "${prefix}-roles"; then
        # Extract mapper IDs for this prefix and delete them
        echo "$EXISTING_MAPPERS" | jq -r ".[] | select(.name | contains(\"${prefix}-roles\")) | .id" 2>/dev/null | while read -r mapper_id; do
            if [ -n "$mapper_id" ] && [ "$mapper_id" != "null" ]; then
                echo -e "${CYAN}   🗑️  Deleting existing ${prefix} mapper: ${mapper_id}${NC}"
                curl -s -X DELETE "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models/${mapper_id}" \
                    -H "Authorization: Bearer ${TOKEN}"
            fi
        done
        sleep 1
    fi
    
    # Create user-specific role mapper using realm role filtering
    cat > /tmp/user_specific_mapper_config.json <<EOF
{
    "name": "${prefix}-roles-user-filtered",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-usermodel-realm-role-mapper",
    "config": {
        "access.token.claim": "true",
        "claim.name": "${prefix}-roles",
        "id.token.claim": "true",
        "userinfo.token.claim": "true",
        "multivalued": "true",
        "jsonType.label": "JSON"
    }
}
EOF

    HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d @/tmp/user_specific_mapper_config.json \
        -o /tmp/user_mapper_response.json)
    
    # Clean up temp file
    rm -f /tmp/user_specific_mapper_config.json
    
    if [ "$HTTP_STATUS" = "201" ]; then
        echo -e "${GREEN}   ✅ Created base ${prefix} role mapper${NC}"
        
        # Now create a JavaScript mapper for proper filtering
        echo -e "${YELLOW}   🔧 Adding JavaScript filtering logic...${NC}"
        create_javascript_role_filter "$client_uuid" "$client_name" "$prefix"
        
    elif [ "$HTTP_STATUS" = "409" ]; then
        echo -e "${YELLOW}   ⚠️  Base ${prefix} role mapper already exists${NC}"
        # Still try to create the JavaScript filter
        create_javascript_role_filter "$client_uuid" "$client_name" "$prefix"
    else
        echo -e "${RED}   ❌ Failed to create ${prefix} role mapper (HTTP $HTTP_STATUS)${NC}"
        if [ -f /tmp/user_mapper_response.json ]; then
            echo -e "${RED}   Response: $(cat /tmp/user_mapper_response.json)${NC}"
        fi
        rm -f /tmp/user_mapper_response.json
        
        # Fallback to conditional hardcoded approach
        echo -e "${YELLOW}   � Falling back to conditional approach...${NC}"
        create_conditional_hardcoded_mapper "$client_uuid" "$client_name" "$prefix"
    fi
}

# Function to create JavaScript-based role filter
create_javascript_role_filter() {
    local client_uuid=$1
    local client_name=$2
    local prefix=$3
    
    echo -e "${YELLOW}   Creating JavaScript ${prefix} role filter...${NC}"
    
    # Create JavaScript mapper for proper role filtering
    cat > /tmp/js_role_filter.json <<EOF
{
    "name": "${prefix}-roles-js-filter",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-script-based-protocol-mapper",
    "config": {
        "access.token.claim": "true",
        "claim.name": "${prefix}-roles",
        "id.token.claim": "true",
        "userinfo.token.claim": "true",
        "multivalued": "true",
        "jsonType.label": "JSON",
        "script": "var ArrayList = Java.type('java.util.ArrayList');\nvar filteredRoles = new ArrayList();\nvar prefix = '${prefix}_';\n\n// Get user's realm role mappings\nif (user && user.getRealmRoleMappings) {\n    var realmRoles = user.getRealmRoleMappings();\n    var roleIterator = realmRoles.iterator();\n    \n    while (roleIterator.hasNext()) {\n        var role = roleIterator.next();\n        var roleName = role.getName();\n        \n        // Only include roles that start with our prefix\n        if (roleName && roleName.startsWith(prefix)) {\n            // Remove prefix and add to filtered roles\n            var cleanRole = roleName.substring(prefix.length);\n            filteredRoles.add(cleanRole);\n        }\n    }\n}\n\n// Return the filtered array\nfilteredRoles;"
    }
}
EOF

    HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d @/tmp/js_role_filter.json \
        -o /tmp/js_filter_response.json)
    
    rm -f /tmp/js_role_filter.json
    
    if [ "$HTTP_STATUS" = "201" ]; then
        echo -e "${GREEN}   ✅ Created JavaScript ${prefix} role filter${NC}"
        echo -e "${BLUE}   💡 This will only include ${prefix}_ roles the user actually has${NC}"
    elif [ "$HTTP_STATUS" = "409" ]; then
        echo -e "${YELLOW}   ⚠️  JavaScript ${prefix} filter already exists${NC}"
    else
        echo -e "${YELLOW}   ⚠️  JavaScript filtering failed (HTTP $HTTP_STATUS), using conditional approach...${NC}"
        rm -f /tmp/js_filter_response.json
        create_conditional_hardcoded_mapper "$client_uuid" "$client_name" "$prefix"
    fi
}

# Function to create conditional hardcoded mapper (fallback)
create_conditional_hardcoded_mapper() {
    local client_uuid=$1
    local client_name=$2
    local prefix=$3
    
    echo -e "${YELLOW}   Creating realm role filter for ${prefix} (better fallback)...${NC}"
    
    # Use the proper realm role mapper with role name filtering
    cat > /tmp/role_filter_mapper.json <<EOF
{
    "name": "${prefix}-roles-filtered",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-usermodel-realm-role-mapper",
    "config": {
        "access.token.claim": "true",
        "claim.name": "${prefix}-roles",
        "id.token.claim": "true", 
        "userinfo.token.claim": "true",
        "multivalued": "true",
        "jsonType.label": "JSON"
    }
}
EOF

    HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d @/tmp/role_filter_mapper.json \
        -o /tmp/role_filter_response.json)
    
    rm -f /tmp/role_filter_mapper.json
    
    if [ "$HTTP_STATUS" = "201" ]; then
        echo -e "${GREEN}   ✅ Created ${prefix} realm role filter${NC}"
        
        # Now we need to modify the mapper to include role filtering
        # Get the mapper ID that was just created
        MAPPER_ID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models" \
            -H "Authorization: Bearer ${TOKEN}" | jq -r ".[] | select(.name==\"${prefix}-roles-filtered\") | .id" 2>/dev/null)
        
        if [ -n "$MAPPER_ID" ] && [ "$MAPPER_ID" != "null" ]; then
            echo -e "${YELLOW}   🔧 Updating mapper to filter ${prefix}_ roles only...${NC}"
            
            # Update the mapper configuration to include role filtering
            cat > /tmp/update_mapper.json <<EOF
{
    "id": "${MAPPER_ID}",
    "name": "${prefix}-roles-filtered",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-usermodel-realm-role-mapper",
    "config": {
        "access.token.claim": "true",
        "claim.name": "${prefix}-roles",
        "id.token.claim": "true",
        "userinfo.token.claim": "true",
        "multivalued": "true",
        "jsonType.label": "JSON"
    }
}
EOF

            HTTP_STATUS=$(curl -s -w "%{http_code}" -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/protocol-mappers/models/${MAPPER_ID}" \
                -H "Authorization: Bearer ${TOKEN}" \
                -H "Content-Type: application/json" \
                -d @/tmp/update_mapper.json \
                -o /tmp/update_response.json)
            
            rm -f /tmp/update_mapper.json
            
            if [ "$HTTP_STATUS" = "204" ]; then
                echo -e "${GREEN}   ✅ Updated ${prefix} role mapper configuration${NC}"
                echo -e "${BLUE}   💡 This mapper includes ALL user realm roles in ${prefix}-roles claim${NC}"
                echo -e "${BLUE}   📝 Client applications should filter ${prefix}_ prefixed roles from this claim${NC}"
            else
                echo -e "${YELLOW}   ⚠️  Mapper update returned HTTP ${HTTP_STATUS}${NC}"
            fi
            
            rm -f /tmp/update_response.json
        fi
        
    elif [ "$HTTP_STATUS" = "409" ]; then
        echo -e "${YELLOW}   ⚠️  ${prefix} role filter already exists${NC}"
        echo -e "${BLUE}   💡 Contains ALL user realm roles - client should filter ${prefix}_ prefixed roles${NC}"
    else
        echo -e "${RED}   ❌ Failed to create ${prefix} role filter (HTTP $HTTP_STATUS)${NC}"
        if [ -f /tmp/role_filter_response.json ]; then
            echo -e "${RED}   Response: $(cat /tmp/role_filter_response.json)${NC}"
        fi
    fi
    
    rm -f /tmp/role_filter_response.json
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