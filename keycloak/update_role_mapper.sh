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

# Keycloak LDAP Role Mapper Script
# This script creates or updates a role-ldap-mapper for mapping LDAP groups to Keycloak roles

# Check if realm name parameter is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <realm-name>"
    echo "Example: $0 wallmart"
    exit 1
fi

REALM="$1"
ADMIN_USERNAME="admin-${REALM}"
ADMIN_PASSWORD="${ADMIN_USERNAME}"  # Password same as username

KEYCLOAK_URL="http://localhost:8090"

echo -e "${GREEN}🔧 Creating/Updating ${CYAN}LDAP${NC} Role Mapper for realm: ${REALM}${NC}"

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

# Function to find LDAP provider
find_ldap_provider() {
    echo -e "${YELLOW}🔍 Finding ${CYAN}LDAP${NC} provider...${NC}"
    LDAP_ID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/components?type=org.keycloak.storage.UserStorageProvider" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" | \
        jq -r '.[] | select(.name=="ldap-provider-'${REALM}'") | .id')
    
    if [ -z "$LDAP_ID" ] || [ "$LDAP_ID" = "null" ]; then
        echo -e "${RED}❌ ${CYAN}LDAP${NC} provider not found. Make sure to run add_ldap_provider_for_keycloak.sh first${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Found ${CYAN}LDAP${NC} provider (ID: ${LDAP_ID})${NC}"
}

# Function to check if role mapper already exists
check_role_mapper_exists() {
    echo -e "${YELLOW}🔍 Checking if role mapper already exists...${NC}"
    EXISTING_ROLE_MAPPER=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/components?parent=${LDAP_ID}&type=org.keycloak.storage.ldap.mappers.LDAPStorageMapper" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" | \
        jq -r '.[] | select(.name=="role-mapper-'${REALM}'") | .id')
    
    if [ -n "$EXISTING_ROLE_MAPPER" ] && [ "$EXISTING_ROLE_MAPPER" != "null" ]; then
        echo -e "${YELLOW}⚠️  Role mapper already exists (ID: ${EXISTING_ROLE_MAPPER})${NC}"
        echo -e "${YELLOW}🔄 Removing existing role mapper...${NC}"
        curl -s -X DELETE "${KEYCLOAK_URL}/admin/realms/${REALM}/components/${EXISTING_ROLE_MAPPER}" \
            -H "Authorization: Bearer ${TOKEN}"
        echo -e "${GREEN}✅ Removed existing role mapper${NC}"
    fi
}

# Function to create role mapper
create_role_mapper() {
    echo -e "${YELLOW}🏗️  Creating ${CYAN}LDAP${NC} role mapper...${NC}"
    
    ROLE_MAPPER_CONFIG=$(cat <<EOF
{
    "name": "role-mapper-${REALM}",
    "providerId": "role-ldap-mapper",
    "providerType": "org.keycloak.storage.ldap.mappers.LDAPStorageMapper",
    "parentId": "${LDAP_ID}",
    "config": {
        "roles.dn": ["ou=groups,dc=mycompany,dc=local"],
        "role.name.ldap.attribute": ["cn"],
        "role.object.classes": ["posixGroup"],
        "membership.ldap.attribute": ["memberUid"],
        "membership.attribute.type": ["UID"],
        "membership.user.ldap.attribute": ["uid"],
        "roles.ldap.filter": ["(|(cn=admins)(cn=developers)(cn=ds1)(cn=ds2)(cn=ds3)(cn=user))"],
        "mode": ["READ_ONLY"],
        "use.realm.roles.mapping": ["true"],
        "client.id": [""],
        "role.attributes": [""],
        "roles.batch.sync.threshold": ["1000"]
    }
}
EOF
)

    HTTP_STATUS=$(curl -s -w "%{http_code}" -D /tmp/role_mapper_headers.txt -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/components" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${ROLE_MAPPER_CONFIG}" \
        -o /tmp/role_mapper_response.json)
    
    RESPONSE=$(cat /tmp/role_mapper_response.json)
    
    if [ "$HTTP_STATUS" != "201" ]; then
        echo -e "${RED}❌ Failed to create role mapper (HTTP $HTTP_STATUS)${NC}"
        echo -e "${RED}Response: $RESPONSE${NC}"
        exit 1
    fi
    
    # Extract ID from Location header
    LOCATION=$(grep -i "^location:" /tmp/role_mapper_headers.txt | cut -d' ' -f2- | tr -d '\r\n')
    
    if [ -n "$LOCATION" ]; then
        ROLE_MAPPER_ID=$(echo "$LOCATION" | sed 's|.*/components/||')
    else
        echo -e "${RED}❌ No Location header found${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Created role mapper (ID: ${ROLE_MAPPER_ID})${NC}"
}

# Function to sync roles
sync_roles() {
    echo -e "${YELLOW}🔄 Syncing roles from ${CYAN}LDAP${NC}...${NC}"
    
    if [ -n "$ROLE_MAPPER_ID" ] && [ "$ROLE_MAPPER_ID" != "null" ]; then
        ROLE_SYNC_RESPONSE=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/user-storage/${LDAP_ID}/mappers/${ROLE_MAPPER_ID}/sync?direction=fedToKeycloak" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -o /tmp/role_sync_response.json)
        
        if [ "$ROLE_SYNC_RESPONSE" = "200" ]; then
            SYNC_RESULT=$(cat /tmp/role_sync_response.json)
            echo -e "${GREEN}✅ Role sync completed${NC}"
            if [ "$SYNC_RESULT" != "{}" ]; then
                echo -e "${BLUE}   Result: $SYNC_RESULT${NC}"
            fi
        else
            echo -e "${RED}❌ Role sync failed (HTTP $ROLE_SYNC_RESPONSE)${NC}"
            cat /tmp/role_sync_response.json
        fi
    else
        echo -e "${RED}❌ Role mapper ID not available for sync${NC}"
    fi
}

# Function to verify role mapper
verify_role_mapper() {
    echo -e "${YELLOW}🔍 Verifying role mapper...${NC}"
    
    VERIFICATION=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/components/${ROLE_MAPPER_ID}" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json")
    
    if echo "$VERIFICATION" | jq -e '.id' > /dev/null 2>&1; then
        MAPPER_NAME=$(echo "$VERIFICATION" | jq -r '.name')
        MAPPER_TYPE=$(echo "$VERIFICATION" | jq -r '.providerId')
        ROLES_DN=$(echo "$VERIFICATION" | jq -r '.config["roles.dn"][0] // "Not set"')
        ROLES_FILTER=$(echo "$VERIFICATION" | jq -r '.config["roles.ldap.filter"][0] // "No filter"')
        
        echo -e "${GREEN}✅ Role mapper verified:${NC}"
        echo -e "   • ID: ${ROLE_MAPPER_ID}"
        echo -e "   • Name: ${MAPPER_NAME}"
        echo -e "   • Type: ${MAPPER_TYPE}"
        echo -e "   • Roles DN: ${ROLES_DN}"
        echo -e "   • Roles Filter: ${ROLES_FILTER}"
    else
        echo -e "${RED}❌ Failed to verify role mapper${NC}"
        echo -e "${RED}Response: $VERIFICATION${NC}"
    fi
}

# Function to list current roles
list_roles() {
    echo -e "${YELLOW}📋 Current realm roles in Keycloak:${NC}"
    ROLES=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/roles" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json")
    
    if [ "$(echo "$ROLES" | jq '. | length')" -gt 0 ]; then
        echo "$ROLES" | jq -r '.[] | "   • " + .name + " (ID: " + .id + ")"'
    else
        echo -e "${YELLOW}   No roles found${NC}"
    fi
}

# Main execution
echo -e "${GREEN}🚀 Starting ${CYAN}LDAP${NC} role mapper configuration...${NC}"

wait_for_keycloak
get_admin_token
find_ldap_provider
check_role_mapper_exists
create_role_mapper
sync_roles
verify_role_mapper
list_roles

echo -e "${GREEN}🎉 ${CYAN}LDAP${NC} role mapper configuration completed successfully!${NC}"

echo -e "${YELLOW}📋 Configuration Summary:${NC}"
echo -e "   • Realm: ${REALM}"
echo -e "   • ${CYAN}LDAP${NC} Provider: ldap-provider-${REALM} (ID: ${LDAP_ID})"
echo -e "   • Role Mapper: role-mapper-${REALM} (ID: ${ROLE_MAPPER_ID})"
echo -e "   • Roles DN: ou=groups,dc=mycompany,dc=local"
echo -e "   • Pre-created Roles: admin, developer (created during realm setup)"
echo -e "   • Auto-created Roles: Will be created from LDAP group names during sync"
echo -e "   • LDAP Filter: Groups (admins, developers, ds1, ds2, ds3, user)"
echo -e "   • Mode: READ_ONLY"
echo -e "   • Mapping Type: Realm Roles (mix of pre-created and auto-created)"

echo ""
echo -e "${GREEN}🌐 Access URLs:${NC}"
echo -e "   • Role Mapper Config: ${BLUE}${KEYCLOAK_URL}/admin/${REALM}/console/#/${REALM}/user-federation/ldap/${LDAP_ID}/mappers/${ROLE_MAPPER_ID}${NC}"
echo -e "   • Realm Roles: ${BLUE}${KEYCLOAK_URL}/admin/${REALM}/console/#/${REALM}/roles${NC}"

echo ""
echo -e "${YELLOW}💡 Role Mapping Strategy:${NC}"
echo -e "${YELLOW}   • Pre-created roles (clean names):${NC}"
echo -e "${YELLOW}     - LDAP Group 'admins' → Realm Role 'admin' (pre-created)${NC}"
echo -e "${YELLOW}     - LDAP Group 'developers' → Realm Role 'developer' (pre-created)${NC}"
echo -e "${YELLOW}   • Auto-created roles (LDAP group names):${NC}"
echo -e "${YELLOW}     - LDAP Group 'ds1' → Realm Role 'ds1' (auto-created)${NC}"
echo -e "${YELLOW}     - LDAP Group 'ds2' → Realm Role 'ds2' (auto-created)${NC}"
echo -e "${YELLOW}     - LDAP Group 'ds3' → Realm Role 'ds3' (auto-created)${NC}"
echo -e "${YELLOW}     - LDAP Group 'user' → Realm Role 'user' (auto-created)${NC}"
echo -e "${CYAN}   📝 To add more pre-created roles, modify REALM_ROLES_TO_CREATE in the script${NC}"

echo ""
echo -e "${YELLOW}🔧 To test role mappings:${NC}"
echo -e "${YELLOW}   1. Log in with an LDAP user${NC}"
echo -e "${YELLOW}   2. Check user's roles in the admin console${NC}"
echo -e "${YELLOW}   3. Verify role assignments match LDAP group memberships${NC}"

echo ""
echo -e "${CYAN}➡️  Next steps:${NC}"
echo -e "${CYAN}   • Test user login to verify role mappings${NC}"
echo -e "${CYAN}   • Configure application-specific role mappings if needed${NC}"
echo -e "${CYAN}   • Run user sync to ensure all role mappings are applied:${NC}"
echo -e "${CYAN}     ./sync_ldap.sh ${REALM}${NC}"