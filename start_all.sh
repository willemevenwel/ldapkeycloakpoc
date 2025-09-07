#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if realm name parameter is provided
CHECK_STEPS=false
REALM_NAME=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --check-steps)
            CHECK_STEPS=true
            shift
            ;;
        *)
            if [ -z "$REALM_NAME" ]; then
                REALM_NAME="$1"
            fi
            shift
            ;;
    esac
done

if [ -z "$REALM_NAME" ]; then
    echo -e "${YELLOW}⚠️  No realm name provided${NC}"
    echo -e "${YELLOW}Please enter the realm name to create:${NC}"
    read -p "Realm name: " REALM_NAME
    
    if [ -z "$REALM_NAME" ]; then
        echo -e "${RED}❌ No realm name provided. Exiting.${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}🚀 Starting complete LDAP-Keycloak setup for realm: ${MAGENTA}${REALM_NAME}${NC}"
if [ "$CHECK_STEPS" = true ]; then
    echo -e "${CYAN}🔍 Check steps mode enabled - you will be prompted before each step${NC}"
fi
echo -e "${YELLOW}📋 This will execute the following steps:${NC}"
echo -e "${YELLOW}   1. Start all services (Docker containers)${NC}"
echo -e "${YELLOW}   2. Load additional users into LDAP${NC}"
echo -e "${YELLOW}   3. Create Keycloak realm: ${REALM_NAME}${NC}"
echo -e "${YELLOW}   4. Add LDAP provider with group mapping${NC}"
echo -e "${YELLOW}   5. Sync users and groups from LDAP${NC}"
echo ""

# Function to check if previous command succeeded
check_success() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Previous step failed. Stopping execution.${NC}"
        exit 1
    fi
}

# Function to prompt user for confirmation
confirm_step() {
    if [ "$CHECK_STEPS" = true ]; then
        echo -e "${CYAN}❓ $1${NC}"
        echo -e "${CYAN}Continue? (Y/n):${NC}"
        read -r response
        case "$response" in
            [nN][oO]|[nN])
                echo -e "${YELLOW}⏸️  Step skipped by user. Exiting.${NC}"
                exit 0
                ;;
            *)
                echo -e "${GREEN}✅ Proceeding...${NC}"
                ;;
        esac
        echo ""
    fi
}

# Step 1: Start all services
confirm_step "About to start all Docker services (Keycloak, LDAP, LDAP-User-Manager)"
echo -e "${GREEN}🔄 Step 1: Starting all services...${NC}"
./start.sh
check_success
echo -e "${GREEN}✅ Services started successfully${NC}"
echo -e "${YELLOW}⏳ Waiting for services to fully initialize...${NC}"
sleep 5
echo ""

# Step 2: Load additional users
confirm_step "About to load additional users and groups into LDAP from CSV files"
echo -e "${GREEN}🔄 Step 2: Loading additional users into LDAP...${NC}"
./load_additional_users.sh
check_success
echo -e "${GREEN}✅ Additional users loaded successfully${NC}"
echo ""

# Step 3: Create Keycloak realm
confirm_step "About to create Keycloak realm '${REALM_NAME}' with admin user"
echo -e "${GREEN}🔄 Step 3: Creating Keycloak realm '${REALM_NAME}'...${NC}"
cd keycloak
./create_realm.sh "${REALM_NAME}"
check_success
echo -e "${GREEN}✅ Realm '${REALM_NAME}' created successfully${NC}"
echo ""

# Step 4: Add LDAP provider with group mapping
confirm_step "About to create LDAP provider 'ldap-provider-${REALM_NAME}' and group mapper"
echo -e "${GREEN}🔄 Step 4: Adding LDAP provider with group mapping...${NC}"
./add_ldap_provider_for_keycloak.sh "${REALM_NAME}"
check_success
echo -e "${GREEN}✅ LDAP provider and group mapping added successfully${NC}"
echo ""

# Step 5: Sync users and groups from LDAP
confirm_step "About to sync all users and groups from LDAP to Keycloak"
echo -e "${GREEN}🔄 Step 5: Syncing users and groups from LDAP...${NC}"
./sync_ldap.sh "${REALM_NAME}"
check_success
echo -e "${GREEN}✅ Users and groups synced successfully${NC}"
echo ""

# Final summary
echo -e "${GREEN}🎉 Complete setup finished successfully!${NC}"
echo ""
echo -e "${YELLOW}📋 Setup Summary for realm '${REALM_NAME}':${NC}"
echo -e "${YELLOW}   • All Docker services are running${NC}"
echo -e "${YELLOW}   • LDAP server populated with users and groups${NC}"
echo -e "${YELLOW}   • Keycloak realm '${REALM_NAME}' created${NC}"
echo -e "${YELLOW}   • LDAP provider 'ldap-provider-${REALM_NAME}' configured${NC}"
echo -e "${YELLOW}   • Group mapper 'group-mapper-${REALM_NAME}' configured${NC}"
echo -e "${YELLOW}   • Users and groups synced from LDAP to Keycloak${NC}"
echo ""
echo -e "${GREEN}🌐 Access your setup:${NC}"
echo -e "${GREEN}   • Keycloak Admin: ${BLUE}http://localhost:8090/admin/${REALM_NAME}/console/${NC}"
echo -e "${GREEN}   • Realm URL: ${BLUE}http://localhost:8090/realms/${REALM_NAME}${NC}"
echo -e "${GREEN}   • LDAP Manager: ${BLUE}http://localhost:8091${NC}"
echo ""
echo -e "${GREEN}🔑 Admin credentials:${NC}"
echo -e "${GREEN}   • Keycloak Realm Admin: admin-${REALM_NAME} / admin-${REALM_NAME}${NC}"
echo -e "${GREEN}   • Keycloak Master Admin: admin / admin${NC}"
echo -e "${GREEN}   • LDAP Manager: cn=admin,dc=mycompany,dc=local / admin${NC}"
echo ""
echo -e "${YELLOW}💡 Expected groups synced: admins, developers, ds1, ds2, ds3, user${NC}"
echo -e "${YELLOW}💡 Expected users synced: admin, alice, bob, charlie, willem, jp, louis, razvan, jack, andre, anwar${NC}"
echo ""
echo -e "${CYAN}🔄 To sync again later, run: ${WHITE}cd keycloak && ./sync_ldap.sh ${REALM_NAME}${NC}"
echo ""
echo -e "${YELLOW}📖 Usage examples:${NC}"
echo -e "${YELLOW}   ./start_all.sh my-realm${NC}                    # Full automated setup"
echo -e "${YELLOW}   ./start_all.sh my-realm --check-steps${NC}      # Interactive mode with confirmations"
echo -e "${YELLOW}   ./start_all.sh --check-steps${NC}               # Interactive mode, will prompt for realm name"
