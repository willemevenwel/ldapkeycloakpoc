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

# Keycloak LDAP Sync Script
# This script triggers complete synchronization of users and roles from LDAP to Keycloak

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

echo -e "${GREEN}🔄 Syncing ${CYAN}LDAP${NC} Users and Roles for realm: ${REALM}${NC}"

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

# Function to sync users
sync_users() {
    echo -e "${YELLOW}🔄 Syncing users from ${CYAN}LDAP${NC}...${NC}"
    
    USER_SYNC_RESPONSE=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/user-storage/${LDAP_ID}/sync?action=triggerFullSync" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -o /tmp/user_sync_response.json)
    
    if [ "$USER_SYNC_RESPONSE" = "200" ]; then
        SYNC_RESULT=$(cat /tmp/user_sync_response.json)
        echo -e "${GREEN}✅ User sync completed${NC}"
        if [ "$SYNC_RESULT" != "{}" ]; then
            echo -e "${BLUE}   Result: $SYNC_RESULT${NC}"
        fi
    else
        echo -e "${RED}❌ User sync failed (HTTP $USER_SYNC_RESPONSE)${NC}"
        cat /tmp/user_sync_response.json
    fi
}

# Function to sync roles
sync_roles() {
    echo -e "${YELLOW}🔄 Syncing roles from ${CYAN}LDAP${NC}...${NC}"
    
    # Get the role mapper ID
    ROLE_MAPPER_ID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/components?parent=${LDAP_ID}&type=org.keycloak.storage.ldap.mappers.LDAPStorageMapper" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" | \
        jq -r '.[] | select(.name=="role-mapper-'${REALM}'") | .id')
    
    if [ -n "$ROLE_MAPPER_ID" ] && [ "$ROLE_MAPPER_ID" != "null" ]; then
        ROLE_SYNC_RESPONSE=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/user-storage/${LDAP_ID}/mappers/${ROLE_MAPPER_ID}/sync?direction=fedToKeycloak" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -o /tmp/role_sync_response.json)
        
        if [ "$ROLE_SYNC_RESPONSE" = "200" ]; then
            SYNC_RESULT=$(cat /tmp/role_sync_response.json)
            echo -e "${GREEN}✅ Role sync completed (Mapper ID: ${ROLE_MAPPER_ID})${NC}"
            if [ "$SYNC_RESULT" != "{}" ]; then
                echo -e "${BLUE}   Result: $SYNC_RESULT${NC}"
            fi
        else
            echo -e "${RED}❌ Role sync failed (HTTP $ROLE_SYNC_RESPONSE)${NC}"
            cat /tmp/role_sync_response.json
        fi
    else
        echo -e "${RED}❌ Could not find role mapper ID${NC}"
        echo -e "${YELLOW}   Available mappers:${NC}"
        curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/components?parent=${LDAP_ID}&type=org.keycloak.storage.ldap.mappers.LDAPStorageMapper" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" | jq -r '.[] | "   • " + .name + " (ID: " + .id + ")"'
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

# Function to verify role mapper configuration
verify_role_mapper() {
    echo -e "${YELLOW}🔍 Verifying role mapper configuration...${NC}"
    
    ROLE_MAPPER_ID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/components?parent=${LDAP_ID}&type=org.keycloak.storage.ldap.mappers.LDAPStorageMapper" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" | \
        jq -r '.[] | select(.name=="role-mapper-'${REALM}'") | .id')
    
    if [ -n "$ROLE_MAPPER_ID" ] && [ "$ROLE_MAPPER_ID" != "null" ]; then
        MAPPER_CONFIG=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/components/${ROLE_MAPPER_ID}" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json")
        
        ROLES_DN=$(echo "$MAPPER_CONFIG" | jq -r '.config["roles.dn"][0] // "Not set"')
        ROLES_FILTER=$(echo "$MAPPER_CONFIG" | jq -r '.config["roles.ldap.filter"][0] // "No filter"')
        MODE=$(echo "$MAPPER_CONFIG" | jq -r '.config.mode[0] // "Not set"')
        
        echo -e "${GREEN}✅ Role mapper found (ID: ${ROLE_MAPPER_ID})${NC}"
        echo -e "   • Roles DN: ${ROLES_DN}"
        echo -e "   • Roles Filter: ${ROLES_FILTER}"
        echo -e "   • Mode: ${MODE}"
    else
        echo -e "${RED}❌ Role mapper not found${NC}"
    fi
}

# Main execution
echo -e "${GREEN}🚀 Starting complete LDAP sync for realm: ${REALM}${NC}"

get_admin_token
find_ldap_provider
verify_role_mapper
sync_users
sync_roles
list_roles

echo -e "${GREEN}🎉 Complete LDAP sync completed!${NC}"
echo ""
echo -e "${YELLOW}💡 If users or roles are not appearing, try:${NC}"
echo -e "${YELLOW}   1. Check the LDAP filter in the role mapper${NC}"
echo -e "${YELLOW}   2. Verify LDAP connectivity${NC}"
echo -e "${YELLOW}   3. Check LDAP group structure${NC}"
echo -e "${YELLOW}   4. Refresh the Keycloak admin console${NC}"
echo -e "${YELLOW}   5. Re-run this sync script${NC}"
