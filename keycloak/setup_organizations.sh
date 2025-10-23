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

# Keycloak Organizations Setup Script
# This script configures organizations in a Keycloak realm for organization-prefixed role management

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

echo -e "${GREEN}🏢 Setting up ${MAGENTA}Organizations${NC} in realm: ${REALM}${NC}"

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

# Function to check if organizations feature is enabled
check_organizations_feature() {
    echo -e "${YELLOW}🔍 Checking if Organizations feature is available...${NC}"
    
    # First check server info to determine if we should even try Organizations API
    SERVER_INFO=$(curl -s -X GET "${KEYCLOAK_URL}/admin/serverinfo" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" 2>/dev/null)
    
    if command -v jq >/dev/null 2>&1 && [ -n "$SERVER_INFO" ]; then
        KEYCLOAK_VERSION=$(echo "$SERVER_INFO" | jq -r '.systemInfo.version // "Unknown"' 2>/dev/null)
        if [ "$KEYCLOAK_VERSION" != "Unknown" ]; then
            VERSION_MAJOR=$(echo "$KEYCLOAK_VERSION" | cut -d'.' -f1)
            echo -e "${BLUE}💡 Detected Keycloak version: ${KEYCLOAK_VERSION}${NC}"
            
            if [ "$VERSION_MAJOR" -lt 25 ] 2>/dev/null; then
                echo -e "${YELLOW}⚠️  Organizations feature requires Keycloak 25+, detected v${KEYCLOAK_VERSION}${NC}"
                echo -e "${YELLOW}📝 Using group-based organization management${NC}"
                USE_ORGANIZATIONS=false
                return
            fi
        fi
    fi
    
    # Try to check if Organizations feature is enabled by testing realm configuration
    REALM_INFO=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" 2>/dev/null)
    
    # Check if the realm has organizations enabled in its attributes
    if command -v jq >/dev/null 2>&1 && [ -n "$REALM_INFO" ]; then
        ORG_ENABLED=$(echo "$REALM_INFO" | jq -r '.attributes."org.keycloak.organization.enabled" // "false"' 2>/dev/null)
        if [ "$ORG_ENABLED" = "true" ]; then
            echo -e "${BLUE}🔍 Organizations feature is enabled in realm attributes${NC}"
            
            # But we need to test if the API actually works
            HTTP_STATUS=$(curl -s -w "%{http_code}" -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/organizations" \
                -H "Authorization: Bearer ${TOKEN}" \
                -H "Content-Type: application/json" \
                -o /tmp/org_initial_check.json)
            
            if [ "$HTTP_STATUS" = "200" ]; then
                echo -e "${GREEN}✅ Organizations API is functional${NC}"
                USE_ORGANIZATIONS=true
                return
            else
                echo -e "${YELLOW}⚠️  Organizations attribute is set but API not functional (HTTP $HTTP_STATUS)${NC}"
                if [ -f /tmp/org_initial_check.json ]; then
                    echo -e "${YELLOW}📋 API Response:${NC}"
                    cat /tmp/org_initial_check.json
                fi
                echo -e "${YELLOW}💡 This may require server-level configuration or feature flags${NC}"
            fi
        fi
    fi
    
    # Try to enable Organizations feature in the realm first
    echo -e "${YELLOW}🔧 Attempting to enable Organizations feature in realm...${NC}"
    
    # Get current realm configuration
    if [ -n "$REALM_INFO" ]; then
        # Add both organization configurations to realm (both are required!)
        UPDATED_REALM=$(echo "$REALM_INFO" | jq '.attributes."org.keycloak.organization.enabled" = "true" | .organizationsEnabled = true' 2>/dev/null)
        
        if [ -n "$UPDATED_REALM" ]; then
            HTTP_STATUS=$(curl -s -w "%{http_code}" -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM}" \
                -H "Authorization: Bearer ${TOKEN}" \
                -H "Content-Type: application/json" \
                -d "${UPDATED_REALM}" \
                -o /tmp/realm_update_response.json)
            
            if [ "$HTTP_STATUS" = "204" ]; then
                echo -e "${GREEN}✅ Organizations feature fully enabled in realm (both attribute and flag set)${NC}"
                
                # Now test if Organizations API is accessible
                HTTP_STATUS=$(curl -s -w "%{http_code}" -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/organizations" \
                    -H "Authorization: Bearer ${TOKEN}" \
                    -H "Content-Type: application/json" \
                    -o /tmp/org_check_response.json)
                
                if [ "$HTTP_STATUS" = "200" ]; then
                    echo -e "${GREEN}✅ Organizations API is now accessible${NC}"
                    USE_ORGANIZATIONS=true
                    return
                else
                    echo -e "${YELLOW}⚠️  Organizations attribute set but API still not accessible (HTTP $HTTP_STATUS)${NC}"
                    if [ -f /tmp/org_check_response.json ]; then
                        echo -e "${YELLOW}📋 API Response:${NC}"
                        cat /tmp/org_check_response.json
                    fi
                    echo -e "${YELLOW}💡 Organizations feature may require server restart or additional configuration${NC}"
                fi
            else
                echo -e "${RED}❌ Failed to enable Organizations in realm (HTTP $HTTP_STATUS)${NC}"
                if [ -f /tmp/realm_update_response.json ]; then
                    cat /tmp/realm_update_response.json
                fi
            fi
        fi
    fi
    
    # Final fallback test
    echo -e "${YELLOW}� Testing Organizations API availability...${NC}"
    HTTP_STATUS=$(curl -s -w "%{http_code}" -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/organizations" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -o /tmp/org_check_response.json)
    
    if [ "$HTTP_STATUS" = "200" ]; then
        echo -e "${GREEN}✅ Organizations feature is available${NC}"
        USE_ORGANIZATIONS=true
    else
        echo -e "${YELLOW}⚠️  Organizations API not available (HTTP $HTTP_STATUS)${NC}"
        echo -e "${YELLOW}� This may be due to feature flags or configuration${NC}"
        echo -e "${YELLOW}📝 Using group-based organization management${NC}"
        USE_ORGANIZATIONS=false
    fi
}

# Function to create organization using native Organizations feature
create_organization_native() {
    local org_prefix=$1
    local org_name=$(echo "${org_prefix}" | tr '[:lower:]' '[:upper:]')
    local org_alias=$(echo "${org_prefix}" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    
    echo -e "${YELLOW}🏢 Creating organization: ${org_name} (prefix: ${org_prefix}, alias: ${org_alias})...${NC}"
    
    ORG_CONFIG=$(cat <<EOF
{
    "name": "${org_name}",
    "alias": "${org_alias}",
    "description": "Organization for ${org_prefix} prefixed roles and users",
    "enabled": true,
    "domains": [
        {
            "name": "${org_prefix}.${REALM}.local",
            "verified": false
        }
    ],
    "attributes": {
        "role_prefix": ["${org_prefix}"]
    }
}
EOF
)

    HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/organizations" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${ORG_CONFIG}" \
        -o /tmp/org_create_response.json)
    
    if [ "$HTTP_STATUS" = "201" ]; then
        echo -e "${GREEN}✅ Created organization: ${org_name}${NC}"
        
        # Get organization ID from response
        ORG_ID=$(cat /tmp/org_create_response.json | jq -r '.id // empty')
        if [ -n "$ORG_ID" ]; then
            echo -e "${GREEN}   Organization ID: ${ORG_ID}${NC}"
        fi
    elif [ "$HTTP_STATUS" = "409" ]; then
        echo -e "${YELLOW}⚠️  Organization ${org_name} already exists${NC}"
    else
        echo -e "${RED}❌ Failed to create organization ${org_name} (HTTP $HTTP_STATUS)${NC}"
        cat /tmp/org_create_response.json
    fi
}

# Function to create organization using groups (fallback)
create_organization_group() {
    local org_prefix=$1
    local org_name=$(echo "${org_prefix}" | tr '[:lower:]' '[:upper:]')
    local group_name="${org_name}_ORGANIZATION"
    
    echo -e "${YELLOW}👥 Creating organization group: ${group_name} (prefix: ${org_prefix})...${NC}"
    
    GROUP_CONFIG=$(cat <<EOF
{
    "name": "${group_name}",
    "attributes": {
        "organization_prefix": ["${org_prefix}"],
        "organization_name": ["${org_name}"],
        "description": ["Organization group for ${org_prefix} prefixed roles and users"]
    }
}
EOF
)

    HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/groups" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${GROUP_CONFIG}" \
        -o /tmp/group_create_response.json)
    
    if [ "$HTTP_STATUS" = "201" ]; then
        echo -e "${GREEN}✅ Created organization group: ${group_name}${NC}"
        
        # Get group ID from Location header or response
        GROUP_ID=$(cat /tmp/group_create_response.json | jq -r '.id // empty')
        if [ -n "$GROUP_ID" ]; then
            echo -e "${GREEN}   Group ID: ${GROUP_ID}${NC}"
        fi
    elif [ "$HTTP_STATUS" = "409" ]; then
        echo -e "${YELLOW}⚠️  Group ${group_name} already exists${NC}"
    else
        echo -e "${RED}❌ Failed to create organization group ${group_name} (HTTP $HTTP_STATUS)${NC}"
        cat /tmp/group_create_response.json
    fi
}

# Function to update LDAP group mapper for organization filtering
update_ldap_group_mapper() {
    echo -e "${YELLOW}🔧 Updating LDAP group mapper for organization filtering...${NC}"
    
    # Get LDAP components
    LDAP_COMPONENTS=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/components?type=org.keycloak.storage.UserStorageProvider" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json")
    
    LDAP_ID=$(echo "$LDAP_COMPONENTS" | jq -r '.[] | select(.name | startswith("ldap-provider")) | .id')
    
    if [ -z "$LDAP_ID" ] || [ "$LDAP_ID" = "null" ]; then
        echo -e "${YELLOW}⚠️  No LDAP provider found, skipping group mapper update${NC}"
        return
    fi
    
    echo -e "${GREEN}✅ Found LDAP provider: ${LDAP_ID}${NC}"
    
    # Build group filter for all organization prefixes
    GROUP_FILTER_PARTS=()
    for prefix in "${ORGANIZATION_PREFIXES[@]}"; do
        GROUP_FILTER_PARTS+=("(cn=${prefix}*)")
    done
    
    # Add standard groups
    GROUP_FILTER_PARTS+=("(cn=admins)" "(cn=developers)")
    
    # Join with OR logic
    GROUP_FILTER="(|${GROUP_FILTER_PARTS[*]})"
    
    echo -e "${BLUE}📋 Group filter: ${GROUP_FILTER}${NC}"
    
    # Get existing group mappers
    GROUP_MAPPERS=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/components?parent=${LDAP_ID}&type=org.keycloak.storage.ldap.mappers.LDAPStorageMapper" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json")
    
    if [ $? -ne 0 ] || [ -z "$GROUP_MAPPERS" ]; then
        echo -e "${RED}❌ Failed to get LDAP mappers${NC}"
        return 1
    fi
    
    # Look for existing group mappers
    if command -v jq >/dev/null 2>&1; then
        # Debug: check what we got from the API
        echo -e "${BLUE}🔍 Debug: Got $(echo "$GROUP_MAPPERS" | jq '. | length' 2>/dev/null || echo 0) total mappers${NC}"
        
        GROUP_MAPPER_IDS=$(echo "$GROUP_MAPPERS" | jq -r '.[] | select(.providerId == "group-ldap-mapper") | .id' 2>/dev/null)
        
        # Fix the count calculation to avoid newline issues
        if [ -n "$GROUP_MAPPER_IDS" ] && [ "$GROUP_MAPPER_IDS" != "null" ]; then
            GROUP_MAPPER_COUNT=$(echo "$GROUP_MAPPER_IDS" | wc -l | tr -d ' ')
        else
            GROUP_MAPPER_COUNT=0
        fi
        
        echo -e "${BLUE}🔍 Found ${GROUP_MAPPER_COUNT} group mapper(s)${NC}"
        
        if [ "$GROUP_MAPPER_COUNT" -eq 0 ]; then
            echo -e "${YELLOW}⚠️  No group mapper found, creating new one...${NC}"
            create_organization_group_mapper "$LDAP_ID" "$GROUP_FILTER"
        elif [ "$GROUP_MAPPER_COUNT" -eq 1 ]; then
            GROUP_MAPPER_ID=$(echo "$GROUP_MAPPER_IDS" | head -1)
            echo -e "${GREEN}✅ Found existing group mapper: ${GROUP_MAPPER_ID}${NC}"
            update_existing_group_mapper "$GROUP_MAPPER_ID" "$GROUP_FILTER"
        else
            echo -e "${YELLOW}⚠️  Multiple group mappers found (${GROUP_MAPPER_COUNT}), updating the first one...${NC}"
            GROUP_MAPPER_ID=$(echo "$GROUP_MAPPER_IDS" | head -1)
            echo -e "${BLUE}📝 Using mapper: ${GROUP_MAPPER_ID}${NC}"
            update_existing_group_mapper "$GROUP_MAPPER_ID" "$GROUP_FILTER"
            
            # Optionally warn about duplicates
            echo -e "${YELLOW}💡 You may want to manually review and remove duplicate group mappers${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  jq not available, attempting to create new group mapper${NC}"
        create_organization_group_mapper "$LDAP_ID" "$GROUP_FILTER"
    fi
}

# Function to create new organization-aware group mapper
create_organization_group_mapper() {
    local ldap_id=$1
    local group_filter=$2
    
    echo -e "${YELLOW}🏗️  Creating organization-aware group mapper...${NC}"
    
    GROUP_MAPPER_CONFIG=$(cat <<EOF
{
    "name": "organization-group-mapper-${REALM}",
    "providerId": "group-ldap-mapper",
    "providerType": "org.keycloak.storage.ldap.mappers.LDAPStorageMapper",
    "parentId": "${ldap_id}",
    "config": {
        "groups.dn": ["ou=groups,dc=min,dc=io"],
        "group.name.ldap.attribute": ["cn"],
        "group.object.classes": ["posixGroup"],
        "preserve.group.inheritance": ["false"],
        "ignore.missing.groups": ["false"],
        "membership.ldap.attribute": ["memberUid"],
        "membership.attribute.type": ["UID"],
        "membership.user.ldap.attribute": ["uid"],
        "groups.ldap.filter": ["${group_filter}"],
        "mode": ["READ_ONLY"],
        "user.roles.retrieve.strategy": ["LOAD_GROUPS_BY_MEMBER_ATTRIBUTE"],
        "mapped.group.attributes": [],
        "drop.non.existing.groups.during.sync": ["false"]
    }
}
EOF
)

    HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/components" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${GROUP_MAPPER_CONFIG}" \
        -o /tmp/group_mapper_create_response.json)
    
    if [ "$HTTP_STATUS" = "201" ]; then
        echo -e "${GREEN}✅ Created organization-aware group mapper${NC}"
    else
        echo -e "${RED}❌ Failed to create group mapper (HTTP $HTTP_STATUS)${NC}"
        cat /tmp/group_mapper_create_response.json
    fi
}

# Function to update existing group mapper
update_existing_group_mapper() {
    local mapper_id=$1
    local group_filter=$2
    
    echo -e "${YELLOW}🔄 Updating existing group mapper with organization filter...${NC}"
    
    # Validate mapper ID
    if [ -z "$mapper_id" ] || [ "$mapper_id" = "null" ]; then
        echo -e "${RED}❌ Invalid mapper ID: '${mapper_id}'${NC}"
        return 1
    fi
    
    # Get current mapper config
    CURRENT_CONFIG=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/components/${mapper_id}" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json")
    
    if [ $? -ne 0 ] || [ -z "$CURRENT_CONFIG" ]; then
        echo -e "${RED}❌ Failed to get current mapper configuration${NC}"
        return 1
    fi
    
    # Check current filter to avoid unnecessary updates
    if command -v jq >/dev/null 2>&1; then
        # Debug: check the structure of the config
        echo -e "${BLUE}🔍 Debug: Checking current mapper configuration...${NC}"
        
        # First check if we have the config properly
        if echo "$CURRENT_CONFIG" | jq -e '.config' >/dev/null 2>&1; then
            CURRENT_FILTER=$(echo "$CURRENT_CONFIG" | jq -r '.config["groups.ldap.filter"][0] // ""' 2>/dev/null)
        else
            echo -e "${YELLOW}⚠️  Config structure unexpected, attempting fallback...${NC}"
            CURRENT_FILTER=""
        fi
        
        if [ "$CURRENT_FILTER" = "$group_filter" ]; then
            echo -e "${GREEN}✅ Group mapper already has the correct filter${NC}"
            return 0
        fi
        
        echo -e "${BLUE}📝 Current filter: ${CURRENT_FILTER}${NC}"
        echo -e "${BLUE}📝 New filter: ${group_filter}${NC}"
        
        # Update the groups.ldap.filter - ensure we're updating the right field
        UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | jq --arg filter "$group_filter" '.config["groups.ldap.filter"] = [$filter]')
    else
        echo -e "${YELLOW}⚠️  jq not available, performing basic update${NC}"
        # Fallback without jq - this is more fragile but functional
        UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | sed "s/\"groups.ldap.filter\":\[\"[^\"]*\"\]/\"groups.ldap.filter\":[\"${group_filter}\"]/")
    fi
    
    # Debug: check the URL and payload before sending
    echo -e "${BLUE}🔍 Debug: Updating mapper ${mapper_id} at URL: ${KEYCLOAK_URL}/admin/realms/${REALM}/components/${mapper_id}${NC}"
    
    # Save the config to a temp file for debugging
    echo "$UPDATED_CONFIG" | jq . > /tmp/group_mapper_update_payload.json 2>/dev/null
    
    HTTP_STATUS=$(curl -s -w "%{http_code}" -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/components/${mapper_id}" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${UPDATED_CONFIG}" \
        -o /tmp/group_mapper_update_response.json)
    
    if [ "$HTTP_STATUS" = "204" ]; then
        echo -e "${GREEN}✅ Updated group mapper with organization filter${NC}"
    else
        echo -e "${RED}❌ Failed to update group mapper (HTTP $HTTP_STATUS)${NC}"
        echo -e "${BLUE}📋 Request URL: ${KEYCLOAK_URL}/admin/realms/${REALM}/components/${mapper_id}${NC}"
        echo -e "${BLUE}📋 Mapper ID: ${mapper_id}${NC}"
        if [ -f /tmp/group_mapper_update_response.json ]; then
            echo -e "${BLUE}📋 Response:${NC}"
            cat /tmp/group_mapper_update_response.json
        fi
        if [ -f /tmp/group_mapper_update_payload.json ]; then
            echo -e "${BLUE}📋 Payload sent:${NC}"
            head -10 /tmp/group_mapper_update_payload.json
        fi
        return 1
    fi
}

# Function to create example organization roles
create_example_roles() {
    echo -e "${YELLOW}🎭 Creating example organization roles...${NC}"
    
    # Common role suffixes for organizations
    ROLE_SUFFIXES=("admin" "developer" "user" "manager" "specialist")
    
    for prefix in "${ORGANIZATION_PREFIXES[@]}"; do
        echo -e "${BLUE}📝 Creating roles for organization: ${prefix}${NC}"
        
        for suffix in "${ROLE_SUFFIXES[@]}"; do
            role_name="${prefix}_${suffix}"
            
            echo -e "${YELLOW}   Creating role: ${role_name}${NC}"
            
            ROLE_CONFIG=$(cat <<EOF
{
    "name": "${role_name}",
    "description": "Role ${suffix} for organization ${prefix}",
    "attributes": {
        "organization_prefix": ["${prefix}"],
        "role_suffix": ["${suffix}"]
    }
}
EOF
)
            
            HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/roles" \
                -H "Authorization: Bearer ${TOKEN}" \
                -H "Content-Type: application/json" \
                -d "${ROLE_CONFIG}" \
                -o /tmp/role_create_response.json)
            
            if [ "$HTTP_STATUS" = "201" ]; then
                echo -e "${GREEN}   ✅ Created role: ${role_name}${NC}"
            elif [ "$HTTP_STATUS" = "409" ]; then
                echo -e "${YELLOW}   ⚠️  Role ${role_name} already exists${NC}"
            else
                echo -e "${RED}   ❌ Failed to create role ${role_name} (HTTP $HTTP_STATUS)${NC}"
            fi
        done
    done
}

# Function to create organization-specific test users
create_organization_test_users() {
    echo -e "${YELLOW}👤 Creating organization-specific test users for JWT testing...${NC}"
    
    # Define test user scenarios using regular arrays (compatible with zsh/older bash)
    test_users_data=(
        "test-acme-admin:acme_admin"
        "test-acme-developer:acme_developer" 
        "test-acme-user:acme_user"
        "test-xyz-admin:xyz_admin"
        "test-xyz-developer:xyz_developer"
        "test-xyz-user:xyz_user"
        "test-multi-org:acme_user,xyz_user"
        "test-no-org:developers"
    )
    
    for user_data in "${test_users_data[@]}"; do
        username="${user_data%%:*}"
        roles="${user_data#*:}"
        echo -e "${BLUE}📝 Creating test user: ${username} with roles: ${roles}${NC}"
        
        # Create user
        USER_CONFIG=$(cat <<EOF
{
    "username": "${username}",
    "firstName": "Test",
    "lastName": "User ${username}",
    "email": "${username}@test.local",
    "enabled": true,
    "credentials": [
        {
            "type": "password",
            "value": "${username}",
            "temporary": false
        }
    ],
    "attributes": {
        "description": ["Organization test user for JWT role verification"]
    }
}
EOF
)

        HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/users" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d "${USER_CONFIG}" \
            -o /tmp/test_user_create_response.json)
        
        if [ "$HTTP_STATUS" = "201" ]; then
            echo -e "${GREEN}   ✅ Created test user: ${username}${NC}"
            
            # Get user ID
            USER_ID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/users?username=${username}" \
                -H "Authorization: Bearer ${TOKEN}" | jq -r '.[0].id')
            
            if [ "$USER_ID" != "null" ] && [ -n "$USER_ID" ]; then
                echo -e "${GREEN}   📋 User ID: ${USER_ID}${NC}"
                
                # Assign roles
                IFS=',' read -ra ROLE_ARRAY <<< "$roles"
                for role in "${ROLE_ARRAY[@]}"; do
                    assign_role_to_user "$USER_ID" "$username" "$role"
                done
            else
                echo -e "${RED}   ❌ Failed to get user ID for ${username}${NC}"
            fi
            
        elif [ "$HTTP_STATUS" = "409" ]; then
            echo -e "${YELLOW}   ⚠️  Test user ${username} already exists, updating roles...${NC}"
            
            # Get existing user ID
            USER_ID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/users?username=${username}" \
                -H "Authorization: Bearer ${TOKEN}" | jq -r '.[0].id')
            
            if [ "$USER_ID" != "null" ] && [ -n "$USER_ID" ]; then
                # Assign roles to existing user
                IFS=',' read -ra ROLE_ARRAY <<< "$roles"
                for role in "${ROLE_ARRAY[@]}"; do
                    assign_role_to_user "$USER_ID" "$username" "$role"
                done
            fi
        else
            echo -e "${RED}   ❌ Failed to create test user ${username} (HTTP $HTTP_STATUS)${NC}"
            cat /tmp/test_user_create_response.json 2>/dev/null
        fi
    done
    
    echo -e "${GREEN}✅ Organization test users created successfully!${NC}"
}

# Function to assign role to user
assign_role_to_user() {
    local user_id=$1
    local username=$2
    local role_name=$3
    
    echo -e "${YELLOW}     Assigning role ${role_name} to ${username}...${NC}"
    
    # Get role ID
    ROLE_ID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/roles/${role_name}" \
        -H "Authorization: Bearer ${TOKEN}" | jq -r '.id')
    
    if [ "$ROLE_ID" = "null" ] || [ -z "$ROLE_ID" ]; then
        echo -e "${RED}     ❌ Role ${role_name} not found${NC}"
        return 1
    fi
    
    # Assign role
    ROLE_ASSIGNMENT=$(cat <<EOF
[
    {
        "id": "${ROLE_ID}",
        "name": "${role_name}"
    }
]
EOF
)

    HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/users/${user_id}/role-mappings/realm" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${ROLE_ASSIGNMENT}" \
        -o /tmp/role_assignment_response.json)
    
    if [ "$HTTP_STATUS" = "204" ]; then
        echo -e "${GREEN}     ✅ Assigned role ${role_name}${NC}"
    elif [ "$HTTP_STATUS" = "409" ]; then
        echo -e "${YELLOW}     ⚠️  Role ${role_name} already assigned${NC}"
    else
        echo -e "${RED}     ❌ Failed to assign role ${role_name} (HTTP $HTTP_STATUS)${NC}"
        cat /tmp/role_assignment_response.json 2>/dev/null
    fi
}

# Function to display organization setup summary
display_summary() {
    echo -e "${GREEN}🎉 Organization setup completed successfully!${NC}"
    echo ""
    echo -e "${YELLOW}📋 Configuration Summary:${NC}"
    echo -e "   • Realm: ${GREEN}${REALM}${NC}"
    echo -e "   • Organizations: ${GREEN}${ORGANIZATION_PREFIXES[*]}${NC}"
    echo -e "   • Implementation: ${GREEN}$([ "$USE_ORGANIZATIONS" = "true" ] && echo "Native Organizations" || echo "Group-based")${NC}"
    echo -e "   • Role Pattern: ${GREEN}{org_prefix}_{role_name}${NC}"
    echo -e "   • LDAP Integration: ${GREEN}Updated for organization filtering${NC}"
    echo ""
    
    echo -e "${GREEN}🏢 Created Organizations:${NC}"
    for prefix in "${ORGANIZATION_PREFIXES[@]}"; do
        org_name=$(echo "${prefix}" | tr '[:lower:]' '[:upper:]')
        if [ "$USE_ORGANIZATIONS" = "true" ]; then
            echo -e "   • ${org_name} Organization (prefix: ${prefix})"
        else
            echo -e "   • ${org_name}_ORGANIZATION Group (prefix: ${prefix})"
        fi
    done
    echo ""
    
    echo -e "${GREEN}🎭 Example Roles Created:${NC}"
    for prefix in "${ORGANIZATION_PREFIXES[@]}"; do
        echo -e "   • ${prefix}_admin, ${prefix}_developer, ${prefix}_user, ${prefix}_manager, ${prefix}_specialist"
    done
    echo ""
    
    echo -e "${GREEN}👤 Organization Test Users Created:${NC}"
    echo -e "   • test-acme-admin (acme_admin role)"
    echo -e "   • test-acme-developer (acme_developer role)"
    echo -e "   • test-acme-user (acme_user role)"
    echo -e "   • test-xyz-admin (xyz_admin role)"
    echo -e "   • test-xyz-developer (xyz_developer role)"
    echo -e "   • test-xyz-user (xyz_user role)"
    echo -e "   • test-multi-org (acme_user + xyz_user roles)"
    echo -e "   • test-no-org (developers role only)"
    echo -e "   💡 Password for all test users: same as username"
    echo ""
    
    echo -e "${GREEN}🌐 Access URLs:${NC}"
    echo -e "   • Realm URL: ${BLUE}${KEYCLOAK_URL}/realms/${REALM}${NC}"
    echo -e "   • Admin Console: ${BLUE}${KEYCLOAK_URL}/admin/${REALM}/console/${NC}"
    if [ "$USE_ORGANIZATIONS" = "true" ]; then
        echo -e "   • Organizations: ${BLUE}${KEYCLOAK_URL}/admin/${REALM}/console/#/${REALM}/organizations${NC}"
    else
        echo -e "   • Groups: ${BLUE}${KEYCLOAK_URL}/admin/${REALM}/console/#/${REALM}/groups${NC}"
    fi
    echo -e "   • Roles: ${BLUE}${KEYCLOAK_URL}/admin/${REALM}/console/#/${REALM}/roles${NC}"
    echo ""
    
    echo -e "${CYAN}➡️  Next steps:${NC}"
    echo -e "${CYAN}   1. Configure shared clients: ./configure_shared_clients.sh ${REALM} ${ORGANIZATION_PREFIXES[*]}${NC}"
    echo -e "${CYAN}   2. Sync LDAP data: ./sync_ldap.sh ${REALM}${NC}"
    echo -e "${CYAN}   3. Test role filtering with your applications${NC}"
}

# Main execution
echo -e "${GREEN}🚀 Starting organization setup...${NC}"

wait_for_keycloak
get_admin_token
check_organizations_feature

# Create organizations
for prefix in "${ORGANIZATION_PREFIXES[@]}"; do
    if [ "$USE_ORGANIZATIONS" = "true" ]; then
        create_organization_native "$prefix"
    else
        create_organization_group "$prefix"
    fi
done

# Update LDAP configuration
update_ldap_group_mapper

# Create example roles
create_example_roles

# Create organization-specific test users
create_organization_test_users

# Display summary
display_summary

echo -e "${GREEN}✨ Organization setup complete!${NC}"