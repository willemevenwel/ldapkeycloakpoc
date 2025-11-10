#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${GREEN}🏢 Keycloak Organization Setup - Usage Guide${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""

echo -e "${YELLOW}📋 Overview:${NC}"
echo -e "This enhanced setup adds organization-aware role management to your existing Keycloak realm."
echo -e "Roles follow the pattern: ${CYAN}{organization_prefix}_{role_name}${NC}"
echo -e "Example: ${CYAN}acme_developer${NC}, ${CYAN}xyz_admin${NC}, ${CYAN}abc_specialist${NC}"
echo ""

echo -e "${YELLOW}🔧 Setup Process:${NC}"
echo -e "${BLUE}1. Create your realm (existing):${NC}"
echo -e "   ${WHITE}./create_realm.sh walmart${NC}"
echo ""

echo -e "${BLUE}2. Add LDAP provider (existing):${NC}"
echo -e "   ${WHITE}./add_ldap_provider.sh walmart${NC}"
echo ""

echo -e "${BLUE}3. Setup organizations (NEW):${NC}"
echo -e "   ${WHITE}./setup_organizations.sh walmart acme xyz abc${NC}"
echo -e "   ${CYAN}# This will create organizations for prefixes: acme, xyz, abc${NC}"
echo -e "   ${CYAN}# Creates example roles: acme_admin, acme_developer, xyz_user, etc.${NC}"
echo -e "   ${CYAN}# Updates LDAP group mapper to sync acme*, xyz*, abc* groups${NC}"
echo ""

echo -e "${BLUE}4. Configure shared clients (NEW):${NC}"
echo -e "   ${WHITE}./configure_shared_clients.sh walmart acme xyz abc${NC}"
echo -e "   ${CYAN}# Creates shared-web-client and shared-api-client${NC}"
echo -e "   ${CYAN}# Sets up role filtering by organization prefix${NC}"
echo -e "   ${CYAN}# Configures JWT token claims for each organization${NC}"
echo ""

echo -e "${BLUE}5. Create role mappers (existing):${NC}"
echo -e "   ${WHITE}./update_role_mapper.sh walmart${NC}"
echo ""

echo -e "${BLUE}6. Sync LDAP data (existing):${NC}"
echo -e "   ${WHITE}./sync_ldap.sh walmart${NC}"
echo ""

echo -e "${YELLOW}🏢 Organization Features:${NC}"
echo ""

echo -e "${CYAN}Native Organizations (Keycloak 25+):${NC}"
echo -e "• Uses Keycloak's built-in Organizations feature"
echo -e "• Creates actual organization entities"
echo -e "• Each organization has attributes including role prefix"
echo -e "• Requires both organizationsEnabled=true AND org.keycloak.organization.enabled=true"
echo ""

echo -e "${CYAN}Group-based Organizations (Fallback):${NC}"
echo -e "• Creates groups named {ORG}_ORGANIZATION"
echo -e "• Uses group attributes to store organization info"
echo -e "• Compatible with older Keycloak versions"
echo ""

echo -e "${YELLOW}🎭 Role Management:${NC}"
echo ""

echo -e "${CYAN}Role Pattern:${NC}"
echo -e "• Format: ${WHITE}{org_prefix}_{role_name}${NC}"
echo -e "• Examples: ${WHITE}acme_admin, xyz_developer, abc_specialist1${NC}"
echo -e "• LDAP groups sync directly to these role names"
echo ""

echo -e "${CYAN}LDAP Integration:${NC}"
echo -e "• LDAP groups like ${WHITE}acme_developer${NC} → Keycloak role ${WHITE}acme_developer${NC}"
echo -e "• Group filter updated to: ${WHITE}(|(cn=admins)(cn=developers)(cn=acme*)(cn=xyz*)(cn=abc*))${NC}"
echo -e "• Automatic role creation from LDAP group sync"
echo ""

echo -e "${YELLOW}🔧 Client Configuration:${NC}"
echo ""

echo -e "${CYAN}Shared Web Client:${NC}"
echo -e "• Client ID: ${WHITE}shared-web-client${NC}"
echo -e "• Standard flow enabled for web applications"
echo -e "• Redirect URIs: localhost:3000, 8000, 8080"
echo ""

echo -e "${CYAN}Shared API Client:${NC}"
echo -e "• Client ID: ${WHITE}shared-api-client${NC}"
echo -e "• Bearer-only for API access"
echo -e "• Service account enabled"
echo ""

echo -e "${CYAN}Role Mappers:${NC}"
echo -e "• ${WHITE}realm_access.roles${NC}: All user roles"
echo -e "• ${WHITE}acme_roles${NC}: Only acme_ prefixed roles (prefix removed)"
echo -e "• ${WHITE}xyz_roles${NC}: Only xyz_ prefixed roles (prefix removed)"
echo -e "• ${WHITE}organization${NC}: Organization membership info"
echo ""

echo -e "${YELLOW}🧪 Testing Your Setup:${NC}"
echo ""

echo -e "${CYAN}1. Get Authentication Token:${NC}"
echo -e "${WHITE}curl -X POST 'http://localhost:8090/realms/walmart/protocol/openid-connect/token' \\
  -H 'Content-Type: application/x-www-form-urlencoded' \\
  -d 'username=testuser' \\
  -d 'password=password' \\
  -d 'grant_type=password' \\
  -d 'client_id=shared-web-client' \\
  -d 'client_secret=YOUR_CLIENT_SECRET'${NC}"
echo ""

echo -e "${CYAN}2. Decode JWT Token Claims:${NC}"
echo -e "Expected claims in the JWT token:"
echo -e "• ${WHITE}realm_access.roles${NC}: [\"acme_admin\", \"acme_developer\", \"xyz_user\"]"
echo -e "• ${WHITE}acme_roles${NC}: [\"admin\", \"developer\"] (prefix removed)"
echo -e "• ${WHITE}xyz_roles${NC}: [\"user\"] (prefix removed)"
echo -e "• ${WHITE}organization${NC}: {\"organizations\": [{\"prefix\": \"acme\", \"name\": \"ACME\"}, ...]}"
echo ""

echo -e "${CYAN}3. Application Integration:${NC}"
echo -e "Your applications can now:"
echo -e "• Filter roles by organization using ${WHITE}acme_roles${NC}, ${WHITE}xyz_roles${NC} claims"
echo -e "• Determine user's organizations from ${WHITE}organization${NC} claim"
echo -e "• Use ${WHITE}realm_access.roles${NC} for global permissions"
echo ""

echo -e "${YELLOW}🔍 Troubleshooting:${NC}"
echo ""

echo -e "${CYAN}Common Issues:${NC}"
echo -e "• ${RED}Organizations not visible in UI${NC}: Both organizationsEnabled AND org.keycloak.organization.enabled must be true"
echo -e "• ${RED}Organizations feature not available${NC}: Falls back to group-based approach"
echo -e "• ${RED}Script-based mappers fail${NC}: Falls back to regex-based role filtering"
echo -e "• ${RED}LDAP groups not syncing${NC}: Check group filter patterns in LDAP mapper"
echo ""

echo -e "${CYAN}Verification Steps:${NC}"
echo -e "1. Check Organizations/Groups: Admin Console → Organizations or Groups"
echo -e "2. Verify Roles: Admin Console → Roles (should see org_prefixed roles)"
echo -e "3. Test Client Mappers: Admin Console → Clients → Protocol Mappers"
echo -e "4. Check LDAP Sync: Admin Console → User Federation → Sync Users"
echo -e "5. Organizations UI visible: Refresh browser after realm update"
echo ""

echo -e "${YELLOW}📁 File Structure:${NC}"
echo -e "${CYAN}keycloak/${NC}"
echo -e "├── ${WHITE}create_realm.sh${NC}              # Creates basic realm (existing)"
echo -e "├── ${WHITE}add_ldap_provider.sh${NC}         # Adds LDAP (existing)"
echo -e "├── ${GREEN}setup_organizations.sh${NC}        # NEW: Sets up organizations"
echo -e "├── ${GREEN}configure_shared_clients.sh${NC}   # NEW: Configures shared clients"
echo -e "├── ${WHITE}update_role_mapper.sh${NC}         # Creates role mappers (existing)"
echo -e "└── ${WHITE}sync_ldap.sh${NC}                  # Syncs LDAP data (existing)"
echo ""

echo -e "${GREEN}✨ Your realm is now ready for multi-organization role management!${NC}"
echo ""

echo -e "${YELLOW}💡 Pro Tips:${NC}"
echo -e "• Use different organization prefixes for different business units"
echo -e "• Role suffixes can be anything: admin, developer, specialist1, manager_level2"
echo -e "• LDAP groups automatically create matching Keycloak roles"
echo -e "• JWT tokens contain both global and organization-filtered role claims"
echo -e "• Client applications can request specific organization scopes"