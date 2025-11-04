#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
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

# Keycloak Full Setup Script
# This script handles all Keycloak configuration tasks extracted from start_all.sh

# Check if realm name parameter is provided
if [ $# -eq 0 ]; then
    echo -e "${RED}❌ Error: Realm name is required${NC}"
    echo -e "${YELLOW}Usage: $0 <realm-name> [--check-steps] [--defaults]${NC}"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo -e "${YELLOW}  $0 myrealm${NC}"
    echo -e "${YELLOW}  $0 myrealm --defaults${NC}"
    echo -e "${YELLOW}  $0 myrealm --check-steps${NC}"
    exit 1
fi

REALM_NAME="$1"
CHECK_STEPS=false
USE_DEFAULTS=false

# Parse additional arguments
shift
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
        *)
            echo -e "${YELLOW}⚠️  Unknown option: $1${NC}"
            shift
            ;;
    esac
done

echo -e "${GREEN}🔧 Starting complete Keycloak setup for realm: ${MAGENTA}${REALM_NAME}${NC}"
if [ "$CHECK_STEPS" = true ]; then
    echo -e "${CYAN}🔍 Check steps mode enabled - you will be prompted for confirmations${NC}"
elif [ "$USE_DEFAULTS" = true ]; then
    echo -e "${CYAN}🎯 Defaults mode enabled - using default values for all prompts${NC}"
fi

echo -e "${YELLOW}📋 This will execute the following Keycloak setup steps:${NC}"
echo -e "${YELLOW}   1. Check Keycloak server details and existing realms${NC}"
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

# Step 1: Get Keycloak details for debugging
confirm_step "About to check Keycloak server details and existing realms"
echo -e "${GREEN}🔄 Step 1: Getting Keycloak server details...${NC}"
./keycloak_details.sh
check_success
echo -e "${GREEN}✅ Keycloak details retrieved successfully${NC}"
echo ""

# Step 2: Create Keycloak realm
confirm_step "About to create Keycloak realm '${REALM_NAME}' with admin user and anticipated roles"
echo -e "${GREEN}🔄 Step 2: Creating Keycloak realm '${REALM_NAME}'...${NC}"
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

# Organization Setup Section
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🏢 Organization Setup (Advanced Feature)${NC}"
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
    
    # Step 9: Configure Application Clients (Automatic with organizations)
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}📱 Application-Specific Client Setup${NC}"
    echo -e "${YELLOW}   This creates organization-specific clients for each application${NC}"
    echo -e "${YELLOW}   Pattern: {org}-{app}-client (e.g., acme-app-a-client)${NC}"
    echo -e "${YELLOW}   Each client has unique credentials and organization-aware tokens${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo ""
    echo -e "${YELLOW}📱 Setting up application clients...${NC}"
    echo -e "${BLUE}💡 Enter application name (e.g., app-a, app-b, my-service)${NC}"
    echo -e "${BLUE}   Default application: app-a${NC}"
    
    if [ "$CHECK_STEPS" = true ]; then
        echo -en "${CYAN}Enter application name (or press Enter for default): ${NC}"
        read -r app_name
    elif [ "$USE_DEFAULTS" = true ]; then
        app_name="app-a"
        echo -e "${CYAN}Enter application name (or press Enter for default): ${YELLOW}[using default: app-a]${NC}"
    else
        echo -en "${CYAN}Enter application name (or press Enter for default): ${NC}"
        read -r app_name
    fi
    
    if [ -z "$app_name" ]; then
        app_name="app-a"
        echo -e "${YELLOW}Using default application name: ${app_name}${NC}"
    else
        echo -e "${GREEN}Using application name: ${app_name}${NC}"
    fi
    
    echo ""
    confirm_step "About to create application clients for: ${app_name} across organizations: ${org_prefixes}"
    echo -e "${GREEN}🔄 Step 9: Configuring application clients...${NC}"
    echo -e "${BLUE}📋 Using provided organization prefixes: ${org_prefixes}${NC}"
    ./configure_application_clients.sh "${REALM_NAME}" "${app_name}" ${org_prefixes}
    check_success
    echo -e "${GREEN}✅ Application clients configured successfully${NC}"
    echo ""
    APP_CLIENTS_CONFIGURED=true
    APP_NAME="${app_name}"
    
    echo ""
    echo -e "${GREEN}🎉 Organization setup completed!${NC}"
    echo -e "${YELLOW}📋 Organization Summary:${NC}"
    echo -e "${YELLOW}   • Organizations created: ${org_prefixes}${NC}"
    echo -e "${YELLOW}   • Domain format: {org}.${REALM_NAME}.local${NC}"
    echo -e "${YELLOW}   • Shared clients: shared-web-client, shared-api-client${NC}"
    if [ "$APP_CLIENTS_CONFIGURED" = true ]; then
        echo -e "${YELLOW}   • Application clients: {org}-${APP_NAME}-client for each organization${NC}"
    fi
    echo -e "${YELLOW}   • Role filtering: JWT tokens contain org-specific claims${NC}"
    echo -e "${YELLOW}   • LDAP groups matching org prefixes will sync automatically${NC}"
    echo -e "${YELLOW}   • Mock OAuth2 Identity Provider: Configured for org testing${NC}"
    echo ""
    
    # Step 10: Configure Dashboard Client
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}📊 Dashboard Client Setup${NC}"
    echo -e "${YELLOW}   This creates a confidential client for the dashboard/token-viewer${NC}"
    echo -e "${YELLOW}   The dashboard client enables API access to query realms and clients${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    confirm_step "About to create dashboard client for API access in the token viewer"
    echo -e "${GREEN}🔄 Step 10: Configuring dashboard client...${NC}"
    ./configure_dashboard_client.sh "${REALM_NAME}"
    check_success
    echo -e "${GREEN}✅ Dashboard client configured successfully${NC}"
    echo ""
    
    ORGANIZATIONS_CONFIGURED=true
else
    echo -e "${YELLOW}Skipped organization setup. You can run it manually later with:${NC}"
    echo -e "${YELLOW}   ./setup_organizations.sh ${REALM_NAME} acme xyz${NC}"
    echo -e "${YELLOW}   ./configure_shared_clients.sh ${REALM_NAME} acme xyz${NC}"
    echo ""
    ORGANIZATIONS_CONFIGURED=false
fi

# Summary
echo -e "${GREEN}🎉 Complete Keycloak setup finished successfully!${NC}"
echo ""
echo -e "${YELLOW}📋 Keycloak Setup Summary for realm '${REALM_NAME}':${NC}"
echo -e "${YELLOW}   • Keycloak realm '${REALM_NAME}' created${NC}"
echo -e "${YELLOW}   • LDAP provider 'ldap-provider-${REALM_NAME}' configured${NC}"
echo -e "${YELLOW}   • Role mapper 'role-mapper-${REALM_NAME}' configured${NC}"
echo -e "${YELLOW}   • Users and roles synced from LDAP to Keycloak${NC}"
if [ "$ORGANIZATIONS_CONFIGURED" = true ]; then
    echo -e "${YELLOW}   • Organizations configured: ${org_prefixes} (domains: {org}.${REALM_NAME}.local)${NC}"
    echo -e "${YELLOW}   • Shared clients with role filtering configured${NC}"
    if [ "$APP_CLIENTS_CONFIGURED" = true ]; then
        echo -e "${YELLOW}   • Application clients configured for: ${APP_NAME}${NC}"
    fi
    echo -e "${YELLOW}   • Dashboard client configured for token-viewer API access${NC}"
    echo -e "${YELLOW}   • Mock OAuth2 Identity Provider configured for multi-provider testing${NC}"
fi
echo ""
echo -e "${GREEN}🌐 Access your Keycloak setup:${NC}"
KEYCLOAK_DISPLAY_URL="$(get_keycloak_url)"
echo -e "${GREEN}   • Keycloak Admin     : ${BLUE}${KEYCLOAK_DISPLAY_URL}/admin/${REALM_NAME}/console/${NC}"
echo -e "${GREEN}   • Realm URL          : ${BLUE}${KEYCLOAK_DISPLAY_URL}/realms/${REALM_NAME}${NC}"
if [ "$ORGANIZATIONS_CONFIGURED" = true ]; then
    echo -e "${GREEN}   • Organizations      : ${BLUE}${KEYCLOAK_DISPLAY_URL}/admin/${REALM_NAME}/console/#/${REALM_NAME}/organizations${NC}"
    echo -e "${GREEN}   • Clients            : ${BLUE}${KEYCLOAK_DISPLAY_URL}/admin/${REALM_NAME}/console/#/${REALM_NAME}/clients${NC}"
fi
echo ""
echo -e "${GREEN}🔑 Keycloak Admin credentials:${NC}"
echo -e "${GREEN}   • Keycloak Realm Admin: admin-${REALM_NAME} / admin-${REALM_NAME}${NC}"
echo -e "${GREEN}   • Keycloak Master Admin: admin / admin${NC}"
echo ""
echo -e "${CYAN}🔄 To sync LDAP again later, run: ./sync_ldap.sh ${REALM_NAME}${NC}"
echo ""
if [ "$ORGANIZATIONS_CONFIGURED" = true ]; then
    echo -e "${CYAN}🏢 Organization Features Configured:${NC}"
    echo -e "${CYAN}   • JWT tokens contain organization-specific role claims${NC}"
    echo -e "${CYAN}   • Shared clients: shared-web-client, shared-api-client${NC}"
    if [ "$APP_CLIENTS_CONFIGURED" = true ]; then
        echo -e "${CYAN}   • Application clients: {org}-${APP_NAME}-client (one per organization)${NC}"
    fi
    echo -e "${CYAN}   • Dashboard client: dashboard-admin-client (for token-viewer)${NC}"
    echo -e "${CYAN}   • Role filtering by organization prefix in JWT tokens${NC}"
    echo -e "${CYAN}   • Organization domains: {org}.${REALM_NAME}.local format${NC}"
    echo -e "${CYAN}   • Mock OAuth2 Identity Provider for multi-provider testing${NC}"
    echo -e "${CYAN}   • Organization-specific OAuth2 clients configured${NC}"
    echo -e "${CYAN}   • View organization setup guide: ./organization_setup_guide.sh${NC}"
    echo ""
fi

if [ "$APP_CLIENTS_CONFIGURED" = true ]; then
    echo -e "${CYAN}🧪 Test Application Clients:${NC}"
    echo -e "${CYAN}   ./test_application_jwt_bastion.sh ${REALM_NAME} ${APP_NAME} acme test-acme-admin${NC}"
    echo -e "${CYAN}   ./test_application_jwt_bastion.sh --defaults${NC}"
    echo ""
fi

echo -e "${GREEN}✅ Keycloak setup complete! Ready for testing.${NC}"