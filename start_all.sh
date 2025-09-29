#!/bin/bash


# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Save the starting directory
START_DIR="$(pwd)"

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
echo -e "${YELLOW}   2. Create Keycloak realm: ${REALM_NAME}${NC}"
echo -e "${YELLOW}   3. Add LDAP provider${NC}"
echo -e "${YELLOW}   4. Create role mapper for LDAP groups${NC}"
echo -e "${YELLOW}   5. Sync users and roles from LDAP${NC}"

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

# More robust wait for Windows/slower systems
echo -e "${CYAN}Checking service readiness...${NC}"
sleep 5

# Check if containers are actually running
containers_running=0
for container in "ldap" "keycloak" "python-bastion"; do
    if docker ps --format "table {{.Names}}" | grep -q "^${container}$"; then
        echo -e "${GREEN}✓${NC} ${container} container is running"
        containers_running=$((containers_running + 1))
    else
        echo -e "${RED}✗${NC} ${container} container is not running"
    fi
done

if [ $containers_running -ne 3 ]; then
    echo -e "${RED}❌ Not all containers are running. Please check 'docker ps'${NC}"
    exit 1
fi

echo -e "${YELLOW}⏳ Allowing additional startup time for Windows/slower systems...${NC}"
sleep 15

# Step 1.5: Generate LDIF files and load initial data
confirm_step "About to generate LDIF files from CSV data and load them into LDAP"
echo -e "${GREEN}🔄 Step 1.5: Generating LDIF files and loading initial data...${NC}"
echo -e "${CYAN}📝 Generating LDIF from CSV files using containerized Python...${NC}"
docker exec python-bastion python python/csv_to_ldif.py data/admins.csv
check_success
echo -e "${CYAN}📥 Loading admin users into LDAP...${NC}"
./ldap/setup_ldap_data.sh
check_success
echo -e "${GREEN}✅ Initial LDAP data loaded successfully${NC}"
echo ""

# Step 2: Create Keycloak realm
confirm_step "About to create Keycloak realm '${REALM_NAME}' with admin user and anticipated roles"
echo -e "${GREEN}🔄 Step 2: Creating Keycloak realm '${REALM_NAME}'...${NC}"
cd keycloak
./create_realm.sh "${REALM_NAME}"
check_success
echo -e "${GREEN}✅ Realm '${REALM_NAME}' created successfully${NC}"
echo ""

# Step 3: Add LDAP provider
confirm_step "About to create LDAP provider 'ldap-provider-${REALM_NAME}'"
echo -e "${GREEN}🔄 Step 3: Adding LDAP provider...${NC}"
./add_ldap_provider_for_keycloak.sh "${REALM_NAME}"
check_success
echo -e "${GREEN}✅ LDAP provider added successfully${NC}"
echo ""

# Step 4: Create role mapper
confirm_step "About to create role mapper 'role-mapper-${REALM_NAME}' for LDAP groups"
echo -e "${GREEN}🔄 Step 4: Creating role mapper for LDAP groups...${NC}"
./update_role_mapper.sh "${REALM_NAME}"
check_success
echo -e "${GREEN}✅ Role mapper created successfully${NC}"
echo ""

# Step 5: Sync users and roles from LDAP
confirm_step "About to sync all users and roles from LDAP to Keycloak"
echo -e "${GREEN}🔄 Step 5: Syncing users and roles from LDAP...${NC}"
./sync_ldap.sh "${REALM_NAME}"
check_success
echo -e "${GREEN}✅ Users and roles synced successfully${NC}"
echo ""

# Return to the original directory before final prompt
cd "$START_DIR"

# Final summary
echo -e "${GREEN}🎉 Complete setup finished successfully!${NC}"
echo ""
echo -e "${YELLOW}📋 Setup Summary for realm '${REALM_NAME}':${NC}"
echo -e "${YELLOW}   • All Docker services are running${NC}"
echo -e "${YELLOW}   • LDAP server populated with users and groups${NC}"
echo -e "${YELLOW}   • Keycloak realm '${REALM_NAME}' created${NC}"
echo -e "${YELLOW}   • LDAP provider 'ldap-provider-${REALM_NAME}' configured${NC}"
echo -e "${YELLOW}   • Role mapper 'role-mapper-${REALM_NAME}' configured${NC}"
echo -e "${YELLOW}   • Users and roles synced from LDAP to Keycloak${NC}"
echo ""
echo -e "${GREEN}🌐 Access your setup:${NC}"
echo -e "${GREEN}   • Keycloak Admin     : ${BLUE}http://localhost:8090/admin/${REALM_NAME}/console/${NC}"
echo -e "${GREEN}   • Realm URL          : ${BLUE}http://localhost:8090/realms/${REALM_NAME}${NC}"
echo -e "${GREEN}   • ${CYAN}LDAP${NC} Web Manager   : ${BLUE}http://localhost:8091${NC}"
echo ""
echo -e "${GREEN}🔑 Admin credentials:${NC}"
echo -e "${GREEN}   • Keycloak Realm Admin: admin-${REALM_NAME} / admin-${REALM_NAME}${NC}"
echo -e "${GREEN}   • Keycloak Master Admin: admin / admin${NC}"
echo -e "${GREEN}   • ${CYAN}LDAP${NC} Server (protocol): cn=admin,dc=mycompany,dc=local / admin${NC}"
echo -e "${GREEN}   • ${CYAN}LDAP${NC} Web Manager (web UI): admin / admin${NC}"
echo ""
echo -e "${YELLOW}💡 Expected roles created: admin, developer, ds_member, user${NC}"

echo -e "${YELLOW}💡 Expected users synced: admin, alice, bob, charlie, willem, jp, louis, razvan, jack, andre, anwar${NC}"
echo ""
echo -e "${CYAN}🔄 To sync again later, run: ${WHITE}cd keycloak && ./sync_ldap.sh ${REALM_NAME}${NC}"
echo ""
echo -e "${YELLOW}📖 Usage examples:${NC}"
echo -e "${YELLOW}   ./start_all.sh my-realm${NC}                    # Full automated setup"
echo -e "${YELLOW}   ./start_all.sh my-realm --check-steps${NC}      # Interactive mode with confirmations"
echo -e "${YELLOW}   ./start_all.sh --check-steps${NC}               # Interactive mode, will prompt for realm name"

# --- Optional: Load additional users ---
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}💡 Optional: Load additional users and group assignments into LDAP${NC}"
echo -e "${YELLOW}   This will import additional data from users.ldif and group_assign.ldif${NC}"
echo -e "${YELLOW}   Run this if you want to add more test users beyond the basic setup${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -en "${CYAN}Do you want to load additional users now? (y/N - default is No): ${NC}"
read -r run_additional
if [ "${run_additional}" = "Y" ] || [ "${run_additional}" = "y" ]; then
    "$START_DIR"/ldap/load_additional_users.sh "${REALM_NAME}"
    echo ""
    echo -e "${GREEN}✅ Additional users loaded. You may want to re-sync LDAP:${NC}"
    echo -e "${GREEN}   cd keycloak && ./sync_ldap.sh ${REALM_NAME}${NC}"
else
    echo -e "${YELLOW}Skipped additional users import. You can run it manually later with:${NC}"
    echo -e "${YELLOW}   ./ldap/load_additional_users.sh${NC}"
    echo -e "${YELLOW}   Then re-sync with: cd keycloak && ./sync_ldap.sh ${REALM_NAME}${NC}"
fi

