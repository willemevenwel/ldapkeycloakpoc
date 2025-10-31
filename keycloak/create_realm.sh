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

# Get script directory for relative imports
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source network detection utility
if [ -f "${SCRIPT_DIR}/../network_detect.sh" ]; then
    source "${SCRIPT_DIR}/../network_detect.sh"
else
    echo -e "${RED}❌ Network detection utility not found${NC}"
    exit 1
fi

# Keycloak Realm Creation Script
# This script creates a new realm and an admin user for that realm

# Check if realm name parameter is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <realm-name>"
    echo "Example: $0 walmart"
    exit 1
fi

REALM_NAME="$1"
ADMIN_USERNAME="admin-${REALM_NAME}"
ADMIN_PASSWORD="${ADMIN_USERNAME}"  # Password same as username

KEYCLOAK_URL="$(get_keycloak_url)"
MASTER_ADMIN_USER="admin"
MASTER_ADMIN_PASSWORD="admin"

echo -e "${GREEN}🏗️  Creating ${MAGENTA}Keycloak${NC} Realm: ${REALM_NAME}${NC}"

# Function to wait for Keycloak to be ready
wait_for_keycloak() {
    echo -e "${YELLOW}⏳ Waiting for ${MAGENTA}Keycloak${NC} to be ready...${NC}"
    until curl -s -f "${KEYCLOAK_URL}/realms/master" > /dev/null 2>&1; do
        echo -n "."
        sleep 2
    done
    echo -e "${GREEN}✅ ${MAGENTA}Keycloak${NC} is ready!${NC}"
}

# Function to get master admin token
get_master_admin_token() {
    echo -e "${YELLOW}🔑 Getting master admin token...${NC}"
    TOKEN_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${MASTER_ADMIN_USER}" \
        -d "password=${MASTER_ADMIN_PASSWORD}" \
        -d "grant_type=password" \
        -d "client_id=admin-cli")
    
    MASTER_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
    
    if [ "$MASTER_TOKEN" = "null" ] || [ -z "$MASTER_TOKEN" ]; then
        echo -e "${RED}❌ Failed to get master admin token${NC}"
        echo -e "${RED}Response: $TOKEN_RESPONSE${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Got master admin token${NC}"
}

# Function to check if realm already exists
check_realm_exists() {
    echo -e "${YELLOW}🔍 Checking if realm '${REALM_NAME}' already exists...${NC}"
    
    HTTP_STATUS=$(curl -s -w "%{http_code}" -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}" \
        -H "Authorization: Bearer ${MASTER_TOKEN}" \
        -o /dev/null)
    
    if [ "$HTTP_STATUS" = "200" ]; then
        echo -e "${YELLOW}⚠️  Realm '${REALM_NAME}' already exists${NC}"
        read -p "Do you want to delete and recreate it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}🗑️  Deleting existing realm...${NC}"
            curl -s -X DELETE "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}" \
                -H "Authorization: Bearer ${MASTER_TOKEN}"
            echo -e "${GREEN}✅ Deleted existing realm${NC}"
        else
            echo -e "${BLUE}ℹ️  Keeping existing realm${NC}"
            exit 0
        fi
    fi
}

# Function to create realm
create_realm() {
    echo -e "${YELLOW}🏗️  Creating realm '${REALM_NAME}'...${NC}"
    
    # Capitalize first letter of realm name for display
    DISPLAY_NAME="$(echo ${REALM_NAME:0:1} | tr 'a-z' 'A-Z')${REALM_NAME:1} Realm"
    
    REALM_CONFIG=$(cat <<EOF
{
    "realm": "${REALM_NAME}",
    "displayName": "${DISPLAY_NAME}",
    "enabled": true,
    "registrationAllowed": false,
    "loginWithEmailAllowed": true,
    "duplicateEmailsAllowed": false,
    "resetPasswordAllowed": true,
    "editUsernameAllowed": false,
    "bruteForceProtected": true,
    "rememberMe": true,
    "verifyEmail": false,
    "loginTheme": "keycloak",
    "accountTheme": "keycloak",
    "adminTheme": "keycloak",
    "emailTheme": "keycloak"
}
EOF
)

    HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms" \
        -H "Authorization: Bearer ${MASTER_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${REALM_CONFIG}" \
        -o /tmp/realm_response.json)
    
    if [ "$HTTP_STATUS" = "201" ]; then
        echo -e "${GREEN}✅ Created realm '${REALM_NAME}'${NC}"
    else
        echo -e "${RED}❌ Failed to create realm (HTTP ${HTTP_STATUS})${NC}"
        cat /tmp/realm_response.json
        exit 1
    fi
}

# Function to create realm admin user
create_realm_admin() {
    echo -e "${YELLOW}👤 Creating realm admin user '${ADMIN_USERNAME}'...${NC}"
    
    # Capitalize first letter for lastName
    LAST_NAME="$(echo ${REALM_NAME:0:1} | tr 'a-z' 'A-Z')${REALM_NAME:1}"
    
    USER_CONFIG=$(cat <<EOF
{
    "username": "${ADMIN_USERNAME}",
    "enabled": true,
    "emailVerified": true,
    "firstName": "Admin",
    "lastName": "${LAST_NAME}",
    "email": "${ADMIN_USERNAME}@${REALM_NAME}.local",
    "credentials": [
        {
            "type": "password",
            "value": "${ADMIN_PASSWORD}",
            "temporary": false
        }
    ]
}
EOF
)

    HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users" \
        -H "Authorization: Bearer ${MASTER_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${USER_CONFIG}" \
        -o /tmp/user_response.json)
    
    if [ "$HTTP_STATUS" = "201" ]; then
        echo -e "${GREEN}✅ Created user '${ADMIN_USERNAME}'${NC}"
    else
        echo -e "${RED}❌ Failed to create user (HTTP ${HTTP_STATUS})${NC}"
        cat /tmp/user_response.json
        exit 1
    fi
}

# Function to get user ID
get_user_id() {
    echo -e "${YELLOW}🔍 Getting user ID for '${ADMIN_USERNAME}'...${NC}"
    
    USER_ID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users?username=${ADMIN_USERNAME}" \
        -H "Authorization: Bearer ${MASTER_TOKEN}" \
        -H "Content-Type: application/json" | \
        jq -r '.[0].id')
    
    if [ "$USER_ID" = "null" ] || [ -z "$USER_ID" ]; then
        echo -e "${RED}❌ Failed to get user ID${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Got user ID: ${USER_ID}${NC}"
}

# Function to create anticipated realm roles (expected from future LDAP group mappings)
create_anticipated_realm_roles() {
    echo -e "${YELLOW}🏗️  Creating anticipated realm roles (expected from LDAP groups)...${NC}"
    
    # Configure which roles to pre-create in anticipation of LDAP group mappings
    # Add additional roles here if you expect more LDAP groups to map to specific role names
    REALM_ROLES_TO_CREATE=("admins" "developers")
    
    echo -e "${BLUE}💡 These roles are created in anticipation of LDAP groups that will map to them${NC}"
    echo -e "${BLUE}   Future LDAP groups can be mapped to these pre-defined role names${NC}"
    echo -e "${BLUE}   To add more anticipated roles, modify REALM_ROLES_TO_CREATE array above${NC}"
    echo ""
    
    for ROLE in "${REALM_ROLES_TO_CREATE[@]}"; do
        echo -e "${YELLOW}   Creating anticipated role: ${ROLE} (expected from LDAP group mapping)${NC}"
        
        ROLE_CONFIG=$(cat <<EOF
{
    "name": "${ROLE}",
    "description": "Pre-created role anticipating LDAP group mapping"
}
EOF
)
        
        HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/roles" \
            -H "Authorization: Bearer ${MASTER_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "${ROLE_CONFIG}" \
            -o /tmp/role_create_response.json)
        
        if [ "$HTTP_STATUS" = "201" ]; then
            echo -e "${GREEN}   ✅ Created anticipated role: ${ROLE}${NC}"
        elif [ "$HTTP_STATUS" = "409" ]; then
            echo -e "${YELLOW}   ⚠️  Role ${ROLE} already exists${NC}"
        else
            echo -e "${RED}   ❌ Failed to create role ${ROLE} (HTTP $HTTP_STATUS)${NC}"
            cat /tmp/role_create_response.json
        fi
    done
    
    echo -e "${CYAN}📝 Note: Additional roles will be auto-created by LDAP mapper for groups not listed above${NC}"
    echo ""
}

# Function to assign realm management roles to admin user
assign_admin_roles() {
    echo -e "${YELLOW}👑 Assigning realm admin roles to '${ADMIN_USERNAME}'...${NC}"
    
    # Get realm-management client ID
    CLIENT_ID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients?clientId=realm-management" \
        -H "Authorization: Bearer ${MASTER_TOKEN}" \
        -H "Content-Type: application/json" | \
        jq -r '.[0].id')
    
    if [ "$CLIENT_ID" = "null" ] || [ -z "$CLIENT_ID" ]; then
        echo -e "${RED}❌ Failed to get realm-management client ID${NC}"
        exit 1
    fi
    
    # Get available realm roles
    AVAILABLE_ROLES=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients/${CLIENT_ID}/roles" \
        -H "Authorization: Bearer ${MASTER_TOKEN}" \
        -H "Content-Type: application/json" | \
        jq '[.[] | select(.name | test("^(realm-admin|manage-users|manage-clients|manage-realm|view-users|view-clients|view-realm)$"))]')
    
    # Assign roles to user
    curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users/${USER_ID}/role-mappings/clients/${CLIENT_ID}" \
        -H "Authorization: Bearer ${MASTER_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${AVAILABLE_ROLES}" > /dev/null
    
    echo -e "${GREEN}✅ Assigned realm admin roles${NC}"
}

# Function to test realm admin login
test_realm_admin_login() {
    echo -e "${YELLOW}🧪 Testing realm admin login...${NC}"
    
    TEST_TOKEN_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${ADMIN_USERNAME}" \
        -d "password=${ADMIN_PASSWORD}" \
        -d "grant_type=password" \
        -d "client_id=admin-cli")
    
    TEST_TOKEN=$(echo "$TEST_TOKEN_RESPONSE" | jq -r '.access_token')
    
    if [ "$TEST_TOKEN" = "null" ] || [ -z "$TEST_TOKEN" ]; then
        echo -e "${RED}❌ Realm admin login test failed${NC}"
        echo -e "${RED}Response: $TEST_TOKEN_RESPONSE${NC}"
    else
        echo -e "${GREEN}✅ Realm admin login successful${NC}"
    fi
}

# Main execution
echo -e "${GREEN}🚀 Starting realm creation process...${NC}"

wait_for_keycloak
get_master_admin_token
check_realm_exists
create_realm
create_realm_admin
get_user_id
create_anticipated_realm_roles
assign_admin_roles
test_realm_admin_login

echo -e "${GREEN}🎉 Realm creation completed successfully!${NC}"

echo -e "${YELLOW}📋 Configuration Summary:${NC}"
echo -e "   • Realm Name      : ${GREEN}${REALM_NAME}${NC}"
echo -e "   • Admin Username  : ${GREEN}${ADMIN_USERNAME}${NC}"
echo -e "   • Admin Password  : ${GREEN}${ADMIN_PASSWORD}${NC}"
echo -e "   • Admin Email     : ${GREEN}${ADMIN_USERNAME}@${REALM_NAME}.local${NC}"
echo ""
echo -e "${GREEN}🌐 Access URLs:${NC}"
echo -e "   • Realm URL       : ${BLUE}${KEYCLOAK_URL}/realms/${REALM_NAME}${NC}"
echo -e "   • Admin Console   : ${BLUE}${KEYCLOAK_URL}/admin/${REALM_NAME}/console/${NC}"
echo -e "   • Account Console : ${BLUE}${KEYCLOAK_URL}/realms/${REALM_NAME}/account/${NC}"
echo ""
echo -e "${BLUE}💡 You can now use this realm for further configuration!${NC}"
