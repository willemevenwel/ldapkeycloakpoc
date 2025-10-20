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
USE_DEFAULTS=false
REALM_NAME=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --check-steps)
            CHECK_STEPS=true
            shift
            ;;
        --defaults)
            USE_DEFAULTS=true
            shift
            ;;
        --help|-h)
            echo -e "${GREEN}LDAP-Keycloak POC Setup Script${NC}"
            echo -e "${YELLOW}Usage: $0 [realm-name] [options]${NC}"
            echo ""
            echo -e "${CYAN}Options:${NC}"
            echo -e "  --defaults         Use default values for all prompts (fully automated)"
            echo -e "  --check-steps      Interactive mode with step-by-step confirmations"
            echo -e "                     Note: --check-steps overrides --defaults"
            echo -e "  --help, -h         Show this help message"
            echo ""
            echo -e "${CYAN}Examples:${NC}"
            echo -e "  $0 myrealm                         # Create 'myrealm' with prompts"
            echo -e "  $0 myrealm --defaults              # Create 'myrealm' with all defaults"
            echo -e "  $0 --defaults                      # Use default realm name and all defaults"
            echo -e "  $0 myrealm --check-steps           # Interactive mode with confirmations"
            echo -e "  $0 --defaults --check-steps        # Interactive mode (check-steps wins)"
            echo ""
            echo -e "${CYAN}Default Values (when using --defaults):${NC}"
            echo -e "  • Realm name: myrealm"
            echo -e "  • Organizations: Yes (acme xyz)"
            echo -e "  • Load additional users: Yes"
            exit 0
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
    if [ "$CHECK_STEPS" = true ]; then
        # Always prompt when in check-steps mode, regardless of defaults
        echo -e "${YELLOW}⚠️  No realm name provided${NC}"
        echo -e "${YELLOW}Please enter the realm name to create:${NC}"
        read -p "Realm name: " REALM_NAME
        
        if [ -z "$REALM_NAME" ]; then
            echo -e "${RED}❌ No realm name provided. Exiting.${NC}"
            exit 1
        fi
    elif [ "$USE_DEFAULTS" = true ]; then
        REALM_NAME="myrealm"
        echo -e "${CYAN}Using default realm name: ${REALM_NAME}${NC}"
    else
        echo -e "${YELLOW}⚠️  No realm name provided${NC}"
        echo -e "${YELLOW}Please enter the realm name to create:${NC}"
        read -p "Realm name: " REALM_NAME
        
        if [ -z "$REALM_NAME" ]; then
            echo -e "${RED}❌ No realm name provided. Exiting.${NC}"
            exit 1
        fi
    fi
fi

echo -e "${GREEN}🚀 Starting complete LDAP-Keycloak setup for realm: ${MAGENTA}${REALM_NAME}${NC}"
if [ "$CHECK_STEPS" = true ]; then
    echo -e "${CYAN}🔍 Check steps mode enabled - you will be prompted for all confirmations and inputs${NC}"
    if [ "$USE_DEFAULTS" = true ]; then
        echo -e "${YELLOW}   Note: --defaults flag overridden by --check-steps${NC}"
    fi
elif [ "$USE_DEFAULTS" = true ]; then
    echo -e "${CYAN}🎯 Defaults mode enabled - using default values for all prompts${NC}"
fi
echo -e "${YELLOW}📋 This will execute the following steps:${NC}"
echo -e "${YELLOW}   1. Start all services (Docker containers + Mock OAuth2)${NC}"
echo -e "${YELLOW}   1.5. Generate and load initial LDAP data${NC}"
echo -e "${YELLOW}   1.9. Check Keycloak server details and existing realms${NC}"
echo -e "${YELLOW}   2. Create Keycloak realm: ${REALM_NAME}${NC}"
echo -e "${YELLOW}   3. Add LDAP provider${NC}"
echo -e "${YELLOW}   4. Create role mapper for LDAP groups${NC}"
echo -e "${YELLOW}   5. Sync users and roles from LDAP${NC}"
echo -e "${YELLOW}   6. Setup organizations with domain format: org.realm.local${NC}"
echo -e "${YELLOW}   7. Configure shared clients with organization role filtering${NC}"
echo -e "${YELLOW}   8. Configure Mock OAuth2 as Identity Provider for org testing${NC}"

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

# Cross-platform robust service readiness check
echo -e "${CYAN}Checking service readiness...${NC}"
sleep 5

# Check if containers are actually running
containers_running=0
expected_containers=("ldap" "keycloak" "python-bastion")
for container in "${expected_containers[@]}"; do
    if docker ps --format "table {{.Names}}" | grep -q "^${container}$"; then
        echo -e "${GREEN}✓${NC} ${container} container is running"
        containers_running=$((containers_running + 1))
    else
        echo -e "${RED}✗${NC} ${container} container is not running"
        echo -e "${YELLOW}  Checking container status...${NC}"
        docker ps -a --filter "name=${container}" --format "table {{.Names}}\t{{.Status}}"
    fi
done

if [ $containers_running -ne ${#expected_containers[@]} ]; then
    echo -e "${RED}❌ Not all containers are running. Please check 'docker ps'${NC}"
    echo -e "${YELLOW}Expected: ${expected_containers[*]}${NC}"
    exit 1
fi

# Enhanced startup time for cross-platform compatibility
echo -e "${YELLOW}⏳ Allowing startup time for services to initialize...${NC}"
echo -e "${CYAN}This ensures compatibility across macOS, Windows, and slower systems${NC}"

# Progressive wait with service checks
for i in {1..6}; do
    echo -e "${CYAN}Startup check $i/6...${NC}"
    sleep 5
    
    # Check if LDAP is responding (basic connectivity test)
    if docker exec ldap ldapsearch -x -H ldap://localhost:389 -b "" -s base >/dev/null 2>&1; then
        echo -e "${GREEN}✓ LDAP service is responding${NC}"
        break
    else
        echo -e "${YELLOW}⏳ LDAP service still initializing...${NC}"
        if [ $i -eq 6 ]; then
            echo -e "${RED}❌ LDAP service failed to initialize within expected time${NC}"
            echo -e "${YELLOW}Container logs:${NC}"
            docker logs ldap --tail 10
            exit 1
        fi
    fi
done

# Step 1.5: Generate LDIF files and load initial data
confirm_step "About to generate LDIF files from CSV data and load them into LDAP"
echo -e "${GREEN}🔄 Step 1.5: Generating LDIF files and loading initial data...${NC}"
echo -e "${CYAN}📝 Generating LDIF from CSV files using containerized Python...${NC}"

# Generate LDIF files
if docker exec python-bastion python python/csv_to_ldif.py data/admins.csv; then
    echo -e "${GREEN}✓ LDIF generation completed${NC}"
else
    echo -e "${RED}❌ LDIF generation failed${NC}"
    exit 1
fi

# Validate that LDIF files were created with content
echo -e "${CYAN}🔍 Validating generated LDIF files...${NC}"
if [ -f ldif/admins_only.ldif ]; then
    admin_entries=$(grep -c "^dn: uid=" ldif/admins_only.ldif || echo 0)
    group_entries=$(grep -c "^dn: cn=" ldif/admins_only.ldif || echo 0)
    echo -e "${GREEN}✓ admins_only.ldif exists with $admin_entries users and $group_entries groups${NC}"
    
    if [ $admin_entries -eq 0 ]; then
        echo -e "${RED}❌ No admin users found in LDIF file${NC}"
        echo -e "${YELLOW}Checking admins.csv content:${NC}"
        cat data/admins.csv
        exit 1
    fi
else
    echo -e "${RED}❌ admins_only.ldif file not found${NC}"
    echo -e "${YELLOW}Available files in ldif/:${NC}"
    ls -la ldif/ || echo "ldif/ directory not found"
    exit 1
fi

echo -e "${CYAN}📥 Loading admin users into LDAP...${NC}"
./ldap/setup_ldap_data.sh
check_success
echo -e "${GREEN}✅ Initial LDAP data loaded and validated successfully${NC}"
echo ""

# Step 1.9: Get Keycloak details for debugging
confirm_step "About to check Keycloak server details and existing realms"
echo -e "${GREEN}🔄 Step 1.9: Getting Keycloak server details...${NC}"
cd keycloak
./keycloak_details.sh
check_success
cd "$START_DIR"
echo -e "${GREEN}✅ Keycloak details retrieved successfully${NC}"
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

# Return to the original directory before organization setup
cd "$START_DIR"

# NEW: Organization Setup Section
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🏢 Organization Setup (NEW FEATURE)${NC}"
echo -e "${YELLOW}   This will configure organizations with role prefixes like: acme_admin, xyz_developer${NC}"
echo -e "${YELLOW}   Organizations enable role filtering by prefix in shared clients${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ "$CHECK_STEPS" = true ]; then
    # Always prompt when in check-steps mode, regardless of defaults
    echo -en "${CYAN}Do you want to set up organizations? (Y/n - default is Yes): ${NC}"
    read -r setup_organizations
elif [ "$USE_DEFAULTS" = true ]; then
    setup_organizations="y"
    echo -e "${CYAN}Do you want to set up organizations? (Y/n - default is Yes): ${YELLOW}[using default: Yes]${NC}"
else
    echo -en "${CYAN}Do you want to set up organizations? (Y/n - default is Yes): ${NC}"
    read -r setup_organizations
fi

# Default to Yes if no input or if user presses enter
if [ -z "${setup_organizations}" ] || [ "${setup_organizations}" = "Y" ] || [ "${setup_organizations}" = "y" ]; then
    echo ""
    echo -e "${YELLOW}🏢 Setting up organizations...${NC}"
    echo -e "${BLUE}💡 Enter organization prefixes (e.g., acme xyz abc)${NC}"
    echo -e "${BLUE}   These will be used for role prefixes like: acme_admin, xyz_developer${NC}"
    echo -e "${BLUE}   Default organizations: acme xyz${NC}"
    if [ "$CHECK_STEPS" = true ]; then
        # Always prompt when in check-steps mode, regardless of defaults
        echo -en "${CYAN}Enter organization prefixes (space-separated, or press Enter for defaults): ${NC}"
        read -r org_prefixes
    elif [ "$USE_DEFAULTS" = true ]; then
        org_prefixes="acme xyz"
        echo -e "${CYAN}Enter organization prefixes (space-separated, or press Enter for defaults): ${YELLOW}[using defaults: acme xyz]${NC}"
    else
        echo -en "${CYAN}Enter organization prefixes (space-separated, or press Enter for defaults): ${NC}"
        read -r org_prefixes
    fi
    
    # Use defaults if no input provided
    if [ -z "$org_prefixes" ]; then
        org_prefixes="acme xyz"
        echo -e "${YELLOW}Using default organizations: ${org_prefixes}${NC}"
    else
        echo -e "${GREEN}Using organizations: ${org_prefixes}${NC}"
    fi
    
    # Step 6: Setup Organizations
    echo ""
    confirm_step "About to setup organizations: ${org_prefixes}"
    echo -e "${GREEN}🔄 Step 6: Setting up organizations...${NC}"
    cd keycloak
    ./setup_organizations.sh "${REALM_NAME}" ${org_prefixes}
    check_success
    echo -e "${GREEN}✅ Organizations setup completed successfully${NC}"
    
    # Step 7: Configure Shared Clients
    echo ""
    confirm_step "About to configure shared clients with organization-aware role filtering"
    echo -e "${GREEN}🔄 Step 7: Configuring shared clients...${NC}"
    ./configure_shared_clients.sh "${REALM_NAME}" ${org_prefixes}
    check_success
    echo -e "${GREEN}✅ Shared clients configured successfully${NC}"
    
    # Step 8: Configure Mock OAuth2 as Identity Provider
    echo ""
    confirm_step "About to configure Mock OAuth2 Server as Identity Provider for organization testing"
    echo -e "${GREEN}🔄 Step 8: Configuring Mock OAuth2 Identity Provider...${NC}"
    ./configure_mock_oauth2_idp.sh "${REALM_NAME}" ${org_prefixes}
    check_success
    echo -e "${GREEN}✅ Mock OAuth2 Identity Provider configured successfully${NC}"
    
    # Return to start directory
    cd "$START_DIR"
    
    echo ""
    echo -e "${GREEN}🎉 Organization setup completed!${NC}"
    echo -e "${YELLOW}📋 Organization Summary:${NC}"
    echo -e "${YELLOW}   • Organizations created: ${org_prefixes}${NC}"
    echo -e "${YELLOW}   • Domain format: {org}.${REALM_NAME}.local${NC}"
    echo -e "${YELLOW}   • Shared clients: shared-web-client, shared-api-client${NC}"
    echo -e "${YELLOW}   • Role filtering: JWT tokens contain org-specific claims${NC}"
    echo -e "${YELLOW}   • LDAP groups matching org prefixes will sync automatically${NC}"
    echo -e "${YELLOW}   • Mock OAuth2 Identity Provider: Configured for org testing${NC}"
    echo ""
    ORGANIZATIONS_CONFIGURED=true
else
    echo -e "${YELLOW}Skipped organization setup. You can run it manually later with:${NC}"
    echo -e "${YELLOW}   cd keycloak && ./setup_organizations.sh ${REALM_NAME} acme xyz${NC}"
    echo -e "${YELLOW}   cd keycloak && ./configure_shared_clients.sh ${REALM_NAME} acme xyz${NC}"
    echo ""
    ORGANIZATIONS_CONFIGURED=false
fi

# Final summary
echo -e "${GREEN}🎉 Complete setup finished successfully!${NC}"
echo ""
echo -e "${YELLOW}📋 Setup Summary for realm '${REALM_NAME}':${NC}"
echo -e "${YELLOW}   • All Docker services are running (including Mock OAuth2)${NC}"
echo -e "${YELLOW}   • LDAP server populated with users and groups${NC}"
echo -e "${YELLOW}   • Keycloak realm '${REALM_NAME}' created${NC}"
echo -e "${YELLOW}   • LDAP provider 'ldap-provider-${REALM_NAME}' configured${NC}"
echo -e "${YELLOW}   • Role mapper 'role-mapper-${REALM_NAME}' configured${NC}"
echo -e "${YELLOW}   • Users and roles synced from LDAP to Keycloak${NC}"
if [ "$ORGANIZATIONS_CONFIGURED" = true ]; then
    echo -e "${YELLOW}   • Organizations configured: ${org_prefixes} (domains: {org}.${REALM_NAME}.local)${NC}"
    echo -e "${YELLOW}   • Shared clients with role filtering configured${NC}"
    echo -e "${YELLOW}   • Mock OAuth2 Identity Provider configured for multi-provider testing${NC}"
fi
echo ""
echo -e "${GREEN}🌐 Access your setup:${NC}"
echo -e "${GREEN}   • ${YELLOW}🚀 POC Dashboard${NC}     : ${BLUE}http://localhost:8888${NC}"
echo -e "${GREEN}     └─ ${WHITE}Complete overview with all service links & credentials${NC}"
echo -e "${GREEN}   • Keycloak Admin     : ${BLUE}http://localhost:8090/admin/${REALM_NAME}/console/${NC}"
echo -e "${GREEN}   • Realm URL          : ${BLUE}http://localhost:8090/realms/${REALM_NAME}${NC}"
if [ "$ORGANIZATIONS_CONFIGURED" = true ]; then
    echo -e "${GREEN}   • Organizations      : ${BLUE}http://localhost:8090/admin/${REALM_NAME}/console/#/${REALM_NAME}/organizations${NC}"
    echo -e "${GREEN}   • Clients            : ${BLUE}http://localhost:8090/admin/${REALM_NAME}/console/#/${REALM_NAME}/clients${NC}"
fi
echo -e "${GREEN}   • ${CYAN}LDAP${NC} Web Manager   : ${BLUE}http://localhost:8080${NC}"
echo -e "${GREEN}   • ${YELLOW}Weave Scope${NC}       : ${BLUE}http://localhost:4040${NC}"
echo -e "${GREEN}     └─ Real-time network topology and container visualization${NC}"
echo -e "${GREEN}   • ${WHITE}Mock OAuth2${NC}       : ${BLUE}http://localhost:8081${NC}"
echo -e "${GREEN}     └─ OAuth2/OIDC testing server for integration development${NC}"
echo ""
echo -e "${GREEN}🔑 Admin credentials:${NC}"
echo -e "${GREEN}   • Keycloak Realm Admin: admin-${REALM_NAME} / admin-${REALM_NAME}${NC}"
echo -e "${GREEN}   • Keycloak Master Admin: admin / admin${NC}"
echo -e "${GREEN}   • ${CYAN}LDAP${NC} Server (protocol): cn=admin,dc=min,dc=io / admin${NC}"
echo -e "${GREEN}   • ${CYAN}LDAP${NC} Web Manager (web UI): admin / admin${NC}"
echo ""
if [ "$ORGANIZATIONS_CONFIGURED" = true ]; then
    echo -e "${YELLOW}💡 Expected roles created: admin, developer, ds_member, user${NC}"
    echo -e "${YELLOW}💡 Organization roles created: $(echo ${org_prefixes} | sed 's/\([^ ]*\)/\1_admin, \1_developer, \1_user, \1_manager, \1_specialist/g' | sed 's/, *$//')${NC}"
    echo -e "${YELLOW}💡 Role pattern: {org_prefix}_{role_name} (e.g., abc_admin, xyz_developer)${NC}"
else
    echo -e "${YELLOW}💡 Expected roles created: admin, developer, ds_member, user${NC}"
fi

echo -e "${YELLOW}💡 Expected users synced: admin, alice, bob, charlie, willem, jp, louis, razvan, jack, andre, anwar${NC}"
echo ""
echo -e "${CYAN}🔄 To sync again later, run: ${WHITE}cd keycloak && ./sync_ldap.sh ${REALM_NAME}${NC}"
echo ""
echo -e "${YELLOW}📖 Usage examples:${NC}"
echo -e "${YELLOW}   ./start_all.sh my-realm${NC}                    # Full automated setup"
echo -e "${YELLOW}   ./start_all.sh my-realm --defaults${NC}         # Fully automated with all defaults"
echo -e "${YELLOW}   ./start_all.sh my-realm --check-steps${NC}      # Interactive mode with confirmations"
echo -e "${YELLOW}   ./start_all.sh --defaults${NC}                  # Use defaults for realm name and all prompts"
echo -e "${YELLOW}   ./start_all.sh --check-steps${NC}               # Interactive mode, will prompt for realm name"
echo ""
if [ "$ORGANIZATIONS_CONFIGURED" = true ]; then
    echo -e "${CYAN}🏢 Organization Features Available:${NC}"
    echo -e "${CYAN}   • JWT tokens contain organization-specific role claims${NC}"
    echo -e "${CYAN}   • Shared clients: shared-web-client, shared-api-client${NC}"
    echo -e "${CYAN}   • Role filtering by organization prefix in JWT tokens${NC}"
    echo -e "${CYAN}   • Organization domains: {org}.${REALM_NAME}.local format${NC}"
    echo -e "${CYAN}   • Mock OAuth2 Identity Provider for multi-provider testing${NC}"
    echo -e "${CYAN}   • Organization-specific OAuth2 clients configured${NC}"
    echo -e "${CYAN}   • View organization setup guide: ./keycloak/organization_setup_guide.sh${NC}"
    echo ""
fi

# --- Optional: Load additional users ---
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}💡 Optional: Load additional users and group assignments into LDAP${NC}"
echo -e "${YELLOW}   This will import additional data from users.ldif and group_assign.ldif${NC}"
echo -e "${YELLOW}   Run this if you want to add more test users beyond the basic setup${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ "$CHECK_STEPS" = true ]; then
    # Always prompt when in check-steps mode, regardless of defaults
    echo -en "${CYAN}Do you want to load additional users now? (y/N - default is No): ${NC}"
    read -r run_additional
elif [ "$USE_DEFAULTS" = true ]; then
    run_additional="y"
    echo -e "${CYAN}Do you want to load additional users now? (y/N - default is No): ${YELLOW}[using default: Yes]${NC}"
else
    echo -en "${CYAN}Do you want to load additional users now? (y/N - default is No): ${NC}"
    read -r run_additional
fi
if [ "${run_additional}" = "Y" ] || [ "${run_additional}" = "y" ]; then
    if [ "$USE_DEFAULTS" = true ]; then
        "$START_DIR"/ldap/load_additional_users.sh "${REALM_NAME}" --defaults
    else
        "$START_DIR"/ldap/load_additional_users.sh "${REALM_NAME}"
    fi
    echo ""
    echo -e "${GREEN}✅ Additional users loaded. You may want to re-sync LDAP:${NC}"
    echo -e "${GREEN}   cd keycloak && ./sync_ldap.sh ${REALM_NAME}${NC}"
else
    echo -e "${YELLOW}Skipped additional users import. You can run it manually later with:${NC}"
    echo -e "${YELLOW}   ./ldap/load_additional_users.sh${NC}"
    echo -e "${YELLOW}   Then re-sync with: cd keycloak && ./sync_ldap.sh ${REALM_NAME}${NC}"
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🎉 SETUP COMPLETE! Your LDAP-Keycloak POC is ready!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${WHITE}🚀 ${GREEN}START HERE:${NC} ${BLUE}http://localhost:8888${NC}"
echo -e "${YELLOW}   └─ Complete dashboard with all services, links, and credentials${NC}"
echo ""
echo -e "${CYAN}💡 The dashboard provides centralized access to:${NC}"
echo -e "${CYAN}   • Keycloak Admin Console (realm: ${REALM_NAME})${NC}"
echo -e "${CYAN}   • LDAP Web Manager${NC}"
echo -e "${CYAN}   • Weave Scope Network Visualization${NC}"
echo -e "${CYAN}   • All login credentials with security warnings${NC}"
echo ""
echo -e "${GREEN}Happy testing with your LDAP-Keycloak integration! 🔐✨${NC}"

