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

# Keycloak LDAP Configuration Script
# This script configures an LDAP user federation provider in Keycloak

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

echo -e "${GREEN}🔧 Configuring ${MAGENTA}Keycloak${NC} ${CYAN}LDAP${NC} Provider for realm: ${REALM}${NC}"

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

# Function to check if LDAP provider already exists
check_ldap_exists() {
    echo -e "${YELLOW}🔍 Checking if ${CYAN}LDAP${NC} provider already exists...${NC}"
    EXISTING_LDAP=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/components?type=org.keycloak.storage.UserStorageProvider" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" | \
        jq -r '.[] | select(.name=="ldap-provider-'${REALM}'") | .id')
    
    if [ -n "$EXISTING_LDAP" ] && [ "$EXISTING_LDAP" != "null" ]; then
        echo -e "${YELLOW}⚠️  ${CYAN}LDAP${NC} provider already exists (ID: ${EXISTING_LDAP})${NC}"
        echo -e "${YELLOW}🔄 Removing existing provider...${NC}"
        curl -s -X DELETE "${KEYCLOAK_URL}/admin/realms/${REALM}/components/${EXISTING_LDAP}" \
            -H "Authorization: Bearer ${TOKEN}"
        echo -e "${GREEN}✅ Removed existing ${CYAN}LDAP${NC} provider${NC}"
    fi
}

# Function to get realm ID
get_realm_id() {
    echo -e "${YELLOW}🔍 Getting realm ID...${NC}"
    REALM_INFO=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json")
    
    REALM_ID=$(echo "$REALM_INFO" | jq -r '.id')
    
    if [ "$REALM_ID" = "null" ] || [ -z "$REALM_ID" ]; then
        echo -e "${RED}❌ Failed to get realm ID${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Got realm ID: ${REALM_ID}${NC}"
}

# Function to create LDAP provider
create_ldap_provider() {
    echo -e "${YELLOW}🏗️  Creating ${CYAN}LDAP${NC} provider...${NC}"
    
    LDAP_CONFIG=$(cat <<EOF
{
    "name": "ldap-provider-${REALM}",
    "providerId": "ldap",
    "providerType": "org.keycloak.storage.UserStorageProvider",
    "parentId": "${REALM_ID}",
    "config": {
        "enabled": ["true"],
        "priority": ["0"],
        "fullSyncPeriod": ["-1"],
        "changedSyncPeriod": ["-1"],
        "cachePolicy": ["DEFAULT"],
        "batchSizeForSync": ["1000"],
        "editMode": ["READ_ONLY"],
        "syncRegistrations": ["true"],
        "importEnabled": ["true"],
        "vendor": ["other"],
        "usernameLDAPAttribute": ["uid"],
        "rdnLDAPAttribute": ["uid"],
        "uuidLDAPAttribute": ["entryUUID"],
        "userObjectClasses": ["inetOrgPerson"],
        "connectionUrl": ["ldap://ldap:389"],
        "usersDn": ["ou=users,dc=min,dc=io"],
        "authType": ["simple"],
        "bindDn": ["cn=admin,dc=min,dc=io"],
        "bindCredential": ["admin"],
        "searchScope": ["1"],
        "validatePasswordPolicy": ["false"],
        "trustEmail": ["false"],
        "useTruststoreSpi": ["always"],
        "connectionPooling": ["true"],
        "pagination": ["true"],
        "allowKerberosAuthentication": ["false"],
        "debug": ["false"],
        "usePasswordModifyExtendedOp": ["false"],
        "connectionTrace": ["false"],
        "startTls": ["false"],
        "useKerberosForPasswordAuthentication": ["false"],
        "removeInvalidUsersEnabled": ["true"]
    }
}
EOF
)

    # Make the request and capture headers
    HTTP_STATUS=$(curl -s -w "%{http_code}" -D /tmp/keycloak_headers.txt -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/components" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${LDAP_CONFIG}" \
        -o /tmp/keycloak_response.json)
    
    RESPONSE=$(cat /tmp/keycloak_response.json)
    
    if [ "$HTTP_STATUS" != "201" ]; then
        echo -e "${RED}❌ Failed to create ${CYAN}LDAP${NC} provider (HTTP $HTTP_STATUS)${NC}"
        echo -e "${RED}Response: $RESPONSE${NC}"
        exit 1
    fi
    
    # Extract ID from Location header
    LOCATION=$(grep -i "^location:" /tmp/keycloak_headers.txt | cut -d' ' -f2- | tr -d '\r\n')
    
    if [ -n "$LOCATION" ]; then
        LDAP_ID=$(echo "$LOCATION" | sed 's|.*/components/||')
    else
        echo -e "${RED}❌ No Location header found${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Created ${CYAN}LDAP${NC} provider (ID: ${LDAP_ID})${NC}"
}

# Function to create group mapper
create_group_mapper() {
    echo -e "${YELLOW}👥 Creating ${CYAN}LDAP${NC} group mapper...${NC}"
    
    # Define which groups to sync (you can modify this list)
    GROUPS_TO_SYNC="admins|developers|acme*|xyz*"  # Sync admins, developers, and any groups containing acme or xyz
    
    GROUP_MAPPER_CONFIG=$(cat <<EOF
{
    "name": "group-mapper-${REALM}",
    "providerId": "group-ldap-mapper",
    "providerType": "org.keycloak.storage.ldap.mappers.LDAPStorageMapper",
    "parentId": "${LDAP_ID}",
    "config": {
        "groups.dn": ["ou=groups,dc=min,dc=io"],
        "group.name.ldap.attribute": ["cn"],
        "group.object.classes": ["posixGroup"],
        "preserve.group.inheritance": ["false"],
        "ignore.missing.groups": ["false"],
        "membership.ldap.attribute": ["memberUid"],
        "membership.attribute.type": ["UID"],
        "membership.user.ldap.attribute": ["uid"],
        "groups.ldap.filter": ["(|(cn=admins)(cn=developers)(cn=acme*)(cn=xyz*))"],
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
        -o /tmp/group_mapper_response.json)
    
    if [ "$HTTP_STATUS" != "201" ]; then
        echo -e "${RED}❌ Failed to create ${CYAN}LDAP${NC} group mapper (HTTP $HTTP_STATUS)${NC}"
        RESPONSE=$(cat /tmp/group_mapper_response.json)
        echo -e "${RED}Response: $RESPONSE${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Created ${CYAN}LDAP${NC} group mapper (syncing: ${GROUPS_TO_SYNC})${NC}"
}

# Function to verify LDAP provider was created
verify_ldap_provider() {
    echo -e "${YELLOW}🔍 Verifying ${CYAN}LDAP${NC} provider was created...${NC}"
    
    VERIFICATION=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/components/${LDAP_ID}" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json")
    
    if echo "$VERIFICATION" | jq -e '.id' > /dev/null 2>&1; then
        PROVIDER_NAME=$(echo "$VERIFICATION" | jq -r '.name')
        PROVIDER_TYPE=$(echo "$VERIFICATION" | jq -r '.providerType')
        PARENT_ID=$(echo "$VERIFICATION" | jq -r '.parentId')
        
        echo -e "${GREEN}✅ ${CYAN}LDAP${NC} provider verified:${NC}"
        echo -e "   • ID: ${LDAP_ID}"
        echo -e "   • Name: ${PROVIDER_NAME}"
        echo -e "   • Type: ${PROVIDER_TYPE}"
        echo -e "   • Parent Realm ID: ${PARENT_ID}"
        
        if [ "$PARENT_ID" != "$REALM_ID" ]; then
            echo -e "${RED}⚠️  WARNING: Provider parent ID (${PARENT_ID}) doesn't match expected realm ID (${REALM_ID})${NC}"
        else
            echo -e "${GREEN}✅ Parent ID correctly set to realm UUID${NC}"
        fi
    else
        echo -e "${RED}❌ Failed to verify ${CYAN}LDAP${NC} provider${NC}"
        echo -e "${RED}Response: $VERIFICATION${NC}"
    fi
}

# Main execution
echo -e "${GREEN}🚀 Starting ${MAGENTA}Keycloak${NC} ${CYAN}LDAP${NC} configuration...${NC}"

wait_for_keycloak
get_admin_token
get_realm_id
check_ldap_exists
create_ldap_provider
verify_ldap_provider

echo -e "${GREEN}🎉 ${MAGENTA}Keycloak${NC} ${CYAN}LDAP${NC} configuration completed successfully!${NC}"

# Verify the LDAP provider was created
echo -e "${YELLOW}🔍 ${CYAN}LDAP${NC} provider created with ID: ${LDAP_ID}${NC}"

echo -e "${YELLOW}📋 Configuration Summary:${NC}"
echo -e "   • Realm: ${REALM}"
echo -e "   • ${CYAN}LDAP${NC} Provider     : ldap-provider-${REALM} (ID: ${LDAP_ID})"
echo -e "   • ${CYAN}LDAP${NC} Provider url : ${BLUE}${KEYCLOAK_URL}/admin/master/console/#/mirai/user-federation/ldap/${LDAP_ID}${NC}"
echo -e "   • ${CYAN}LDAP${NC} Server       : ${CYAN}ldap://ldap:389${NC}"
echo -e "   • Users DN       : ou=users,dc=min,dc=io"
echo -e "   • Groups DN      : ou=groups,dc=min,dc=io"
echo -e "   • Groups Filter  : Syncing groups: admins, developers, and any groups starting with 'acme' or 'xyz'"
echo -e "   • Edit Mode      : READ_ONLY"
echo -e "   • Role Mapper    : Will be created by update_role_mapper.sh"
echo -e "   • Authentication : $([ "$USE_MASTER_ADMIN" = "true" ] && echo "Master Admin" || echo "Realm Admin")"
echo ""
echo -e "${GREEN}🌐 Access URLs:${NC}"
echo -e "   • Realm URL       : ${BLUE}${KEYCLOAK_URL}/realms/${REALM}${NC}"
echo -e "   • Admin Console   : ${BLUE}${KEYCLOAK_URL}/admin/${REALM}/console/${NC}"
echo -e "   • User Federation : ${BLUE}${KEYCLOAK_URL}/admin/${REALM}/console/#/${REALM}/user-federation${NC}"
echo ""
echo -e "${GREEN}🔑 Admin credentials:${NC}"
if [ "$USE_MASTER_ADMIN" = "true" ]; then
    echo -e "   • Master Admin: admin/admin"
else
    echo -e "   • Realm Admin: ${ADMIN_USERNAME}/${ADMIN_PASSWORD}"
fi
echo ""
echo -e "${YELLOW}💡 The ${CYAN}LDAP${YELLOW} provider should now appear in:${NC}"
echo -e "${YELLOW}   User Federation → ldap-provider-${REALM}${NC}"
echo -e "${YELLOW}   If it doesn't appear immediately, try:${NC}"
echo -e "${YELLOW}   1. Refreshing the page (Ctrl+F5)${NC}"
echo -e "${YELLOW}   2. Clearing browser cache${NC}"
echo -e "${YELLOW}   3. Logging out and back in to ${MAGENTA}Keycloak${NC}${NC}"
echo ""
echo -e "${YELLOW}🔧 To debug further, run: ${WHITE}./debug_ldap_provider.sh ${REALM}${NC}"
echo ""
echo -e "${CYAN}➡️  Next steps:${NC}"
echo -e "${CYAN}   1. Create role mapper: ./update_role_mapper.sh ${REALM}${NC}"
echo -e "${CYAN}   2. Sync users and roles: ./sync_ldap.sh ${REALM}${NC}"
