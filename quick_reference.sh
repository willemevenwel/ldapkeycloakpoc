#!/bin/bash

# Color definitions (consistent with project)
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color

# Check admin count from CSV
ADMIN_COUNT=$(grep -v '^username' data/admins.csv 2>/dev/null | wc -l | tr -d ' ')
TOTAL_USERS=$(grep -v '^username' data/users.csv 2>/dev/null | wc -l | tr -d ' ')

# Check LDAP status
LDAP_RUNNING=$(docker ps --filter "name=ldap" --filter "status=running" -q | wc -l | tr -d ' ')
if [ "$LDAP_RUNNING" -eq 1 ]; then
    LDAP_STATUS="${GREEN}RUNNING${NC}"
    # Get current user count from LDAP
    LDAP_USER_COUNT=$(docker exec ldap ldapsearch -x -D "cn=admin,dc=min,dc=io" -w admin -b "ou=users,dc=min,dc=io" "(objectClass=inetOrgPerson)" dn 2>/dev/null | grep -c "^dn:" || echo "0")
else
    LDAP_STATUS="${RED}STOPPED${NC}"
    LDAP_USER_COUNT="0"
fi

echo -e "${BLUE}🔧 ${CYAN}LDAP${NC}${BLUE} Admin-Only Startup - Quick Reference${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

echo -e "${WHITE}📋 Current Configuration:${NC}"
echo -e "   Admins loaded on startup: ${GREEN}${ADMIN_COUNT}${NC}"
echo -e "   Total users in CSV:      ${GREEN}${TOTAL_USERS}${NC}"
echo ""

echo -e "${WHITE}🚀 Startup Commands:${NC}"
echo -e "   ${GREEN}./start.sh${NC}                                # Start with admins only"
echo -e "   ${CYAN}./ldap/load_additional_users.sh${NC}          # Load remaining users manually"
echo -e "   ${RED}./stop.sh${NC}                                 # Stop all services"
echo ""

echo -e "${WHITE}🔧 ${MAGENTA}Keycloak${NC}${WHITE} Integration Commands:${NC}"
echo -e "   ${MAGENTA}./keycloak/create_realm.sh <realm>${NC}        # Create new ${MAGENTA}Keycloak${NC} realm"
echo -e "   ${MAGENTA}./keycloak/add_ldap_provider_for_keycloak.sh <realm>${NC}  # Add ${CYAN}LDAP${NC} provider"
echo -e "   ${MAGENTA}./keycloak/update_role_mapper.sh <realm>${NC}   # Create ${CYAN}LDAP${NC} role mapper"
echo -e "   ${MAGENTA}./keycloak/sync_ldap.sh <realm>${NC}           # Sync users/roles from ${CYAN}LDAP${NC}"
echo -e "   ${MAGENTA}./keycloak/debug_realm_ldap.sh <realm>${NC}    # Debug realm and ${CYAN}LDAP${NC} status"
echo ""

echo -e "${WHITE}🧪 Development Commands:${NC}"
echo -e "   ${GREEN}docker exec python-bastion python python/csv_to_ldif.py help${NC}  # Show CSV converter help"
echo -e "   ${GREEN}./quick_reference.sh${NC}                      # Show this reference"
echo ""

echo -e "${WHITE}📋 CSV Converter Examples:${NC}"
echo -e "   ${GREEN}docker exec python-bastion python python/csv_to_ldif.py data/admins.csv${NC}  # Process admin users"
echo -e "   ${GREEN}docker exec python-bastion python python/csv_to_ldif.py data/users.csv${NC}   # Process additional users"
echo ""

echo -e "${WHITE}🌐 Access Points:${NC}"
echo -e "   ${CYAN}LDAP${NC} Web Manager: ${CYAN}http://localhost:8091${NC}  ${YELLOW}(admin/admin)${NC}"
echo -e "   ${MAGENTA}Keycloak${NC}:         ${CYAN}http://localhost:8090${NC}  ${YELLOW}(admin/admin)${NC}"
echo -e "   ${CYAN}LDAP${NC} Protocol:    ${CYAN}ldap://localhost:389${NC}"
echo ""

echo -e "${WHITE}📝 Configuration Files:${NC}"
echo -e "   ${WHITE}data/admins.csv${NC}                           # Admin users (loaded on startup)"
echo -e "   ${WHITE}data/users.csv${NC}                            # Additional users (for manual loading)"
echo ""

echo -e "${WHITE}🔍 Verification:${NC}"
echo -e "${WHITE}   # Check loaded users:${NC}"
echo -e "${GREEN}   ldapsearch -x -H ldap://localhost:389 \\${NC}"
echo -e "${GREEN}     -D 'cn=admin,dc=min,dc=io' -w admin \\${NC}"
echo -e "${GREEN}     -b 'ou=users,dc=min,dc=io' \\${NC}"
echo -e "${GREEN}     '(objectClass=inetOrgPerson)' uid${NC}"
echo ""

echo -e "${WHITE}✅ ${CYAN}LDAP${NC}${WHITE} Status:${NC} ${LDAP_STATUS}"
echo -e "${WHITE}   Current users in ${CYAN}LDAP${NC}:${NC} ${GREEN}${LDAP_USER_COUNT}${NC}"
echo -e "${BLUE}============================================${NC}"