#!/bin/bash

# Python Bastion Container Quick Reference Guide
# Container operations, CSV conversion, and utility commands

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}        Python Bastion Container Quick Reference${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${CYAN}📦 About Python Bastion Container${NC}"
echo -e "${BLUE}The python-bastion container provides a consistent Linux environment${NC}"
echo -e "${BLUE}for running scripts, eliminating Windows/WSL/Git Bash compatibility issues.${NC}"
echo ""
echo -e "${YELLOW}Key Features:${NC}"
echo -e "  ✅ Pre-installed tools: docker, curl, jq, ldap-utils, python3"
echo -e "  ✅ Automatic network detection (container vs host URLs)"
echo -e "  ✅ Cross-platform consistency"
echo -e "  ✅ Clean professional output"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${MAGENTA}1. Container Access${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}Interactive Shell:${NC}"
echo -e "  ${GREEN}docker exec -it python-bastion bash${NC}"
echo ""

echo -e "${YELLOW}Run Single Command:${NC}"
echo -e "  ${GREEN}docker exec python-bastion <command>${NC}"
echo -e "  ${GREEN}docker exec python-bastion python --version${NC}"
echo -e "  ${GREEN}docker exec python-bastion curl --version${NC}"
echo ""

echo -e "${YELLOW}Check Container Status:${NC}"
echo -e "  ${GREEN}docker ps | grep python-bastion${NC}"
echo -e "  ${GREEN}docker logs python-bastion${NC}"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${MAGENTA}2. CSV to LDIF Conversion${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}Convert Admin Users:${NC}"
echo -e "  ${GREEN}docker exec python-bastion python python-bastion/csv_to_ldif.py data/admins.csv${NC}"
echo -e "  ${BLUE}Output:${NC} ldif/admins_only.ldif"
echo ""

echo -e "${YELLOW}Convert Regular Users:${NC}"
echo -e "  ${GREEN}docker exec python-bastion python python-bastion/csv_to_ldif.py data/users.csv${NC}"
echo -e "  ${BLUE}Output:${NC} ldif/users.ldif, ldif/group_assign.ldif"
echo ""

echo -e "${YELLOW}Show Help:${NC}"
echo -e "  ${GREEN}docker exec python-bastion python python-bastion/csv_to_ldif.py help${NC}"
echo ""

echo -e "${YELLOW}CSV Format:${NC}"
echo -e "  ${BLUE}username,firstname,lastname,email,password,groups${NC}"
echo -e "  ${BLUE}alice,Alice,Smith,alice@mycompany.local,alice123,developers;admins${NC}"
echo ""

echo -e "${YELLOW}What Gets Created:${NC}"
echo -e "  • ${BLUE}User entries${NC} in ou=users,dc=mycompany,dc=local"
echo -e "  • ${BLUE}Group entries${NC} in ou=groups,dc=mycompany,dc=local"
echo -e "  • ${BLUE}Group memberships${NC} (memberUid attributes)"
echo -e "  • ${BLUE}SHA-hashed passwords${NC}"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${MAGENTA}3. Running Scripts Inside Container${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}All Bastion Scripts (Recommended):${NC}"
echo -e "  ${GREEN}./start_all_bastion.sh <realm> --defaults${NC}"
echo -e "  ${GREEN}./test_all_bastion.sh <realm>${NC}"
echo -e "  ${GREEN}./test_jwt_bastion.sh --defaults${NC}"
echo -e "  ${GREEN}./test_application_jwt_bastion.sh --defaults${NC}"
echo ""

echo -e "${BLUE}These scripts automatically:${NC}"
echo -e "  1. Check if python-bastion container is running"
echo -e "  2. Execute the internal version inside the container"
echo -e "  3. Use service names (keycloak:8080, ldap:389) automatically"
echo ""

echo -e "${YELLOW}Direct Internal Script Execution:${NC}"
echo -e "  ${GREEN}docker exec python-bastion bash -c \"cd /workspace && ./test_all.sh capgemini\"${NC}"
echo -e "  ${GREEN}docker exec python-bastion bash -c \"cd /workspace && ./keycloak/sync_ldap.sh capgemini\"${NC}"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${MAGENTA}4. Network Detection${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}Automatic URL Detection:${NC}"
echo -e "  ${BLUE}Inside Container:${NC}"
echo -e "    • Keycloak: http://keycloak:8080"
echo -e "    • LDAP: ldap://ldap:389"
echo ""
echo -e "  ${BLUE}On Host:${NC}"
echo -e "    • Keycloak: http://localhost:8090"
echo -e "    • LDAP: ldap://localhost:389"
echo ""

echo -e "${YELLOW}Test Network Detection:${NC}"
echo -e "  ${GREEN}source network_detect.sh${NC}"
echo -e "  ${GREEN}get_keycloak_url${NC}"
echo -e "  ${GREEN}get_ldap_url${NC}"
echo ""

echo -e "${YELLOW}Inside Container Test:${NC}"
echo -e "  ${GREEN}docker exec python-bastion bash -c \"source network_detect.sh && get_keycloak_url\"${NC}"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${MAGENTA}5. Development Workflow${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}Complete Setup:${NC}"
echo -e "  1. ${GREEN}./start_all_bastion.sh capgemini --defaults${NC}"
echo -e "     ${BLUE}Starts all services + creates realm + configures LDAP${NC}"
echo ""

echo -e "${YELLOW}Test Everything:${NC}"
echo -e "  2. ${GREEN}./test_all_bastion.sh capgemini${NC}"
echo -e "     ${BLUE}Verifies services, realm, LDAP, organizations${NC}"
echo ""

echo -e "${YELLOW}Test JWT Tokens:${NC}"
echo -e "  3. ${GREEN}./test_jwt_bastion.sh --defaults${NC}"
echo -e "     ${BLUE}Tests authentication and JWT token generation${NC}"
echo ""

echo -e "${YELLOW}Test Application Clients:${NC}"
echo -e "  4. ${GREEN}./test_application_jwt_bastion.sh --defaults${NC}"
echo -e "     ${BLUE}Tests org-specific application clients${NC}"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${MAGENTA}6. Utility Commands${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}Check Installed Tools:${NC}"
echo -e "  ${GREEN}docker exec python-bastion which curl jq python3 ldapsearch${NC}"
echo ""

echo -e "${YELLOW}Python Version:${NC}"
echo -e "  ${GREEN}docker exec python-bastion python --version${NC}"
echo ""

echo -e "${YELLOW}Test jq (JSON Processing):${NC}"
echo -e "  ${GREEN}docker exec python-bastion echo '{\"test\":\"value\"}' | jq .${NC}"
echo ""

echo -e "${YELLOW}Test LDAP Tools:${NC}"
echo -e "  ${GREEN}docker exec python-bastion ldapsearch -x -H ldap://ldap:389 \\${NC}"
echo -e "    ${GREEN}-D \"cn=admin,dc=mycompany,dc=local\" -w admin \\${NC}"
echo -e "    ${GREEN}-b \"dc=mycompany,dc=local\" -s base${NC}"
echo ""

echo -e "${YELLOW}Test Curl (API Access):${NC}"
echo -e "  ${GREEN}docker exec python-bastion curl -s http://keycloak:8080/realms/master${NC}"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${MAGENTA}7. File Access and Permissions${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}Workspace Mount:${NC}"
echo -e "  ${BLUE}Host Path:${NC} /Users/willemevenwel/Research/ldapkeycloakpoc"
echo -e "  ${BLUE}Container Path:${NC} /workspace"
echo ""

echo -e "${YELLOW}List Workspace Files:${NC}"
echo -e "  ${GREEN}docker exec python-bastion ls -la /workspace${NC}"
echo ""

echo -e "${YELLOW}Read CSV File:${NC}"
echo -e "  ${GREEN}docker exec python-bastion cat /workspace/data/users.csv${NC}"
echo ""

echo -e "${YELLOW}View Generated LDIF:${NC}"
echo -e "  ${GREEN}docker exec python-bastion cat /workspace/ldif/users.ldif | head -20${NC}"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${MAGENTA}8. Troubleshooting${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}Container Not Running:${NC}"
echo -e "  ${GREEN}docker-compose up -d python-bastion${NC}"
echo -e "  ${GREEN}docker-compose restart python-bastion${NC}"
echo ""

echo -e "${YELLOW}Container Won't Start:${NC}"
echo -e "  1. ${BLUE}Check logs:${NC}"
echo -e "     ${GREEN}docker logs python-bastion${NC}"
echo ""
echo -e "  2. ${BLUE}Rebuild image:${NC}"
echo -e "     ${GREEN}docker-compose build python-bastion${NC}"
echo ""
echo -e "  3. ${BLUE}Force recreate:${NC}"
echo -e "     ${GREEN}docker-compose up -d --force-recreate python-bastion${NC}"
echo ""

echo -e "${YELLOW}Tool Missing in Container:${NC}"
echo -e "  1. ${BLUE}Check if tool is installed:${NC}"
echo -e "     ${GREEN}docker exec python-bastion which <tool-name>${NC}"
echo ""
echo -e "  2. ${BLUE}Rebuild with updated Dockerfile:${NC}"
echo -e "     ${GREEN}docker-compose build --no-cache python-bastion${NC}"
echo ""

echo -e "${YELLOW}Script Execution Fails:${NC}"
echo -e "  1. ${BLUE}Check script permissions:${NC}"
echo -e "     ${GREEN}docker exec python-bastion ls -l /workspace/keycloak/*.sh${NC}"
echo ""
echo -e "  2. ${BLUE}Make scripts executable:${NC}"
echo -e "     ${GREEN}chmod +x keycloak/*.sh${NC}"
echo ""
echo -e "  3. ${BLUE}Check line endings (Windows):${NC}"
echo -e "     ${GREEN}dos2unix keycloak/*.sh${NC}  ${BLUE}# If dos2unix is installed${NC}"
echo ""

echo -e "${YELLOW}Network Connectivity Issues:${NC}"
echo -e "  1. ${BLUE}Test Keycloak from container:${NC}"
echo -e "     ${GREEN}docker exec python-bastion curl -f http://keycloak:8080/realms/master${NC}"
echo ""
echo -e "  2. ${BLUE}Test LDAP from container:${NC}"
echo -e "     ${GREEN}docker exec python-bastion ldapsearch -x -H ldap://ldap:389 -s base${NC}"
echo ""
echo -e "  3. ${BLUE}Check container network:${NC}"
echo -e "     ${GREEN}docker network inspect ldapkeycloakpoc_default${NC}"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${MAGENTA}9. Advanced Operations${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}Run Multi-line Script:${NC}"
echo -e "  ${GREEN}docker exec python-bastion bash -c '${NC}"
echo -e "    ${GREEN}cd /workspace && \\${NC}"
echo -e "    ${GREEN}source network_detect.sh && \\${NC}"
echo -e "    ${GREEN}echo \"Keycloak: \$(get_keycloak_url)\" && \\${NC}"
echo -e "    ${GREEN}echo \"LDAP: \$(get_ldap_url)\"${NC}"
echo -e "  ${GREEN}'${NC}"
echo ""

echo -e "${YELLOW}Copy File from Container:${NC}"
echo -e "  ${GREEN}docker cp python-bastion:/workspace/ldif/users.ldif ./backup/users.ldif${NC}"
echo ""

echo -e "${YELLOW}Copy File to Container:${NC}"
echo -e "  ${GREEN}docker cp ./data/new_users.csv python-bastion:/workspace/data/users.csv${NC}"
echo ""

echo -e "${YELLOW}Install Additional Package:${NC}"
echo -e "  ${GREEN}docker exec python-bastion apt-get update${NC}"
echo -e "  ${GREEN}docker exec python-bastion apt-get install -y <package-name>${NC}"
echo -e "  ${BLUE}Note: Changes will be lost on container restart. Update Dockerfile for permanent changes.${NC}"
echo ""

echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}💡 Best Practices:${NC}"
echo -e "  • ${BLUE}Always use bastion scripts for cross-platform compatibility${NC}"
echo -e "  • ${BLUE}Check container logs if commands fail: ${GREEN}docker logs python-bastion${NC}"
echo -e "  • ${BLUE}Use ${GREEN}source network_detect.sh${NC} in scripts for automatic URL detection"
echo -e "  • ${BLUE}Remember: Scripts inside container use service names (keycloak, ldap)"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
echo ""
