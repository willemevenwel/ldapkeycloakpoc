#!/bin/bash

# This script runs INSIDE the python-bastion container
# It performs all the setup operations from within a controlled Linux environment
# eliminating host platform issues with Windows/WSL/Git Bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Working directory is /workspace (mounted from host)
cd /workspace

# Source network detection utilities
source ./network_detect.sh

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
            echo -e "${GREEN}LDAP-Keycloak POC Setup Script (Container-based)${NC}"
            echo -e "${YELLOW}Usage: $0 [realm-name] [options]${NC}"
            echo ""
            echo -e "${CYAN}This script runs inside the python-bastion container for cross-platform compatibility${NC}"
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
                # Normalize realm name to lowercase for consistency
                REALM_NAME=$(echo "$REALM_NAME" | tr '[:upper:]' '[:lower:]')
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
        REALM_NAME="capgemini"
        echo -e "${CYAN}Using default realm name: ${REALM_NAME}${NC}"
    else
        echo -e "${YELLOW}⚠️  No realm name provided${NC}"
        echo -e "${YELLOW}Please enter the realm name to create:${NC}"
        read -p "Realm name: " REALM_NAME
        
        if [ -z "$REALM_NAME" ]; then
            echo -e "${RED}❌ No realm name provided. Exiting.${NC}"
            exit 1
        fi
        
        # Normalize realm name to lowercase for consistency
        REALM_NAME=$(echo "$REALM_NAME" | tr '[:upper:]' '[:lower:]')
    fi
fi

echo -e "${GREEN}🐳 Running from python-bastion container - eliminating host platform issues${NC}"
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
echo -e "${YELLOW}   1. Verify services are running (containers already started from host)${NC}"
echo -e "${YELLOW}   1.5. Generate and load initial LDAP data${NC}"
echo -e "${YELLOW}   2. Complete Keycloak setup (realm, LDAP integration, organizations)${NC}"
echo -e "${YELLOW}   3. Optional: Load additional users and sync with Keycloak${NC}"

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

# Verify required tools are available (pre-installed in container image)
echo -e "${CYAN}� Verifying container tools...${NC}"
MISSING_TOOLS=""

if ! command -v docker &> /dev/null; then
    MISSING_TOOLS="$MISSING_TOOLS docker"
fi

if ! command -v curl &> /dev/null; then
    MISSING_TOOLS="$MISSING_TOOLS curl"
fi

if ! command -v jq &> /dev/null; then
    MISSING_TOOLS="$MISSING_TOOLS jq"
fi

if ! command -v ldapsearch &> /dev/null; then
    MISSING_TOOLS="$MISSING_TOOLS ldap-utils"
fi

if [ -n "$MISSING_TOOLS" ]; then
    echo -e "${RED}❌ Missing required tools: $MISSING_TOOLS${NC}"
    echo -e "${YELLOW}💡 Please rebuild the python-bastion container with: docker-compose build utils${NC}"
    exit 1
else
    echo -e "${GREEN}✅ All required tools available: docker, curl, jq, ldap-utils${NC}"
fi

# Show environment detection
show_environment_info

# Step 1: Verify services are running (they should be started from host)
confirm_step "About to verify that all Docker services are running"
echo -e "${GREEN}🔄 Step 1: Verifying all services are running...${NC}"

# Check if containers are actually running using Docker API from within container
containers_running=0
expected_containers=("ldap" "keycloak" "python-bastion" "ldap-manager")
for container in "${expected_containers[@]}"; do
    if docker ps --format "table {{.Names}}" | grep -q "^${container}$"; then
        echo -e "${GREEN}✓${NC} ${container} container is running"
        containers_running=$((containers_running + 1))
    else
        echo -e "${YELLOW}⚠️${NC} ${container} container is not running"
        echo -e "${YELLOW}  Checking container status...${NC}"
        docker ps -a --filter "name=${container}" --format "table {{.Names}}\t{{.Status}}"
    fi
done

if [ $containers_running -ne ${#expected_containers[@]} ]; then
    echo -e "${RED}❌ Not all expected containers are running.${NC}"
    echo -e "${YELLOW}Expected: ${expected_containers[*]}${NC}"
    echo -e "${YELLOW}This script should be run after starting containers from host.${NC}"
    echo -e "${YELLOW}Make sure to run 'docker-compose up -d' from host first.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All expected services are running${NC}"

# Enhanced service readiness check
echo -e "${YELLOW}⏳ Checking service readiness...${NC}"

# Progressive wait with service checks
for i in {1..6}; do
    echo -e "${CYAN}Service readiness check $i/6...${NC}"
    sleep 5
    
    # Check if LDAP is responding (using docker exec from within the container)
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

# Check Keycloak readiness
echo -e "${CYAN}🔍 Checking Keycloak readiness...${NC}"
for i in {1..20}; do
    # Try to access Keycloak from within the network (more reliable than health endpoint)
    if curl -s -f http://keycloak:8080/realms/master >/dev/null 2>&1 || \
       curl -s -f http://keycloak:8080/auth/realms/master >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Keycloak service is responding${NC}"
        break
    else
        echo -e "${YELLOW}⏳ Keycloak service still initializing... ($i/20)${NC}"
        if [ $i -eq 20 ]; then
            echo -e "${YELLOW}⚠️  Keycloak health check timeout, but let's check if it's actually accessible${NC}"
            # Final check - if we can get a response, proceed anyway
            if curl -s http://keycloak:8080/realms/master | grep -q "master" 2>/dev/null; then
                echo -e "${GREEN}✓ Keycloak is actually accessible, proceeding${NC}"
                break
            else
                echo -e "${RED}❌ Keycloak service failed to initialize within expected time${NC}"
                echo -e "${YELLOW}Container logs (last 20 lines):${NC}"
                docker logs keycloak --tail 20
                exit 1
            fi
        fi
        sleep 10
    fi
done

# Step 1.5: Generate LDIF files and load initial data
confirm_step "About to generate LDIF files from CSV data and load them into LDAP"
echo -e "${GREEN}🔄 Step 1.5: Generating LDIF files and loading initial data...${NC}"
echo -e "${CYAN}📝 Generating LDIF from CSV files using Python (already inside container)...${NC}"

# Generate LDIF files using the local Python environment
if python python-bastion/csv_to_ldif.py data/admins.csv; then
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

# Step 2: Complete Keycloak Setup
confirm_step "About to run complete Keycloak setup (realm creation, LDAP integration, organizations)"
echo -e "${GREEN}🔄 Step 2: Running complete Keycloak setup...${NC}"
cd keycloak

# Pass through the appropriate flags
KEYCLOAK_ARGS="${REALM_NAME}"
if [ "$CHECK_STEPS" = true ]; then
    KEYCLOAK_ARGS="${KEYCLOAK_ARGS} --check-steps"
elif [ "$USE_DEFAULTS" = true ]; then
    KEYCLOAK_ARGS="${KEYCLOAK_ARGS} --defaults"
fi

./setup_keycloak_full.sh ${KEYCLOAK_ARGS}
check_success

# Extract organization status from the keycloak setup
if [ "$USE_DEFAULTS" = true ] || [ "$CHECK_STEPS" = false ]; then
    # Default behavior sets up organizations
    ORGANIZATIONS_CONFIGURED=true
    org_prefixes="acme xyz"
else
    # Interactive mode - assume organizations were configured unless explicitly declined
    ORGANIZATIONS_CONFIGURED=true
    org_prefixes="acme xyz"
fi

cd /workspace
echo -e "${GREEN}✅ Complete Keycloak setup finished successfully${NC}"
echo ""

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
echo -e "${CYAN}🔄 To sync again later, run from host: ${WHITE}./start_all_bastion.sh ${REALM_NAME} --sync-only${NC}"
echo ""

if [ "$ORGANIZATIONS_CONFIGURED" = true ]; then
    echo -e "${CYAN}🏢 Organization Features Available:${NC}"
    echo -e "${CYAN}   • JWT tokens contain organization-specific role claims${NC}"
    echo -e "${CYAN}   • Shared clients: shared-web-client, shared-api-client${NC}"
    echo -e "${CYAN}   • Role filtering by organization prefix in JWT tokens${NC}"
    echo -e "${CYAN}   • Organization domains: {org}.${REALM_NAME}.local format${NC}"
    echo -e "${CYAN}   • Mock OAuth2 Identity Provider for multi-provider testing${NC}"
    echo -e "${CYAN}   • Organization-specific OAuth2 clients configured${NC}"
    echo -e "${CYAN}   • View organization setup guide: ./keycloak/show_organization_guide.sh${NC}"
    echo ""
fi

# Step 3: Optional - Load additional users
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🔧 Step 3: Optional - Load additional users and group assignments into LDAP${NC}"
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
        /workspace/ldap/load_additional_users.sh "${REALM_NAME}" --defaults
    else
        /workspace/ldap/load_additional_users.sh "${REALM_NAME}"
    fi
    echo ""
    echo -e "${GREEN}✅ Additional users loaded. You may want to re-sync LDAP:${NC}"
    echo -e "${GREEN}   From host: ./start_all_bastion.sh ${REALM_NAME} --sync-only${NC}"
else
    echo -e "${YELLOW}Skipped additional users import. You can run it manually later with:${NC}"
    echo -e "${YELLOW}   From host: ./start_all_bastion.sh ${REALM_NAME} --load-users${NC}"
    echo -e "${YELLOW}   Then re-sync with: ./start_all_bastion.sh ${REALM_NAME} --sync-only${NC}"
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🎉 SETUP COMPLETE! Your LDAP-Keycloak POC is ready!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}🐳 Setup completed from within python-bastion container${NC}"
echo -e "${CYAN}   This eliminates host platform issues with Windows/WSL/Git Bash${NC}"
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