#!/bin/bash

# Keycloak Scripts Quick Reference
# Shows available scripts and their usage

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Keycloak Configuration Scripts - Quick Reference${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${CYAN}📋 All scripts support --help flag for detailed information${NC}"
echo -e "${CYAN}   Example: ./create_realm.sh --help${NC}"
echo ""

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}SETUP WORKFLOW (Run in order for new realm)${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${MAGENTA}1. Check Keycloak Version (Optional)${NC}"
echo -e "   ${BLUE}./check_version.sh --check-orgs${NC}"
echo ""

echo -e "${MAGENTA}2. Create Realm${NC}"
echo -e "   ${BLUE}./create_realm.sh <realm-name> [--force|--skip|--update]${NC}"
echo -e "   Example: ./create_realm.sh walmart"
echo ""

echo -e "${MAGENTA}3. Add LDAP Provider${NC}"
echo -e "   ${BLUE}./add_ldap_provider.sh <realm-name> [--force|--skip]${NC}"
echo -e "   Example: ./add_ldap_provider.sh walmart"
echo ""

echo -e "${MAGENTA}4. Create Role Mapper${NC}"
echo -e "   ${BLUE}./update_role_mapper.sh <realm-name> [--force|--skip]${NC}"
echo -e "   Example: ./update_role_mapper.sh walmart"
echo ""

echo -e "${MAGENTA}5. Sync LDAP Data${NC}"
echo -e "   ${BLUE}./sync_ldap.sh <realm-name>${NC}"
echo -e "   Example: ./sync_ldap.sh walmart"
echo ""

echo -e "${MAGENTA}6. Setup Organizations (Optional)${NC}"
echo -e "   ${BLUE}./setup_organizations.sh <realm-name> [org1 org2 ...]${NC}"
echo -e "   Example: ./setup_organizations.sh walmart acme xyz"
echo ""

echo -e "${MAGENTA}7. Configure Shared Clients (Optional)${NC}"
echo -e "   ${BLUE}./configure_shared_clients.sh <realm-name> [org1 org2 ...]${NC}"
echo -e "   Example: ./configure_shared_clients.sh walmart acme xyz"
echo ""

echo -e "${MAGENTA}8. Configure Application Clients (Optional)${NC}"
echo -e "   ${BLUE}./configure_application_clients.sh <realm-name> <app-name> [org1 org2 ...]${NC}"
echo -e "   Example: ./configure_application_clients.sh walmart app-a acme xyz"
echo ""

echo -e "${MAGENTA}9. Configure Mock OAuth2 IdP (Optional)${NC}"
echo -e "   ${BLUE}./configure_mock_oauth2_idp.sh <realm-name> [org1 org2 ...]${NC}"
echo -e "   Example: ./configure_mock_oauth2_idp.sh walmart acme xyz"
echo ""

echo -e "${MAGENTA}10. Configure Dashboard Client (Optional)${NC}"
echo -e "   ${BLUE}./configure_dashboard_client.sh <realm-name>${NC}"
echo -e "   Example: ./configure_dashboard_client.sh walmart"
echo ""

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}ORCHESTRATOR (Automated Setup)${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${MAGENTA}Full Automated Setup${NC}"
echo -e "   ${BLUE}./setup_keycloak_full.sh <realm-name> [--defaults|--check-steps|--dry-run]${NC}"
echo -e "   Examples:"
echo -e "     ./setup_keycloak_full.sh walmart --defaults     # Automation mode"
echo -e "     ./setup_keycloak_full.sh walmart --check-steps  # Interactive mode"
echo -e "     ./setup_keycloak_full.sh walmart --dry-run      # Show what would happen"
echo ""

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}MAINTENANCE SCRIPTS${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${MAGENTA}Re-sync LDAP Data${NC}"
echo -e "   ${BLUE}./sync_ldap.sh <realm-name>${NC}"
echo -e "   Run after LDAP changes"
echo ""

echo -e "${MAGENTA}Debug LDAP Configuration${NC}"
echo -e "   ${BLUE}./debug_realm_ldap.sh <realm-name>${NC}"
echo -e "   Troubleshoot LDAP issues"
echo ""

echo -e "${MAGENTA}View Realm Details${NC}"
echo -e "   ${BLUE}./show_keycloak_details.sh <realm-name>${NC}"
echo -e "   Show realm configuration"
echo ""

echo -e "${MAGENTA}Check Keycloak Version${NC}"
echo -e "   ${BLUE}./check_version.sh [--check-orgs] [--min-version <ver>]${NC}"
echo -e "   Verify version and feature availability"
echo ""

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}COMMON USE CASES${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${MAGENTA}Use Case 1: Create Minimal Realm (No Organizations)${NC}"
echo -e "   ${BLUE}./create_realm.sh mycompany${NC}"
echo -e "   ${BLUE}./add_ldap_provider.sh mycompany${NC}"
echo -e "   ${BLUE}./update_role_mapper.sh mycompany${NC}"
echo -e "   ${BLUE}./sync_ldap.sh mycompany${NC}"
echo ""

echo -e "${MAGENTA}Use Case 2: Full Setup with Organizations${NC}"
echo -e "   ${BLUE}./setup_keycloak_full.sh mycompany --defaults${NC}"
echo ""

echo -e "${MAGENTA}Use Case 3: Add Organizations to Existing Realm${NC}"
echo -e "   ${BLUE}./setup_organizations.sh existing-realm org1 org2 org3${NC}"
echo -e "   ${BLUE}./configure_shared_clients.sh existing-realm org1 org2 org3${NC}"
echo ""

echo -e "${MAGENTA}Use Case 4: Add Application Client${NC}"
echo -e "   ${BLUE}./configure_application_clients.sh walmart app-b acme xyz${NC}"
echo ""

echo -e "${MAGENTA}Use Case 5: Refresh LDAP After Changes${NC}"
echo -e "   ${BLUE}./sync_ldap.sh walmart${NC}"
echo ""

echo -e "${MAGENTA}Use Case 6: Force Recreate LDAP Provider${NC}"
echo -e "   ${BLUE}./add_ldap_provider.sh walmart --force${NC}"
echo -e "   ${BLUE}./update_role_mapper.sh walmart --force${NC}"
echo -e "   ${BLUE}./sync_ldap.sh walmart${NC}"
echo ""

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}AVAILABLE FLAGS${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${CYAN}Common Flags:${NC}"
echo -e "   ${BLUE}-h, --help${NC}        Show detailed help for any script"
echo -e "   ${BLUE}--force${NC}           Delete and recreate if exists (no prompt)"
echo -e "   ${BLUE}--skip${NC}            Skip if already exists (no prompt)"
echo -e "   ${BLUE}--update${NC}          Update existing configuration"
echo -e "   ${BLUE}--defaults${NC}        Use default values for all prompts"
echo -e "   ${BLUE}--check-steps${NC}     Prompt before each step"
echo -e "   ${BLUE}--dry-run${NC}         Show what would be done without executing"
echo ""

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}TIPS${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "  ${GREEN}✓${NC} Use ${BLUE}--help${NC} on any script for detailed information"
echo -e "  ${GREEN}✓${NC} Scripts are ${CYAN}idempotent${NC} - safe to re-run"
echo -e "  ${GREEN}✓${NC} Use ${BLUE}--defaults${NC} for CI/CD automation"
echo -e "  ${GREEN}✓${NC} Use ${BLUE}--dry-run${NC} to preview changes"
echo -e "  ${GREEN}✓${NC} Check ${BLUE}README.md${NC} for detailed documentation"
echo -e "  ${GREEN}✓${NC} Scripts detect container vs host environment automatically"
echo ""

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}For more information:${NC}"
echo -e "  • Run any script with ${BLUE}--help${NC} flag"
echo -e "  • Read ${BLUE}./README.md${NC} for comprehensive guide"
echo -e "  • Check ${BLUE}../README.md${NC} for project overview"
echo ""
