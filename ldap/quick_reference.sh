#!/bin/bash

# LDAP Quick Reference Guide
# Common LDAP commands, CSV operations, and troubleshooting tips

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}           LDAP Quick Reference Guide${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${CYAN}📁 LDAP Configuration${NC}"
echo -e "${YELLOW}Domain:${NC} mycompany.local"
echo -e "${YELLOW}Base DN:${NC} dc=mycompany,dc=local"
echo -e "${YELLOW}Admin DN:${NC} cn=admin,dc=mycompany,dc=local"
echo -e "${YELLOW}Admin Password:${NC} admin"
echo -e "${YELLOW}Users OU:${NC} ou=users,dc=mycompany,dc=local"
echo -e "${YELLOW}Groups OU:${NC} ou=groups,dc=mycompany,dc=local"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${MAGENTA}1. CSV Data Management${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}CSV File Locations:${NC}"
echo -e "  ${BLUE}data/admins.csv${NC}  - Admin users (loaded on startup)"
echo -e "  ${BLUE}data/users.csv${NC}   - Regular users (loaded manually)"
echo ""

echo -e "${YELLOW}Load Additional Users:${NC}"
echo -e "  ${GREEN}./ldap/load_additional_users.sh${NC}"
echo -e "  ${GREEN}./ldap/load_additional_users.sh <realm-name>${NC}  # With Keycloak sync"
echo ""

echo -e "${YELLOW}CSV Format:${NC}"
echo -e "  ${BLUE}username,firstname,lastname,email,password,groups${NC}"
echo -e "  ${BLUE}alice,Alice,Smith,alice@mycompany.local,alice123,developers${NC}"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${MAGENTA}2. LDAP Search Commands${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}Search All Entries:${NC}"
echo -e "  ${GREEN}ldapsearch -x -H ldap://localhost:389 \\${NC}"
echo -e "    ${GREEN}-D \"cn=admin,dc=mycompany,dc=local\" -w admin \\${NC}"
echo -e "    ${GREEN}-b \"dc=mycompany,dc=local\" \"(objectClass=*)\"${NC}"
echo ""

echo -e "${YELLOW}Search Users Only:${NC}"
echo -e "  ${GREEN}ldapsearch -x -H ldap://localhost:389 \\${NC}"
echo -e "    ${GREEN}-D \"cn=admin,dc=mycompany,dc=local\" -w admin \\${NC}"
echo -e "    ${GREEN}-b \"ou=users,dc=mycompany,dc=local\" \"(objectClass=inetOrgPerson)\"${NC}"
echo ""

echo -e "${YELLOW}Search Groups Only:${NC}"
echo -e "  ${GREEN}ldapsearch -x -H ldap://localhost:389 \\${NC}"
echo -e "    ${GREEN}-D \"cn=admin,dc=mycompany,dc=local\" -w admin \\${NC}"
echo -e "    ${GREEN}-b \"ou=groups,dc=mycompany,dc=local\" \"(objectClass=posixGroup)\"${NC}"
echo ""

echo -e "${YELLOW}Search Specific User:${NC}"
echo -e "  ${GREEN}ldapsearch -x -H ldap://localhost:389 \\${NC}"
echo -e "    ${GREEN}-D \"cn=admin,dc=mycompany,dc=local\" -w admin \\${NC}"
echo -e "    ${GREEN}-b \"ou=users,dc=mycompany,dc=local\" \"(uid=alice)\"${NC}"
echo ""

echo -e "${YELLOW}Test User Authentication:${NC}"
echo -e "  ${GREEN}ldapsearch -x -H ldap://localhost:389 \\${NC}"
echo -e "    ${GREEN}-D \"uid=alice,ou=users,dc=mycompany,dc=local\" -w alice123 \\${NC}"
echo -e "    ${GREEN}-b \"dc=mycompany,dc=local\" \"(uid=alice)\"${NC}"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${MAGENTA}3. Container Operations${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}Access LDAP Container:${NC}"
echo -e "  ${GREEN}docker exec -it ldap sh${NC}"
echo ""

echo -e "${YELLOW}Check LDAP Logs:${NC}"
echo -e "  ${GREEN}docker logs ldap${NC}"
echo -e "  ${GREEN}docker logs -f ldap${NC}  # Follow logs"
echo ""

echo -e "${YELLOW}Run LDAP Commands in Container:${NC}"
echo -e "  ${GREEN}docker exec ldap ldapsearch -x -b \"dc=mycompany,dc=local\" \\${NC}"
echo -e "    ${GREEN}-D \"cn=admin,dc=mycompany,dc=local\" -w admin${NC}"
echo ""

echo -e "${YELLOW}Check LDAP Service Status:${NC}"
echo -e "  ${GREEN}docker exec ldap ps aux | grep slapd${NC}"
echo -e "  ${GREEN}docker exec ldap netstat -tlnp | grep 389${NC}"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${MAGENTA}4. Password Management${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}Fix LDAP Passwords for Keycloak:${NC}"
echo -e "  ${GREEN}./ldap/fix_ldap_passwords.sh${NC}"
echo -e "  ${BLUE}Converts passwords from SSHA to cleartext for Keycloak auth${NC}"
echo ""

echo -e "${YELLOW}Update Individual User Password:${NC}"
echo -e "  ${GREEN}ldappasswd -x -H ldap://localhost:389 \\${NC}"
echo -e "    ${GREEN}-D \"cn=admin,dc=mycompany,dc=local\" -w admin \\${NC}"
echo -e "    ${GREEN}-s newpassword \"uid=alice,ou=users,dc=mycompany,dc=local\"${NC}"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${MAGENTA}5. Troubleshooting${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}Connection Issues:${NC}"
echo -e "  1. ${BLUE}Check container status:${NC}"
echo -e "     ${GREEN}docker ps | grep ldap${NC}"
echo ""
echo -e "  2. ${BLUE}Check LDAP logs:${NC}"
echo -e "     ${GREEN}docker logs ldap | tail -50${NC}"
echo ""
echo -e "  3. ${BLUE}Test basic connection:${NC}"
echo -e "     ${GREEN}ldapsearch -x -H ldap://localhost:389 -s base${NC}"
echo ""

echo -e "${YELLOW}Authentication Failures:${NC}"
echo -e "  1. ${BLUE}Check user exists:${NC}"
echo -e "     ${GREEN}ldapsearch -x -H ldap://localhost:389 \\${NC}"
echo -e "       ${GREEN}-D \"cn=admin,dc=mycompany,dc=local\" -w admin \\${NC}"
echo -e "       ${GREEN}-b \"ou=users,dc=mycompany,dc=local\" \"(uid=alice)\"${NC}"
echo ""
echo -e "  2. ${BLUE}Test user authentication:${NC}"
echo -e "     ${GREEN}ldapwhoami -x -H ldap://localhost:389 \\${NC}"
echo -e "       ${GREEN}-D \"uid=alice,ou=users,dc=mycompany,dc=local\" -w alice123${NC}"
echo ""
echo -e "  3. ${BLUE}Fix password format:${NC}"
echo -e "     ${GREEN}./ldap/fix_ldap_passwords.sh${NC}"
echo ""

echo -e "${YELLOW}No Data Found:${NC}"
echo -e "  1. ${BLUE}Check if LDAP has loaded data:${NC}"
echo -e "     ${GREEN}ldapsearch -x -H ldap://localhost:389 \\${NC}"
echo -e "       ${GREEN}-D \"cn=admin,dc=mycompany,dc=local\" -w admin \\${NC}"
echo -e "       ${GREEN}-b \"dc=mycompany,dc=local\" | grep dn:${NC}"
echo ""
echo -e "  2. ${BLUE}Reload data:${NC}"
echo -e "     ${GREEN}./stop.sh && ./start.sh${NC}"
echo ""
echo -e "  3. ${BLUE}Load additional users:${NC}"
echo -e "     ${GREEN}./ldap/load_additional_users.sh${NC}"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${MAGENTA}6. Common Tasks${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}Add New User to LDAP:${NC}"
echo -e "  1. ${BLUE}Add user to data/users.csv:${NC}"
echo -e "     ${GREEN}dave,Dave,Wilson,dave@mycompany.local,dave123,developers${NC}"
echo ""
echo -e "  2. ${BLUE}Load additional users:${NC}"
echo -e "     ${GREEN}./ldap/load_additional_users.sh${NC}"
echo ""
echo -e "  3. ${BLUE}Sync to Keycloak (if using Keycloak):${NC}"
echo -e "     ${GREEN}./keycloak/sync_ldap.sh <realm-name>${NC}"
echo ""

echo -e "${YELLOW}Create New Group:${NC}"
echo -e "  1. ${BLUE}Add group to user's groups field in CSV:${NC}"
echo -e "     ${GREEN}alice,Alice,Smith,alice@mycompany.local,alice123,developers;newgroup${NC}"
echo ""
echo -e "  2. ${BLUE}Reload data:${NC}"
echo -e "     ${GREEN}./stop.sh && ./start.sh${NC}"
echo ""

echo -e "${YELLOW}Check User's Groups:${NC}"
echo -e "  ${GREEN}ldapsearch -x -H ldap://localhost:389 \\${NC}"
echo -e "    ${GREEN}-D \"cn=admin,dc=mycompany,dc=local\" -w admin \\${NC}"
echo -e "    ${GREEN}-b \"ou=groups,dc=mycompany,dc=local\" \"(memberUid=alice)\"${NC}"
echo ""

echo -e "${YELLOW}Backup LDAP Data:${NC}"
echo -e "  ${GREEN}ldapsearch -x -H ldap://localhost:389 \\${NC}"
echo -e "    ${GREEN}-D \"cn=admin,dc=mycompany,dc=local\" -w admin \\${NC}"
echo -e "    ${GREEN}-b \"dc=mycompany,dc=local\" > backup.ldif${NC}"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${MAGENTA}7. Integration with Keycloak${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}Sync LDAP to Keycloak:${NC}"
echo -e "  ${GREEN}./keycloak/sync_ldap.sh <realm-name>${NC}"
echo ""

echo -e "${YELLOW}Check LDAP Provider Status:${NC}"
echo -e "  ${GREEN}./keycloak/debug_realm_ldap.sh <realm-name>${NC}"
echo ""

echo -e "${YELLOW}After Adding Users to CSV:${NC}"
echo -e "  1. ${GREEN}./ldap/load_additional_users.sh <realm-name>${NC}  ${BLUE}# Loads and syncs${NC}"
echo -e "  2. ${BLUE}Or manually:${NC}"
echo -e "     ${GREEN}./ldap/load_additional_users.sh${NC}  ${BLUE}# Load to LDAP${NC}"
echo -e "     ${GREEN}./keycloak/sync_ldap.sh <realm-name>${NC}  ${BLUE}# Sync to Keycloak${NC}"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${MAGENTA}8. Web UI Management${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}LDAP Web Manager Access:${NC}"
echo -e "  ${BLUE}URL:${NC} http://localhost:8080"
echo -e "  ${BLUE}Username:${NC} admin"
echo -e "  ${BLUE}Password:${NC} admin"
echo ""

echo -e "${YELLOW}Web UI Features:${NC}"
echo -e "  • Browse users and groups"
echo -e "  • Add/edit/delete users"
echo -e "  • Manage group memberships"
echo -e "  • Change passwords"
echo -e "  • View user attributes"
echo ""

echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}💡 Tips:${NC}"
echo -e "  • Use ${GREEN}./ldap/load_additional_users.sh <realm>${NC} to load and sync in one command"
echo -e "  • Password format matters for Keycloak - use ${GREEN}fix_ldap_passwords.sh${NC} if auth fails"
echo -e "  • Check logs first: ${GREEN}docker logs ldap${NC}"
echo -e "  • CSV changes require reload: ${GREEN}./stop.sh && ./start.sh${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
echo ""
